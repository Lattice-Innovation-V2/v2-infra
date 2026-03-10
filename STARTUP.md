# V2 Service Startup Order

## Prerequisites

1. **PostgreSQL** — running on localhost:5432 (Homebrew)
   ```bash
   brew services start postgresql@17
   ```

2. **Database** — create and initialize
   ```bash
   createdb lattice_v2
   psql -d lattice_v2 -f v2-infra/init-db.sql
   ```

3. **Redis** (optional, for caching) — via Docker
   ```bash
   cd v2-infra && docker compose up -d redis
   ```

## Backend Services (start in this order)

Backends must start before frontends since frontends proxy API calls.

| Order | Service | Port | Command | Notes |
|-------|---------|------|---------|-------|
| 1 | integrator-service | 8080 | `cd v2-payment-admin-services && ./mvnw quarkus:dev -pl integrator-service` | No dependencies on other services |
| 2 | merchant-service | 8081 | `cd v2-payment-admin-services && ./mvnw quarkus:dev -pl merchant-service` | No dependencies on other services |
| 3 | payment-config-service | 8082 | `cd v2-payment-config-service && ./mvnw quarkus:dev` | No dependencies on other services |
| 4 | payment-runtime-service | 8083 | `cd v2-payment-runtime-service && ./mvnw quarkus:dev` | Calls config-service (8082) for resolved configs |
| 5 | brand-registry | 8085 | `cd v2-brand-registry && ./mvnw quarkus:dev` | No dependencies on other services |
| 6 | reporting-api | 8084 | `cd v2-reporting-api && ./mvnw quarkus:dev` | Reads from BigQuery (stubs in dev) |

Services 1-3 and 5-6 are independent and can start in parallel. Service 4 (payment-runtime) benefits from config-service being up first but will retry on failure.

## Frontend Applications (start after backends)

All frontends can start in parallel.

| Service | Port | Command | Backend Dependencies |
|---------|------|---------|---------------------|
| integrator-portal | 3000 | `cd v2-integrator-portal && npm run dev` | 8080, 8081, 8082, 8083, 8084 |
| merchant-console | 3001 | `cd v2-merchant-console && npm run dev` | 8080, 8081, 8082, 8083 |
| admin-console | 3002 | `cd v2-admin-console && npm run dev` | 8080, 8081, 8082, 8083, 8084, 8085 |
| demo | 3003 | `cd v2-demo && npm run dev` | 8083 (widget serving) |

## Quick Start (minimum for development)

For most frontend work, you only need:

```bash
# Terminal 1: integrator + merchant services
cd v2-payment-admin-services && ./mvnw quarkus:dev -pl integrator-service

# Terminal 2: merchant service
cd v2-payment-admin-services && ./mvnw quarkus:dev -pl merchant-service

# Terminal 3: your frontend
cd v2-integrator-portal && npm run dev
```

Pages that call unavailable backends will show error states but won't crash.

## Health Checks

Each backend exposes health at `/q/health/ready`:

```bash
curl -s localhost:8080/q/health/ready | jq .status
curl -s localhost:8081/q/health/ready | jq .status
curl -s localhost:8082/q/health/ready | jq .status
curl -s localhost:8083/q/health/ready | jq .status
curl -s localhost:8084/q/health/ready | jq .status
curl -s localhost:8085/q/health/ready | jq .status
```
