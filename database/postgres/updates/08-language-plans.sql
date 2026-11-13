-- 08-language-plans.sql
--
-- Agrega soporte de seleccion ordenada de idiomas por plan, bloqueo anual de
-- cambios de idioma y creditos pagados de desbloqueo en `user_settings`.
-- Todos los statements son idempotentes para ejecutarse con seguridad sobre
-- bases creadas con `updates/06-user-settings.sql`.

ALTER TABLE user_settings
  ALTER COLUMN preferred_language DROP NOT NULL;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS selected_languages JSONB NOT NULL DEFAULT '[]'::jsonb;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS last_language_change_at TIMESTAMP;

ALTER TABLE user_settings
  ADD COLUMN IF NOT EXISTS language_change_credits INTEGER NOT NULL DEFAULT 0;
