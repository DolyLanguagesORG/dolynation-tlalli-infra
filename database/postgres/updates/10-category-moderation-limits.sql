-- 10-category-moderation-limits.sql
--
-- Persiste:
--   1. `moderated_categories`: caché global permanente de veredictos de moderación
--      por clave canónica para evitar llamadas repetidas a OpenAI Moderation o MiniMax-M3.
--   2. `category_daily_usage`: registro diario por usuario de categorías dinámicas
--      distintas evaluadas (`America/Mexico_City`) para frenar el abuso de borrado/creación
--      en bucle (`CATEGORY_DAILY_LIMIT`, por defecto 20/día).
--
-- Statements 100% idempotentes aptos para PostgreSQL 15+.

CREATE TABLE IF NOT EXISTS moderated_categories (
    canonical_key VARCHAR(120) PRIMARY KEY,
    sample_category VARCHAR(100) NOT NULL,
    allowed BOOLEAN NOT NULL,
    layer VARCHAR(30),
    reason VARCHAR(120),
    provider VARCHAR(30) NOT NULL DEFAULT 'system',
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_moderated_categories_provider ON moderated_categories(provider);

CREATE TABLE IF NOT EXISTS category_daily_usage (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    usage_date VARCHAR(10) NOT NULL,
    canonical_key VARCHAR(120) NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uq_category_daily_usage_user_day_key UNIQUE (user_id, usage_date, canonical_key)
);
