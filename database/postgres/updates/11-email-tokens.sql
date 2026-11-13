-- 11-email-tokens.sql
--
-- Persiste:
--   1. `auth_email_tokens`: tokens de un solo uso para confirmar el correo de la
--      cuenta y para restablecer la contraseña. Se guarda **el hash SHA-256**
--      del token, nunca el token en claro (mismo criterio que
--      `auth_access_tokens.hash`).
--   2. `users.email_verified_at`: marca de verificación del correo.
--   3. `users.locale`: locale de interfaz del usuario (`es` | `en`) usado para
--      elegir el idioma de los correos transaccionales. No es el idioma de
--      estudio, que vive en `user_settings.selected_languages`.
--
-- Statements 100% idempotentes aptos para PostgreSQL 15+.

-- Columnas nuevas en users
ALTER TABLE users ADD COLUMN IF NOT EXISTS email_verified_at TIMESTAMP;
ALTER TABLE users ADD COLUMN IF NOT EXISTS locale VARCHAR(10) NOT NULL DEFAULT 'es';

-- Backfill: las cuentas existentes quedan como verificadas para que activar
-- `EMAIL_VERIFICATION_REQUIRED` en produccion no bloquee a nadie. Es
-- re-ejecutable porque solo toca las filas con `email_verified_at IS NULL`.
UPDATE users SET email_verified_at = created_at WHERE email_verified_at IS NULL;

-- Tabla: auth_email_tokens
CREATE TABLE IF NOT EXISTS auth_email_tokens (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(30) NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    consumed_at TIMESTAMP,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- El hash es único: garantiza que un token no se puede reutilizar bajo dos filas.
CREATE UNIQUE INDEX IF NOT EXISTS uq_auth_email_tokens_hash
    ON auth_email_tokens(token_hash);

-- Búsqueda habitual: tokens activos de un usuario por tipo.
CREATE INDEX IF NOT EXISTS idx_auth_email_tokens_user_type
    ON auth_email_tokens(user_id, type);
