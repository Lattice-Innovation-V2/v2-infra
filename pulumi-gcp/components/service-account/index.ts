import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface ServiceAccountArgs {
  environment: string;
  projectId: string;
  purpose: string;
  description?: string;
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

    const { environment, projectId, purpose, description } = args;

    const account = new gcp.serviceaccount.Account(
      `${environment}-${purpose}-sa`,
      {
        project: projectId,
        accountId: `${environment}-${purpose}-sa`,
        displayName:
          description || `${environment} ${purpose} service account`,
      },
      { parent: this },
    );

    this.email = account.email;
    this.id = account.id;

    this.registerOutputs({
      email: this.email,
      id: this.id,
    });
  }
}
