import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { CloudRun, CloudRunEnvVar, CloudRunSecretEnvVar } from "../../components/cloud-run";
import { getEnvironmentConfig } from "../../config/environments";
import { MICROSERVICES } from "../../config/services";

const stack = pulumi.getStack();
const envConfig = getEnvironmentConfig(stack);

const gcpConfig = new pulumi.Config("gcp");
const projectId = gcpConfig.require("project");
const region = gcpConfig.require("region");

const appsConfig = new pulumi.Config("apps");
const networkingStackName = appsConfig.require("networkingStack");
const dataStackName = appsConfig.require("dataStack");
// Service name prefix for Cloud Run URLs (e.g. "linno-v2" → linno-v2-integrator-portal)
const servicePrefix = appsConfig.get("servicePrefix") ?? stack;

// Reference networking stack outputs
const networkingStack = new pulumi.StackReference(networkingStackName);
const vpcName = networkingStack.getOutput("vpcName") as pulumi.Output<string>;
const subnetName = networkingStack.getOutput(
  "subnetName",
) as pulumi.Output<string>;

// Reference data stack outputs
const dataStack = new pulumi.StackReference(dataStackName);
const cloudSqlConnectionName = dataStack.getOutput(
  "cloudSqlConnectionName",
) as pulumi.Output<string>;
const cloudSqlInstanceName = dataStack.getOutput(
  "cloudSqlInstanceName",
) as pulumi.Output<string>;

// Track created Cloud Run services for cross-service references
const serviceUrls: Record<string, pulumi.Output<string>> = {};
const serviceAccountEmails: Record<string, pulumi.Output<string>> = {};
const serviceNames: Record<string, pulumi.Output<string>> = {};

// Create Cloud Run services for all microservices
for (const svc of MICROSERVICES) {
  const envVars: CloudRunEnvVar[] = [
    { name: "ENVIRONMENT", value: stack },
  ];

  if (svc.runtime === "quarkus") {
    envVars.push({ name: "QUARKUS_HTTP_PORT", value: "8080" });
    envVars.push({ name: "QUARKUS_PROFILE", value: "prod" });
  }

  if (svc.runtime === "nextjs") {
    // Bypass IAP in V2 sandbox (no GLB/IAP configured yet)
    envVars.push({ name: "BYPASS_IAP", value: "true" });

    // Backend URL env vars — map dependency service names to env var names
    const backendEnvVarMap: Record<string, string> = {
      "integrator-service": "INTEGRATOR_API_URL",
      "merchant-service": "MERCHANT_API_URL",
      "payment-config-service": "PAYMENT_CONFIG_API_URL",
      "payment-runtime-service": "PAYMENT_RUNTIME_API_URL",
      "reporting-api": "REPORTING_API_URL",
      "brand-registry": "BRAND_REGISTRY_API_URL",
    };

    if (svc.backendDependencies) {
      for (const dep of svc.backendDependencies) {
        const envName = backendEnvVarMap[dep];
        if (envName && serviceUrls[dep]) {
          envVars.push({ name: envName, value: serviceUrls[dep] });
        }
      }
    }
  }

  // Database-specific env vars and secrets
  let sqlConnectionName: pulumi.Input<string> | undefined;
  const secretEnvVars: CloudRunSecretEnvVar[] = [];
  if (svc.hasDatabase && svc.database) {
    envVars.push({ name: "DB_NAME", value: svc.database });

    // DB credentials from Secret Manager
    secretEnvVars.push({ name: "DB_URL", secretName: "DB_URL" });
    secretEnvVars.push({ name: "DB_USER", secretName: "DB_USER" });
    secretEnvVars.push({ name: "DB_PASSWORD", secretName: "DB_PASSWORD" });
  }

  const cloudRun = new CloudRun(`${stack}-${svc.name}`, {
    environment: stack,
    projectId: projectId,
    region: region,
    serviceName: svc.name,
    serviceNamePrefix: servicePrefix,
    vpcName: vpcName,
    subnetName: subnetName,
    containerPort: svc.containerPort,
    envVars: envVars,
    secrets: secretEnvVars.length > 0 ? secretEnvVars : undefined,
    minInstances: envConfig.scaling.minInstances,
    maxInstances: envConfig.scaling.maxInstances,
    // Quarkus: /path/q/health/started and /path/q/health/live
    // Next.js: /api/health for both (no sub-paths)
    startupProbePath: svc.healthPath
      ? svc.runtime === "quarkus"
        ? `${svc.healthPath}/started`
        : svc.healthPath
      : undefined,
    livenessProbePath: svc.healthPath
      ? svc.runtime === "quarkus"
        ? `${svc.healthPath}/live`
        : svc.healthPath
      : undefined,
  });

  serviceUrls[svc.name] = cloudRun.serviceUrl;
  serviceAccountEmails[svc.name] = cloudRun.serviceAccountEmail;
  serviceNames[svc.name] = cloudRun.cloudRunServiceName;

  // Grant Cloud SQL roles and create IAM DB user for database services
  if (svc.hasDatabase) {
    new gcp.projects.IAMMember(
      `${stack}-${svc.name}-sql-client`,
      {
        project: projectId,
        role: "roles/cloudsql.client",
        member: pulumi.interpolate`serviceAccount:${cloudRun.serviceAccountEmail}`,
      },
    );

    new gcp.projects.IAMMember(
      `${stack}-${svc.name}-sql-instance-user`,
      {
        project: projectId,
        role: "roles/cloudsql.instanceUser",
        member: pulumi.interpolate`serviceAccount:${cloudRun.serviceAccountEmail}`,
      },
    );

    // Grant Secret Manager access for DB credentials
    new gcp.projects.IAMMember(
      `${stack}-${svc.name}-secret-accessor`,
      {
        project: projectId,
        role: "roles/secretmanager.secretAccessor",
        member: pulumi.interpolate`serviceAccount:${cloudRun.serviceAccountEmail}`,
      },
    );

    // Create IAM DB user (depends on SA via serviceAccountEmail output)
    new gcp.sql.User(
      `${stack}-${svc.name}-db-user`,
      {
        project: projectId,
        name: cloudRun.serviceAccountEmail.apply(
          (email) => email.replace(".gserviceaccount.com", ""),
        ),
        instance: cloudSqlInstanceName,
        type: "CLOUD_IAM_SERVICE_ACCOUNT",
      },
    );
  }
}

// Create github-actions SA IAM DB user (for Liquibase migrations)
new gcp.sql.User(
  `${stack}-github-actions-db-user`,
  {
    project: projectId,
    name: `github-actions-sa@${projectId}.iam`,
    instance: cloudSqlInstanceName,
    type: "CLOUD_IAM_SERVICE_ACCOUNT",
  },
);

// Grant service-to-service invoker permissions
// Frontends need to invoke their backend dependencies
for (const svc of MICROSERVICES) {
  if (svc.backendDependencies && svc.backendDependencies.length > 0) {
    for (const dep of svc.backendDependencies) {
      if (serviceAccountEmails[svc.name] && serviceNames[dep]) {
        new gcp.cloudrunv2.ServiceIamMember(
          `${stack}-${svc.name}-invoke-${dep}`,
          {
            project: projectId,
            location: region,
            name: serviceNames[dep],  // uses resource output → implicit dependency
            role: "roles/run.invoker",
            member: pulumi.interpolate`serviceAccount:${serviceAccountEmails[svc.name]}`,
          },
        );
      }
    }
  }
}

// Make public services accessible (allUsers invoker)
for (const svc of MICROSERVICES) {
  if (svc.isPublic) {
    new gcp.cloudrunv2.ServiceIamMember(
      `${stack}-${svc.name}-public`,
      {
        project: projectId,
        location: region,
        name: serviceNames[svc.name],  // uses resource output → implicit dependency
        role: "roles/run.invoker",
        member: "allUsers",
      },
    );
  }
}

// Stack outputs - all service URLs
export const services: Record<string, pulumi.Output<string>> = {};
for (const svc of MICROSERVICES) {
  services[svc.name] = serviceUrls[svc.name];
}
