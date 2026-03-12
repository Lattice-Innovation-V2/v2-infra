export interface EnvironmentConfig {
  projectId: string;
  region: string;
  cloudSql: {
    tier: string;
    diskSizeGb: number;
    availabilityType: string;
    pointInTimeRecovery: boolean;
    deletionProtection: boolean;
  };
  redis: {
    tier: string;
    memorySizeGb: number;
  };
  network: {
    subnetCidr: string;
  };
  scaling: {
    minInstances: number;
    maxInstances: number;
  };
}

export const environments: Record<string, EnvironmentConfig> = {
  dev: {
    projectId: "lattice-innovation-v2",
    region: "us-central1",
    cloudSql: {
      tier: "db-f1-micro",
      diskSizeGb: 10,
      availabilityType: "ZONAL",
      pointInTimeRecovery: false,
      deletionProtection: false,
    },
    redis: { tier: "BASIC", memorySizeGb: 1 },
    network: { subnetCidr: "10.10.0.0/24" },
    scaling: { minInstances: 0, maxInstances: 10 },
  },
};

export function getEnvironmentConfig(env: string): EnvironmentConfig {
  const config = environments[env];
  if (!config) throw new Error(`Unknown environment: ${env}`);
  return config;
}
