export interface MicroserviceConfig {
  name: string;
  runtime: "quarkus" | "nextjs";
  containerPort: number;
  database?: string;
  schema?: string;
  hasDatabase: boolean;
  hasRedis: boolean;
  isPublic: boolean;
  pathPrefix?: string;
  backendDependencies?: string[];
  healthPath?: string;
}

export const MICROSERVICES: MicroserviceConfig[] = [
  {
    name: "integrator-service",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "integrator_mgmt",
    hasDatabase: true,
    hasRedis: false,
    isPublic: true,
    pathPrefix: "/v1/integrator-service",
    healthPath: "/v1/integrator-service/q/health",
  },
  {
    name: "merchant-service",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "merchant_mgmt",
    hasDatabase: true,
    hasRedis: false,
    isPublic: true,
    pathPrefix: "/v1/merchant-service",
    healthPath: "/v1/merchant-service/q/health",
  },
  {
    name: "payment-config-service",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "payment_config",
    hasDatabase: true,
    hasRedis: false,
    isPublic: true,
    pathPrefix: "/v1/payment-config-service",
    healthPath: "/v1/payment-config-service/health",
  },
  {
    name: "payment-runtime-service",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "payment_txn",
    hasDatabase: true,
    hasRedis: false,
    isPublic: true,
    pathPrefix: "/v1/payment-runtime-service",
    healthPath: "/v1/payment-runtime-service/health",
  },
  {
    name: "reporting-service",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "payment_txn",
    hasDatabase: true,
    hasRedis: true,
    isPublic: true,
    pathPrefix: "/v1/reporting",
    healthPath: "/v1/reporting/health",
  },
  {
    name: "brand-registry",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "brand_registry",
    hasDatabase: true,
    hasRedis: false,
    isPublic: true,
    pathPrefix: "/v1/brand-registry",
    healthPath: "/v1/brand-registry/q/health",
  },
  // --- Frontends ---
  {
    name: "integrator-portal",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    healthPath: "/api/health",
    backendDependencies: [
      "integrator-service",
      "merchant-service",
      "payment-config-service",
      "payment-runtime-service",
      "reporting-service",
    ],
  },
  {
    name: "admin-console",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    healthPath: "/api/health",
    backendDependencies: [
      "integrator-service",
      "merchant-service",
      "payment-config-service",
      "brand-registry",
      "reporting-service",
      "payment-runtime-service",
    ],
  },
  {
    name: "demo",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    healthPath: "/api/health",
    backendDependencies: ["payment-runtime-service"],
  },
  {
    name: "merchant-console-widget",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    healthPath: "/api/health",
    backendDependencies: [
      "merchant-service",
      "payment-config-service",
      "payment-runtime-service",
    ],
  },
  {
    name: "checkout-widget",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    healthPath: "/api/health",
    backendDependencies: [
      "payment-runtime-service",
      "payment-config-service",
    ],
  },
  // connector-library is an SDK (npm package), not a deployed service.
];
