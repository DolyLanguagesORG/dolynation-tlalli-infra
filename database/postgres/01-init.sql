-- Tabla: users
CREATE TABLE users (
  id SERIAL PRIMARY KEY,
  full_name VARCHAR(255),
  email VARCHAR(254) NOT NULL UNIQUE,
  password VARCHAR(255) NOT NULL,
  current_streak INTEGER NOT NULL DEFAULT 0,
  last_streak_date DATE,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP,
  deleted_at TIMESTAMP
);

-- Tabla: user_settings
-- Preferencias de estudio por usuario (idioma de superficie y categorias
-- elegidas). El backend las mapea en Drizzle (`user_settings`); sin esta
-- tabla el modulo de settings no puede leer ni escribir.
-- Ver `updates/06-user-settings.sql`.
CREATE TABLE user_settings (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  preferred_language VARCHAR(10) NOT NULL DEFAULT 'en',
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

-- Tabla: readings
CREATE TABLE readings (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    description TEXT NOT NULL,
    content TEXT NOT NULL,
    category VARCHAR(50) NOT NULL DEFAULT 'technology',
    difficulty VARCHAR(20) NOT NULL DEFAULT 'medium',
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
