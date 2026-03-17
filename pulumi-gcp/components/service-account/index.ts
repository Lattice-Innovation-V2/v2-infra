import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ServiceAccountArgs {
  environment: string;
  projectId: string;
  purpose: string;
  description?: string;
  /** When true, import existing GCP resources instead of creating new ones. */
  importExisting?: boolean;
}

export class ServiceAccount extends pulumi.ComponentResource {
  public readonly email: pulumi.Output<string>;
  public readonly id: pulumi.Output<string>;

  constructor(
    name: string,
    args: ServiceAccountArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("v2:iam:ServiceAccount", name, {}, opts);

    const { environment, projectId, purpose, description, importExisting } = args;
    const importId = (id: string) => importExisting ? id : undefined;

    const saAccountId = `${environment}-${purpose}-sa`;
    const account = new gcp.serviceaccount.Account(
      `${environment}-${purpose}-sa`,
      {
        project: projectId,
        accountId: saAccountId,
        displayName:
          description || `${environment} ${purpose} service account`,
      },
      { parent: this, import: importId(`projects/${projectId}/serviceAccounts/${saAccountId}@${projectId}.iam.gserviceaccount.com`) },
    );

    this.email = account.email;
    this.id = account.id;

    this.registerOutputs({
      email: this.email,
      id: this.id,
    });
  }
}
