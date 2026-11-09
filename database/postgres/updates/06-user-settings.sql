-- 06-user-settings.sql
--
-- Preferencias de estudio por usuario (idioma de superficie y categorias
-- elegidas). El backend ya las mapea en Drizzle
-- (`atl-back`: `src/database/drizzle/schema.ts`, tabla `user_settings`), pero
-- faltaba el CREATE TABLE en el schema de infra: sin esta tabla, el modulo
-- de settings no puede leer ni escribir.
--
-- Idempotente: se puede ejecutar mas de una vez sin romper la base.

CREATE TABLE IF NOT EXISTS user_settings (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  preferred_language VARCHAR(10) NOT NULL DEFAULT 'en',
  preferred_categories JSONB NOT NULL DEFAULT '[]'::jsonb,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_user_settings_user_id ON user_settings(user_id);
