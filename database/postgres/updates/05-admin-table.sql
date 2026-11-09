-- 05-admin-role.sql
--
-- Tabla de administradores. La pidió `atl-back#39` (endpoints /admin/*).
--
-- Se mantiene aparte de `users` a propósito: los SELECTs sobre `users` no
-- cambian hasta que exista la migracion que decida si el rol vive en la
-- tabla de usuarios o en esta.
--
-- Idempotente: se puede ejecutar mas de una vez sin romper la base.

CREATE TABLE IF NOT EXISTS admins (
  user_id INTEGER PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  granted_at TIMESTAMP NOT NULL DEFAULT NOW()
);

-- Un administrador sin fila en `admins` no es administrador: el guard lo
-- consulta en cada peticion, asi que el indice por user_id es el que usa.
CREATE INDEX IF NOT EXISTS idx_admins_user_id ON admins(user_id);
