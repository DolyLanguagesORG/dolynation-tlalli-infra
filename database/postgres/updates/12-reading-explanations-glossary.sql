-- ============================================================
-- Actualización 12: Ayuda contextual enriquecida y glosario persistente
-- ============================================================
-- Extiende `reading_explanations` para almacenar explicaciones estructuradas
-- de palabras y oraciones/expresiones (desglose palabra por palabra, sentido
-- literal vs. contextual, otras formas de decirlo y otros contextos de uso),
-- habilitar caché por lectura y soportar el glosario persistente del usuario.
-- Es 100% idempotente sobre PostgreSQL 15.

ALTER TABLE reading_explanations
    ALTER COLUMN word TYPE TEXT;

ALTER TABLE reading_explanations
    ADD COLUMN IF NOT EXISTS normalized_word TEXT,
    ADD COLUMN IF NOT EXISTS entry_type VARCHAR(20) NOT NULL DEFAULT 'word',
    ADD COLUMN IF NOT EXISTS language VARCHAR(10),
    ADD COLUMN IF NOT EXISTS difficulty VARCHAR(20),
    ADD COLUMN IF NOT EXISTS literal_meaning TEXT,
    ADD COLUMN IF NOT EXISTS word_breakdown JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS other_ways_to_say JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS other_contexts JSONB NOT NULL DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS is_saved BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS saved_at TIMESTAMP,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP;

UPDATE reading_explanations
SET
    normalized_word = LOWER(REGEXP_REPLACE(TRIM(word), '\s+', ' ', 'g')),
    entry_type = CASE
        WHEN REGEXP_REPLACE(TRIM(word), '\s+', ' ', 'g') ~ '\s' THEN 'phrase'
        ELSE 'word'
    END
WHERE normalized_word IS NULL OR normalized_word = '';

UPDATE reading_explanations re
SET
    language = COALESCE(r.language, 'en'),
    difficulty = COALESCE(r.difficulty, 'medium')
FROM readings r
WHERE re.reading_id = r.id
  AND (re.language IS NULL OR re.difficulty IS NULL);

UPDATE reading_explanations SET language = 'en' WHERE language IS NULL;
UPDATE reading_explanations SET difficulty = 'medium' WHERE difficulty IS NULL;

ALTER TABLE reading_explanations
    ALTER COLUMN normalized_word SET DEFAULT '',
    ALTER COLUMN normalized_word SET NOT NULL,
    ALTER COLUMN language SET DEFAULT 'en',
    ALTER COLUMN language SET NOT NULL,
    ALTER COLUMN difficulty SET DEFAULT 'medium',
    ALTER COLUMN difficulty SET NOT NULL;

CREATE INDEX IF NOT EXISTS idx_reading_explanations_lookup
    ON reading_explanations(user_id, reading_id, normalized_word);

CREATE INDEX IF NOT EXISTS idx_reading_explanations_glossary
    ON reading_explanations(user_id, is_saved, language, entry_type, created_at DESC);
