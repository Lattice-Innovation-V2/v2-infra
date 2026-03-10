-- Schemas for payment-admin-services
CREATE SCHEMA IF NOT EXISTS integrator_mgmt;
CREATE SCHEMA IF NOT EXISTS merchant_mgmt;
CREATE SCHEMA IF NOT EXISTS shared;

-- Schema for payment-config-service
CREATE SCHEMA IF NOT EXISTS payment_config;

-- Schema for payment-runtime-service
CREATE SCHEMA IF NOT EXISTS payment_txn;

-- Schema for identity management (Phase 3F agentic identity)
CREATE SCHEMA IF NOT EXISTS identity_mgmt;

-- Schema for brand-registry
CREATE SCHEMA IF NOT EXISTS brand_registry;

-- UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- UUIDv7 function (used by Liquibase changesets)
CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid AS $$
DECLARE
  unix_ts_ms bigint;
  uuid_bytes bytea;
BEGIN
  unix_ts_ms = (extract(epoch from clock_timestamp()) * 1000)::bigint;
  uuid_bytes = substring(int8send(unix_ts_ms) from 3);
  uuid_bytes = uuid_bytes || gen_random_bytes(10);
  uuid_bytes = set_byte(uuid_bytes, 6, (b'0111' || get_byte(uuid_bytes, 6)::bit(4))::bit(8)::int);
  uuid_bytes = set_byte(uuid_bytes, 8, (b'10' || get_byte(uuid_bytes, 8)::bit(6))::bit(8)::int);
  RETURN encode(uuid_bytes, 'hex')::uuid;
END
$$ LANGUAGE plpgsql VOLATILE;
