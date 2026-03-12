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
    healthPath: "/q/health",
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
    healthPath: "/q/health",
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
    healthPath: "/q/health",
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
    healthPath: "/q/health",
  },
  {
    name: "reporting-api",
    runtime: "quarkus",
    containerPort: 8080,
    database: "lattice_v2",
    schema: "payment_txn",
    hasDatabase: true,
    hasRedis: true,
    isPublic: true,
    pathPrefix: "/v1/reporting",
    healthPath: "/q/health",
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
    healthPath: "/q/health",
  },
  {
    name: "integrator-portal",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    backendDependencies: [
      "integrator-service",
      "merchant-service",
      "payment-config-service",
      "reporting-api",
    ],
  },
  {
    name: "merchant-console",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    backendDependencies: [
      "payment-runtime-service",
      "payment-config-service",
      "integrator-service",
    ],
  },
  {
    name: "admin-console",
    runtime: "nextjs",
    containerPort: 8080,
    hasDatabase: false,
    hasRedis: false,
    isPublic: true,
    backendDependencies: [
      "integrator-service",
      "merchant-service",
      "payment-config-service",
      "brand-registry",
      "reporting-api",
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
    backendDependencies: ["payment-runtime-service"],
  },
];
