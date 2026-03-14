/**
 * FeatBit configuration constants.
 *
 * FeatBit is an internal developer tool (feature flag platform), not a LatticePay microservice.
 * Defined separately from MICROSERVICES to keep tooling concerns isolated from payment services.
 */

export const FEATBIT_DB_NAME = "featbit";
export const FEATBIT_DB_USER = "featbit_user";

/** Pinned FeatBit image versions for reproducibility. Update via config when upgrading. */
export const FEATBIT_IMAGE_TAGS = {
  api: "5.2.4",
  ui: "5.2.4",
  eval: "5.2.4",
  da: "5.2.4",
} as const;
