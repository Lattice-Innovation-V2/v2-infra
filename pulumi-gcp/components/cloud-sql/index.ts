import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface CloudSqlArgs {
  environment: string;
  projectId: string;
  region: string;
  vpcId: pulumi.Input<string>;
  vpcSelfLink: pulumi.Input<string>;
  privateConnectionId: pulumi.Input<string>;
  tier: string;
  diskSizeGb: number;
  availabilityType: string;
  pointInTimeRecovery: boolean;
  deletionProtection: boolean;
  databaseFlags?: Array<{ name: string; value: string }>;
  /** When true, import existing GCP resources instead of creating new ones. */
  importExisting?: boolean;
}

export class CloudSql extends pulumi.ComponentResource {
  public readonly instanceName: pulumi.Output<string>;
  public readonly connectionName: pulumi.Output<string>;
  public readonly privateIpAddress: pulumi.Output<string>;

  constructor(
    name: string,
    args: CloudSqlArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("v2:data:CloudSql", name, {}, opts);

    const {
      environment,
      projectId,
      region,
      vpcSelfLink,
      privateConnectionId,
      tier,
      diskSizeGb,
      availabilityType,
      pointInTimeRecovery,
      deletionProtection,
      databaseFlags,
      importExisting,
    } = args;

    const prefix = `v2-${environment}`;
    const importId = (id: string) => importExisting ? id : undefined;

    // Cloud SQL PostgreSQL 15 instance
    const instance = new gcp.sql.DatabaseInstance(
      `${prefix}-postgres`,
      {
        project: projectId,
        name: `${prefix}-postgres`,
        region: region,
        databaseVersion: "POSTGRES_15",
        deletionProtection: deletionProtection,
        settings: {
          tier: tier,
          diskSize: diskSizeGb,
          diskType: "PD_SSD",
          diskAutoresize: true,
          availabilityType: availabilityType,
          ipConfiguration: {
            ipv4Enabled: false,
            privateNetwork: vpcSelfLink,
            sslMode: "ENCRYPTED_ONLY",
          },
          backupConfiguration: {
            enabled: true,
            startTime: "03:00",
            pointInTimeRecoveryEnabled: pointInTimeRecovery,
            backupRetentionSettings: {
              retainedBackups: 7,
              retentionUnit: "COUNT",
            },
          },
          databaseFlags: (databaseFlags || []).map((flag) => ({
            name: flag.name,
            value: flag.value,
          })),
          maintenanceWindow: {
            day: 7, // Sunday
            hour: 4, // 4 AM UTC
            updateTrack: "stable",
          },
          insightsConfig: {
            queryInsightsEnabled: true,
            queryStringLength: 1024,
            recordApplicationTags: true,
            recordClientAddress: false,
          },
        },
      },
      {
        parent: this,
        import: importId(`projects/${projectId}/instances/${prefix}-postgres`),
        customTimeouts: {
          create: "30m",
          update: "30m",
          delete: "30m",
        },
      },
    );

    this.instanceName = instance.name;
    this.connectionName = instance.connectionName;
    this.privateIpAddress = instance.privateIpAddress;

    this.registerOutputs({
      instanceName: this.instanceName,
      connectionName: this.connectionName,
      privateIpAddress: this.privateIpAddress,
    });
  }
}
