-- Tabla: users
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(255),
  email VARCHAR(254) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  subscription_tier VARCHAR(30) DEFAULT NULL,
  current_streak INTEGER NOT NULL DEFAULT 0,
  last_streak_date DATE,
  -- Marca de verificación del correo. NULL = la cuenta todavía no confirmó su correo.
  -- Ver `updates/11-email-tokens.sql`.
  email_verified_at TIMESTAMP,
  -- Locale de interfaz del usuario (`es` | `en`) para los correos transaccionales.
  -- No es el idioma de estudio (vive en `user_settings.selected_languages`).
  locale VARCHAR(10) NOT NULL DEFAULT 'es',
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  deleted_at TIMESTAMP
);

-- Tabla: user_settings
-- Preferencias de estudio por usuario (idiomas ordenados por prioridad,
-- bloqueo de cambio anual, creditos pagados de cambio y categorias elegidas).
-- El backend las mapea en Drizzle (`user_settings`); sin esta tabla el modulo
-- de settings no puede leer ni escribir.
-- Ver `updates/06-user-settings.sql` y `updates/08-language-plans.sql`.
CREATE TABLE user_settings (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  preferred_language VARCHAR(10),
  selected_languages JSONB NOT NULL DEFAULT '[]'::jsonb,
  last_language_change_at TIMESTAMP,
  language_change_credits INTEGER NOT NULL DEFAULT 0,
  preferred_categories JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

-- Índices para user_settings
CREATE INDEX idx_user_settings_user_id ON user_settings(user_id);

-- Tabla: admins
-- Administradores de la aplicacion. Va aparte de `users` a proposito: los
-- SELECTs sobre `users` no cambian hasta que exista la migracion que decida
-- si el rol vive en `users` o aqui.
-- Ver `updates/05-admin-table.sql` y `atl-back#39`.
CREATE TABLE admins (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  granted_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Índices para admins
CREATE INDEX idx_admins_user_id ON admins(user_id);

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
-- Ver `updates/11-email-tokens.sql`.
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
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP,
    deleted_at TIMESTAMP
);

-- Índices para readings
CREATE INDEX idx_readings_user_id ON readings(user_id);
CREATE INDEX idx_readings_status ON readings(status);
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
CREATE INDEX idx_prompt_logs_created_at ON prompt_logs(created_at);
CREATE INDEX idx_prompt_logs_user_created ON prompt_logs(user_id, created_at);
CREATE INDEX idx_prompt_logs_event_created ON prompt_logs(event, created_at);

-- Tabla: moderated_categories (caché permanente de moderación por clave canónica)
CREATE TABLE moderated_categories (
    canonical_key VARCHAR(120) PRIMARY KEY,
    sample_category VARCHAR(100) NOT NULL,
    allowed BOOLEAN NOT NULL,
    layer VARCHAR(30),
    reason VARCHAR(120),
    provider VARCHAR(30) NOT NULL DEFAULT 'system',
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
