# Lattice Pay V2 — Transition Package

> Context package for AI assistants picking up work on the V2 platform.
> Generated 2026-03-12.

---

## 1. What Is This Project?

Lattice Pay V2 is a **microservices payment platform** being migrated from V1 (`dan-innovation`) to adopt production patterns from `latticeorg`. It's an **innovation sandbox** — the goal is for features proven here to be cherry-picked into latticeorg with minimal adaptation.

**15 repositories** under `dan-innovation-v2/`, all in the `Lattice-Innovation-V2` GitHub org:

| Repo | Type | Port | Purpose |
|------|------|------|---------|
| `v2-integrator-service` | Quarkus backend | 10200 | Integrator management |
| `v2-merchant-service` | Quarkus backend | 10201 | Merchant management |
| `v2-payment-config-service` | Quarkus backend | 10202 | PSP catalog, payment configs |
| `v2-payment-runtime-service` | Quarkus backend | 10203 | Transaction processing + widget serving |
| `v2-reporting-service` | Quarkus backend | 10204 | Reporting (PostgreSQL, future BigQuery) |
| `v2-brand-registry` | Quarkus backend | 10205 | Brand management |
| `v2-payment-mcp` | Quarkus backend | 10206 | Payment MCP server (AI/LLM) |
| `v2-agentic-api` | Quarkus backend | 10207 | Agentic financial API |
| `v2-integrator-portal` | Next.js frontend | 10210 | Integrator dashboard |
| `v2-merchant-console` | Next.js frontend | 10211 | Merchant checkout builder |
| `v2-admin-console` | Next.js frontend | 10212 | Platform admin |
| `v2-demo` | Next.js frontend | 10213 | Demo apps (fashion, POS, etc.) |
| `v2-shared-security` | Quarkus extension | N/A | Shared auth library (latticepay-security) |
| `v2-payment-admin-services` | Quarkus multi-module | 10200/10201 | Legacy multi-module (same as standalone) |
| `v2-infra` | Infrastructure | N/A | Docker Compose, init SQL, CI/CD workflows, Pulumi |

---

## 2. Tech Stack

### Backends
- **Quarkus 3.31.2**, Java 21, Maven
- **PostgreSQL** (multi-schema: integrator_mgmt, merchant_mgmt, payment_config, payment_txn, identity_mgmt, shared, brand_registry)
- **Liquibase** for migrations (disabled in dev — schemas managed by `v2-infra/init-lattice-v2.sql`)
- **MapStruct 1.6.3** for entity↔DTO mapping
- **latticepay-security 0.6.4** — shared Quarkus extension for auth (OIDC hybrid tenant resolver)
- **RFC 9457** Problem Details via `quarkus-resteasy-problem`
- No Lombok — Java Records for DTOs, standard POJOs for entities

### Frontends
- **Next.js 15**, Node 22+, TypeScript
- **BFF proxy pattern** — all backend calls through `src/app/api/` Route Handlers
- **Circuit breakers** per backend service
- **CSP nonce injection** per request in middleware
- **Zod** for env validation, **Pino** for logging, **shadcn-style** UI components

### Infrastructure
- **GCP Project**: `lattice-innovation-v2` (497764988925), region `us-central1`
- **Cloud Run** for all services (prefix: `linno-v2-*`)
- **Cloud SQL** (PostgreSQL, private IP only, VPC-connected)
- **Artifact Registry**: `us-central1-docker.pkg.dev/lattice-innovation-v2/v2-images`
- **CI/CD**: GitHub Actions with reusable workflows in `v2-infra/.github/workflows/`
- **Auth**: Workload Identity Federation (no service account keys)

---

## 3. Authentication Architecture

### How Auth Works

```
Frontend (Next.js middleware)
  ├── Production: Google Cloud IAP verifies x-goog-iap-jwt-assertion
  └── V2 Sandbox (BYPASS_IAP=true): middleware generates dev JWT
        signed with test-privateKey.pem
                    ↓
BFF Route Handler (src/app/api/*)
  - withRequireIntegrator() validates auth context
  - buildProxyHeaders() adds Authorization Bearer + identity token
                    ↓
Backend (Quarkus, latticepay-security)
  - HybridTenantConfigResolver selects OIDC tenant:
    IAP → Forwarded-Auth → Dev → WIF → GCIP
  - Dev tenant verifies JWT against test-publicKey.pem
  - CallerScope (immutable record) built from JWT claims
  - CallerScopeResolvingFilter populates RequestCallerScope
```

### Key Config (every backend `application.properties`)
```properties
# Production (Cloud Run) — dev tenant with restrict-to-dev-profile=false
%prod.latticepay.security.dev.enabled=true
%prod.latticepay.security.dev.issuer=https://dev.issuer.local
%prod.latticepay.security.dev.public-key-location=test-publicKey.pem
%prod.latticepay.security.dev.restrict-to-dev-profile=false
%prod.latticepay.security.iap.enabled=false
%prod.latticepay.security.gcip.enabled=false
```

**CRITICAL RULES:**
- JWT is ALWAYS enforced, even in dev. Dev uses test PEM keypair, not disabled security.
- Never "fix" auth by disabling it.
- The `restrict-to-dev-profile=false` flag is intentional for V2 sandbox — it allows the dev tenant to work outside Quarkus dev mode.
- `test-publicKey.pem` and `test-privateKey.pem` exist in all backend `src/main/resources/`.

---

## 4. Deployment Status (as of 2026-03-12)

All 10 services deployed to Cloud Run under the `linno-v2-*` prefix:

| Service | URL | Status |
|---------|-----|--------|
| integrator-service | `https://linno-v2-integrator-service-lvwlxumqfa-uc.a.run.app` | UP |
| merchant-service | `https://linno-v2-merchant-service-lvwlxumqfa-uc.a.run.app` | UP |
| payment-config-service | `https://linno-v2-payment-config-service-lvwlxumqfa-uc.a.run.app` | UP |
| payment-runtime-service | `https://linno-v2-payment-runtime-service-lvwlxumqfa-uc.a.run.app` | UP |
| reporting-api | `https://linno-v2-reporting-service-lvwlxumqfa-uc.a.run.app` | UP |
| brand-registry | `https://linno-v2-brand-registry-lvwlxumqfa-uc.a.run.app` | UP |
| integrator-portal | `https://linno-v2-integrator-portal-lvwlxumqfa-uc.a.run.app` | UP |
| merchant-console | `https://linno-v2-merchant-console-lvwlxumqfa-uc.a.run.app` | UP |
| admin-console | `https://linno-v2-admin-console-lvwlxumqfa-uc.a.run.app` | UP |
| demo | `https://linno-v2-demo-lvwlxumqfa-uc.a.run.app` | UP |

**Note:** Cloud Run URLs contain a hash (`lvwlxumqfa`) that changes on redeployment. Use `gcloud run services describe <name> --format="value(status.url)"` to get the current URL.

### Cloud SQL
- Instance: `v2-dev-postgres` (private IP only: `10.232.0.3`)
- Database: `lattice_v2`
- App user: `v2_app` (password in Secret Manager `DB_PASSWORD`)
- Admin user: `postgres` (password: `v2-postgres-admin-2026`)
- **Public IP is disabled** — access only via VPC or Cloud SQL Auth Proxy
- Seed data fully loaded (2 integrators, 11 merchants, 16 PSPs, 53 transactions, etc.)

### Frontend Env Vars (Cloud Run)
```
BYPASS_IAP=true                    # No GLB/IAP in V2 sandbox
INTEGRATOR_API_URL=https://linno-v2-integrator-service-...
MERCHANT_API_URL=https://linno-v2-merchant-service-...
PAYMENT_CONFIG_API_URL=https://linno-v2-payment-config-service-...
PAYMENT_RUNTIME_API_URL=https://linno-v2-payment-runtime-service-...
REPORTING_API_URL=https://linno-v2-reporting-service-...
```

---

## 5. Local Development Setup

### Prerequisites
- Java 21 (eclipse-temurin)
- Node 22+
- PostgreSQL (Homebrew or Docker)
- Maven (each repo has `./mvnw` wrapper)

### Database
```bash
# One-time setup (if not already done)
createdb lattice_v2
psql -d lattice_v2 -f v2-infra/init-lattice-v2.sql
```
**DO NOT re-run init-lattice-v2.sql if the database already exists** — it uses `CREATE TABLE` (not `IF NOT EXISTS`) and will fail. The script is idempotent for seed data (uses `ON CONFLICT DO NOTHING`).

### Running Services
```bash
# Backend (each in its own terminal)
cd v2-integrator-service && ./mvnw quarkus:dev      # :10200
cd v2-merchant-service && ./mvnw quarkus:dev         # :10201
cd v2-payment-config-service && ./mvnw quarkus:dev   # :10202
cd v2-payment-runtime-service && ./mvnw quarkus:dev  # :10203

# Frontend
cd v2-integrator-portal && npm install && npm run dev  # :10210
cd v2-merchant-console && npm install && npm run dev   # :10211
cd v2-admin-console && npm install && npm run dev      # :10212
cd v2-demo && npm install && npm run dev               # :10213
```

### Health Check Paths
Health endpoints vary by service config:
- Services with `non-application-root-path=.../q`: `/v1/<service>/q/health`
- Services with `non-application-root-path=${root-path}`: `/v1/<service>/health`

---

## 6. Coding Conventions

### Backend
- **Layered architecture**: resource/ → service/ → repository/ → entity/
- **No Lombok** — Java Records for DTOs, standard POJOs for JPA entities
- **MapStruct** for entity↔DTO mapping (CDI component model)
- **UUID primary keys** with `uuidv7()` PostgreSQL function
- **Multi-schema** — each service owns its schema, never cross-schema queries in app code
- **RFC 9457** Problem Details for all error responses
- **CallerScope** (from latticepay-security) for RBAC — immutable record, never mutable beans

### Frontend
- **BFF proxy** — never call backends directly from client components
- **`window.__RUNTIME_ENV__`** pattern for public env vars (not `NEXT_PUBLIC_*`)
- **Circuit breaker** per backend in BFF routes
- **Path aliases**: `@/` → `src/`
- **No workarounds** — if something is broken, fix it properly or ask

### Testing
- **Backend**: JUnit 5 + REST Assured + TestContainers PostgreSQL
- **Frontend**: Jest + Testing Library
- **Test profile** disables all security tenants: `%test.latticepay.security.dev.enabled=false`

---

## 7. What's Complete vs. In Progress

### COMPLETE
- All 6 backend services: entities aligned to latticeorg DB schema, full CRUD, tests passing
- All 4 frontends: pages, components, API routes, BFF proxy, tests
- Security library: latticepay-security 0.6.4 shared across all services
- Deployment: all 10 services on Cloud Run, CI/CD pipelines, seed data in Cloud SQL
- Demo apps: 5 demos (Fashion Store, StyleCo B2B, Reverb Music, POS Terminal, GP Portal)
- Widget: TypeScript widget built and served by payment-runtime-service

### NOT YET DONE
- **Pulumi IaC** (Phase 6) — infrastructure is currently managed ad-hoc via gcloud; needs migration to Pulumi to match latticeorg
- **payment-mcp** and **agentic-api** — ported but not deployed (no Cloud Run services yet)
- **Mobile** — Flutter app and mobile widget packages not yet ported
- **Production IAP** — V2 sandbox uses dev JWT bypass; real IAP needs GLB + IAP setup

---

## 8. Sibling Projects (Reference)

These sibling directories provide context but should NOT be modified:

| Directory | Purpose |
|-----------|---------|
| `dan-innovation/` | V1 source (Micronaut/Gradle) — reference for business features |
| `latticeorg/` | Production codebase — reference for patterns and conventions |
| `dan-innovation-v2/` | **This project** — migration target |

V1 live reference: `https://demo-site-dev-hoifqixdva-uc.a.run.app/`

---

## 9. Critical Rules

1. **Latticeorg = source of truth** for patterns. When in doubt, check how latticeorg does it.
2. **UX parity is mandatory** — V2 apps must match V1 UX exactly. Users will side-by-side test.
3. **No security compromises** — JWT always enforced, no workarounds, no disabled security.
4. **No workarounds** — if blocked, ask the user rather than introducing hacks.
5. **Don't recreate the database** — it's already set up with all schemas and seed data.
6. **latticepay-security library** (v2-shared-security) is the shared auth layer — don't create per-service security classes.
7. **Port convention**: all V2 services use 10200–10299 range.

---

## 10. Files to Read First

When starting work on this project, read these in order:
1. `v2-infra/CLAUDE.md` (or the root `CLAUDE.md` — same content) — project overview and commands
2. `v2-infra/init-lattice-v2.sql` — authoritative database schema + seed data
3. `v2-shared-security/docs/usage.md` — how to use the security library
4. Any service's `src/main/resources/application.properties` — see config patterns
5. Any frontend's `src/lib/env.ts` — see how backend URLs and env vars work
