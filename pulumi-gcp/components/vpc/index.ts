import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";

export interface VpcArgs {
  environment: string;
  projectId: string;
  region: string;
  subnetCidr: string;
  description?: string;
}

export class Vpc extends pulumi.ComponentResource {
  public readonly vpcId: pulumi.Output<string>;
  public readonly vpcName: pulumi.Output<string>;
  public readonly vpcSelfLink: pulumi.Output<string>;
  public readonly subnetId: pulumi.Output<string>;
  public readonly subnetName: pulumi.Output<string>;
  public readonly privateIpRangeName: pulumi.Output<string>;
  public readonly privateConnectionId: pulumi.Output<string>;

  constructor(
    name: string,
    args: VpcArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("v2:networking:Vpc", name, {}, opts);

    const { environment, projectId, region, subnetCidr, description } = args;
    const prefix = `v2-${environment}`;

    // VPC Network
    const network = new gcp.compute.Network(
      `${prefix}-vpc`,
      {
        project: projectId,
        name: `${prefix}-vpc`,
        autoCreateSubnetworks: false,
        description: description || `V2 ${environment} VPC`,
      },
      { parent: this },
    );

    // Subnet with Private Google Access
    const subnet = new gcp.compute.Subnetwork(
      `${prefix}-subnet`,
      {
        project: projectId,
        name: `${prefix}-subnet`,
        network: network.id,
        region: region,
        ipCidrRange: subnetCidr,
        privateIpGoogleAccess: true,
      },
      { parent: this },
    );

    // Cloud Router (for Cloud NAT)
    const router = new gcp.compute.Router(
      `${prefix}-router`,
      {
        project: projectId,
        name: `${prefix}-router`,
        network: network.id,
        region: region,
      },
      { parent: this },
    );

    // Cloud NAT (egress for private instances)
    new gcp.compute.RouterNat(
      `${prefix}-nat`,
      {
        project: projectId,
        name: `${prefix}-nat`,
        router: router.name,
        region: region,
        natIpAllocateOption: "AUTO_ONLY",
        sourceSubnetworkIpRangesToNat: "ALL_SUBNETWORKS_ALL_IP_RANGES",
        logConfig: {
          enable: true,
          filter: "ERRORS_ONLY",
        },
      },
      { parent: this },
    );

    // Private IP range for VPC peering (Cloud SQL, Redis, etc.)
    const privateIpRange = new gcp.compute.GlobalAddress(
      `${prefix}-private-ip-range`,
      {
        project: projectId,
        name: `${prefix}-private-ip-range`,
        purpose: "VPC_PEERING",
        addressType: "INTERNAL",
        prefixLength: 16,
        network: network.id,
      },
      { parent: this },
    );

    // Private service connection (servicenetworking.googleapis.com)
    const privateConnection =
      new gcp.servicenetworking.Connection(
        `${prefix}-private-connection`,
        {
          network: network.id,
          service: "servicenetworking.googleapis.com",
          reservedPeeringRanges: [privateIpRange.name],
        },
        { parent: this },
      );

    this.vpcId = network.id;
    this.vpcName = network.name;
    this.vpcSelfLink = network.selfLink;
    this.subnetId = subnet.id;
    this.subnetName = subnet.name;
    this.privateIpRangeName = privateIpRange.name;
    this.privateConnectionId = privateConnection.id;

    this.registerOutputs({
      vpcId: this.vpcId,
      vpcName: this.vpcName,
      vpcSelfLink: this.vpcSelfLink,
      subnetId: this.subnetId,
      subnetName: this.subnetName,
      privateIpRangeName: this.privateIpRangeName,
      privateConnectionId: this.privateConnectionId,
    });
  }
}
