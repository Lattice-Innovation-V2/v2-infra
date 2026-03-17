import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface CloudRunEnvVar {
  name: string;
  value?: pulumi.Input<string>;
}

export interface CloudRunSecretEnvVar {
  name: string;
  secretName: pulumi.Input<string>;
  version?: string;
}

export interface CloudRunArgs {
  environment: string;
  projectId: string;
  region: string;
  serviceName: string;
  /** Prefix for Cloud Run service name and SA. Defaults to environment. */
  serviceNamePrefix?: string;
  vpcName: pulumi.Input<string>;
  subnetName: pulumi.Input<string>;
  containerPort: number;
  envVars?: CloudRunEnvVar[];
  secrets?: CloudRunSecretEnvVar[];
  cloudSqlConnectionName?: pulumi.Input<string>;
  minInstances: number;
  maxInstances: number;
  memory?: string;
  cpu?: string;
  startupProbePath?: string;
  livenessProbePath?: string;
  /** Labels applied to the Cloud Run service. */
  labels?: Record<string, string>;
  /** When true, import existing GCP resources instead of creating new ones. */
  importExisting?: boolean;
}

export class CloudRun extends pulumi.ComponentResource {
  public readonly serviceUrl: pulumi.Output<string>;
  public readonly serviceAccountEmail: pulumi.Output<string>;
  public readonly cloudRunServiceName: pulumi.Output<string>;

  constructor(
    name: string,
    args: CloudRunArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("v2:apps:CloudRun", name, {}, opts);

    const {
      environment,
      projectId,
      region,
      serviceName,
      serviceNamePrefix: rawPrefix,
      vpcName,
      subnetName,
      containerPort,
      envVars,
      secrets,
      cloudSqlConnectionName,
      minInstances,
      maxInstances,
      memory = "512Mi",
      cpu = "1",
      startupProbePath,
      livenessProbePath,
      labels,
      importExisting,
    } = args;

    const svcPrefix = rawPrefix ?? environment;
    const prefix = `${svcPrefix}-${serviceName}`;
    const importId = (id: string) => importExisting ? id : undefined;

    // SA accountId must be ≤30 chars. Use shortened prefix if needed.
    const saAccountId = `${svcPrefix}-${serviceName}`.slice(0, 30);

    // Per-service service account
    const serviceAccount = new gcp.serviceaccount.Account(
      `${prefix}-sa`,
      {
        project: projectId,
        accountId: saAccountId,
        displayName: `${svcPrefix} ${serviceName} Cloud Run SA`,
      },
      { parent: this },
    );

    // Build environment variables
    const envVarsList: gcp.types.input.cloudrunv2.ServiceTemplateContainerEnv[] =
      (envVars || []).map((ev) => ({
        name: ev.name,
        value: ev.value as string,
      }));

    // Add secret-sourced env vars
    const secretEnvVars: gcp.types.input.cloudrunv2.ServiceTemplateContainerEnv[] =
      (secrets || []).map((s) => ({
        name: s.name,
        valueSource: {
          secretKeyRef: {
            secret: s.secretName as string,
            version: s.version || "latest",
          },
        },
      }));

    const allEnvVars = [...envVarsList, ...secretEnvVars];

    // Build Cloud SQL volume and volume mount if needed
    const volumes: gcp.types.input.cloudrunv2.ServiceTemplateVolume[] =
      cloudSqlConnectionName
        ? [
            {
              name: "cloudsql",
              cloudSqlInstance: {
                instances: [cloudSqlConnectionName as string],
              },
            },
          ]
        : [];

    const volumeMounts: gcp.types.input.cloudrunv2.ServiceTemplateContainerVolumeMount[] =
      cloudSqlConnectionName
        ? [
            {
              name: "cloudsql",
              mountPath: "/cloudsql",
            },
          ]
        : [];

    // Cloud Run v2 service
    const service = new gcp.cloudrunv2.Service(
      `${prefix}-run`,
      {
        project: projectId,
        name: `${svcPrefix}-${serviceName}`,
        location: region,
        deletionProtection: false,
        labels: labels,
        ingress: "INGRESS_TRAFFIC_ALL",
        template: {
          serviceAccount: serviceAccount.email,
          scaling: {
            minInstanceCount: minInstances,
            maxInstanceCount: maxInstances,
          },
          vpcAccess: {
            networkInterfaces: [
              {
                network: vpcName as string,
                subnetwork: subnetName as string,
              },
            ],
            egress: "PRIVATE_RANGES_ONLY",
          },
          containers: [
            {
              image: "gcr.io/cloudrun/hello",
              ports: { containerPort: containerPort },
              envs: allEnvVars.length > 0 ? allEnvVars : undefined,
              resources: {
                limits: {
                  memory: memory,
                  cpu: cpu,
                },
              },
              startupProbe: startupProbePath
                ? {
                    httpGet: {
                      path: startupProbePath,
                      port: containerPort,
                    },
                    initialDelaySeconds: 5,
                    periodSeconds: 5,
                    failureThreshold: 30,
                    timeoutSeconds: 3,
                  }
                : undefined,
              livenessProbe: livenessProbePath
                ? {
                    httpGet: {
                      path: livenessProbePath,
                      port: containerPort,
                    },
                    periodSeconds: 30,
                    failureThreshold: 3,
                    timeoutSeconds: 3,
                  }
                : undefined,
              volumeMounts:
                volumeMounts.length > 0 ? volumeMounts : undefined,
            },
          ],
          volumes: volumes.length > 0 ? volumes : undefined,
        },
      },
      {
        parent: this,
        import: importId(`projects/${projectId}/locations/${region}/services/${svcPrefix}-${serviceName}`),
        // CI deploys update the container image — Pulumi should not revert it.
        ignoreChanges: ["template.containers[0].image"],
      },
    );

    this.serviceUrl = service.uri;
    this.serviceAccountEmail = serviceAccount.email;
    this.cloudRunServiceName = service.name;

    this.registerOutputs({
      serviceUrl: this.serviceUrl,
      serviceAccountEmail: this.serviceAccountEmail,
      cloudRunServiceName: this.cloudRunServiceName,
    });
  }
}
