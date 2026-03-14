import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { FEATBIT_IMAGE_TAGS, FEATBIT_DB_USER, FEATBIT_DB_NAME } from "../../config/featbit";

/**
 * FeatBit Services Module
 *
 * Deploys FeatBit Standalone OSS (feature flag platform) as 4 Cloud Run services.
 * DA stays internal-only (called by API server). UI, API, and Eval are public.
 *
 * Services:
 * - featbit-da:   Data Analytics Server (Postgres-backed OLAP)
 * - featbit-api:  API Server (flag management, calls DA internally)
 * - featbit-eval: Evaluation Server (SDK WebSocket connections)
 * - featbit-ui:   Nginx SPA (browser calls API + Eval)
 */

export interface FeatBitConfig {
  environment: string;
  projectId: string;
  region: string;
  servicePrefix: string;
  vpcName: pulumi.Input<string>;
  subnetName: pulumi.Input<string>;
  cloudSqlPrivateIp: pulumi.Output<string>;
  connStringSecretId: pulumi.Output<string>;
  dbPasswordSecretId: pulumi.Output<string>;
}

export interface FeatBitOutputs {
  uiUrl: pulumi.Output<string>;
  apiUrl: pulumi.Output<string>;
  evalUrl: pulumi.Output<string>;
  daUrl: pulumi.Output<string>;
}

/**
 * Creates the 4 FeatBit Cloud Run services with appropriate IAM bindings.
 *
 * Uses gcp.cloudrunv2.Service directly (not the CloudRun component) because
 * FeatBit requires ALL_TRAFFIC VPC egress for Cloud SQL private IP access,
 * while the CloudRun component hardcodes PRIVATE_RANGES_ONLY.
 */
export function createFeatBitServices(config: FeatBitConfig): FeatBitOutputs {
  const {
    environment: env,
    projectId,
    region,
    servicePrefix,
    vpcName,
    subnetName,
    cloudSqlPrivateIp,
    connStringSecretId,
    dbPasswordSecretId,
  } = config;

  const prefix = `${servicePrefix}-featbit`;

  // ============================================================================
  // Service Accounts
  // ============================================================================

  const daSa = new gcp.serviceaccount.Account(`${prefix}-da-sa`, {
    project: projectId,
    accountId: `${servicePrefix}-featbit-da`.slice(0, 30),
    displayName: `${servicePrefix} FeatBit DA Cloud Run SA`,
  });

  const apiSa = new gcp.serviceaccount.Account(`${prefix}-api-sa`, {
    project: projectId,
    accountId: `${servicePrefix}-featbit-api`.slice(0, 30),
    displayName: `${servicePrefix} FeatBit API Cloud Run SA`,
  });

  const evalSa = new gcp.serviceaccount.Account(`${prefix}-eval-sa`, {
    project: projectId,
    accountId: `${servicePrefix}-featbit-eval`.slice(0, 30),
    displayName: `${servicePrefix} FeatBit Eval Cloud Run SA`,
  });

  const uiSa = new gcp.serviceaccount.Account(`${prefix}-ui-sa`, {
    project: projectId,
    accountId: `${servicePrefix}-featbit-ui`.slice(0, 30),
    displayName: `${servicePrefix} FeatBit UI Cloud Run SA`,
  });

  // Grant Secret Manager access to services that need secrets
  for (const { sa, name } of [
    { sa: daSa, name: "da" },
    { sa: apiSa, name: "api" },
    { sa: evalSa, name: "eval" },
  ]) {
    new gcp.projects.IAMMember(`${prefix}-${name}-secret-accessor`, {
      project: projectId,
      role: "roles/secretmanager.secretAccessor",
      member: pulumi.interpolate`serviceAccount:${sa.email}`,
    });
  }

  // ============================================================================
  // featbit-da — Data Analytics Server (no inter-service deps, create first)
  // ============================================================================

  const daService = new gcp.cloudrunv2.Service(
    `${prefix}-da-run`,
    {
      project: projectId,
      name: `${servicePrefix}-featbit-da`,
      location: region,
      deletionProtection: false,
      ingress: "INGRESS_TRAFFIC_ALL",
      template: {
        serviceAccount: daSa.email,
        scaling: {
          minInstanceCount: 0,
          maxInstanceCount: 3,
        },
        vpcAccess: {
          networkInterfaces: [
            {
              network: vpcName as string,
              subnetwork: subnetName as string,
            },
          ],
          egress: "ALL_TRAFFIC",
        },
        containers: [
          {
            image: `featbit/featbit-data-analytics-server:${FEATBIT_IMAGE_TAGS.da}`,
            ports: { containerPort: 80 },
            resources: {
              limits: { memory: "512Mi", cpu: "1" },
            },
            envs: [
              { name: "DB_PROVIDER", value: "Postgres" },
              { name: "POSTGRES_HOST", value: cloudSqlPrivateIp },
              { name: "POSTGRES_PORT", value: "5432" },
              { name: "POSTGRES_USER", value: FEATBIT_DB_USER },
              { name: "POSTGRES_DATABASE", value: FEATBIT_DB_NAME },
              { name: "CHECK_DB_LIVNESS", value: "true" },
              {
                name: "POSTGRES_PASSWORD",
                valueSource: {
                  secretKeyRef: { secret: dbPasswordSecretId, version: "latest" },
                },
              },
            ],
          },
        ],
      },
    },
    { ignoreChanges: ["template.containers[0].image"] },
  );

  // ============================================================================
  // featbit-api — API Server (depends on DA URL for OLAP calls)
  // ============================================================================

  const apiService = new gcp.cloudrunv2.Service(
    `${prefix}-api-run`,
    {
      project: projectId,
      name: `${servicePrefix}-featbit-api`,
      location: region,
      deletionProtection: false,
      ingress: "INGRESS_TRAFFIC_ALL",
      template: {
        serviceAccount: apiSa.email,
        scaling: {
          minInstanceCount: 0,
          maxInstanceCount: 3,
        },
        vpcAccess: {
          networkInterfaces: [
            {
              network: vpcName as string,
              subnetwork: subnetName as string,
            },
          ],
          egress: "ALL_TRAFFIC",
        },
        containers: [
          {
            image: `featbit/featbit-api-server:${FEATBIT_IMAGE_TAGS.api}`,
            ports: { containerPort: 5000 },
            resources: {
              limits: { memory: "512Mi", cpu: "1" },
            },
            envs: [
              { name: "DbProvider", value: "Postgres" },
              { name: "MqProvider", value: "Postgres" },
              { name: "CacheProvider", value: "None" },
              { name: "OLAP__ServiceHost", value: daService.uri },
              {
                name: "Postgres__ConnectionString",
                valueSource: {
                  secretKeyRef: { secret: connStringSecretId, version: "latest" },
                },
              },
            ],
          },
        ],
      },
    },
    { ignoreChanges: ["template.containers[0].image"] },
  );

  // ============================================================================
  // featbit-eval — Evaluation Server (SDK WebSocket connections)
  // ============================================================================

  const evalService = new gcp.cloudrunv2.Service(
    `${prefix}-eval-run`,
    {
      project: projectId,
      name: `${servicePrefix}-featbit-eval`,
      location: region,
      deletionProtection: false,
      ingress: "INGRESS_TRAFFIC_ALL",
      template: {
        serviceAccount: evalSa.email,
        scaling: {
          minInstanceCount: 0,
          maxInstanceCount: 3,
        },
        vpcAccess: {
          networkInterfaces: [
            {
              network: vpcName as string,
              subnetwork: subnetName as string,
            },
          ],
          egress: "ALL_TRAFFIC",
        },
        containers: [
          {
            image: `featbit/featbit-evaluation-server:${FEATBIT_IMAGE_TAGS.eval}`,
            ports: { containerPort: 5100 },
            resources: {
              limits: { memory: "512Mi", cpu: "1" },
            },
            envs: [
              { name: "DbProvider", value: "Postgres" },
              { name: "MqProvider", value: "Postgres" },
              { name: "CacheProvider", value: "None" },
              {
                name: "Postgres__ConnectionString",
                valueSource: {
                  secretKeyRef: { secret: connStringSecretId, version: "latest" },
                },
              },
            ],
          },
        ],
      },
    },
    { ignoreChanges: ["template.containers[0].image"] },
  );

  // ============================================================================
  // featbit-ui — Nginx SPA (depends on API + Eval URLs for env vars)
  // ============================================================================

  const uiService = new gcp.cloudrunv2.Service(
    `${prefix}-ui-run`,
    {
      project: projectId,
      name: `${servicePrefix}-featbit-ui`,
      location: region,
      deletionProtection: false,
      ingress: "INGRESS_TRAFFIC_ALL",
      template: {
        serviceAccount: uiSa.email,
        scaling: {
          minInstanceCount: 0,
          maxInstanceCount: 2,
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
            image: `featbit/featbit-ui:${FEATBIT_IMAGE_TAGS.ui}`,
            ports: { containerPort: 80 },
            resources: {
              limits: { memory: "256Mi", cpu: "1" },
            },
            envs: [
              // In V2 without GLB, use the Cloud Run URLs directly.
              // These are overridden at deploy time if a custom domain is configured.
              { name: "API_URL", value: apiService.uri },
              { name: "EVALUATION_URL", value: evalService.uri },
              { name: "DEMO_URL", value: "" },
              { name: "BASE_HREF", value: "/" },
            ],
          },
        ],
      },
    },
    { ignoreChanges: ["template.containers[0].image"] },
  );

  // ============================================================================
  // IAM — Make FeatBit services publicly accessible (no IAP in V2 sandbox)
  // ============================================================================

  for (const { service, name } of [
    { service: uiService, name: "ui" },
    { service: apiService, name: "api" },
    { service: evalService, name: "eval" },
  ]) {
    new gcp.cloudrunv2.ServiceIamMember(`${prefix}-${name}-public`, {
      project: projectId,
      location: region,
      name: service.name,
      role: "roles/run.invoker",
      member: "allUsers",
    });
  }

  // ============================================================================
  // IAM — API Server SA invokes DA Server (for OLAP HTTP calls)
  // ============================================================================

  new gcp.cloudrunv2.ServiceIamMember(
    `${prefix}-api-to-da-invoker`,
    {
      name: daService.name,
      project: projectId,
      location: region,
      role: "roles/run.invoker",
      member: pulumi.interpolate`serviceAccount:${apiSa.email}`,
    },
    { dependsOn: [apiService, daService] },
  );

  return {
    uiUrl: uiService.uri,
    apiUrl: apiService.uri,
    evalUrl: evalService.uri,
    daUrl: daService.uri,
  };
}
