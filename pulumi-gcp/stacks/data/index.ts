import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import { CloudSql } from "../../components/cloud-sql";
import { getEnvironmentConfig } from "../../config/environments";
import { POSTGRES_FLAGS } from "../../config/constants";

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

// IAM DB users are created in the apps stack (after service accounts exist).
// The github-actions SA DB user is also created there.

// Stack outputs
export const cloudSqlInstanceName = cloudSql.instanceName;
export const cloudSqlConnectionName = cloudSql.connectionName;
export const cloudSqlPrivateIp = cloudSql.privateIpAddress;
export const databaseName = pulumi.output("lattice_v2");
