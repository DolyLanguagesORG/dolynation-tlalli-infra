-- 07-subscriptions.sql
--
-- Flujo de suscripciones: columna `subscription_tier` en `users`,
-- tabla `reading_explanations` para tracking diario de preguntas e
-- índice de lecturas por usuario y fecha de creación.
--
-- Idempotente: se puede ejecutar más de una vez sin romper la base.

-- 1. Columna subscription_tier en users (NULL por defecto para usuarios nuevos)
ALTER TABLE users ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(30) DEFAULT NULL;

-- 2. Tabla reading_explanations (persiste preguntas/explicaciones por lectura)
CREATE TABLE IF NOT EXISTS reading_explanations (
    id SERIAL PRIMARY KEY,
    reading_id INTEGER NOT NULL REFERENCES readings(id) ON DELETE CASCADE,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    word VARCHAR(255) NOT NULL,
    context TEXT,
    explanation TEXT NOT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Índices para reading_explanations
CREATE INDEX IF NOT EXISTS idx_reading_explanations_reading_id ON reading_explanations(reading_id);
CREATE INDEX IF NOT EXISTS idx_reading_explanations_user_created ON reading_explanations(user_id, created_at);
CREATE INDEX IF NOT EXISTS idx_reading_explanations_created_at ON reading_explanations(created_at);

-- Índice para conteo diario de lecturas generadas por usuario
CREATE INDEX IF NOT EXISTS idx_readings_user_created_at ON readings(user_id, created_at) WHERE deleted_at IS NULL;
