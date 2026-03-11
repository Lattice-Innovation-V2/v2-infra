-- =============================================================================
-- Supplemental Seed Data — SD-07 through SD-10
-- Run AFTER init-lattice-v2.sql (idempotent via ON CONFLICT DO NOTHING)
-- =============================================================================

-- =============================================================================
-- SD-07: Expand PSP Catalog to V1 Parity
-- V1 had 13+ PSPs; V2 has 8. Add: heartland, afterpay, cashapp, paze, trustly,
-- apple-pay (standalone), google-pay (standalone), crypto-com
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

-- PSP payment methods for new providers
INSERT INTO payment_config.psp_payment_method (psp_id, method_type, display_name, capabilities) VALUES
-- Heartland
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='heartland'), 'credit_debit_cards', 'Credit/Debit Cards', '{"auth":true,"capture":true,"refund":true,"void":true,"tokenize":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='heartland'), 'ach', 'ACH Bank Transfer', '{"auth":true,"capture":true,"refund":true}'),
-- Afterpay
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='afterpay'), 'pay_later', 'Pay in 4', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='afterpay'), 'pay_now', 'Pay Now', '{"auth":true,"capture":true,"refund":true}'),
-- Cash App
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='cashapp'), 'cash_app_pay', 'Cash App Pay', '{"auth":true,"capture":true,"refund":true}'),
-- Paze
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='paze'), 'bank_transfer', 'Paze Bank Transfer', '{"auth":true,"capture":true,"refund":true}'),
-- Trustly
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='trustly'), 'bank_transfer', 'Open Banking Transfer', '{"auth":true,"capture":true,"refund":true}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='trustly'), 'pay_later', 'Pay Later', '{"auth":true,"capture":true,"refund":true}'),
-- Apple Pay (standalone)
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='apple-pay'), 'apple_pay', 'Apple Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
-- Google Pay (standalone)
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='google-pay'), 'google_pay', 'Google Pay', '{"auth":true,"capture":true,"refund":true,"tokenize":true}'),
-- Crypto.com
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'bitcoin', 'Bitcoin', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'ethereum', 'Ethereum', '{"auth":true,"capture":false,"refund":false}'),
((SELECT psp_id FROM payment_config.payment_service_provider WHERE name='crypto-com'), 'usdc', 'USD Coin', '{"auth":true,"capture":false,"refund":false}')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- SD-08: Sample Transactions for Dashboards (30+ days of data)
-- Spread across all demo merchants with realistic amounts, statuses, methods
-- Uses amounts in cents (BIGINT)
-- =============================================================================

-- Create partition for current data if not exists
CREATE TABLE IF NOT EXISTS payment_txn.payment_transaction_default PARTITION OF payment_txn.payment_transaction DEFAULT;
CREATE TABLE IF NOT EXISTS payment_txn.payment_attempt_default PARTITION OF payment_txn.payment_attempt DEFAULT;

-- Fashion Store transactions (14 txns, mix of card/wallet/bnpl)
INSERT INTO payment_txn.payment_transaction (
    merchant_id, psp_id, transaction_type, payment_method, amount, currency, status,
    customer_email, customer_name, order_reference, external_transaction_id,
    authorized_at, captured_at, created_at, updated_at
) VALUES
-- Recent transactions (last 7 days)
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 9999, 'USD', 'captured', 'alice@example.com', 'Alice Johnson', 'FS-001', 'ext-fs-001',
 now() - interval '1 day', now() - interval '1 day', now() - interval '1 day', now() - interval '1 day'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 14950, 'USD', 'captured', 'bob@example.com', 'Bob Smith', 'FS-002', 'ext-fs-002',
 now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 7500, 'USD', 'captured', 'carol@example.com', 'Carol Davis', 'FS-003', 'ext-fs-003',
 now() - interval '3 days', now() - interval '3 days', now() - interval '3 days', now() - interval '3 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'),
 'sale', 'crypto', 25000, 'USD', 'captured', 'dave@example.com', 'Dave Wilson', 'FS-004', 'ext-fs-004',
 now() - interval '4 days', now() - interval '4 days', now() - interval '4 days', now() - interval '4 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 20000, 'USD', 'declined', 'eve@example.com', 'Eve Brown', 'FS-005', 'ext-fs-005',
 NULL, NULL, now() - interval '5 days', now() - interval '5 days'),
-- Older transactions (8-30 days)
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 8999, 'USD', 'captured', 'frank@example.com', 'Frank Garcia', 'FS-006', 'ext-fs-006',
 now() - interval '8 days', now() - interval '8 days', now() - interval '8 days', now() - interval '8 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 34500, 'USD', 'captured', 'grace@example.com', 'Grace Lee', 'FS-007', 'ext-fs-007',
 now() - interval '12 days', now() - interval '12 days', now() - interval '12 days', now() - interval '12 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 12000, 'USD', 'captured', 'henry@example.com', 'Henry Taylor', 'FS-008', 'ext-fs-008',
 now() - interval '15 days', now() - interval '15 days', now() - interval '15 days', now() - interval '15 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 5999, 'USD', 'refunded', 'iris@example.com', 'Iris Martinez', 'FS-009', 'ext-fs-009',
 now() - interval '18 days', now() - interval '18 days', now() - interval '18 days', now() - interval '18 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 15500, 'USD', 'captured', 'jack@example.com', 'Jack Anderson', 'FS-010', 'ext-fs-010',
 now() - interval '22 days', now() - interval '22 days', now() - interval '22 days', now() - interval '22 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='coinbase'),
 'sale', 'crypto', 45000, 'USD', 'captured', 'kim@example.com', 'Kim Nguyen', 'FS-011', 'ext-fs-011',
 now() - interval '25 days', now() - interval '25 days', now() - interval '25 days', now() - interval '25 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 19900, 'USD', 'captured', 'liam@example.com', 'Liam Thomas', 'FS-012', 'ext-fs-012',
 now() - interval '28 days', now() - interval '28 days', now() - interval '28 days', now() - interval '28 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 22500, 'USD', 'captured', 'mia@example.com', 'Mia Jackson', 'FS-013', 'ext-fs-013',
 now() - interval '30 days', now() - interval '30 days', now() - interval '30 days', now() - interval '30 days'),
('00000000-0000-4000-8000-000000000010', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 7200, 'USD', 'failed', 'noah@example.com', 'Noah White', 'FS-014', NULL,
 NULL, NULL, now() - interval '6 days', now() - interval '6 days'),

-- StyleCo Business transactions (10 txns, larger B2B amounts)
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 125000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-001', 'ext-sc-001',
 now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'card', 287500, 'USD', 'captured', 'orders@bigbox.com', 'BigBox Retail', 'SC-002', 'ext-sc-002',
 now() - interval '5 days', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'bank_transfer', 450000, 'USD', 'captured', 'finance@globecorp.com', 'GlobeCorp', 'SC-003', 'ext-sc-003',
 now() - interval '7 days', now() - interval '7 days', now() - interval '7 days', now() - interval '7 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 98000, 'USD', 'captured', 'buy@startup.io', 'Startup Inc', 'SC-004', 'ext-sc-004',
 now() - interval '10 days', now() - interval '10 days', now() - interval '10 days', now() - interval '10 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'bank_transfer', 575000, 'USD', 'captured', 'accounting@megamart.com', 'MegaMart', 'SC-005', 'ext-sc-005',
 now() - interval '14 days', now() - interval '14 days', now() - interval '14 days', now() - interval '14 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 165000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-006', 'ext-sc-006',
 now() - interval '18 days', now() - interval '18 days', now() - interval '18 days', now() - interval '18 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'card', 320000, 'USD', 'declined', 'orders@smallbiz.com', 'SmallBiz LLC', 'SC-007', 'ext-sc-007',
 NULL, NULL, now() - interval '20 days', now() - interval '20 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'bank_transfer', 890000, 'USD', 'captured', 'finance@globecorp.com', 'GlobeCorp', 'SC-008', 'ext-sc-008',
 now() - interval '23 days', now() - interval '23 days', now() - interval '23 days', now() - interval '23 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 72000, 'USD', 'captured', 'buy@startup.io', 'Startup Inc', 'SC-009', 'ext-sc-009',
 now() - interval '26 days', now() - interval '26 days', now() - interval '26 days', now() - interval '26 days'),
('00000000-0000-4000-8000-000000000011', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'card', 195000, 'USD', 'captured', 'procurement@acme.com', 'ACME Corp', 'SC-010', 'ext-sc-010',
 now() - interval '29 days', now() - interval '29 days', now() - interval '29 days', now() - interval '29 days'),

-- Reverb Music transactions (10 txns, medium amounts)
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 129900, 'USD', 'captured', 'guitarist@music.com', 'Mike Rivera', 'RV-001', 'ext-rv-001',
 now() - interval '1 day', now() - interval '1 day', now() - interval '1 day', now() - interval '1 day'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'wallet', 49900, 'USD', 'captured', 'drums@beats.com', 'Sarah Connor', 'RV-002', 'ext-rv-002',
 now() - interval '3 days', now() - interval '3 days', now() - interval '3 days', now() - interval '3 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 299900, 'USD', 'captured', 'keys@piano.com', 'James Wong', 'RV-003', 'ext-rv-003',
 now() - interval '5 days', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 79500, 'USD', 'captured', 'bass@groove.com', 'Lisa Park', 'RV-004', 'ext-rv-004',
 now() - interval '8 days', now() - interval '8 days', now() - interval '8 days', now() - interval '8 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 34900, 'USD', 'refunded', 'effects@tone.com', 'Tom Reed', 'RV-005', 'ext-rv-005',
 now() - interval '10 days', now() - interval '10 days', now() - interval '10 days', now() - interval '10 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 199900, 'USD', 'captured', 'studio@recording.com', 'Amy Chen', 'RV-006', 'ext-rv-006',
 now() - interval '13 days', now() - interval '13 days', now() - interval '13 days', now() - interval '13 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 159900, 'USD', 'captured', 'vintage@collector.com', 'Dan Miller', 'RV-007', 'ext-rv-007',
 now() - interval '16 days', now() - interval '16 days', now() - interval '16 days', now() - interval '16 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'wallet', 24900, 'USD', 'captured', 'strings@play.com', 'Nina Scott', 'RV-008', 'ext-rv-008',
 now() - interval '19 days', now() - interval '19 days', now() - interval '19 days', now() - interval '19 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 449900, 'USD', 'captured', 'pro@musician.com', 'Chris Evans', 'RV-009', 'ext-rv-009',
 now() - interval '24 days', now() - interval '24 days', now() - interval '24 days', now() - interval '24 days'),
('00000000-0000-4000-8000-000000000012', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 89900, 'USD', 'failed', 'amp@loud.com', 'Pete Young', 'RV-010', NULL,
 NULL, NULL, now() - interval '27 days', now() - interval '27 days'),

-- POS Terminal transactions (12 txns, small cafe amounts)
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 575, 'USD', 'captured', NULL, 'Walk-in', 'POS-001', 'ext-pos-001',
 now() - interval '4 hours', now() - interval '4 hours', now() - interval '4 hours', now() - interval '4 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 1250, 'USD', 'captured', NULL, 'Walk-in', 'POS-002', 'ext-pos-002',
 now() - interval '6 hours', now() - interval '6 hours', now() - interval '6 hours', now() - interval '6 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'wallet', 895, 'USD', 'captured', NULL, 'Walk-in', 'POS-003', 'ext-pos-003',
 now() - interval '1 day', now() - interval '1 day', now() - interval '1 day', now() - interval '1 day'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 2100, 'USD', 'captured', NULL, 'Walk-in', 'POS-004', 'ext-pos-004',
 now() - interval '1 day 3 hours', now() - interval '1 day 3 hours', now() - interval '1 day 3 hours', now() - interval '1 day 3 hours'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 425, 'USD', 'captured', NULL, 'Walk-in', 'POS-005', 'ext-pos-005',
 now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'wallet', 1575, 'USD', 'captured', NULL, 'Walk-in', 'POS-006', 'ext-pos-006',
 now() - interval '3 days', now() - interval '3 days', now() - interval '3 days', now() - interval '3 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 750, 'USD', 'captured', NULL, 'Walk-in', 'POS-007', 'ext-pos-007',
 now() - interval '5 days', now() - interval '5 days', now() - interval '5 days', now() - interval '5 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 1800, 'USD', 'captured', NULL, 'Walk-in', 'POS-008', 'ext-pos-008',
 now() - interval '8 days', now() - interval '8 days', now() - interval '8 days', now() - interval '8 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 625, 'USD', 'declined', NULL, 'Walk-in', 'POS-009', 'ext-pos-009',
 NULL, NULL, now() - interval '10 days', now() - interval '10 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 3200, 'USD', 'captured', NULL, 'Walk-in', 'POS-010', 'ext-pos-010',
 now() - interval '14 days', now() - interval '14 days', now() - interval '14 days', now() - interval '14 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'wallet', 950, 'USD', 'captured', NULL, 'Walk-in', 'POS-011', 'ext-pos-011',
 now() - interval '20 days', now() - interval '20 days', now() - interval '20 days', now() - interval '20 days'),
('00000000-0000-4000-8000-000000000013', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 1450, 'USD', 'captured', NULL, 'Walk-in', 'POS-012', 'ext-pos-012',
 now() - interval '25 days', now() - interval '25 days', now() - interval '25 days', now() - interval '25 days')
;

-- =============================================================================
-- SD-09: API Keys for Demo Integrators
-- =============================================================================

-- Test Integrator API keys (6 keys matching V1 patterns)
INSERT INTO integrator_mgmt.integrator_api_key (integrator_id, key_value, key_name, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-platform-api-key', 'Platform API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-merchant-console-key', 'Merchant Console Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-widget-api-key', 'Widget API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-integrator-api-key', 'Integrator Portal Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-admin-api-key', 'Admin Console Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 'lattice-demo-api-key', 'Demo Apps Key', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- SD-10: GP Portal Admin Integrator + Linked Merchants
-- Matches the V1 GlobalPayments portal demo experience
-- =============================================================================

-- GP Admin integrator
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

-- GP Admin API keys
INSERT INTO integrator_mgmt.integrator_api_key (integrator_id, key_value, key_name, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'gp-admin-api-key', 'GP Admin API Key', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'gp-portal-api-key', 'GP Portal API Key', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- GP-managed merchants (5 merchants for the ISV demo portal)
INSERT INTO merchant_mgmt.merchant (
    merchant_id, integrator_id, name, legal_entity_name, email, business_type, mcc, status, onboarding_status
) VALUES
('00000000-0000-4000-8000-000000000030',
 (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'Cafe Sunrise', 'Cafe Sunrise LLC', 'info@cafesunrise.com', 'food_and_beverage', '5812', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000031',
 (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'Urban Threads', 'Urban Threads Inc', 'hello@urbanthreads.com', 'retail', '5651', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000032',
 (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'TechFix Pro', 'TechFix Pro Corp', 'support@techfixpro.com', 'technology', '7372', 'ACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000033',
 (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'Green Garden Nursery', 'Green Garden LLC', 'orders@greengarden.com', 'retail', '5261', 'INACTIVE', 'COMPLETED'),
('00000000-0000-4000-8000-000000000034',
 (SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'Bright Smile Dental', 'Bright Smile Dental PC', 'admin@brightsmile.com', 'healthcare', '8021', 'ACTIVE', 'IN_PROGRESS')
ON CONFLICT DO NOTHING;

-- GP merchant addresses
INSERT INTO merchant_mgmt.merchant_address (merchant_id, address_type, street_1, city, state_province, postal_code, country_code) VALUES
('00000000-0000-4000-8000-000000000030', 'HEADQUARTERS', '150 Peachtree St', 'Atlanta', 'GA', '30303', 'US'),
('00000000-0000-4000-8000-000000000031', 'HEADQUARTERS', '200 Buckhead Ave', 'Atlanta', 'GA', '30305', 'US'),
('00000000-0000-4000-8000-000000000032', 'HEADQUARTERS', '75 Tech Park Dr', 'Marietta', 'GA', '30060', 'US'),
('00000000-0000-4000-8000-000000000033', 'HEADQUARTERS', '500 Garden Way', 'Decatur', 'GA', '30030', 'US'),
('00000000-0000-4000-8000-000000000034', 'HEADQUARTERS', '300 Dental Ln', 'Roswell', 'GA', '30075', 'US')
ON CONFLICT DO NOTHING;

-- GP integrator-merchant relationships
INSERT INTO shared.integrator_relationship (integrator_id, merchant_id, relationship_type, status) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000030', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000031', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000032', 'MANAGED', 'ACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000033', 'MANAGED', 'INACTIVE'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'), '00000000-0000-4000-8000-000000000034', 'MANAGED', 'ACTIVE')
ON CONFLICT DO NOTHING;

-- GP merchant payment configs (link GP merchants to payment methods)
INSERT INTO payment_config.merchant_payment_config (merchant_id, psp_payment_method_id, status, display_order, test_mode) VALUES
-- Cafe Sunrise: Square cards + Cash App
('00000000-0000-4000-8000-000000000030',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='credit_debit_cards'),
 'active', 1, true),
('00000000-0000-4000-8000-000000000030',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='square' AND pm.method_type='cash_app_pay'),
 'active', 2, true),
-- Urban Threads: Stripe cards + Klarna
('00000000-0000-4000-8000-000000000031',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='stripe' AND pm.method_type='credit_debit_cards'),
 'active', 1, true),
('00000000-0000-4000-8000-000000000031',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='klarna' AND pm.method_type='pay_later'),
 'active', 2, true),
-- TechFix Pro: Braintree cards + PayPal
('00000000-0000-4000-8000-000000000032',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='credit_debit_cards'),
 'active', 1, true),
('00000000-0000-4000-8000-000000000032',
 (SELECT psp_payment_method_id FROM payment_config.psp_payment_method pm JOIN payment_config.payment_service_provider p ON pm.psp_id=p.psp_id WHERE p.name='braintree' AND pm.method_type='paypal'),
 'active', 2, true)
ON CONFLICT DO NOTHING;

-- GP merchant transactions (for dashboard metrics)
INSERT INTO payment_txn.payment_transaction (
    merchant_id, psp_id, transaction_type, payment_method, amount, currency, status,
    customer_email, customer_name, order_reference, external_transaction_id,
    authorized_at, captured_at, created_at, updated_at
) VALUES
-- Cafe Sunrise
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 2450, 'USD', 'captured', NULL, 'Walk-in', 'CS-001', 'ext-cs-001',
 now() - interval '1 day', now() - interval '1 day', now() - interval '1 day', now() - interval '1 day'),
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'wallet', 1875, 'USD', 'captured', NULL, 'Walk-in', 'CS-002', 'ext-cs-002',
 now() - interval '3 days', now() - interval '3 days', now() - interval '3 days', now() - interval '3 days'),
('00000000-0000-4000-8000-000000000030', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='square'),
 'sale', 'card', 3200, 'USD', 'captured', NULL, 'Walk-in', 'CS-003', 'ext-cs-003',
 now() - interval '7 days', now() - interval '7 days', now() - interval '7 days', now() - interval '7 days'),
-- Urban Threads
('00000000-0000-4000-8000-000000000031', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='stripe'),
 'sale', 'card', 15900, 'USD', 'captured', 'shopper@email.com', 'Jane Doe', 'UT-001', 'ext-ut-001',
 now() - interval '2 days', now() - interval '2 days', now() - interval '2 days', now() - interval '2 days'),
('00000000-0000-4000-8000-000000000031', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='klarna'),
 'sale', 'bnpl', 28900, 'USD', 'captured', 'fashion@email.com', 'Kate Smith', 'UT-002', 'ext-ut-002',
 now() - interval '6 days', now() - interval '6 days', now() - interval '6 days', now() - interval '6 days'),
-- TechFix Pro
('00000000-0000-4000-8000-000000000032', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'card', 8500, 'USD', 'captured', 'customer@tech.com', 'John Tech', 'TF-001', 'ext-tf-001',
 now() - interval '4 days', now() - interval '4 days', now() - interval '4 days', now() - interval '4 days'),
('00000000-0000-4000-8000-000000000032', (SELECT psp_id FROM payment_config.payment_service_provider WHERE name='braintree'),
 'sale', 'wallet', 12000, 'USD', 'captured', 'repair@request.com', 'Sam Fix', 'TF-002', 'ext-tf-002',
 now() - interval '9 days', now() - interval '9 days', now() - interval '9 days', now() - interval '9 days')
;

-- =============================================================================
-- Integrator Statements (billing data for integrator portal)
-- =============================================================================

-- Statements for Test Integrator (3 months)
INSERT INTO integrator_mgmt.integrator_statement (
    integrator_id, period_start_date, period_end_date, total_volume, total_lattice_fees,
    txn_count, merchant_count, issued_at, due_at, billing_mode, rate_pct, flat_fee, payment_status
) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 '2026-01-01', '2026-01-31', 148725.00, 4461.75, 586, 4, '2026-02-01', '2026-02-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 '2026-02-01', '2026-02-28', 136840.00, 4105.20, 542, 4, '2026-03-01', '2026-03-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com'),
 '2026-03-01', '2026-03-31', 162500.00, 4875.00, 618, 4, NULL, NULL, 'percentage', 0.0300, 0.00, 'pending')
ON CONFLICT DO NOTHING;

-- Statement lines for January
INSERT INTO integrator_mgmt.integrator_statement_line (statement_id, category_code, txn_count, volume, lattice_fee) VALUES
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'CARD', 412, 105200.00, 3156.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'BNPL', 86, 22500.00, 675.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'WALLET', 52, 12025.00, 360.75),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'CRYPTO', 36, 9000.00, 270.00)
ON CONFLICT DO NOTHING;

-- Statement lines for February
INSERT INTO integrator_mgmt.integrator_statement_line (statement_id, category_code, txn_count, volume, lattice_fee) VALUES
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'CARD', 380, 96800.00, 2904.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'BNPL', 78, 20400.00, 612.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'WALLET', 48, 11240.00, 337.20),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-02-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@testintegrator.com')),
 'CRYPTO', 36, 8400.00, 252.00)
ON CONFLICT DO NOTHING;

-- Statements for GP Admin integrator (2 months)
INSERT INTO integrator_mgmt.integrator_statement (
    integrator_id, period_start_date, period_end_date, total_volume, total_lattice_fees,
    txn_count, merchant_count, issued_at, due_at, billing_mode, rate_pct, flat_fee, payment_status
) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 '2026-01-01', '2026-01-31', 48200.00, 1446.00, 186, 3, '2026-02-01', '2026-02-15', 'percentage', 0.0300, 0.00, 'paid'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 '2026-02-01', '2026-02-28', 52750.00, 1582.50, 204, 3, '2026-03-01', '2026-03-15', 'percentage', 0.0300, 0.00, 'pending')
ON CONFLICT DO NOTHING;

-- GP statement lines for January
INSERT INTO integrator_mgmt.integrator_statement_line (statement_id, category_code, txn_count, volume, lattice_fee) VALUES
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')),
 'CARD', 142, 36500.00, 1095.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')),
 'BNPL', 24, 7200.00, 216.00),
((SELECT statement_id FROM integrator_mgmt.integrator_statement WHERE period_start_date='2026-01-01' AND integrator_id=(SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com')),
 'WALLET', 20, 4500.00, 135.00)
ON CONFLICT DO NOTHING;

-- GP Feature toggles (integrator-specific)
INSERT INTO shared.feature_toggle (integrator_id, feature_key, enabled, description) VALUES
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'payment_widget', true, 'Enable the embeddable payment widget'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'brand_registry', true, 'Enable brand management features'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'reporting_api', true, 'Enable the reporting API'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'bulk_merchant_upload', false, 'Enable CSV/Excel bulk merchant upload'),
((SELECT integrator_id FROM integrator_mgmt.integrator WHERE email='admin@globalpayments-isv.com'),
 'multi_currency', false, 'Enable multi-currency support')
ON CONFLICT DO NOTHING;

-- =============================================================================
-- DONE — Supplemental seed data applied
-- =============================================================================
