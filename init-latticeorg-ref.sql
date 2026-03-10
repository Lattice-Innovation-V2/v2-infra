-- =============================================================================
-- Latticeorg Reference Schema — READ-ONLY comparison database
-- Generated from latticeorg Liquibase changelogs for local comparison with lattice_v2
-- =============================================================================

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- UUIDv7 function (same as lattice_v2)
CREATE OR REPLACE FUNCTION uuidv7() RETURNS uuid
    LANGUAGE plpgsql
    AS $$
DECLARE
  unix_ts_ms bigint;
  uuid_bytes bytea;
BEGIN
  unix_ts_ms := (extract(epoch from clock_timestamp()) * 1000)::bigint;
  uuid_bytes := decode(lpad(to_hex(unix_ts_ms), 12, '0'), 'hex') || gen_random_bytes(10);
  uuid_bytes := set_byte(uuid_bytes, 6, (b'0111' || get_byte(uuid_bytes, 6)::bit(4))::bit(8)::int);
  uuid_bytes := set_byte(uuid_bytes, 8, (b'10' || get_byte(uuid_bytes, 8)::bit(6))::bit(8)::int);
  RETURN encode(uuid_bytes, 'hex')::uuid;
END;
$$;

-- 2. Schemas
CREATE SCHEMA IF NOT EXISTS integrator_mgmt;
CREATE SCHEMA IF NOT EXISTS merchant_mgmt;
CREATE SCHEMA IF NOT EXISTS shared;
CREATE SCHEMA IF NOT EXISTS payment_txn;
CREATE SCHEMA IF NOT EXISTS payment_config;

-- =============================================================================
-- 3. Enum Types
-- =============================================================================

-- shared enums
CREATE TYPE shared.address_type AS ENUM ('BILLING', 'SHIPPING', 'HEADQUARTERS', 'LEGAL');
CREATE TYPE shared.address_validation_status AS ENUM ('UNVERIFIED', 'VERIFIED', 'INVALID');
CREATE TYPE shared.deployment_type AS ENUM ('CONSUMER_SITE', 'MOBILE_APP', 'RETAILER_SITE', 'OTHER');
CREATE TYPE shared.entity_status AS ENUM ('ACTIVE', 'INACTIVE', 'SUSPENDED', 'PENDING');
CREATE TYPE shared.integrator_type AS ENUM ('ISV', 'ISO', 'PSP');
CREATE TYPE shared.onboarding_status AS ENUM ('PENDING', 'IN_PROGRESS', 'COMPLETED', 'REJECTED');
CREATE TYPE shared.relationship_type AS ENUM ('MANAGED', 'PARTNER', 'RESELLER');

-- payment_txn enums
CREATE TYPE payment_txn.transaction_type AS ENUM ('sale', 'refund', 'void', 'capture', 'auth');
CREATE TYPE payment_txn.transaction_status AS ENUM ('pending', 'authorized', 'captured', 'settled', 'declined', 'voided', 'refunded', 'partially_refunded', 'failed', 'expired');
CREATE TYPE payment_txn.transaction_method_type AS ENUM ('card', 'wallet', 'bnpl', 'bank_transfer', 'crypto', 'p2p', 'other');
CREATE TYPE payment_txn.attempt_status AS ENUM ('success', 'failed', 'timeout', 'error', 'pending');
CREATE TYPE payment_txn.decline_reason AS ENUM ('insufficient_funds', 'card_expired', 'card_declined', 'invalid_card', 'fraud_suspected', 'authentication_failed', 'processor_error', 'network_error', 'velocity_limit', 'risk_threshold', 'other');
CREATE TYPE payment_txn.dispute_status AS ENUM ('open', 'under_review', 'won', 'lost', 'withdrawn');

-- =============================================================================
-- 4. Tables — integrator_mgmt
-- =============================================================================

CREATE TABLE integrator_mgmt.integrator (
    integrator_id       UUID NOT NULL DEFAULT uuidv7(),
    parent_id           UUID,
    name                VARCHAR(255) NOT NULL,
    legal_name          VARCHAR(255),
    email               VARCHAR(255) NOT NULL,
    phone               VARCHAR(50),
    integrator_type     shared.integrator_type NOT NULL,
    business_type       VARCHAR(50),
    is_self_integrator  BOOLEAN NOT NULL DEFAULT false,
    status              shared.entity_status NOT NULL DEFAULT 'ACTIVE',
    tax_id              VARCHAR(100),
    founded_year        SMALLINT,
    employee_count      VARCHAR(20),
    company_description TEXT,
    demographics        JSONB DEFAULT '{}'::jsonb,
    point_of_contact    JSONB DEFAULT '{}'::jsonb,
    mcc_codes           TEXT[] DEFAULT '{}'::text[],
    billing_config      JSONB DEFAULT '{}'::jsonb,
    social_links        JSONB DEFAULT '{}'::jsonb,
    logo_path           VARCHAR(255),
    credential_map      JSONB DEFAULT '{}'::jsonb,
    risk_override_controls JSONB,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_pkey PRIMARY KEY (integrator_id)
);

CREATE TABLE integrator_mgmt.integrator_address (
    address_id          UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    address_type        shared.address_type NOT NULL,
    street_1            VARCHAR(255),
    street_2            VARCHAR(255),
    city                VARCHAR(100),
    state_province      VARCHAR(50),
    postal_code         VARCHAR(20),
    country_code        CHAR(2) NOT NULL,
    latitude            NUMERIC(9, 6),
    longitude           NUMERIC(9, 6),
    validation_status   shared.address_validation_status DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_address_pkey PRIMARY KEY (address_id)
);

CREATE TABLE integrator_mgmt.widget_default_config (
    config_id           UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    default_theme       JSONB DEFAULT '{}'::jsonb,
    default_customization JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT widget_default_config_pkey PRIMARY KEY (config_id)
);

CREATE TABLE integrator_mgmt.webhook_config (
    webhook_config_id   UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    url                 VARCHAR(2048) NOT NULL,
    subscribed_events   JSONB NOT NULL DEFAULT '[]'::jsonb,
    signing_secret      VARCHAR(255) NOT NULL,
    status              shared.entity_status NOT NULL DEFAULT 'ACTIVE',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_webhook_config PRIMARY KEY (webhook_config_id)
);

-- =============================================================================
-- 5. Tables — merchant_mgmt
-- =============================================================================

CREATE TABLE merchant_mgmt.merchant (
    merchant_id         UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    name                VARCHAR(255) NOT NULL,
    legal_entity_name   VARCHAR(255) NOT NULL,
    email               VARCHAR(255) NOT NULL,
    business_type       VARCHAR(50),
    mcc                 VARCHAR(4),
    status              shared.entity_status NOT NULL DEFAULT 'PENDING',
    onboarding_status   shared.onboarding_status,
    contact_info        JSONB DEFAULT '{}'::jsonb,
    allowed_origins     JSONB DEFAULT '[]'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT merchant_pkey PRIMARY KEY (merchant_id)
);

CREATE TABLE merchant_mgmt.merchant_address (
    address_id          UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    address_type        shared.address_type NOT NULL,
    street_1            VARCHAR(255),
    street_2            VARCHAR(255),
    city                VARCHAR(100),
    state_province      VARCHAR(50),
    postal_code         VARCHAR(20),
    country_code        CHAR(2) NOT NULL,
    latitude            NUMERIC(9, 6),
    longitude           NUMERIC(9, 6),
    validation_status   shared.address_validation_status DEFAULT 'UNVERIFIED',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT merchant_address_pkey PRIMARY KEY (address_id)
);

CREATE TABLE merchant_mgmt.widget_deployment (
    deployment_id       UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    created_by_integrator_id UUID,
    name                VARCHAR(255) NOT NULL,
    deployment_type     shared.deployment_type NOT NULL,
    deployment_url      VARCHAR(500),
    version             VARCHAR(50) NOT NULL,
    is_active           BOOLEAN NOT NULL DEFAULT true,
    customization_allowed BOOLEAN NOT NULL DEFAULT true,
    config              JSONB NOT NULL DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT widget_deployment_pkey PRIMARY KEY (deployment_id)
);

-- =============================================================================
-- 6. Tables — shared
-- =============================================================================

CREATE TABLE shared.feature_toggle (
    toggle_id           UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID,
    merchant_id         UUID,
    feature_key         VARCHAR(100) NOT NULL,
    enabled             BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT feature_toggle_pkey PRIMARY KEY (toggle_id)
);

CREATE TABLE shared.login_audit (
    login_id            UUID NOT NULL DEFAULT uuidv7(),
    identity_uid        VARCHAR(255) NOT NULL,
    email               VARCHAR(255) NOT NULL,
    integrator_id       UUID,
    merchant_id         UUID,
    user_role           VARCHAR(30) NOT NULL,
    login_metadata      JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT login_audit_pkey PRIMARY KEY (login_id)
);

CREATE TABLE shared.admin_changelog (
    changelog_id        UUID NOT NULL DEFAULT uuidv7(),
    identity_uid        VARCHAR(255) NOT NULL,
    integrator_id       UUID,
    merchant_id         UUID,
    tracked_change      JSONB NOT NULL,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT admin_changelog_pkey PRIMARY KEY (changelog_id)
);

CREATE TABLE shared.integrator_relationship (
    relationship_id     UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    merchant_id         UUID NOT NULL,
    relationship_type   shared.relationship_type NOT NULL DEFAULT 'MANAGED',
    external_merchant_id VARCHAR(255),
    revenue_share_pct   SMALLINT,
    status              shared.entity_status NOT NULL DEFAULT 'ACTIVE',
    feature_flags       JSONB DEFAULT '{}'::jsonb,
    config              JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_relationship_pkey PRIMARY KEY (relationship_id)
);

-- =============================================================================
-- 7. Tables — payment_txn (partitioned)
-- =============================================================================

CREATE TABLE payment_txn.payment_transaction (
    transaction_id      UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    psp_id              UUID NOT NULL,
    parent_transaction_id UUID,
    transaction_type    payment_txn.transaction_type NOT NULL,
    payment_method      payment_txn.transaction_method_type NOT NULL,
    amount              BIGINT NOT NULL,
    currency            CHAR(3) NOT NULL,
    status              payment_txn.transaction_status NOT NULL DEFAULT 'pending'::payment_txn.transaction_status,
    decline_reason      payment_txn.decline_reason,
    external_transaction_id VARCHAR(255),
    order_reference     VARCHAR(255),
    customer_email      VARCHAR(255),
    customer_name       VARCHAR(255),
    authorized_at       TIMESTAMP WITH TIME ZONE,
    captured_at         TIMESTAMP WITH TIME ZONE,
    settled_at          TIMESTAMP WITH TIME ZONE,
    completed_at        TIMESTAMP WITH TIME ZONE,
    metadata            JSONB DEFAULT '{}'::jsonb,
    settlement_details  JSONB,
    dispute_status      payment_txn.dispute_status,
    dispute_opened_at   TIMESTAMP WITH TIME ZONE,
    dispute_resolved_at TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT pk_payment_transaction PRIMARY KEY (transaction_id, created_at)
) PARTITION BY RANGE (created_at);

-- Default partition
CREATE TABLE payment_txn.payment_transaction_default PARTITION OF payment_txn.payment_transaction DEFAULT;

CREATE TABLE payment_txn.payment_attempt (
    attempt_id          UUID NOT NULL DEFAULT uuidv7(),
    transaction_id      UUID NOT NULL,
    psp_id              UUID NOT NULL,
    attempt_number      SMALLINT NOT NULL DEFAULT 1,
    attempt_type        payment_txn.transaction_type NOT NULL,
    psp_transaction_id  VARCHAR(255),
    request_payload     JSONB,
    response_payload    JSONB,
    status              payment_txn.attempt_status NOT NULL,
    error_code          VARCHAR(50),
    error_message       TEXT,
    latency_ms          INTEGER,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT pk_payment_attempt PRIMARY KEY (attempt_id, created_at)
) PARTITION BY RANGE (created_at);

-- Default partition
CREATE TABLE payment_txn.payment_attempt_default PARTITION OF payment_txn.payment_attempt DEFAULT;

-- =============================================================================
-- 8. Tables — payment_config
-- =============================================================================

CREATE TABLE payment_config.payment_service_provider (
    psp_id              UUID NOT NULL DEFAULT uuidv7(),
    name                VARCHAR(100) NOT NULL,
    type                VARCHAR(50) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    configuration_schema JSONB,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT payment_service_provider_pkey PRIMARY KEY (psp_id)
);

CREATE TABLE payment_config.psp_payment_method (
    psp_payment_method_id UUID NOT NULL DEFAULT uuidv7(),
    psp_id              UUID NOT NULL,
    method_type         VARCHAR(50) NOT NULL,
    display_name        VARCHAR(100) NOT NULL,
    capabilities        JSONB NOT NULL,
    configuration_schema JSONB,
    requires_setup      BOOLEAN NOT NULL DEFAULT true,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT psp_payment_method_pkey PRIMARY KEY (psp_payment_method_id)
);

CREATE TABLE payment_config.merchant_payment_config (
    config_id           UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    psp_payment_method_id UUID NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'pending_setup',
    configuration       JSONB NOT NULL DEFAULT '{}'::jsonb,
    display_order       INTEGER DEFAULT 0,
    test_mode           BOOLEAN NOT NULL DEFAULT true,
    last_tested_at      TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT merchant_payment_config_pkey PRIMARY KEY (config_id)
);

CREATE TABLE payment_config.encrypted_credentials (
    config_id           UUID NOT NULL,
    secret_id           VARCHAR(255) NOT NULL,
    secret_version      VARCHAR(50) NOT NULL DEFAULT 'latest',
    masked_preview      VARCHAR(50),
    last_rotated_at     TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT encrypted_credentials_pkey PRIMARY KEY (config_id)
);

-- =============================================================================
-- 9. Indexes — integrator_mgmt
-- =============================================================================

CREATE INDEX idx_integrator_status ON integrator_mgmt.integrator (status);
CREATE INDEX idx_integrator_parent ON integrator_mgmt.integrator (parent_id);
CREATE INDEX idx_integrator_type ON integrator_mgmt.integrator (integrator_type);
CREATE INDEX idx_integrator_address_integrator ON integrator_mgmt.integrator_address (integrator_id);
CREATE INDEX idx_integrator_address_country ON integrator_mgmt.integrator_address (country_code);
CREATE INDEX idx_webhook_config_integrator_id ON integrator_mgmt.webhook_config (integrator_id);
CREATE INDEX idx_webhook_config_status ON integrator_mgmt.webhook_config (status);

-- =============================================================================
-- 10. Indexes — merchant_mgmt
-- =============================================================================

CREATE INDEX idx_merchant_status ON merchant_mgmt.merchant (integrator_id, status);
CREATE INDEX idx_merchant_onboarding ON merchant_mgmt.merchant (integrator_id, onboarding_status);
CREATE INDEX idx_merchant_integrator ON merchant_mgmt.merchant (integrator_id);
CREATE INDEX idx_merchant_email ON merchant_mgmt.merchant (email);
CREATE INDEX idx_merchant_address_merchant ON merchant_mgmt.merchant_address (merchant_id);
CREATE INDEX idx_merchant_address_country ON merchant_mgmt.merchant_address (country_code);
CREATE INDEX idx_widget_deployment_integrator ON merchant_mgmt.widget_deployment (created_by_integrator_id);
CREATE INDEX idx_widget_deployment_active ON merchant_mgmt.widget_deployment (merchant_id);

-- =============================================================================
-- 11. Indexes — shared
-- =============================================================================

CREATE INDEX idx_feature_integrator ON shared.feature_toggle (integrator_id);
CREATE INDEX idx_feature_merchant ON shared.feature_toggle (merchant_id);
CREATE INDEX idx_feature_key ON shared.feature_toggle (feature_key);
CREATE INDEX idx_login_identity ON shared.login_audit (identity_uid);
CREATE INDEX idx_login_integrator ON shared.login_audit (integrator_id, created_at DESC);
CREATE INDEX idx_login_merchant ON shared.login_audit (merchant_id, created_at DESC);
CREATE INDEX idx_login_email ON shared.login_audit (email);
CREATE INDEX idx_login_created ON shared.login_audit (created_at DESC);
CREATE INDEX idx_changelog_integrator ON shared.admin_changelog (integrator_id, created_at DESC);
CREATE INDEX idx_changelog_merchant ON shared.admin_changelog (merchant_id, created_at DESC);
CREATE INDEX idx_changelog_identity ON shared.admin_changelog (identity_uid, created_at DESC);
CREATE INDEX idx_changelog_created ON shared.admin_changelog (created_at DESC);
CREATE INDEX idx_relationship_external_id ON shared.integrator_relationship (integrator_id, external_merchant_id);
CREATE INDEX idx_relationship_integrator ON shared.integrator_relationship (integrator_id);
CREATE INDEX idx_relationship_merchant ON shared.integrator_relationship (merchant_id);

-- =============================================================================
-- 12. Indexes — payment_txn
-- =============================================================================

-- payment_transaction (partitioned — indexes on parent propagate to partitions)
CREATE INDEX idx_payment_txn_status ON payment_txn.payment_transaction (merchant_id, status);
CREATE INDEX idx_payment_txn_merchant ON payment_txn.payment_transaction (merchant_id, created_at DESC);
CREATE INDEX idx_payment_txn_external_id ON payment_txn.payment_transaction (external_transaction_id);
CREATE INDEX idx_payment_txn_parent ON payment_txn.payment_transaction (parent_transaction_id);
CREATE INDEX idx_payment_txn_order_ref ON payment_txn.payment_transaction (merchant_id, order_reference);
CREATE INDEX idx_payment_txn_disputes ON payment_txn.payment_transaction (merchant_id, dispute_status);

-- payment_attempt (partitioned)
CREATE INDEX idx_attempt_errors ON payment_txn.payment_attempt (psp_id, error_code, created_at);
CREATE INDEX idx_attempt_transaction ON payment_txn.payment_attempt (transaction_id, created_at);
CREATE INDEX idx_attempt_psp_txn ON payment_txn.payment_attempt (psp_transaction_id);
CREATE INDEX idx_attempt_latency ON payment_txn.payment_attempt (psp_id, created_at);

-- =============================================================================
-- 13. Indexes — payment_config
-- =============================================================================

CREATE INDEX idx_psp_payment_method_psp ON payment_config.psp_payment_method (psp_id);
CREATE INDEX idx_psp_payment_method_type ON payment_config.psp_payment_method (method_type);
CREATE INDEX idx_merchant_payment_config_merchant ON payment_config.merchant_payment_config (merchant_id);
CREATE INDEX idx_merchant_payment_config_display ON payment_config.merchant_payment_config (merchant_id, display_order);
CREATE INDEX idx_merchant_payment_config_status ON payment_config.merchant_payment_config (merchant_id, status);
CREATE INDEX idx_encrypted_credentials_secret ON payment_config.encrypted_credentials (secret_id);

-- =============================================================================
-- 14. Unique Constraints
-- =============================================================================

-- integrator_mgmt
ALTER TABLE integrator_mgmt.integrator ADD CONSTRAINT integrator_email_key UNIQUE (email);
ALTER TABLE integrator_mgmt.integrator ADD CONSTRAINT integrator_tax_id_key UNIQUE (tax_id);
ALTER TABLE integrator_mgmt.widget_default_config ADD CONSTRAINT widget_default_config_integrator_id_key UNIQUE (integrator_id);
ALTER TABLE integrator_mgmt.webhook_config ADD CONSTRAINT uq_webhook_config_integrator_id UNIQUE (integrator_id);

-- shared
ALTER TABLE shared.feature_toggle ADD CONSTRAINT uq_feature_toggle UNIQUE (integrator_id, merchant_id, feature_key);
ALTER TABLE shared.integrator_relationship ADD CONSTRAINT uq_integrator_merchant UNIQUE (integrator_id, merchant_id);

-- payment_config
ALTER TABLE payment_config.payment_service_provider ADD CONSTRAINT payment_service_provider_name_key UNIQUE (name);
ALTER TABLE payment_config.psp_payment_method ADD CONSTRAINT uq_psp_method_type UNIQUE (psp_id, method_type);
ALTER TABLE payment_config.merchant_payment_config ADD CONSTRAINT uq_merchant_payment_method UNIQUE (merchant_id, psp_payment_method_id);

-- =============================================================================
-- 15. Foreign Keys — integrator_mgmt
-- =============================================================================

ALTER TABLE integrator_mgmt.integrator
    ADD CONSTRAINT integrator_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;

ALTER TABLE integrator_mgmt.integrator_address
    ADD CONSTRAINT integrator_address_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;

ALTER TABLE integrator_mgmt.widget_default_config
    ADD CONSTRAINT widget_default_config_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;

ALTER TABLE integrator_mgmt.webhook_config
    ADD CONSTRAINT fk_webhook_config_integrator FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;

-- =============================================================================
-- 16. Foreign Keys — merchant_mgmt
-- =============================================================================

ALTER TABLE merchant_mgmt.merchant
    ADD CONSTRAINT merchant_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;

ALTER TABLE merchant_mgmt.merchant_address
    ADD CONSTRAINT merchant_address_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;

ALTER TABLE merchant_mgmt.widget_deployment
    ADD CONSTRAINT widget_deployment_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;

ALTER TABLE merchant_mgmt.widget_deployment
    ADD CONSTRAINT widget_deployment_created_by_integrator_id_fkey FOREIGN KEY (created_by_integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;

-- =============================================================================
-- 17. Foreign Keys — shared
-- =============================================================================

ALTER TABLE shared.admin_changelog
    ADD CONSTRAINT admin_changelog_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;
ALTER TABLE shared.admin_changelog
    ADD CONSTRAINT admin_changelog_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE NO ACTION;

ALTER TABLE shared.feature_toggle
    ADD CONSTRAINT feature_toggle_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE shared.feature_toggle
    ADD CONSTRAINT feature_toggle_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;

ALTER TABLE shared.integrator_relationship
    ADD CONSTRAINT integrator_relationship_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE shared.integrator_relationship
    ADD CONSTRAINT integrator_relationship_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;

ALTER TABLE shared.login_audit
    ADD CONSTRAINT login_audit_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;
ALTER TABLE shared.login_audit
    ADD CONSTRAINT login_audit_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE NO ACTION;

-- =============================================================================
-- 18. Foreign Keys — payment_config
-- =============================================================================

ALTER TABLE payment_config.psp_payment_method
    ADD CONSTRAINT psp_payment_method_psp_id_fkey FOREIGN KEY (psp_id) REFERENCES payment_config.payment_service_provider (psp_id) ON DELETE CASCADE;

ALTER TABLE payment_config.merchant_payment_config
    ADD CONSTRAINT merchant_payment_config_psp_payment_method_id_fkey FOREIGN KEY (psp_payment_method_id) REFERENCES payment_config.psp_payment_method (psp_payment_method_id) ON DELETE CASCADE;

ALTER TABLE payment_config.encrypted_credentials
    ADD CONSTRAINT encrypted_credentials_config_id_fkey FOREIGN KEY (config_id) REFERENCES payment_config.merchant_payment_config (config_id) ON DELETE CASCADE;

-- =============================================================================
-- 19. Functions — shared
-- =============================================================================

CREATE OR REPLACE FUNCTION shared.can_access_merchant(p_integrator_id uuid, p_merchant_id uuid) RETURNS boolean
    LANGUAGE plpgsql STABLE
    AS $$
DECLARE
  v_result boolean;
BEGIN
  WITH RECURSIVE integrator_tree AS (
    SELECT integrator_id FROM integrator_mgmt.integrator WHERE integrator_id = p_integrator_id
    UNION ALL
    SELECT i.integrator_id FROM integrator_mgmt.integrator i JOIN integrator_tree t ON i.parent_id = t.integrator_id
  )
  SELECT EXISTS (
    SELECT 1 FROM merchant_mgmt.merchant m
    WHERE m.merchant_id = p_merchant_id AND m.integrator_id IN (SELECT integrator_id FROM integrator_tree)
  ) INTO v_result;
  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION shared.get_integrator_hierarchy(p_integrator_id uuid) RETURNS TABLE(integrator_id uuid, integrator_name character varying, parent_id uuid, hierarchy_level integer, path uuid[])
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE
  ancestors AS (
    SELECT i.integrator_id, i.name as integrator_name, i.parent_id, 0 as hierarchy_level, ARRAY[i.integrator_id] as path
    FROM integrator_mgmt.integrator i
    WHERE i.integrator_id = p_integrator_id
    UNION ALL
    SELECT i.integrator_id, i.name as integrator_name, i.parent_id, a.hierarchy_level - 1, i.integrator_id || a.path
    FROM integrator_mgmt.integrator i
    JOIN ancestors a ON i.integrator_id = a.parent_id
  ),
  descendants AS (
    SELECT i.integrator_id, i.name as integrator_name, i.parent_id, 0 as hierarchy_level, ARRAY[i.integrator_id] as path
    FROM integrator_mgmt.integrator i
    WHERE i.integrator_id = p_integrator_id
    UNION ALL
    SELECT i.integrator_id, i.name as integrator_name, i.parent_id, d.hierarchy_level + 1, d.path || i.integrator_id
    FROM integrator_mgmt.integrator i
    JOIN descendants d ON i.parent_id = d.integrator_id
  )
  SELECT * FROM (
    SELECT * FROM ancestors WHERE ancestors.hierarchy_level < 0
    UNION ALL
    SELECT * FROM descendants
  ) AS combined
  ORDER BY combined.hierarchy_level, combined.integrator_name;
END;
$$;

CREATE OR REPLACE FUNCTION shared.get_visible_merchants(p_integrator_id uuid) RETURNS TABLE(merchant_id uuid, merchant_name character varying, integrator_id uuid, integrator_name character varying, hierarchy_level integer)
    LANGUAGE plpgsql STABLE
    AS $$
BEGIN
  RETURN QUERY
  WITH RECURSIVE integrator_tree AS (
    SELECT i.integrator_id, i.name as integrator_name, 0 as level
    FROM integrator_mgmt.integrator i
    WHERE i.integrator_id = p_integrator_id
    UNION ALL
    SELECT i.integrator_id, i.name as integrator_name, t.level + 1
    FROM integrator_mgmt.integrator i
    JOIN integrator_tree t ON i.parent_id = t.integrator_id
  )
  SELECT m.merchant_id, m.name as merchant_name, m.integrator_id, it.integrator_name, it.level as hierarchy_level
  FROM merchant_mgmt.merchant m
  JOIN integrator_tree it ON m.integrator_id = it.integrator_id
  WHERE m.status = 'active'
  ORDER BY it.level, m.name;
END;
$$;

-- =============================================================================
-- 20. Functions — payment_txn
-- =============================================================================

CREATE OR REPLACE FUNCTION payment_txn.create_monthly_partitions(start_date date, end_date date)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
  loop_date date := start_date;
  partition_name text;
  next_month date;
BEGIN
  WHILE loop_date < end_date LOOP
    next_month := loop_date + interval '1 month';

    -- Payment transaction partition
    partition_name := 'payment_transaction_' || to_char(loop_date, 'YYYY_MM');
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS payment_txn.%I PARTITION OF payment_txn.payment_transaction FOR VALUES FROM (%L) TO (%L)',
      partition_name, loop_date, next_month
    );

    -- Payment attempt partition
    partition_name := 'payment_attempt_' || to_char(loop_date, 'YYYY_MM');
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS payment_txn.%I PARTITION OF payment_txn.payment_attempt FOR VALUES FROM (%L) TO (%L)',
      partition_name, loop_date, next_month
    );

    loop_date := next_month;
  END LOOP;
END;
$function$;

-- =============================================================================
-- DONE — latticeorg reference schema loaded
-- =============================================================================
