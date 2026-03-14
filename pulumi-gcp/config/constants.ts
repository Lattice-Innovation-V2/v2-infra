export const DEFAULT_REGION = "us-central1";
export const GITHUB_ORG = "Lattice-Innovation-V2";
export const GITHUB_OIDC_ISSUER = "https://token.actions.githubusercontent.com";

export const IAP_SOURCE_RANGES = ["35.235.240.0/20"];
export const HEALTH_CHECK_SOURCE_RANGES = ["35.191.0.0/16", "130.211.0.0/22"];
export const INTERNAL_RANGES = [
  "10.0.0.0/8",
  "172.16.0.0/12",
  "192.168.0.0/16",
];

export const POSTGRES_FLAGS: Array<{ name: string; value: string }> = [
  { name: "cloudsql.iam_authentication", value: "on" },
  { name: "log_statement", value: "all" },
  { name: "log_min_duration_statement", value: "1000" },
];

export const ENV_SERVICE_PREFIX: Record<string, string> = {
  dev: "linno-v2-dev",
  "preview-a": "linno-v2-pa",
  "preview-b": "linno-v2-pb",
};

export const COMMON_APIS = [
  "compute.googleapis.com",
  "run.googleapis.com",
  "sqladmin.googleapis.com",
  "secretmanager.googleapis.com",
  "artifactregistry.googleapis.com",
  "iam.googleapis.com",
  "cloudresourcemanager.googleapis.com",
  "servicenetworking.googleapis.com",
  "redis.googleapis.com",
];
