---
name: schema-migrations
description: Cómo cambiar el schema PostgreSQL de DolyNation (repo dolynation-tlalli-infra). Cubre 01-init.sql, updates/NN-*.sql, idempotencia, regla de dos fases, backfills y verificación. Úsala al agregar tablas, columnas, índices, constraints o migrar datos.
---

# Schema y migraciones — DolyNation

## Fuente de verdad

- `database/postgres/01-init.sql` — estado final para bases nuevas.
- `database/postgres/updates/NN-<nombre>.sql` — cambios incrementales
  idempotentes.
- El backend **no** ejecuta DDL. Drizzle solo mapea tipos en
  `dolynation-atl-back/src/database/drizzle/`.

Modelo documentado:
[`architecture/data-model.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/architecture/data-model.md).

## Regla de dos fases

### Antes del primer deploy real a prod

- Mantener `01-init.sql` y `updates/` sincronizados.
- Las bases nuevas usan `01-init.sql`; los updates se prueban aparte para
  validar la ruta de migración.
- Los updates de S2/S3/S4 ya están planificados:
  - `02-sprint2-study-config.sql` — preferencias, categorías, idioma,
    longitud y `prompt_hash`.
  - `03-sprint3-evaluations-vocabulary.sql` — `evaluations` y
    `vocabulary_logs`.
  - `04-sprint4-admin-role.sql` — `users.role`.

### Después del primer deploy real a prod

- `01-init.sql` se congela.
- Todo cambio va solo en un nuevo `updates/NN-...sql`.

## Reglas de escritura

- Usa `IF NOT EXISTS` en tablas, columnas e índices.
- Usa `ON CONFLICT` para seeds.
- Backfills en el mismo script, con `WHERE ... IS NULL` para que sea
  re-ejecutable.
- PostgreSQL 15: **no** uses `DROP COLUMN IF EXISTS` (Postgres 16+).
- No borres columnas con datos sin un plan de transición; marca la columna como
  deprecada y elimínala en un update posterior.
- Nombres en `snake_case`; archivos `NN-kebab-case.sql`.

## Ejemplo de migración

```sql
-- 02-sprint2-study-config.sql
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(50) NOT NULL,
  description TEXT,
  is_global BOOLEAN NOT NULL DEFAULT false,
  created_by_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE readings ADD COLUMN IF NOT EXISTS language VARCHAR(10) NOT NULL DEFAULT 'en';
ALTER TABLE readings ADD COLUMN IF NOT EXISTS length_type VARCHAR(20) NOT NULL DEFAULT 'medium';
ALTER TABLE readings ADD COLUMN IF NOT EXISTS prompt_hash VARCHAR(64);

INSERT INTO categories (slug, name, is_global)
VALUES ('technology', 'Technology', true)
ON CONFLICT (slug) DO NOTHING;
```

## Workflow

1. Crear `NN-<nombre>.sql`.
2. Actualizar `01-init.sql` con el mismo estado final.
3. Probar en base limpia y existente; ejecutar dos veces.
4. Verificar con `\d`, conteos y queries de backfill.
5. Commit de ambos archivos en el mismo PR de infra.
6. Cerrar el issue de migración (`infra#20`, `infra#21` o `infra#22`) con
   evidencia.

## Verificación

```bash
docker compose -f docker-compose.test.yml down -v
docker compose -f docker-compose.test.yml up -d
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test -c "\dt"
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test -f /docker-entrypoint-initdb.d/updates/02-sprint2-study-config.sql
```

## Referencias

- [Convención de base de datos](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/database.md)
- [data-model.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/architecture/data-model.md)
- [updates/README.md](../../../database/postgres/updates/README.md)
