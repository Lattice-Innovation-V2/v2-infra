-- =============================================================================
-- Lattice V2 Database Init — latticeorg-first + dan-innovation extensions
-- =============================================================================
-- Foundation: latticeorg production schema (table names, PKs, enums, patterns)
-- Extensions: V2-only tables for dan-innovation features (widget, identity,
--             billing, bulk upload, brand registry, transaction events, etc.)
-- =============================================================================

-- 1. Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- UUIDv7 function
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
CREATE SCHEMA IF NOT EXISTS identity_mgmt;
CREATE SCHEMA IF NOT EXISTS brand_registry;

-- =============================================================================
-- 3. Enum Types (latticeorg)
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

-- V2 extension enums
CREATE TYPE payment_txn.refund_status AS ENUM ('pending', 'processing', 'completed', 'failed');
CREATE TYPE identity_mgmt.person_status AS ENUM ('active', 'inactive', 'merged', 'deleted');

-- =============================================================================
-- 4. Tables — integrator_mgmt (latticeorg base)
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
    -- V2 extension columns
    website             VARCHAR(1024),
    estimated_merchant_count INTEGER,
    estimated_avg_monthly_volume_per_merchant JSONB,
    estimated_avg_transaction_per_merchant NUMERIC(14,2),
    estimated_high_transaction_per_merchant NUMERIC(14,2),
    contract_start_date DATE,
    contract_end_date   DATE,
    operating_regions   JSONB DEFAULT '[]'::jsonb,
    permissions         JSONB DEFAULT '[]'::jsonb,
    additional_fee_items JSONB DEFAULT '[]'::jsonb,
    environments_enabled JSONB DEFAULT '[]'::jsonb,
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
-- 4b. Tables — integrator_mgmt (V2 extensions)
-- =============================================================================

-- V2-only: API key management for integrators
CREATE TABLE integrator_mgmt.integrator_api_key (
    api_key_id          UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    key_value           VARCHAR(512) NOT NULL,
    key_name            VARCHAR(255),
    status              shared.entity_status NOT NULL DEFAULT 'ACTIVE',
    expires_at          TIMESTAMP WITH TIME ZONE,
    last_used_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_api_key_pkey PRIMARY KEY (api_key_id)
);

-- V2-only: Billing statements
CREATE TABLE integrator_mgmt.integrator_statement (
    statement_id        UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    period_start_date   DATE NOT NULL,
    period_end_date     DATE NOT NULL,
    total_volume        NUMERIC(14,2),
    total_lattice_fees  NUMERIC(14,2),
    txn_count           INTEGER,
    merchant_count      INTEGER,
    issued_at           DATE,
    due_at              DATE,
    billing_mode        VARCHAR(50),
    rate_pct            NUMERIC(5,4),
    flat_fee            NUMERIC(10,2),
    payment_status      VARCHAR(50) DEFAULT 'pending',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_statement_pkey PRIMARY KEY (statement_id)
);

CREATE TABLE integrator_mgmt.integrator_statement_line (
    line_id             UUID NOT NULL DEFAULT uuidv7(),
    statement_id        UUID NOT NULL,
    category_code       VARCHAR(50),
    txn_count           INTEGER,
    volume              NUMERIC(14,2),
    lattice_fee         NUMERIC(14,2),
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_statement_line_pkey PRIMARY KEY (line_id)
);

CREATE TABLE integrator_mgmt.integrator_statement_merchant_line (
    line_id             UUID NOT NULL DEFAULT uuidv7(),
    statement_id        UUID NOT NULL,
    merchant_id         UUID,
    merchant_dba        VARCHAR(512),
    txn_count           INTEGER,
    volume              NUMERIC(14,2),
    is_active           BOOLEAN,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT integrator_statement_merchant_line_pkey PRIMARY KEY (line_id)
);

-- =============================================================================
-- 5. Tables — merchant_mgmt (latticeorg base)
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
    -- V2 extension columns
    phone               VARCHAR(50),
    dba_name            VARCHAR(512),
    website             VARCHAR(1024),
    integrator_merchant_reference VARCHAR(255),
    operating_regions   JSONB DEFAULT '[]'::jsonb,
    mcc_codes           JSONB DEFAULT '[]'::jsonb,
    settings            JSONB DEFAULT '{}'::jsonb,
    metadata            JSONB DEFAULT '{}'::jsonb,
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
-- 5b. Tables — merchant_mgmt (V2 extensions)
-- =============================================================================

-- V2-only: Bulk merchant upload tracking
CREATE TABLE merchant_mgmt.bulk_upload_job (
    job_id              UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID NOT NULL,
    status              VARCHAR(50) DEFAULT 'pending',
    progress            NUMERIC(5,2),
    message             TEXT,
    total_count         INTEGER,
    successful_count    INTEGER DEFAULT 0,
    failed_count        INTEGER DEFAULT 0,
    started_at          TIMESTAMP WITH TIME ZONE,
    completed_at        TIMESTAMP WITH TIME ZONE,
    results             JSONB DEFAULT '{}'::jsonb,
    errors              JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT bulk_upload_job_pkey PRIMARY KEY (job_id)
);

-- =============================================================================
-- 6. Tables — shared (latticeorg base + V2 extension column)
-- =============================================================================

CREATE TABLE shared.feature_toggle (
    toggle_id           UUID NOT NULL DEFAULT uuidv7(),
    integrator_id       UUID,
    merchant_id         UUID,
    feature_key         VARCHAR(100) NOT NULL,
    enabled             BOOLEAN NOT NULL DEFAULT true,
    description         TEXT,                           -- V2 extension column
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
-- 7. Tables — payment_txn (latticeorg partitioned base)
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

CREATE TABLE payment_txn.payment_attempt_default PARTITION OF payment_txn.payment_attempt DEFAULT;

-- =============================================================================
-- 7b. Tables — payment_txn (V2 extensions)
-- =============================================================================

-- V2-only: Transaction event sourcing
CREATE TABLE payment_txn.transaction_event (
    event_id            UUID NOT NULL DEFAULT uuidv7(),
    transaction_id      UUID NOT NULL,
    event_type          VARCHAR(50) NOT NULL,
    status_before       VARCHAR(50),
    status_after        VARCHAR(50),
    provider_response   JSONB DEFAULT '{}'::jsonb,
    metadata            JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT transaction_event_pkey PRIMARY KEY (event_id)
);

-- V2-only: Widget payment sessions
CREATE TABLE payment_txn.payment_session (
    session_id          UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    session_token       VARCHAR(512) NOT NULL,
    status              VARCHAR(50) DEFAULT 'active',
    expires_at          TIMESTAMP WITH TIME ZONE NOT NULL,
    payment_method_type VARCHAR(50),
    provider_session_id VARCHAR(255),
    provider_session_data JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT payment_session_pkey PRIMARY KEY (session_id)
);

-- V2-only: Refund tracking
CREATE TABLE payment_txn.refund (
    refund_id           UUID NOT NULL DEFAULT uuidv7(),
    transaction_id      UUID NOT NULL,
    amount              BIGINT NOT NULL,
    currency            CHAR(3) NOT NULL DEFAULT 'USD',
    status              payment_txn.refund_status NOT NULL DEFAULT 'pending',
    reason              TEXT,
    provider_refund_id  VARCHAR(255),
    provider_response   JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT refund_pkey PRIMARY KEY (refund_id)
);

-- =============================================================================
-- 8. Tables — payment_config (latticeorg base)
-- =============================================================================

CREATE TABLE payment_config.payment_service_provider (
    psp_id              UUID NOT NULL DEFAULT uuidv7(),
    name                VARCHAR(100) NOT NULL,
    type                VARCHAR(50) NOT NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'active',
    configuration_schema JSONB,
    -- V2 extension columns
    display_name        VARCHAR(255),
    provider_type       VARCHAR(50),
    supported_countries TEXT[] DEFAULT '{}'::text[],
    supported_currencies TEXT[] DEFAULT '{}'::text[],
    supported_payment_methods TEXT[] DEFAULT '{}'::text[],
    api_base_url        VARCHAR(1024),
    sandbox_base_url    VARCHAR(1024),
    documentation_url   VARCHAR(1024),
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
-- 8b. Tables — payment_config (V2 extensions)
-- =============================================================================

-- V2-only: Per-merchant widget configuration
CREATE TABLE payment_config.widget_config (
    config_id           UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    deployment_id       UUID,
    config_name         VARCHAR(255),
    default_theme       JSONB DEFAULT '{}'::jsonb,
    flow_type           VARCHAR(50) DEFAULT 'ecommerce',
    locale              VARCHAR(10) DEFAULT 'en-US',
    currency_display    VARCHAR(10) DEFAULT 'USD',
    display_toggles     JSONB DEFAULT '{}'::jsonb,
    custom_css          TEXT,
    status              VARCHAR(50) DEFAULT 'active',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT widget_config_pkey PRIMARY KEY (config_id)
);

-- V2-only: Payment methods (aggregated view)
CREATE TABLE payment_config.payment_method (
    payment_method_id   UUID NOT NULL DEFAULT uuidv7(),
    provider_id         UUID NOT NULL,
    method_type         VARCHAR(50) NOT NULL,
    display_name        VARCHAR(255),
    status              VARCHAR(50) DEFAULT 'active',
    configuration       JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT payment_method_pkey PRIMARY KEY (payment_method_id)
);

-- V2-only: Per-merchant payment method enablement
CREATE TABLE payment_config.merchant_payment_method (
    merchant_payment_method_id UUID NOT NULL DEFAULT uuidv7(),
    merchant_id         UUID NOT NULL,
    payment_method_id   UUID NOT NULL,
    provider_id         UUID NOT NULL,
    status              VARCHAR(50) DEFAULT 'active',
    configuration       JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT merchant_payment_method_pkey PRIMARY KEY (merchant_payment_method_id)
);

-- =============================================================================
-- 9. Tables — identity_mgmt (V2 extension — all tables)
-- =============================================================================

CREATE TABLE identity_mgmt.person (
    person_id           UUID NOT NULL DEFAULT uuidv7(),
    primary_email       VARCHAR(255),
    primary_phone       VARCHAR(50),
    first_name          VARCHAR(100),
    last_name           VARCHAR(100),
    date_of_birth       DATE,
    gender              VARCHAR(20),
    nationality         VARCHAR(50),
    preferred_language  VARCHAR(10),
    timezone            VARCHAR(50),
    status              identity_mgmt.person_status NOT NULL DEFAULT 'active',
    metadata            JSONB DEFAULT '{}'::jsonb,
    overall_confidence_score NUMERIC(5,4),
    last_identification_at TIMESTAMP WITH TIME ZONE,
    identification_count INTEGER DEFAULT 0,
    last_seen_at        TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT person_pkey PRIMARY KEY (person_id)
);

CREATE TABLE identity_mgmt.anonymous_session (
    anonymous_session_id UUID NOT NULL DEFAULT uuidv7(),
    session_id          VARCHAR(255) NOT NULL,
    merchant_id         UUID,
    integrator_id       UUID,
    device_fingerprint  VARCHAR(512),
    ip_address          VARCHAR(45),
    user_agent          TEXT,
    metadata            JSONB DEFAULT '{}'::jsonb,
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT anonymous_session_pkey PRIMARY KEY (anonymous_session_id)
);

CREATE TABLE identity_mgmt.anonymous_activity (
    activity_id         UUID NOT NULL DEFAULT uuidv7(),
    anonymous_session_id UUID NOT NULL,
    activity_type       VARCHAR(100) NOT NULL,
    activity_data       JSONB DEFAULT '{}'::jsonb,
    merchant_id         UUID,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT anonymous_activity_pkey PRIMARY KEY (activity_id)
);

CREATE TABLE identity_mgmt.person_activity (
    activity_id         UUID NOT NULL DEFAULT uuidv7(),
    person_id           UUID NOT NULL,
    activity_type       VARCHAR(100) NOT NULL,
    activity_data       JSONB DEFAULT '{}'::jsonb,
    merchant_id         UUID,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT person_activity_pkey PRIMARY KEY (activity_id)
);

CREATE TABLE identity_mgmt.person_persona (
    persona_id          UUID NOT NULL DEFAULT uuidv7(),
    person_id           UUID NOT NULL,
    persona_type        VARCHAR(100) NOT NULL,
    label               VARCHAR(255),
    attributes          JSONB DEFAULT '{}'::jsonb,
    confidence_score    NUMERIC(5,4),
    source              VARCHAR(100),
    active              BOOLEAN DEFAULT true,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT person_persona_pkey PRIMARY KEY (persona_id)
);

CREATE TABLE identity_mgmt.cross_session_link (
    link_id             UUID NOT NULL DEFAULT uuidv7(),
    anonymous_session_id UUID NOT NULL,
    person_id           UUID NOT NULL,
    link_method         VARCHAR(100) NOT NULL,
    confidence_score    NUMERIC(5,4),
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT cross_session_link_pkey PRIMARY KEY (link_id)
);

CREATE TABLE identity_mgmt.person_identification_attempt (
    attempt_id          UUID NOT NULL DEFAULT uuidv7(),
    person_id           UUID,
    anonymous_session_id UUID,
    identification_method VARCHAR(100) NOT NULL,
    confidence_score    NUMERIC(5,4),
    result              VARCHAR(50) NOT NULL,
    metadata            JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT person_identification_attempt_pkey PRIMARY KEY (attempt_id)
);

CREATE TABLE identity_mgmt.person_validation_result (
    validation_id       UUID NOT NULL DEFAULT uuidv7(),
    person_id           UUID NOT NULL,
    validation_type     VARCHAR(100) NOT NULL,
    status              VARCHAR(50) NOT NULL,
    result_data         JSONB DEFAULT '{}'::jsonb,
    validated_at        TIMESTAMP WITH TIME ZONE,
    expires_at          TIMESTAMP WITH TIME ZONE,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT person_validation_result_pkey PRIMARY KEY (validation_id)
);

-- =============================================================================
-- 10. Tables — brand_registry (V2 extension — all tables)
-- =============================================================================

CREATE TABLE brand_registry.brand (
    brand_id            UUID NOT NULL DEFAULT uuidv7(),
    name                VARCHAR(255) NOT NULL,
    display_name        VARCHAR(255),
    description         TEXT,
    logo_url            VARCHAR(1024),
    website_url         VARCHAR(1024),
    status              VARCHAR(50) DEFAULT 'active',
    owner_integrator_id UUID,
    primary_color       VARCHAR(20),
    secondary_color     VARCHAR(20),
    font_family         VARCHAR(100),
    metadata            JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT brand_pkey PRIMARY KEY (brand_id)
);

CREATE TABLE brand_registry.brand_asset (
    asset_id            UUID NOT NULL DEFAULT uuidv7(),
    brand_id            UUID NOT NULL,
    asset_type          VARCHAR(50) NOT NULL,
    file_url            VARCHAR(1024) NOT NULL,
    file_name           VARCHAR(255),
    mime_type           VARCHAR(100),
    file_size           BIGINT,
    status              VARCHAR(50) DEFAULT 'active',
    metadata            JSONB DEFAULT '{}'::jsonb,
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT brand_asset_pkey PRIMARY KEY (asset_id)
);

CREATE TABLE brand_registry.brand_use_case (
    use_case_id         UUID NOT NULL DEFAULT uuidv7(),
    brand_id            UUID NOT NULL,
    use_case_type       VARCHAR(100) NOT NULL,
    configuration       JSONB DEFAULT '{}'::jsonb,
    status              VARCHAR(50) DEFAULT 'active',
    created_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    updated_at          TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT now(),
    CONSTRAINT brand_use_case_pkey PRIMARY KEY (use_case_id)
);

-- =============================================================================
-- 11. Indexes — integrator_mgmt (latticeorg)
-- =============================================================================

CREATE INDEX idx_integrator_status ON integrator_mgmt.integrator (status);
CREATE INDEX idx_integrator_parent ON integrator_mgmt.integrator (parent_id);
CREATE INDEX idx_integrator_type ON integrator_mgmt.integrator (integrator_type);
CREATE INDEX idx_integrator_address_integrator ON integrator_mgmt.integrator_address (integrator_id);
CREATE INDEX idx_integrator_address_country ON integrator_mgmt.integrator_address (country_code);
CREATE INDEX idx_webhook_config_integrator_id ON integrator_mgmt.webhook_config (integrator_id);
CREATE INDEX idx_webhook_config_status ON integrator_mgmt.webhook_config (status);

-- V2 extension indexes
CREATE INDEX idx_api_key_integrator ON integrator_mgmt.integrator_api_key (integrator_id);
CREATE INDEX idx_api_key_value ON integrator_mgmt.integrator_api_key (key_value);
CREATE INDEX idx_statement_integrator ON integrator_mgmt.integrator_statement (integrator_id);
CREATE INDEX idx_statement_payment_status ON integrator_mgmt.integrator_statement (payment_status);
CREATE INDEX idx_statement_line_statement ON integrator_mgmt.integrator_statement_line (statement_id);
CREATE INDEX idx_statement_merchant_line_statement ON integrator_mgmt.integrator_statement_merchant_line (statement_id);

-- =============================================================================
-- 12. Indexes — merchant_mgmt (latticeorg)
-- =============================================================================

CREATE INDEX idx_merchant_status ON merchant_mgmt.merchant (integrator_id, status);
CREATE INDEX idx_merchant_onboarding ON merchant_mgmt.merchant (integrator_id, onboarding_status);
CREATE INDEX idx_merchant_integrator ON merchant_mgmt.merchant (integrator_id);
CREATE INDEX idx_merchant_email ON merchant_mgmt.merchant (email);
CREATE INDEX idx_merchant_address_merchant ON merchant_mgmt.merchant_address (merchant_id);
CREATE INDEX idx_merchant_address_country ON merchant_mgmt.merchant_address (country_code);
CREATE INDEX idx_widget_deployment_integrator ON merchant_mgmt.widget_deployment (created_by_integrator_id);
CREATE INDEX idx_widget_deployment_active ON merchant_mgmt.widget_deployment (merchant_id);

-- V2 extension indexes
CREATE INDEX idx_bulk_upload_job_integrator ON merchant_mgmt.bulk_upload_job (integrator_id);
CREATE INDEX idx_bulk_upload_job_status ON merchant_mgmt.bulk_upload_job (status);

-- =============================================================================
-- 13. Indexes — shared (latticeorg)
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
-- 14. Indexes — payment_txn (latticeorg partitioned)
-- =============================================================================

CREATE INDEX idx_payment_txn_status ON payment_txn.payment_transaction (merchant_id, status);
CREATE INDEX idx_payment_txn_merchant ON payment_txn.payment_transaction (merchant_id, created_at DESC);
CREATE INDEX idx_payment_txn_external_id ON payment_txn.payment_transaction (external_transaction_id);
CREATE INDEX idx_payment_txn_parent ON payment_txn.payment_transaction (parent_transaction_id);
CREATE INDEX idx_payment_txn_order_ref ON payment_txn.payment_transaction (merchant_id, order_reference);
CREATE INDEX idx_payment_txn_disputes ON payment_txn.payment_transaction (merchant_id, dispute_status);
CREATE INDEX idx_attempt_errors ON payment_txn.payment_attempt (psp_id, error_code, created_at);
CREATE INDEX idx_attempt_transaction ON payment_txn.payment_attempt (transaction_id, created_at);
CREATE INDEX idx_attempt_psp_txn ON payment_txn.payment_attempt (psp_transaction_id);
CREATE INDEX idx_attempt_latency ON payment_txn.payment_attempt (psp_id, created_at);

-- V2 extension indexes
CREATE INDEX idx_txn_event_transaction ON payment_txn.transaction_event (transaction_id);
CREATE INDEX idx_txn_event_type ON payment_txn.transaction_event (event_type);
CREATE INDEX idx_payment_session_token ON payment_txn.payment_session (session_token);
CREATE INDEX idx_payment_session_merchant ON payment_txn.payment_session (merchant_id);
CREATE INDEX idx_refund_transaction ON payment_txn.refund (transaction_id);
CREATE INDEX idx_refund_status ON payment_txn.refund (status);

-- =============================================================================
-- 15. Indexes — payment_config (latticeorg)
-- =============================================================================

CREATE INDEX idx_psp_payment_method_psp ON payment_config.psp_payment_method (psp_id);
CREATE INDEX idx_psp_payment_method_type ON payment_config.psp_payment_method (method_type);
CREATE INDEX idx_merchant_payment_config_merchant ON payment_config.merchant_payment_config (merchant_id);
CREATE INDEX idx_merchant_payment_config_display ON payment_config.merchant_payment_config (merchant_id, display_order);
CREATE INDEX idx_merchant_payment_config_status ON payment_config.merchant_payment_config (merchant_id, status);
CREATE INDEX idx_encrypted_credentials_secret ON payment_config.encrypted_credentials (secret_id);

-- V2 extension indexes
CREATE INDEX idx_widget_config_merchant ON payment_config.widget_config (merchant_id);
CREATE INDEX idx_payment_method_provider ON payment_config.payment_method (provider_id);
CREATE INDEX idx_merchant_payment_method_merchant ON payment_config.merchant_payment_method (merchant_id);
CREATE INDEX idx_merchant_payment_method_payment ON payment_config.merchant_payment_method (payment_method_id);

-- =============================================================================
-- 16. Indexes — identity_mgmt (V2 extensions)
-- =============================================================================

CREATE INDEX idx_person_email ON identity_mgmt.person (primary_email);
CREATE INDEX idx_person_phone ON identity_mgmt.person (primary_phone);
CREATE INDEX idx_person_status ON identity_mgmt.person (status);
CREATE INDEX idx_person_last_seen ON identity_mgmt.person (last_seen_at DESC);
CREATE UNIQUE INDEX idx_anonymous_session_session_id ON identity_mgmt.anonymous_session (session_id);
CREATE INDEX idx_anonymous_session_merchant ON identity_mgmt.anonymous_session (merchant_id);
CREATE INDEX idx_anonymous_activity_session ON identity_mgmt.anonymous_activity (anonymous_session_id);
CREATE INDEX idx_anonymous_activity_type ON identity_mgmt.anonymous_activity (activity_type);
CREATE INDEX idx_person_activity_person ON identity_mgmt.person_activity (person_id);
CREATE INDEX idx_person_activity_type ON identity_mgmt.person_activity (activity_type);
CREATE INDEX idx_persona_person ON identity_mgmt.person_persona (person_id);
CREATE INDEX idx_persona_type ON identity_mgmt.person_persona (persona_type);
CREATE INDEX idx_cross_session_link_session ON identity_mgmt.cross_session_link (anonymous_session_id);
CREATE INDEX idx_cross_session_link_person ON identity_mgmt.cross_session_link (person_id);
CREATE INDEX idx_identification_attempt_person ON identity_mgmt.person_identification_attempt (person_id);
CREATE INDEX idx_identification_attempt_session ON identity_mgmt.person_identification_attempt (anonymous_session_id);
CREATE INDEX idx_validation_result_person ON identity_mgmt.person_validation_result (person_id);

-- =============================================================================
-- 17. Indexes — brand_registry (V2 extensions)
-- =============================================================================

CREATE INDEX idx_brand_status ON brand_registry.brand (status);
CREATE INDEX idx_brand_owner ON brand_registry.brand (owner_integrator_id);
CREATE INDEX idx_brand_asset_brand ON brand_registry.brand_asset (brand_id);
CREATE INDEX idx_brand_use_case_brand ON brand_registry.brand_use_case (brand_id);

-- =============================================================================
-- 18. Unique Constraints
-- =============================================================================

-- integrator_mgmt (latticeorg)
ALTER TABLE integrator_mgmt.integrator ADD CONSTRAINT integrator_email_key UNIQUE (email);
ALTER TABLE integrator_mgmt.integrator ADD CONSTRAINT integrator_tax_id_key UNIQUE (tax_id);
ALTER TABLE integrator_mgmt.widget_default_config ADD CONSTRAINT widget_default_config_integrator_id_key UNIQUE (integrator_id);
ALTER TABLE integrator_mgmt.webhook_config ADD CONSTRAINT uq_webhook_config_integrator_id UNIQUE (integrator_id);

-- integrator_mgmt (V2 extensions)
ALTER TABLE integrator_mgmt.integrator_api_key ADD CONSTRAINT integrator_api_key_value_key UNIQUE (key_value);
ALTER TABLE integrator_mgmt.integrator_statement ADD CONSTRAINT uq_statement_integrator_period UNIQUE (integrator_id, period_start_date);

-- shared (latticeorg)
ALTER TABLE shared.feature_toggle ADD CONSTRAINT uq_feature_toggle UNIQUE (integrator_id, merchant_id, feature_key);
ALTER TABLE shared.integrator_relationship ADD CONSTRAINT uq_integrator_merchant UNIQUE (integrator_id, merchant_id);

-- payment_config (latticeorg)
ALTER TABLE payment_config.payment_service_provider ADD CONSTRAINT payment_service_provider_name_key UNIQUE (name);
ALTER TABLE payment_config.psp_payment_method ADD CONSTRAINT uq_psp_method_type UNIQUE (psp_id, method_type);
ALTER TABLE payment_config.merchant_payment_config ADD CONSTRAINT uq_merchant_payment_method UNIQUE (merchant_id, psp_payment_method_id);

-- payment_txn (V2 extensions)
ALTER TABLE payment_txn.payment_session ADD CONSTRAINT payment_session_token_key UNIQUE (session_token);

-- brand_registry (V2 extensions)
ALTER TABLE brand_registry.brand ADD CONSTRAINT brand_name_key UNIQUE (name);
ALTER TABLE brand_registry.brand_use_case ADD CONSTRAINT uq_brand_use_case UNIQUE (brand_id, use_case_type);

-- =============================================================================
-- 19. Foreign Keys — integrator_mgmt
-- =============================================================================

-- latticeorg
ALTER TABLE integrator_mgmt.integrator
    ADD CONSTRAINT integrator_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;
ALTER TABLE integrator_mgmt.integrator_address
    ADD CONSTRAINT integrator_address_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE integrator_mgmt.widget_default_config
    ADD CONSTRAINT widget_default_config_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE integrator_mgmt.webhook_config
    ADD CONSTRAINT fk_webhook_config_integrator FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;

-- V2 extensions
ALTER TABLE integrator_mgmt.integrator_api_key
    ADD CONSTRAINT fk_api_key_integrator FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE integrator_mgmt.integrator_statement
    ADD CONSTRAINT fk_statement_integrator FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;
ALTER TABLE integrator_mgmt.integrator_statement_line
    ADD CONSTRAINT fk_statement_line_statement FOREIGN KEY (statement_id) REFERENCES integrator_mgmt.integrator_statement (statement_id) ON DELETE CASCADE;
ALTER TABLE integrator_mgmt.integrator_statement_merchant_line
    ADD CONSTRAINT fk_merchant_line_statement FOREIGN KEY (statement_id) REFERENCES integrator_mgmt.integrator_statement (statement_id) ON DELETE CASCADE;

-- =============================================================================
-- 20. Foreign Keys — merchant_mgmt
-- =============================================================================

-- latticeorg
ALTER TABLE merchant_mgmt.merchant
    ADD CONSTRAINT merchant_integrator_id_fkey FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;
ALTER TABLE merchant_mgmt.merchant_address
    ADD CONSTRAINT merchant_address_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;
ALTER TABLE merchant_mgmt.widget_deployment
    ADD CONSTRAINT widget_deployment_merchant_id_fkey FOREIGN KEY (merchant_id) REFERENCES merchant_mgmt.merchant (merchant_id) ON DELETE CASCADE;
ALTER TABLE merchant_mgmt.widget_deployment
    ADD CONSTRAINT widget_deployment_created_by_integrator_id_fkey FOREIGN KEY (created_by_integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE NO ACTION;

-- V2 extensions
ALTER TABLE merchant_mgmt.bulk_upload_job
    ADD CONSTRAINT fk_bulk_upload_job_integrator FOREIGN KEY (integrator_id) REFERENCES integrator_mgmt.integrator (integrator_id) ON DELETE CASCADE;

-- =============================================================================
-- 21. Foreign Keys — shared
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
-- 22. Foreign Keys — payment_config
-- =============================================================================

ALTER TABLE payment_config.psp_payment_method
    ADD CONSTRAINT psp_payment_method_psp_id_fkey FOREIGN KEY (psp_id) REFERENCES payment_config.payment_service_provider (psp_id) ON DELETE CASCADE;
ALTER TABLE payment_config.merchant_payment_config
    ADD CONSTRAINT merchant_payment_config_psp_payment_method_id_fkey FOREIGN KEY (psp_payment_method_id) REFERENCES payment_config.psp_payment_method (psp_payment_method_id) ON DELETE CASCADE;
ALTER TABLE payment_config.encrypted_credentials
    ADD CONSTRAINT encrypted_credentials_config_id_fkey FOREIGN KEY (config_id) REFERENCES payment_config.merchant_payment_config (config_id) ON DELETE CASCADE;
ALTER TABLE payment_config.payment_method
    ADD CONSTRAINT payment_method_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES payment_config.payment_service_provider (psp_id) ON DELETE CASCADE;
ALTER TABLE payment_config.merchant_payment_method
    ADD CONSTRAINT merchant_payment_method_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES payment_config.payment_method (payment_method_id) ON DELETE CASCADE;
ALTER TABLE payment_config.merchant_payment_method
    ADD CONSTRAINT merchant_payment_method_provider_id_fkey FOREIGN KEY (provider_id) REFERENCES payment_config.payment_service_provider (psp_id) ON DELETE CASCADE;

-- =============================================================================
-- 23. Foreign Keys — identity_mgmt (V2 extensions)
-- =============================================================================

ALTER TABLE identity_mgmt.anonymous_activity
    ADD CONSTRAINT fk_anonymous_activity_session FOREIGN KEY (anonymous_session_id) REFERENCES identity_mgmt.anonymous_session (anonymous_session_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.person_activity
    ADD CONSTRAINT fk_person_activity_person FOREIGN KEY (person_id) REFERENCES identity_mgmt.person (person_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.person_persona
    ADD CONSTRAINT fk_persona_person FOREIGN KEY (person_id) REFERENCES identity_mgmt.person (person_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.cross_session_link
    ADD CONSTRAINT fk_cross_session_link_session FOREIGN KEY (anonymous_session_id) REFERENCES identity_mgmt.anonymous_session (anonymous_session_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.cross_session_link
    ADD CONSTRAINT fk_cross_session_link_person FOREIGN KEY (person_id) REFERENCES identity_mgmt.person (person_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.person_identification_attempt
    ADD CONSTRAINT fk_identification_attempt_person FOREIGN KEY (person_id) REFERENCES identity_mgmt.person (person_id) ON DELETE CASCADE;
ALTER TABLE identity_mgmt.person_validation_result
    ADD CONSTRAINT fk_validation_result_person FOREIGN KEY (person_id) REFERENCES identity_mgmt.person (person_id) ON DELETE CASCADE;

-- =============================================================================
-- 24. Foreign Keys — brand_registry (V2 extensions)
-- =============================================================================

ALTER TABLE brand_registry.brand_asset
    ADD CONSTRAINT fk_brand_asset_brand FOREIGN KEY (brand_id) REFERENCES brand_registry.brand (brand_id) ON DELETE CASCADE;
ALTER TABLE brand_registry.brand_use_case
    ADD CONSTRAINT fk_brand_use_case_brand FOREIGN KEY (brand_id) REFERENCES brand_registry.brand (brand_id) ON DELETE CASCADE;

-- =============================================================================
-- 25. Functions — shared (latticeorg)
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
  WHERE m.status = 'ACTIVE'
  ORDER BY it.level, m.name;
END;
$$;

-- =============================================================================
-- 26. Functions — payment_txn (latticeorg)
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
    partition_name := 'payment_transaction_' || to_char(loop_date, 'YYYY_MM');
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS payment_txn.%I PARTITION OF payment_txn.payment_transaction FOR VALUES FROM (%L) TO (%L)',
      partition_name, loop_date, next_month
    );
    partition_name := 'payment_attempt_' || to_char(loop_date, 'YYYY_MM');
    EXECUTE format(
      'CREATE TABLE IF NOT EXISTS payment_txn.%I PARTITION OF payment_txn.payment_attempt FOR VALUES FROM (%L) TO (%L)',
      partition_name, loop_date, next_month
    );
    loop_date := next_month;
  END LOOP;
END;
$function$;

-- Create partitions for 2025-2026
SELECT payment_txn.create_monthly_partitions('2025-01-01'::date, '2027-01-01'::date);

-- =============================================================================
-- 27. Seed Data — PSPs (adapted from V2 to latticeorg UUID structure)
-- =============================================================================

INSERT INTO payment_config.payment_service_provider (name, type, status, configuration_schema) VALUES
('braintree',       'gateway',     'active', '{"required":["merchant_id","public_key","private_key"],"optional":["environment"]}'),
('stripe',          'gateway',     'active', '{"required":["secret_key","publishable_key"],"optional":["webhook_secret"]}'),
('paypal',          'gateway',     'active', '{"required":["client_id","client_secret"],"optional":["environment"]}'),
('square',          'gateway',     'active', '{"required":["access_token","location_id"],"optional":["environment"]}'),
('klarna',          'bnpl',        'active', '{"required":["api_key","api_secret"],"optional":["environment"]}'),
('global-payments', 'gateway',     'active', '{"required":["merchant_id","account_id","shared_secret"],"optional":["environment"]}'),
('cardpointe',      'gateway',     'active', '{"required":["merchant_id","api_key"],"optional":["environment"]}'),
('coinbase',        'crypto',      'active', '{"required":["api_key"],"optional":["webhook_secret"]}')
ON CONFLICT DO NOTHING;

-- Seed PSP payment methods (latticeorg psp_payment_method table)
INSERT INTO payment_config.psp_payment_method (psp_id, method_type, display_name, capabilities) VALUES
-- Braintree
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'paypal', 'PayPal', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'venmo', 'Venmo', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'apple_pay', 'Apple Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
-- Stripe
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"tokenize":true,"3ds":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'apple_pay', 'Apple Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'google_pay', 'Google Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'bank_transfer', 'Bank Transfer (ACH)', '{"auth":true,"capture":true,"refund":true}'),
-- Klarna
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'pay_later', 'Pay Later', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'pay_now', 'Pay Now', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'slice_it', 'Slice It', '{"auth":true,"capture":true,"refund":true}'),
-- PayPal
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='paypal'), 'paypal', 'PayPal', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='paypal'), 'venmo', 'Venmo', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='paypal'), 'pay_later', 'Pay Later', '{"auth":true,"capture":true,"refund":true}'),
-- Square
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'cash_app_pay', 'Cash App Pay', '{"auth":true,"capture":true,"refund":true}'),
-- Global Payments
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='global-payments'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"3ds":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='global-payments'), 'apple_pay', 'Apple Pay', '{"auth":true,"capture":true,"refund":true}'),
-- CardPointe
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='cardpointe'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='cardpointe'), 'ach', 'ACH', '{"auth":true,"capture":true,"refund":true}'),
-- Coinbase
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'), 'bitcoin', 'Bitcoin', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'), 'ethereum', 'Ethereum', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'), 'usdc', 'USD Coin', '{"auth":true,"capture":false,"refund":false}')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 28. Seed Data — Test Integrator + Merchant
-- =============================================================================

INSERT INTO integrator_mgmt.integrator (
    name, legal_name, email, phone, integrator_type, business_type,
    is_self_integrator, status, company_description
) VALUES (
    'Test Integrator', 'Test Integrator LLC', 'admin@testintegrator.com', '+1-555-0100',
    'ISV', 'technology', true, 'ACTIVE', 'A test integrator for local development'
) ON CONFLICT DO NOTHING;

INSERT INTO integrator_mgmt.integrator_address (
    integrator_id, address_type, street_1, city, state_province, postal_code, country_code
) VALUES (
    (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
    'HEADQUARTERS', '123 Test Street', 'San Francisco', 'CA', '94105', 'US'
) ON CONFLICT DO NOTHING;

INSERT INTO merchant_mgmt.merchant (
    integrator_id, name, legal_entity_name, email, business_type, mcc, status, onboarding_status
) VALUES (
    (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
    'Test Merchant', 'Test Merchant Inc', 'info@testmerchant.com', 'retail', '5411', 'ACTIVE', 'COMPLETED'
) ON CONFLICT DO NOTHING;

INSERT INTO merchant_mgmt.merchant_address (
    merchant_id, address_type, street_1, city, state_province, postal_code, country_code
) VALUES (
    (SELECT merchant_id FROM merchant_mgmt.merchant WHERE email='info@testmerchant.com'),
    'HEADQUARTERS', '456 Commerce Ave', 'San Francisco', 'CA', '94107', 'US'
) ON CONFLICT DO NOTHING;

INSERT INTO shared.integrator_relationship (
    integrator_id, merchant_id, relationship_type, status
) VALUES (
    (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
    (SELECT merchant_id FROM merchant_mgmt.merchant WHERE email='info@testmerchant.com'),
    'MANAGED', 'ACTIVE'
) ON CONFLICT DO NOTHING;

-- =============================================================================
-- 29. Seed Data — Feature Toggles
-- =============================================================================

INSERT INTO shared.feature_toggle (integrator_id, feature_key, enabled, description) VALUES
(NULL, 'payment_widget', true, 'Enable the embeddable payment widget'),
(NULL, 'bulk_merchant_upload', true, 'Enable CSV/Excel bulk merchant upload'),
(NULL, 'agentic_identity', false, 'Enable agentic identity resolution'),
(NULL, 'brand_registry', true, 'Enable brand management features'),
(NULL, 'reporting_api', true, 'Enable the reporting API'),
(NULL, 'multi_currency', false, 'Enable multi-currency support')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 30. Seed Data — Demo Merchants (for v2-demo apps)
-- =============================================================================

-- 4 demo merchants linked to the test integrator
INSERT INTO merchant_mgmt.merchant (
    merchant_id, integrator_id, name, legal_entity_name, email, business_type, mcc, status, onboarding_status
) VALUES
    ('00000000-0000-4000-8000-000000000010', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
     'Fashion Store', 'Fashion Store LLC', 'demo-fashion@latticepay.dev', 'retail', '5651', 'ACTIVE', 'COMPLETED'),
    ('00000000-0000-4000-8000-000000000011', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
     'StyleCo Business', 'StyleCo Business Inc', 'demo-styleco@latticepay.dev', 'wholesale', '5699', 'ACTIVE', 'COMPLETED'),
    ('00000000-0000-4000-8000-000000000012', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
     'Reverb Music', 'Reverb Music LLC', 'demo-reverb@latticepay.dev', 'retail', '5733', 'ACTIVE', 'COMPLETED'),
    ('00000000-0000-4000-8000-000000000013', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
     'POS Terminal', 'POS Terminal Co', 'demo-pos@latticepay.dev', 'food_and_beverage', '5812', 'ACTIVE', 'COMPLETED')
ON CONFLICT DO NOTHING;

-- Demo merchant addresses
INSERT INTO merchant_mgmt.merchant_address (merchant_id, address_type, street_1, city, state_province, postal_code, country_code) VALUES
    ('00000000-0000-4000-8000-000000000010', 'HEADQUARTERS', '100 Fashion Blvd', 'New York', 'NY', '10001', 'US'),
    ('00000000-0000-4000-8000-000000000011', 'HEADQUARTERS', '200 Business Park', 'Chicago', 'IL', '60601', 'US'),
    ('00000000-0000-4000-8000-000000000012', 'HEADQUARTERS', '300 Music Row', 'Nashville', 'TN', '37203', 'US'),
    ('00000000-0000-4000-8000-000000000013', 'HEADQUARTERS', '400 Terminal Way', 'Austin', 'TX', '73301', 'US')
ON CONFLICT DO NOTHING;

-- Demo integrator-merchant relationships
INSERT INTO shared.integrator_relationship (integrator_id, merchant_id, relationship_type, status) VALUES
    ((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '00000000-0000-4000-8000-000000000010', 'MANAGED', 'ACTIVE'),
    ((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '00000000-0000-4000-8000-000000000011', 'MANAGED', 'ACTIVE'),
    ((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '00000000-0000-4000-8000-000000000012', 'MANAGED', 'ACTIVE'),
    ((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '00000000-0000-4000-8000-000000000013', 'MANAGED', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- Demo widget deployments
INSERT INTO merchant_mgmt.widget_deployment (deployment_id, merchant_id, name, deployment_type, version, is_active) VALUES
    ('00000000-0000-4000-8000-000000000020', '00000000-0000-4000-8000-000000000010', 'Fashion Store Checkout', 'CONSUMER_SITE', '1.0', true),
    ('00000000-0000-4000-8000-000000000021', '00000000-0000-4000-8000-000000000011', 'StyleCo Business Checkout', 'RETAILER_SITE', '1.0', true),
    ('00000000-0000-4000-8000-000000000022', '00000000-0000-4000-8000-000000000012', 'Reverb Checkout', 'CONSUMER_SITE', '1.0', true),
    ('00000000-0000-4000-8000-000000000023', '00000000-0000-4000-8000-000000000013', 'POS Terminal Checkout', 'OTHER', '1.0', true)
ON CONFLICT DO NOTHING;

-- Demo widget configs (theme matches v2-demo frontend)
INSERT INTO payment_config.widget_config (merchant_id, deployment_id, config_name, default_theme, flow_type, locale, currency_display) VALUES
    ('00000000-0000-4000-8000-000000000010', '00000000-0000-4000-8000-000000000020', 'Fashion Store',
     '{"mode":"light","primaryColor":"#000000","fontFamily":"Inter","cornerRadius":"rounded","buttonShape":"rounded"}', 'ecommerce', 'en-US', 'USD'),
    ('00000000-0000-4000-8000-000000000011', '00000000-0000-4000-8000-000000000021', 'StyleCo Business',
     '{"mode":"light","primaryColor":"#1a365d","fontFamily":"Inter","cornerRadius":"rounded","buttonShape":"rounded"}', 'ecommerce', 'en-US', 'USD'),
    ('00000000-0000-4000-8000-000000000012', '00000000-0000-4000-8000-000000000022', 'Reverb Music',
     '{"mode":"dark","primaryColor":"#ea580c","fontFamily":"Inter","cornerRadius":"rounded","buttonShape":"pill"}', 'ecommerce', 'en-US', 'USD'),
    ('00000000-0000-4000-8000-000000000013', '00000000-0000-4000-8000-000000000023', 'POS Terminal',
     '{"mode":"dark","primaryColor":"#22c55e","fontFamily":"Inter","cornerRadius":"rounded","buttonShape":"rounded"}', 'pos', 'en-US', 'USD')
ON CONFLICT DO NOTHING;

-- Demo merchant payment configs (link merchants to PSP payment methods)
-- Fashion Store: Square cards, Klarna BNPL, Coinbase crypto
INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
    ('00000000-0000-4000-8000-000000000010',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='credit_debit_cards'),
     'active', 1, true),
    ('00000000-0000-4000-8000-000000000010',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='klarna' AND pm.method_type='pay_later'),
     'active', 2, true),
    ('00000000-0000-4000-8000-000000000010',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='coinbase' AND pm.method_type='bitcoin'),
     'active', 3, true)
ON CONFLICT DO NOTHING;

-- StyleCo Business: Square cards, Stripe cards, Stripe bank transfer
INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
    ('00000000-0000-4000-8000-000000000011',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='credit_debit_cards'),
     'active', 1, true),
    ('00000000-0000-4000-8000-000000000011',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='stripe' AND pm.method_type='credit_debit_cards'),
     'active', 2, true),
    ('00000000-0000-4000-8000-000000000011',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='stripe' AND pm.method_type='bank_transfer'),
     'active', 3, true)
ON CONFLICT DO NOTHING;

-- Reverb Music: Braintree cards, Braintree PayPal, Klarna BNPL
INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
    ('00000000-0000-4000-8000-000000000012',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='credit_debit_cards'),
     'active', 1, true),
    ('00000000-0000-4000-8000-000000000012',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='paypal'),
     'active', 2, true),
    ('00000000-0000-4000-8000-000000000012',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='klarna' AND pm.method_type='pay_later'),
     'active', 3, true)
ON CONFLICT DO NOTHING;

-- POS Terminal: Square cards, Square Cash App Pay
INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
    ('00000000-0000-4000-8000-000000000013',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='credit_debit_cards'),
     'active', 1, true),
    ('00000000-0000-4000-8000-000000000013',
     (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='cash_app_pay'),
     'active', 2, true)
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 31. Seed Data — Expanded PSP Catalog (V1 Parity)
-- =============================================================================

INSERT INTO payment_config.payment_service_provider (name, type, status, display_name, configuration_schema, supported_countries, supported_currencies) VALUES
('heartland',    'gateway',       'active', 'Heartland Payment Systems', '{"required":["merchant_id","api_key","api_secret"],"optional":["environment"]}',
 '{US,CA}', '{USD,CAD}'),
('afterpay',     'bnpl',          'active', 'Afterpay',                  '{"required":["merchant_id","secret_key"],"optional":["environment"]}',
 '{US,CA,AU,NZ,GB}', '{USD,CAD,AUD,NZD,GBP}'),
('cashapp',      'digital_wallet','active', 'Cash App Pay',              '{"required":["client_id","api_key"],"optional":["environment"]}',
 '{US,GB}', '{USD,GBP}'),
('paze',         'digital_wallet','active', 'Paze',                      '{"required":["partner_id","api_key"],"optional":["environment"]}',
 '{US}', '{USD}'),
('trustly',      'bank_transfer', 'active', 'Trustly',                   '{"required":["merchant_id","api_key","api_secret"],"optional":["environment"]}',
 '{US,CA,DE,SE,FI,DK,NO,GB}', '{USD,EUR,SEK,GBP,CAD}'),
('apple-pay',    'digital_wallet','active', 'Apple Pay',                 '{"required":["merchant_id","certificate"],"optional":["domain_verification"]}',
 '{US,CA,GB,AU,DE,FR,JP}', '{USD,CAD,GBP,AUD,EUR,JPY}'),
('google-pay',   'digital_wallet','active', 'Google Pay',                '{"required":["merchant_id","gateway_id"],"optional":["environment"]}',
 '{US,CA,GB,AU,DE,FR,JP,IN}', '{USD,CAD,GBP,AUD,EUR,JPY,INR}'),
('crypto-com',   'crypto',        'active', 'Crypto.com Pay',            '{"required":["api_key","secret_key"],"optional":["webhook_secret"]}',
 '{US,CA,GB,AU,SG}', '{USD,EUR,GBP,AUD,SGD}')
ON CONFLICT DO NOTHING;

INSERT INTO payment_config.psp_payment_method (psp_id, method_type, display_name, capabilities) VALUES
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='heartland'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='heartland'), 'ach', 'ACH Bank Transfer', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='afterpay'), 'pay_later', 'Pay in 4', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='afterpay'), 'pay_now', 'Pay Now', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='cashapp'), 'cash_app_pay', 'Cash App Pay', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='paze'), 'bank_transfer', 'Paze Bank Transfer', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='trustly'), 'bank_transfer', 'Open Banking Transfer', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='trustly'), 'pay_later', 'Pay Later', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='apple-pay'), 'apple_pay', 'Apple Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='google-pay'), 'google_pay', 'Google Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'bitcoin', 'Bitcoin', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'ethereum', 'Ethereum', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'usdc', 'USD Coin', '{"auth":true,"capture":false,"refund":false}')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 32. Seed Data — Sample Transactions (30+ days for dashboards)
-- =============================================================================

CREATE TABLE IF NOT EXISTS payment_txn.payment_transaction_default PARTITION OF payment_txn.payment_transaction DEFAULT;
CREATE TABLE IF NOT EXISTS payment_txn.payment_attempt_default PARTITION OF payment_txn.payment_attempt DEFAULT;

INSERT INTO payment_txn.payment_transaction (
    merchant_id, psp_id, transaction_type, payment_method, amount, currency, status,
    customer_email, customer_name, order_reference, external_transaction_id,
    authorized_at, captured_at, created_at, updated_at
) VALUES
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 9999, 'USD', 'captured', 'alice@example.com', 'Alice Johnson', 'FS-001', 'ext-fs-001', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 14950, 'USD', 'captured', 'bob@example.com', 'Bob Smith', 'FS-002', 'ext-fs-002', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 7500, 'USD', 'captured', 'carol@example.com', 'Carol Davis', 'FS-003', 'ext-fs-003', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'), 'sale', 'crypto', 25000, 'USD', 'captured', 'dave@example.com', 'Dave Wilson', 'FS-004', 'ext-fs-004', now()-interval '4 days', now()-interval '4 days', now()-interval '4 days', now()-interval '4 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 20000, 'USD', 'declined', 'eve@example.com', 'Eve Brown', 'FS-005', 'ext-fs-005', NULL, NULL, now()-interval '5 days', now()-interval '5 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 8999, 'USD', 'captured', 'frank@example.com', 'Frank Garcia', 'FS-006', 'ext-fs-006', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 34500, 'USD', 'captured', 'grace@example.com', 'Grace Lee', 'FS-007', 'ext-fs-007', now()-interval '12 days', now()-interval '12 days', now()-interval '12 days', now()-interval '12 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 12000, 'USD', 'captured', 'henry@example.com', 'Henry Taylor', 'FS-008', 'ext-fs-008', now()-interval '15 days', now()-interval '15 days', now()-interval '15 days', now()-interval '15 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 5999, 'USD', 'refunded', 'iris@example.com', 'Iris Martinez', 'FS-009', 'ext-fs-009', now()-interval '18 days', now()-interval '18 days', now()-interval '18 days', now()-interval '18 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 15500, 'USD', 'captured', 'jack@example.com', 'Jack Anderson', 'FS-010', 'ext-fs-010', now()-interval '22 days', now()-interval '22 days', now()-interval '22 days', now()-interval '22 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'), 'sale', 'crypto', 45000, 'USD', 'captured', 'kim@example.com', 'Kim Nguyen', 'FS-011', 'ext-fs-011', now()-interval '25 days', now()-interval '25 days', now()-interval '25 days', now()-interval '25 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 19900, 'USD', 'captured', 'liam@example.com', 'Liam Thomas', 'FS-012', 'ext-fs-012', now()-interval '28 days', now()-interval '28 days', now()-interval '28 days', now()-interval '28 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 22500, 'USD', 'captured', 'mia@example.com', 'Mia Jackson', 'FS-013', 'ext-fs-013', now()-interval '30 days', now()-interval '30 days', now()-interval '30 days', now()-interval '30 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 7200, 'USD', 'failed', 'noah@example.com', 'Noah White', 'FS-014', NULL, NULL, NULL, now()-interval '6 days', now()-interval '6 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 125000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-001', 'ext-sc-001', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'card', 287500, 'USD', 'captured', 'orders@bigbox.com', 'BigBox Retail', 'SC-002', 'ext-sc-002', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'bank_transfer', 450000, 'USD', 'captured', 'finance@globecorp.com', 'GlobeCorp', 'SC-003', 'ext-sc-003', now()-interval '7 days', now()-interval '7 days', now()-interval '7 days', now()-interval '7 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 98000, 'USD', 'captured', 'buy@startup.io', 'Startup Inc', 'SC-004', 'ext-sc-004', now()-interval '10 days', now()-interval '10 days', now()-interval '10 days', now()-interval '10 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'bank_transfer', 575000, 'USD', 'captured', 'accounting@megamart.com', 'MegaMart', 'SC-005', 'ext-sc-005', now()-interval '14 days', now()-interval '14 days', now()-interval '14 days', now()-interval '14 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 165000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-006', 'ext-sc-006', now()-interval '18 days', now()-interval '18 days', now()-interval '18 days', now()-interval '18 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'card', 320000, 'USD', 'declined', 'orders@smallbiz.com', 'SmallBiz LLC', 'SC-007', 'ext-sc-007', NULL, NULL, now()-interval '20 days', now()-interval '20 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'bank_transfer', 890000, 'USD', 'captured', 'finance@globecorp.com', 'GlobeCorp', 'SC-008', 'ext-sc-008', now()-interval '23 days', now()-interval '23 days', now()-interval '23 days', now()-interval '23 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 72000, 'USD', 'captured', 'buy@startup.io', 'Startup Inc', 'SC-009', 'ext-sc-009', now()-interval '26 days', now()-interval '26 days', now()-interval '26 days', now()-interval '26 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'card', 195000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-010', 'ext-sc-010', now()-interval '29 days', now()-interval '29 days', now()-interval '29 days', now()-interval '29 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 129900, 'USD', 'captured', 'guitarist@music.com', 'Mike Rivera', 'RV-001', 'ext-rv-001', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'wallet', 49900, 'USD', 'captured', 'drums@beats.com', 'Sarah Connor', 'RV-002', 'ext-rv-002', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 299900, 'USD', 'captured', 'keys@piano.com', 'James Wong', 'RV-003', 'ext-rv-003', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 79500, 'USD', 'captured', 'bass@groove.com', 'Lisa Park', 'RV-004', 'ext-rv-004', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 34900, 'USD', 'refunded', 'effects@tone.com', 'Tom Reed', 'RV-005', 'ext-rv-005', now()-interval '10 days', now()-interval '10 days', now()-interval '10 days', now()-interval '10 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 199900, 'USD', 'captured', 'studio@recording.com', 'Amy Chen', 'RV-006', 'ext-rv-006', now()-interval '13 days', now()-interval '13 days', now()-interval '13 days', now()-interval '13 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 159900, 'USD', 'captured', 'vintage@collector.com', 'Dan Miller', 'RV-007', 'ext-rv-007', now()-interval '16 days', now()-interval '16 days', now()-interval '16 days', now()-interval '16 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'wallet', 24900, 'USD', 'captured', 'strings@play.com', 'Nina Scott', 'RV-008', 'ext-rv-008', now()-interval '19 days', now()-interval '19 days', now()-interval '19 days', now()-interval '19 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 449900, 'USD', 'captured', 'pro@musician.com', 'Chris Evans', 'RV-009', 'ext-rv-009', now()-interval '24 days', now()-interval '24 days', now()-interval '24 days', now()-interval '24 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 89900, 'USD', 'failed', 'amp@loud.com', 'Pete Young', 'RV-010', NULL, NULL, NULL, now()-interval '27 days', now()-interval '27 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 575, 'USD', 'captured', NULL, 'Walk-in', 'POS-001', 'ext-pos-001', now()-interval '4 hours', now()-interval '4 hours', now()-interval '4 hours', now()-interval '4 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 1250, 'USD', 'captured', NULL, 'Walk-in', 'POS-002', 'ext-pos-002', now()-interval '6 hours', now()-interval '6 hours', now()-interval '6 hours', now()-interval '6 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'wallet', 895, 'USD', 'captured', NULL, 'Walk-in', 'POS-003', 'ext-pos-003', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 2100, 'USD', 'captured', NULL, 'Walk-in', 'POS-004', 'ext-pos-004', now()-interval '1 day 3 hours', now()-interval '1 day 3 hours', now()-interval '1 day 3 hours', now()-interval '1 day 3 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 425, 'USD', 'captured', NULL, 'Walk-in', 'POS-005', 'ext-pos-005', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'wallet', 1575, 'USD', 'captured', NULL, 'Walk-in', 'POS-006', 'ext-pos-006', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 750, 'USD', 'captured', NULL, 'Walk-in', 'POS-007', 'ext-pos-007', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days', now()-interval '5 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 1800, 'USD', 'captured', NULL, 'Walk-in', 'POS-008', 'ext-pos-008', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days', now()-interval '8 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 625, 'USD', 'declined', NULL, 'Walk-in', 'POS-009', 'ext-pos-009', NULL, NULL, now()-interval '10 days', now()-interval '10 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 3200, 'USD', 'captured', NULL, 'Walk-in', 'POS-010', 'ext-pos-010', now()-interval '14 days', now()-interval '14 days', now()-interval '14 days', now()-interval '14 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'wallet', 950, 'USD', 'captured', NULL, 'Walk-in', 'POS-011', 'ext-pos-011', now()-interval '20 days', now()-interval '20 days', now()-interval '20 days', now()-interval '20 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 1450, 'USD', 'captured', NULL, 'Walk-in', 'POS-012', 'ext-pos-012', now()-interval '25 days', now()-interval '25 days', now()-interval '25 days', now()-interval '25 days')
;

-- =============================================================================
-- 33. Seed Data — API Keys
-- =============================================================================

INSERT INTO integrator_mgmt.integrator_api_key (integrator_id, key_value, key_name, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-platform-api-key', 'Platform API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-merchant-console-key', 'Merchant Console Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-widget-api-key', 'Widget API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-integrator-api-key', 'Integrator Portal Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-admin-api-key', 'Admin Console Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), 'lattice-demo-api-key', 'Demo Apps Key', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- 34. Seed Data — GP Portal Admin Integrator + Merchants
-- =============================================================================

INSERT INTO integrator_mgmt.integrator (
    name, legal_name, email, phone, integrator_type, business_type,
    is_self_integrator, status, company_description, website
) VALUES (
    'Global Payments ISV', 'Global Payments ISV Inc', 'admin@globalpayments-isv.com', '+1-555-0200',
    'ISV', 'financial_services', false, 'ACTIVE',
    'A demo ISV integrator for the PayConnect portal experience',
    'https://globalpayments-isv.example.com'
) ON CONFLICT DO NOTHING;

INSERT INTO integrator_mgmt.integrator_address (
    integrator_id, address_type, street_1, city, state_province, postal_code, country_code
) VALUES (
    (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
    'HEADQUARTERS', '3550 Lenox Road NE', 'Atlanta', 'GA', '30326', 'US'
) ON CONFLICT DO NOTHING;

INSERT INTO integrator_mgmt.integrator_api_key (integrator_id, key_value, key_name, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'gp-admin-api-key', 'GP Admin API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'gp-portal-api-key', 'GP Portal API Key', 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO merchant_mgmt.merchant (
    merchant_id, integrator_id, name, legal_entity_name, email, business_type, mcc, status, onboarding_status
) VALUES
('00000000-0000-4000-8000-000000000030', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'Cafe Sunrise', 'Cafe Sunrise LLC', 'info@cafesunrise.com', 'food_and_beverage', '5812', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000031', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'Urban Threads', 'Urban Threads Inc', 'hello@urbanthreads.com', 'retail', '5651', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000032', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'TechFix Pro', 'TechFix Pro Corp', 'support@techfixpro.com', 'technology', '7372', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000033', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'Green Garden Nursery', 'Green Garden LLC', 'orders@greengarden.com', 'retail', '5261', 'INACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000034', (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'Bright Smile Dental', 'Bright Smile Dental PC', 'admin@brightsmile.com', 'healthcare', '8021', 'ACTIVE', 'IN_PROGRESS')
ON CONFLICT DO NOTHING;

INSERT INTO merchant_mgmt.merchant_address (merchant_id, address_type, street_1, city, state_province, postal_code, country_code) VALUES
('00000000-0000-4000-8000-000000000030', 'HEADQUARTERS', '150 Peachtree St', 'Atlanta', 'GA', '30303', 'US'),
('00000000-0000-4000-8000-000000000031', 'HEADQUARTERS', '200 Buckhead Ave', 'Atlanta', 'GA', '30305', 'US'),
('00000000-0000-4000-8000-000000000032', 'HEADQUARTERS', '75 Tech Park Dr', 'Marietta', 'GA', '30060', 'US'),
('00000000-0000-4000-8000-000000000033', 'HEADQUARTERS', '500 Garden Way', 'Decatur', 'GA', '30030', 'US'),
('00000000-0000-4000-8000-000000000034', 'HEADQUARTERS', '300 Dental Ln', 'Roswell', 'GA', '30075', 'US')
ON CONFLICT DO NOTHING;

INSERT INTO shared.integrator_relationship (integrator_id, merchant_id, relationship_type, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000030', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000031', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000032', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000033', 'MANAGED', 'INACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000034', 'MANAGED', 'ACTIVE')
ON CONFLICT DO NOTHING;

INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
('00000000-0000-4000-8000-000000000030', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='credit_debit_cards'), 'active', 1, true),
('00000000-0000-4000-8000-000000000030', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='cash_app_pay'), 'active', 2, true),
('00000000-0000-4000-8000-000000000031', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='stripe' AND pm.method_type='credit_debit_cards'), 'active', 1, true),
('00000000-0000-4000-8000-000000000031', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='klarna' AND pm.method_type='pay_later'), 'active', 2, true),
('00000000-0000-4000-8000-000000000032', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='credit_debit_cards'), 'active', 1, true),
('00000000-0000-4000-8000-000000000032', (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='paypal'), 'active', 2, true)
ON CONFLICT DO NOTHING;

INSERT INTO payment_txn.payment_transaction (
    merchant_id, psp_id, transaction_type, payment_method, amount, currency, status,
    customer_email, customer_name, order_reference, external_transaction_id,
    authorized_at, captured_at, created_at, updated_at
) VALUES
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 2450, 'USD', 'captured', NULL, 'Walk-in', 'CS-001', 'ext-cs-001', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day', now()-interval '1 day'),
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'wallet', 1875, 'USD', 'captured', NULL, 'Walk-in', 'CS-002', 'ext-cs-002', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days', now()-interval '3 days'),
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'), 'sale', 'card', 3200, 'USD', 'captured', NULL, 'Walk-in', 'CS-003', 'ext-cs-003', now()-interval '7 days', now()-interval '7 days', now()-interval '7 days', now()-interval '7 days'),
('00000000-0000-4000-8000-000000000031', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'), 'sale', 'card', 15900, 'USD', 'captured', 'shopper@email.com', 'Jane Doe', 'UT-001', 'ext-ut-001', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days', now()-interval '2 days'),
('00000000-0000-4000-8000-000000000031', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'), 'sale', 'bnpl', 28900, 'USD', 'captured', 'fashion@email.com', 'Kate Smith', 'UT-002', 'ext-ut-002', now()-interval '6 days', now()-interval '6 days', now()-interval '6 days', now()-interval '6 days'),
('00000000-0000-4000-8000-000000000032', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'card', 8500, 'USD', 'captured', 'customer@tech.com', 'John Tech', 'TF-001', 'ext-tf-001', now()-interval '4 days', now()-interval '4 days', now()-interval '4 days', now()-interval '4 days'),
('00000000-0000-4000-8000-000000000032', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'), 'sale', 'wallet', 12000, 'USD', 'captured', 'repair@request.com', 'Sam Fix', 'TF-002', 'ext-tf-002', now()-interval '9 days', now()-interval '9 days', now()-interval '9 days', now()-interval '9 days')
;

-- =============================================================================
-- 35. Seed Data — Integrator Statements (billing)
-- =============================================================================

INSERT INTO integrator_mgmt.integrator_statement (
    integrator_id, period_start_date, period_end_date, total_volume, total_lattice_fees,
    txn_count, merchant_count, issued_at, due_at, billing_mode, rate_pct, flat_fee, payment_status
) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '2026-01-01', '2026-01-31', 148725.00, 4461.75, 586, 4, '2026-02-01', '2026-02-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '2026-02-01', '2026-02-28', 136840.00, 4105.20, 542, 4, '2026-03-01', '2026-03-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'), '2026-03-01', '2026-03-31', 162500.00, 4875.00, 618, 4, NULL, NULL, 'percentage', 0.0300, 0.00, 'pending'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '2026-01-01', '2026-01-31', 48200.00, 1446.00, 186, 3, '2026-02-01', '2026-02-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '2026-02-01', '2026-02-28', 52750.00, 1582.50, 204, 3, '2026-03-01', '2026-03-15', 'percentage', 0.0300, 0.00, 'pending')
ON CONFLICT DO NOTHING;

INSERT INTO integrator_mgmt.integrator_statement_line (statement_id, category_code, txn_count, volume, lattice_fee) VALUES
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'CARD', 412, 105200.00, 3156.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'BNPL', 86, 22500.00, 675.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'WALLET', 52, 12025.00, 360.75),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'CRYPTO', 36, 9000.00, 270.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'CARD', 380, 96800.00, 2904.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'BNPL', 78, 20400.00, 612.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'WALLET', 48, 11240.00, 337.20),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')), 'CRYPTO', 36, 8400.00, 252.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')), 'CARD', 142, 36500.00, 1095.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')), 'BNPL', 24, 7200.00, 216.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')), 'WALLET', 20, 4500.00, 135.00)
ON CONFLICT DO NOTHING;

INSERT INTO shared.feature_toggle (integrator_id, feature_key, enabled, description) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'payment_widget', true, 'Enable the embeddable payment widget'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'brand_registry', true, 'Enable brand management features'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'reporting_api', true, 'Enable the reporting API'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'bulk_merchant_upload', false, 'Enable CSV/Excel bulk merchant upload'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), 'multi_currency', false, 'Enable multi-currency support')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- DONE — lattice_v2 database initialized (latticeorg-first + V2 extensions)
-- =============================================================================
