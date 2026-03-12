import * as pulumi from "@pulumi/pulumi";
import { Vpc } from "../../components/vpc";
import { Firewall } from "../../components/firewall";
import { getEnvironmentConfig } from "../../config/environments";

const stack = pulumi.getStack();
const envConfig = getEnvironmentConfig(stack);

const gcpConfig = new pulumi.Config("gcp");
const projectId = gcpConfig.require("project");
const region = gcpConfig.require("region");

// VPC + Subnet + Cloud Router + NAT + Private Service Connection
const vpc = new Vpc("v2-vpc", {
  environment: stack,
  projectId: projectId,
  region: region,
  subnetCidr: envConfig.network.subnetCidr,
  description: `Lattice V2 ${stack} VPC`,
});

// Firewall rules (IAP SSH, internal, health checks)
new Firewall("v2-firewall", {
  environment: stack,
  projectId: projectId,
  networkId: vpc.vpcId,
});

// Stack outputs for cross-stack references
export const vpcId = vpc.vpcId;
export const vpcName = vpc.vpcName;
export const vpcSelfLink = vpc.vpcSelfLink;
export const subnetId = vpc.subnetId;
export const subnetName = vpc.subnetName;
export const privateIpRangeName = vpc.privateIpRangeName;
export const privateConnectionId = vpc.privateConnectionId;
