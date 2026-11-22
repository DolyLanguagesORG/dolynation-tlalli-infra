-- Tabla: roles
-- Roles del sistema (`student`, `admin`). Reemplaza a la tabla temporal `admins`.
CREATE TABLE roles (
  id SERIAL PRIMARY KEY,
  name VARCHAR(30) NOT NULL UNIQUE,
  description VARCHAR(255),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO roles (id, name, description) VALUES
  (1, 'student', 'Usuario estudiante con acceso a lecturas y suscripciones'),
  (2, 'admin', 'Administrador del sistema con acceso exclusivo al panel de gestión')
ON CONFLICT (name) DO NOTHING;

SELECT setval(
  pg_get_serial_sequence('roles', 'id'),
  COALESCE((SELECT MAX(id) FROM roles), 1),
  true
);

-- Tabla: users
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(255),
  email VARCHAR(254) NOT NULL UNIQUE,
  password VARCHAR(255),
  role_id INTEGER NOT NULL DEFAULT 1 REFERENCES roles(id),
  subscription_tier VARCHAR(30) DEFAULT NULL,
  stripe_customer_id VARCHAR(64),
  current_streak INTEGER NOT NULL DEFAULT 0,
  last_streak_date DATE,
  -- Marca de verificación del correo. NULL = la cuenta todavía no confirmó su correo.
  email_verified_at TIMESTAMP,
  -- Locale de interfaz del usuario (`es` | `en`) para los correos transaccionales.
  -- No es el idioma de estudio (vive en `user_settings.selected_languages`).
  locale VARCHAR(10) NOT NULL DEFAULT 'es',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  deleted_at TIMESTAMP
);

CREATE INDEX idx_users_role_id ON users(role_id);
CREATE UNIQUE INDEX uq_users_stripe_customer_id
  ON users(stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;

-- Tabla: user_oauth_accounts
-- Identidades externas OAuth 2.0 / OIDC vinculadas (Google, Microsoft, etc.).
CREATE TABLE user_oauth_accounts (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(30) NOT NULL,
  provider_user_id VARCHAR(255) NOT NULL,
  provider_email VARCHAR(254),
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_user_oauth_accounts_provider_sub
  ON user_oauth_accounts(provider, provider_user_id);
CREATE UNIQUE INDEX uq_user_oauth_accounts_user_provider
  ON user_oauth_accounts(user_id, provider);
CREATE INDEX idx_user_oauth_accounts_user_id
  ON user_oauth_accounts(user_id);

-- Tabla: user_settings
-- Preferencias de estudio por usuario (idiomas ordenados por prioridad,
-- bloqueo de cambio anual, creditos pagados de cambio y categorias elegidas).
-- El backend las mapea en Drizzle (`user_settings`); sin esta tabla el modulo
-- de settings no puede leer ni escribir.
-- `preferred_language` es opcional (DEFAULT 'en'): el backend lo usa para
-- los correos transaccionales cuando el usuario no elige uno.
CREATE TABLE user_settings (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  preferred_language VARCHAR(10) DEFAULT 'en',
  selected_languages JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_language_change_at TIMESTAMP,
  language_change_credits INTEGER NOT NULL DEFAULT 0,
  preferred_categories JSONB NOT NULL DEFAULT '[]'::jsonb,
  saved_categories JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- Índices para user_settings
CREATE INDEX idx_user_settings_user_id ON user_settings(user_id);

-- Tabla: access_requests
-- Solicitudes de acceso a planes de suscripción o desbloqueo de cambio de idioma
-- enviadas por los usuarios cuando `ACCESS_REQUESTS_ENABLED=true`.
CREATE TABLE access_requests (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  request_type VARCHAR(30) NOT NULL,
  requested_tier VARCHAR(30),
  current_tier VARCHAR(30),
  user_message TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  rejection_reason TEXT,
  reviewed_by_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
  reviewed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_access_requests_user_id ON access_requests(user_id);
CREATE INDEX idx_access_requests_status ON access_requests(status);
CREATE INDEX idx_access_requests_user_type_status ON access_requests(user_id, request_type, status);
CREATE UNIQUE INDEX uq_access_requests_pending_per_user_type
  ON access_requests(user_id, request_type)
  WHERE status = 'pending';

-- Tabla: auth_access_tokens
CREATE TABLE auth_access_tokens (
  id SERIAL PRIMARY KEY,
  tokenable_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(255) NOT NULL,
  name VARCHAR(255),
  hash VARCHAR(255) NOT NULL,
  abilities TEXT NOT NULL,
  created_at TIMESTAMP,
  updated_at TIMESTAMP,
  last_used_at TIMESTAMP,
  expires_at TIMESTAMP,
  deleted_at TIMESTAMP
);

-- Tabla: auth_email_tokens
-- Tokens de un solo uso para confirmar el correo de la cuenta y para restablecer
-- la contraseña. Se almacena el hash SHA-256 del token, nunca el token en claro.
CREATE TABLE auth_email_tokens (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  type VARCHAR(30) NOT NULL,
  token_hash VARCHAR(64) NOT NULL,
  expires_at TIMESTAMP NOT NULL,
  consumed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX uq_auth_email_tokens_hash ON auth_email_tokens(token_hash);
CREATE INDEX idx_auth_email_tokens_user_type ON auth_email_tokens(user_id, type);

-- Tabla: readings
CREATE TABLE readings (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    content TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'technology',
    difficulty VARCHAR(20) NOT NULL DEFAULT 'medium',
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    word_count INTEGER NOT NULL DEFAULT 0,
    status VARCHAR(20) NOT NULL DEFAULT 'pending',
    score INTEGER,
    passed BOOLEAN,
    user_response TEXT,
    feedback TEXT,
    -- La clave de idempotencia de la evaluacion: la envia el cliente (la
    -- app PWA la genera al encolar la respuesta sin conexion). Si la misma
    -- operacion llega dos veces, la segunda devuelve la evaluacion ya hecha
    -- en vez de error: sin esto, un envio reintentado evaluaria dos veces
    -- (y la IA cobraria dos veces).
    evaluation_operation_id VARCHAR(100),
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Índices para readings
CREATE INDEX idx_readings_user_id ON readings(user_id);
CREATE INDEX idx_readings_status ON readings(status);
CREATE UNIQUE INDEX uq_readings_evaluation_operation_id
    ON readings(evaluation_operation_id)
    WHERE evaluation_operation_id IS NOT NULL;
CREATE INDEX idx_readings_user_status ON readings(user_id, status) WHERE deleted_at IS NULL;
CREATE INDEX idx_readings_user_created_at ON readings(user_id, created_at) WHERE deleted_at IS NULL;

-- Tabla: reading_explanations (persiste preguntas/explicaciones de vocabulario, oraciones y glosario)
CREATE TABLE reading_explanations (
    id SERIAL PRIMARY KEY,
    reading_id INTEGER NOT NULL REFERENCES readings(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    word TEXT NOT NULL,
    normalized_word TEXT NOT NULL DEFAULT '',
    entry_type VARCHAR(20) NOT NULL DEFAULT 'word',
    language VARCHAR(10) NOT NULL DEFAULT 'en',
    difficulty VARCHAR(20) NOT NULL DEFAULT 'medium',
    context TEXT,
    literal_meaning TEXT,
    explanation TEXT NOT NULL,
    word_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
    other_ways_to_say JSONB NOT NULL DEFAULT '[]'::jsonb,
    other_contexts JSONB NOT NULL DEFAULT '[]'::jsonb,
    is_saved BOOLEAN NOT NULL DEFAULT FALSE,
    saved_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices para reading_explanations
CREATE INDEX idx_reading_explanations_reading_id ON reading_explanations(reading_id);
CREATE INDEX idx_reading_explanations_user_created ON reading_explanations(user_id, created_at);
CREATE INDEX idx_reading_explanations_created_at ON reading_explanations(created_at);
CREATE INDEX idx_reading_explanations_lookup ON reading_explanations(user_id, reading_id, normalized_word);
CREATE INDEX idx_reading_explanations_glossary ON reading_explanations(user_id, is_saved, language, entry_type, created_at DESC);

-- Tabla: prompt_logs (para persistir logs de generación de prompts)
CREATE TABLE prompt_logs (
    id SERIAL PRIMARY KEY,
    level VARCHAR(20) NOT NULL,
    event VARCHAR(100) NOT NULL,
    message TEXT NOT NULL,
    seed VARCHAR(255),
    user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    text_id INTEGER REFERENCES readings(id) ON DELETE SET NULL,
    request_id VARCHAR(64),
    ip_address VARCHAR(64),
    provider VARCHAR(30),
    model VARCHAR(60),
    params JSONB,
    system_prompt TEXT,
    user_prompt TEXT,
    error_message TEXT,
    error_stack TEXT,
    duration_ms INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices para prompt_logs
CREATE INDEX idx_prompt_logs_level ON prompt_logs(level);
CREATE INDEX idx_prompt_logs_event ON prompt_logs(event);
CREATE INDEX idx_prompt_logs_seed ON prompt_logs(seed);
CREATE INDEX idx_prompt_logs_user_id ON prompt_logs(user_id);
CREATE INDEX idx_prompt_logs_request_id ON prompt_logs(request_id);
CREATE INDEX idx_prompt_logs_created_at ON prompt_logs(created_at);
CREATE INDEX idx_prompt_logs_user_created ON prompt_logs(user_id, created_at);
CREATE INDEX idx_prompt_logs_event_created ON prompt_logs(event, created_at);

-- Tabla: moderated_categories (caché interna permanente de moderación y blueprint de prompt por clave canónica; no es catálogo global de usuarios)
CREATE TABLE moderated_categories (
    canonical_key VARCHAR(120) PRIMARY KEY,
    sample_category VARCHAR(100) NOT NULL,
    allowed BOOLEAN NOT NULL,
    layer VARCHAR(30),
    reason VARCHAR(120),
    provider VARCHAR(30) NOT NULL DEFAULT 'system',
    prompt_profile JSONB,
    profile_model VARCHAR(60),
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_moderated_categories_provider ON moderated_categories(provider);

-- Tabla: category_daily_usage (control diario por usuario de categorías distintas evaluadas)
CREATE TABLE category_daily_usage (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    usage_date VARCHAR(10) NOT NULL,
    canonical_key VARCHAR(120) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_category_daily_usage_user_day_key UNIQUE (user_id, usage_date, canonical_key)
);

-- Tabla: audit_logs (trazabilidad completa de operaciones, cambios CRUD before/after y eventos del sistema)
CREATE TABLE audit_logs (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(64),
    actor_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    actor_email VARCHAR(254),
    actor_role VARCHAR(30),
    target_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    ip_address VARCHAR(64),
    user_agent TEXT,
    http_method VARCHAR(10),
    http_path VARCHAR(500),
    http_status INTEGER,
    module VARCHAR(50) NOT NULL,
    action VARCHAR(30) NOT NULL,
    event VARCHAR(100) NOT NULL,
    entity_type VARCHAR(60),
    entity_id VARCHAR(120),
    summary TEXT NOT NULL,
    before_state JSONB,
    after_state JSONB,
    changed_fields JSONB NOT NULL DEFAULT '[]'::jsonb,
    metadata JSONB,
    duration_ms INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices para audit_logs
CREATE INDEX idx_audit_logs_request_id ON audit_logs(request_id);
CREATE INDEX idx_audit_logs_actor_user_id ON audit_logs(actor_user_id);
CREATE INDEX idx_audit_logs_target_user_id ON audit_logs(target_user_id);
CREATE INDEX idx_audit_logs_module_action ON audit_logs(module, action);
CREATE INDEX idx_audit_logs_event ON audit_logs(event);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_ip_address ON audit_logs(ip_address);
CREATE INDEX idx_audit_logs_created_at ON audit_logs(created_at DESC);
CREATE INDEX idx_audit_logs_actor_created ON audit_logs(actor_user_id, created_at DESC);

-- Tabla: error_logs (registro centralizado de fallos HTTP 4xx/5xx, excepciones no controladas, fallos SMTP/IA/moderación)
CREATE TABLE error_logs (
    id SERIAL PRIMARY KEY,
    request_id VARCHAR(64),
    severity VARCHAR(20) NOT NULL DEFAULT 'error',
    source VARCHAR(40) NOT NULL,
    module VARCHAR(50),
    error_code VARCHAR(80) NOT NULL,
    http_status INTEGER,
    message TEXT NOT NULL,
    error_name VARCHAR(120),
    error_stack TEXT,
    actor_user_id INTEGER REFERENCES users(id) ON DELETE SET NULL,
    actor_email VARCHAR(254),
    actor_role VARCHAR(30),
    ip_address VARCHAR(64),
    user_agent TEXT,
    http_method VARCHAR(10),
    http_path VARCHAR(500),
    request_body JSONB,
    request_query JSONB,
    details JSONB,
    duration_ms INTEGER,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices para error_logs
CREATE INDEX idx_error_logs_request_id ON error_logs(request_id);
CREATE INDEX idx_error_logs_severity ON error_logs(severity);
CREATE INDEX idx_error_logs_source ON error_logs(source);
CREATE INDEX idx_error_logs_error_code ON error_logs(error_code);
CREATE INDEX idx_error_logs_http_status ON error_logs(http_status);
CREATE INDEX idx_error_logs_actor_user_id ON error_logs(actor_user_id);
CREATE INDEX idx_error_logs_ip_address ON error_logs(ip_address);
CREATE INDEX idx_error_logs_created_at ON error_logs(created_at DESC);

-- Tabla: billing_subscriptions (espejo de la suscripción recurrente en Stripe por usuario)
CREATE TABLE billing_subscriptions (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL UNIQUE REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(20) NOT NULL DEFAULT 'stripe',
  stripe_customer_id VARCHAR(64) NOT NULL,
  stripe_subscription_id VARCHAR(64) NOT NULL UNIQUE,
  stripe_price_id VARCHAR(64) NOT NULL,
  tier VARCHAR(30) NOT NULL,
  status VARCHAR(30) NOT NULL,
  current_period_start TIMESTAMP,
  current_period_end TIMESTAMP,
  cancel_at_period_end BOOLEAN NOT NULL DEFAULT FALSE,
  canceled_at TIMESTAMP,
  payment_method_brand VARCHAR(30),
  payment_method_last4 VARCHAR(4),
  payment_method_exp_month INTEGER,
  payment_method_exp_year INTEGER,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_billing_subscriptions_customer ON billing_subscriptions(stripe_customer_id);
CREATE INDEX idx_billing_subscriptions_status ON billing_subscriptions(status);

-- Tabla: billing_payments (historial e idempotencia de pagos únicos y facturas de suscripción)
CREATE TABLE billing_payments (
  id SERIAL PRIMARY KEY,
  user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider VARCHAR(20) NOT NULL DEFAULT 'stripe',
  kind VARCHAR(40) NOT NULL,
  tier VARCHAR(30),
  stripe_checkout_session_id VARCHAR(128) UNIQUE,
  stripe_payment_intent_id VARCHAR(128),
  stripe_invoice_id VARCHAR(128) UNIQUE,
  amount_cents INTEGER NOT NULL DEFAULT 0,
  currency VARCHAR(10) NOT NULL DEFAULT 'mxn',
  status VARCHAR(30) NOT NULL DEFAULT 'pending',
  fulfilled_at TIMESTAMP,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_billing_payments_user_created ON billing_payments(user_id, created_at DESC);
CREATE INDEX idx_billing_payments_kind_status ON billing_payments(kind, status);

-- Tabla: billing_webhook_events (registro de deduplicación e idempotencia por event_id de Stripe)
CREATE TABLE billing_webhook_events (
  event_id VARCHAR(120) PRIMARY KEY,
  provider VARCHAR(20) NOT NULL DEFAULT 'stripe',
  event_type VARCHAR(100) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'processing',
  error_message TEXT,
  processed_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_billing_webhook_events_type_created ON billing_webhook_events(event_type, created_at DESC);
