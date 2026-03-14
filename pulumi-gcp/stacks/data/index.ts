import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import * as random from "@pulumi/random";
import { CloudSql } from "../../components/cloud-sql";
import { getEnvironmentConfig } from "../../config/environments";
import { POSTGRES_FLAGS } from "../../config/constants";
import { FEATBIT_DB_NAME, FEATBIT_DB_USER } from "../../config/featbit";

const stack = pulumi.getStack();
const envConfig = getEnvironmentConfig(stack);

const gcpConfig = new pulumi.Config("gcp");
const projectId = gcpConfig.require("project");
const region = gcpConfig.require("region");

const dataConfig = new pulumi.Config("data");
const networkingStackName = dataConfig.require("networkingStack");

// Reference networking stack outputs
const networkingStack = new pulumi.StackReference(networkingStackName);
const vpcId = networkingStack.getOutput("vpcId") as pulumi.Output<string>;
const vpcSelfLink = networkingStack.getOutput(
  "vpcSelfLink",
) as pulumi.Output<string>;
const privateConnectionId = networkingStack.getOutput(
  "privateConnectionId",
) as pulumi.Output<string>;

// Cloud SQL instance
const cloudSql = new CloudSql("v2-cloudsql", {
  environment: stack,
  projectId: projectId,
  region: region,
  vpcId: vpcId,
  vpcSelfLink: vpcSelfLink,
  privateConnectionId: privateConnectionId,
  tier: envConfig.cloudSql.tier,
  diskSizeGb: envConfig.cloudSql.diskSizeGb,
  availabilityType: envConfig.cloudSql.availabilityType,
  pointInTimeRecovery: envConfig.cloudSql.pointInTimeRecovery,
  deletionProtection: envConfig.cloudSql.deletionProtection,
  databaseFlags: POSTGRES_FLAGS,
});

// Create the lattice_v2 database
const database = new gcp.sql.Database(
  `${stack}-lattice-v2-db`,
  {
    project: projectId,
    name: "lattice_v2",
    instance: cloudSql.instanceName,
    charset: "UTF8",
    collation: "en_US.UTF8",
  },
  { dependsOn: [cloudSql] },
);

// Create preview environment databases on the same Cloud SQL instance
const databasePa = new gcp.sql.Database(
  `${stack}-lattice-v2-pa-db`,
  {
    project: projectId,
    name: "lattice_v2_pa",
    instance: cloudSql.instanceName,
    charset: "UTF8",
    collation: "en_US.UTF8",
  },
  { dependsOn: [cloudSql] },
);

const databasePb = new gcp.sql.Database(
  `${stack}-lattice-v2-pb-db`,
  {
    project: projectId,
    name: "lattice_v2_pb",
    instance: cloudSql.instanceName,
    charset: "UTF8",
    collation: "en_US.UTF8",
  },
  { dependsOn: [cloudSql] },
);

// IAM DB users are created in the apps stack (after service accounts exist).
// The github-actions SA DB user is also created there.

// ============================================================================
// FeatBit Database, User & Secrets
// ============================================================================
// FeatBit (feature flag platform) uses a dedicated database and built-in user
// on the shared Cloud SQL instance. Fully isolated from payment databases.

const featbitEnabled = dataConfig.getBoolean("featbitEnabled") ?? false;

const featbitDb = featbitEnabled
  ? new gcp.sql.Database(
      `${stack}-featbit-db`,
      {
        name: FEATBIT_DB_NAME,
        instance: cloudSql.instanceName,
        project: projectId,
      },
      { dependsOn: [cloudSql] },
    )
  : undefined;

const featbitDbPassword = featbitEnabled
  ? new random.RandomPassword(`${stack}-featbit-db-password`, {
      length: 24,
      special: false,
    })
  : undefined;

const featbitDbUser =
  featbitEnabled && featbitDb && featbitDbPassword
    ? new gcp.sql.User(
        `${stack}-featbit-db-user`,
        {
          name: FEATBIT_DB_USER,
          instance: cloudSql.instanceName,
          project: projectId,
          password: featbitDbPassword.result,
          type: "BUILT_IN",
          deletionPolicy: "ABANDON",
        },
        { dependsOn: [cloudSql, featbitDb] },
      )
    : undefined;

// Password secret — used by the DA server (individual env vars, not a connection string)
const featbitDbPasswordSecret =
  featbitEnabled && featbitDbPassword
    ? new gcp.secretmanager.Secret(`${stack}-featbit-db-password`, {
        secretId: `${stack}-featbit-db-password`,
        project: projectId,
        replication: { auto: {} },
      })
    : undefined;

if (featbitDbPasswordSecret && featbitDbPassword) {
  new gcp.secretmanager.SecretVersion(`${stack}-featbit-db-password-v1`, {
    secret: featbitDbPasswordSecret.id,
    secretData: featbitDbPassword.result,
  });
}

// Connection string secret — used by API Server and Evaluation Server (.NET Npgsql format)
const featbitConnStringSecret =
  featbitEnabled && featbitDbPassword
    ? new gcp.secretmanager.Secret(`${stack}-featbit-conn-string`, {
        secretId: `${stack}-featbit-conn-string`,
        project: projectId,
        replication: { auto: {} },
      })
    : undefined;

if (featbitConnStringSecret && featbitDbPassword) {
  new gcp.secretmanager.SecretVersion(`${stack}-featbit-conn-string-v1`, {
    secret: featbitConnStringSecret.id,
    secretData: pulumi.interpolate`Host=${cloudSql.privateIpAddress};Port=5432;Username=${FEATBIT_DB_USER};Password=${featbitDbPassword.result};Database=${FEATBIT_DB_NAME};SSL Mode=Prefer`,
  });
}

// Stack outputs
export const cloudSqlInstanceName = cloudSql.instanceName;
export const cloudSqlConnectionName = cloudSql.connectionName;
export const cloudSqlPrivateIp = cloudSql.privateIpAddress;
export const databaseName = pulumi.output("lattice_v2");
export const databaseNamePa = pulumi.output("lattice_v2_pa");
export const databaseNamePb = pulumi.output("lattice_v2_pb");

// FeatBit secrets (referenced by apps stack when featbit is enabled)
export const featbitConnStringSecretId = featbitConnStringSecret?.secretId;
export const featbitDbPasswordSecretId = featbitDbPasswordSecret?.secretId;
