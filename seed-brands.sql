-- Payment method brands for the Lattice widget
-- These brands provide button styling, colors, and logos for the payment widget.
-- Run against the lattice_v2 database.

INSERT INTO brand_registry.brand (brand_id, name, display_name, description, primary_color, secondary_color, status, metadata) VALUES
('00000000-0000-4000-b000-000000000001', 'credit-debit-cards', 'Credit/Debit Cards', 'Pay with Visa, Mastercard, or other cards', '#1a1a2e', '#ffffff', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000002', 'apple-pay', 'Apple Pay', 'Pay with Apple Pay', '#000000', '#ffffff', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000003', 'google-pay', 'Google Pay', 'Pay with Google Pay', '#ffffff', '#3c4043', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000004', 'paypal', 'PayPal', 'Pay with PayPal', '#ffc439', '#003087', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000005', 'klarna', 'Klarna', 'Buy now, pay later with Klarna', '#ffb3c7', '#0a0b09', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000006', 'coinbase', 'Coinbase', 'Pay with cryptocurrency via Coinbase', '#0052ff', '#ffffff', 'active', '{"category": "payment-method"}'),
('00000000-0000-4000-b000-000000000007', 'venmo', 'Venmo', 'Pay with Venmo', '#3d95ce', '#ffffff', 'active', '{"category": "payment-method"}')
ON CONFLICT (brand_id) DO NOTHING;

-- Payment button use cases (JSON config for widget button rendering)
INSERT INTO brand_registry.brand_use_case (brand_id, use_case_type, configuration, status) VALUES
('00000000-0000-4000-b000-000000000001', 'payment-button', '{"backgroundColor": "#1a1a2e", "textColor": "#ffffff", "borderRadius": "8px", "label": "Pay by Card", "icon": "credit-card", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000002', 'payment-button', '{"backgroundColor": "#000000", "textColor": "#ffffff", "borderRadius": "8px", "label": "Apple Pay", "logoUrl": "/branding/apple-pay-logo.png", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000003', 'payment-button', '{"backgroundColor": "#ffffff", "textColor": "#3c4043", "borderRadius": "8px", "border": "1px solid #dadce0", "label": "Google Pay", "logoUrl": "/branding/google-pay-logo.png", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000004', 'payment-button', '{"backgroundColor": "#ffc439", "textColor": "#003087", "borderRadius": "8px", "label": "PayPal", "logoUrl": "/branding/paypal-logo.png", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000005', 'payment-button', '{"backgroundColor": "#ffb3c7", "textColor": "#0a0b09", "borderRadius": "8px", "label": "Klarna", "logoUrl": "/branding/klarna-logo.png", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000006', 'payment-button', '{"backgroundColor": "#0052ff", "textColor": "#ffffff", "borderRadius": "8px", "label": "Coinbase", "logoUrl": "/branding/coinbase-logo.png", "height": "56px", "width": "100%"}', 'active'),
('00000000-0000-4000-b000-000000000007', 'payment-button', '{"backgroundColor": "#3d95ce", "textColor": "#ffffff", "borderRadius": "8px", "label": "Venmo", "logoUrl": "/branding/venmo-logo.png", "height": "56px", "width": "100%"}', 'active')
ON CONFLICT DO NOTHING;
