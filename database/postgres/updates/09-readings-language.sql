-- 09-readings-language.sql
--
-- Persiste el idioma objetivo de cada lectura (`es`, `en`, `fr`, `it`) en la
-- tabla `readings` para trazabilidad, evaluación de comprensión y explicaciones
-- contextuales en los 4 idiomas soportados.
-- Statement idempotente seguro sobre bases ya inicializadas.

ALTER TABLE readings
  ADD COLUMN IF NOT EXISTS language VARCHAR(10) NOT NULL DEFAULT 'en';
