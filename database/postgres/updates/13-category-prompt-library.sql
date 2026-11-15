-- ============================================================
-- Actualización 13: Biblioteca global de prompts por categoría
-- ============================================================
-- Extiende la caché global permanente `moderated_categories` para almacenar
-- también el blueprint editorial reutilizable (`prompt_profile` JSONB y
-- `profile_model`) de cada categoría personalizada aprobada.
--
-- Cuando un usuario registra o consulta por primera vez una categoría válida
-- (p. ej. "Día de Muertos"), el veredicto de moderación y su guía editorial /
-- subtemas / ángulos / conceptos clave se persisten una sola vez para todos
-- los usuarios, evitando repetir llamadas de enriquecimiento en cada lectura.
--
-- Statements 100% idempotentes aptos para PostgreSQL 15+.

ALTER TABLE moderated_categories
    ADD COLUMN IF NOT EXISTS prompt_profile JSONB,
    ADD COLUMN IF NOT EXISTS profile_model VARCHAR(60);
