import * as pulumi from "@pulumi/pulumi";
import * as gcp from "@pulumi/gcp";
import {
  IAP_SOURCE_RANGES,
  INTERNAL_RANGES,
  HEALTH_CHECK_SOURCE_RANGES,
} from "../../config/constants";

export interface FirewallArgs {
  environment: string;
  projectId: string;
  networkId: pulumi.Input<string>;
  importExisting?: boolean;
}

export class Firewall extends pulumi.ComponentResource {
  constructor(
    name: string,
    args: FirewallArgs,
    opts?: pulumi.ComponentResourceOptions,
  ) {
    super("v2:networking:Firewall", name, {}, opts);

    const { environment, projectId, networkId, importExisting } = args;
    const prefix = `v2-${environment}`;
    const importId = (id: string) => importExisting ? id : undefined;

    // IAP SSH access
    new gcp.compute.Firewall(
      `${prefix}-allow-iap-ssh`,
      {
        project: projectId,
        name: `${prefix}-allow-iap-ssh`,
        network: networkId,
        direction: "INGRESS",
        priority: 1000,
        sourceRanges: IAP_SOURCE_RANGES,
        allows: [
          {
            protocol: "tcp",
            ports: ["22"],
          },
        ],
        description: "Allow SSH via Identity-Aware Proxy",
      },
      { parent: this, import: importId(`projects/${projectId}/global/firewalls/${prefix}-allow-iap-ssh`) },
    );

    // Internal traffic
    new gcp.compute.Firewall(
      `${prefix}-allow-internal`,
      {
        project: projectId,
        name: `${prefix}-allow-internal`,
        network: networkId,
        direction: "INGRESS",
        priority: 1000,
        sourceRanges: INTERNAL_RANGES,
        allows: [
          { protocol: "tcp", ports: ["0-65535"] },
          { protocol: "udp", ports: ["0-65535"] },
          { protocol: "icmp" },
        ],
        description: "Allow internal VPC traffic",
      },
      { parent: this, import: importId(`projects/${projectId}/global/firewalls/${prefix}-allow-internal`) },
    );

    // Health check traffic
    new gcp.compute.Firewall(
      `${prefix}-allow-health-checks`,
      {
        project: projectId,
        name: `${prefix}-allow-health-checks`,
        network: networkId,
        direction: "INGRESS",
        priority: 1000,
        sourceRanges: HEALTH_CHECK_SOURCE_RANGES,
        allows: [
          {
            protocol: "tcp",
            ports: ["8080"],
          },
        ],
        description: "Allow GCP health check probes",
      },
      { parent: this, import: importId(`projects/${projectId}/global/firewalls/${prefix}-allow-health-checks`) },
    );

    this.registerOutputs({});
  }
}
