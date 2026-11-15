---
name: schema-migrations
description: Cómo cambiar el schema PostgreSQL de DolyNation (repo dolynation-tlalli-infra). Cubre el schema en un solo archivo (01-init.sql), el runner apply-schema.sh, la fase de updates/NN-*.sql cuando haya datos en producción, idempotencia, backfills y verificación. Úsala al agregar tablas, columnas, índices o constraints.
---

# Schema y migraciones — DolyNation

## Fuente de verdad

- `database/postgres/01-init.sql` — **el schema completo, en un solo archivo**.
- El backend **no** ejecuta DDL. Drizzle solo mapea tipos en
  `dolynation-atl-back/src/database/drizzle/`.
- `scripts/apply-schema.sh` — el runner que deja la base del ambiente con el
  schema actual. Lo ejecutan los deploys (infra, staging, produccion).

Modelo documentado:
[`architecture/data-model.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/architecture/data-model.md).

## Fase 1 (la actual): el schema en un solo archivo

**Mientras no haya datos en produccion, el schema se cambia en un solo
lugar**: `database/postgres/01-init.sql`. No hay carpeta `updates/`.

Por qué funciona:

- `01-init.sql` se monta en `/docker-entrypoint-initdb.d`, pero PostgreSQL
  **solo ejecuta esos scripts cuando el volumen de datos esta vacio**. Por
  eso, cambiar el archivo no cambia la base de un ambiente que ya existe.
- `scripts/apply-schema.sh` resuelve eso: compara el hash de `01-init.sql`
  con el hash guardado **dentro de la base** (tabla `schema_metadata`) y, si
  cambio, **recrea** la base (que es lo unico que hace que Postgres aplique
  el schema de nuevo).
- Si la base **tiene datos** y el schema cambio, el script **se niega** a
  recrearla y falla: en staging y produccion el deploy se detiene antes de
  dejar la app contra un schema incompatible.

Consecuencia práctica: **un cambio de schema y un deploy son la misma
operación**. No hay que acordarse de aplicar nada a mano.

### Reglas de escritura

- Usa `IF NOT EXISTS` en tablas, columnas e índices.
- Usa `ON CONFLICT` para seeds.
- Backfills en el mismo script, con `WHERE ... IS NULL` para que sea
  re-ejecutable.
- PostgreSQL 15: **no** uses `DROP COLUMN IF EXISTS` (Postgres 16+).
- No borres columnas con datos sin un plan de transición; marca la columna como
  deprecada y elimínala en otro script posterior.
- Nombres en `snake_case`.

## Fase 2: cuando produccion tenga datos

En cuanto producción tenga datos reales, recrear la base deja de ser una
opción. Ahi se activa la ruta de migraciones incrementales:

- `01-init.sql` **se congela**: ya no se edita.
- Los cambios van en `database/postgres/updates/NN-<nombre>.sql`, en orden
  numérico, **idempotentes** (`IF NOT EXISTS`, `ON CONFLICT`, backfills con
  `WHERE ... IS NULL`).
- `apply-schema.sh` deja de recrear y pasa a **aplicar los updates** sobre la
  base existente, registrando los ya aplicados.

El cambio de fase se hace **a mano y con un PR propio**: no se mezcla con un
cambio de schema normal.

### Cómo se ve un update

```sql
-- 02-sprint2-study-config.sql
CREATE TABLE IF NOT EXISTS categories (
  id SERIAL PRIMARY KEY,
  slug VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(50) NOT NULL,
  created_by_user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE readings ADD COLUMN IF NOT EXISTS language VARCHAR(10) NOT NULL DEFAULT 'en';
ALTER TABLE readings ADD COLUMN IF NOT EXISTS prompt_hash VARCHAR(64);

INSERT INTO categories (slug, name, is_global)
VALUES ('technology', 'Technology', true)
ON CONFLICT (slug) DO NOTHING;
```

## Workflow

### Fase 1 (schema en un solo archivo)

1. Editar `database/postgres/01-init.sql` con el estado nuevo.
2. Comprobar que el schema sigue siendo **válido**:
   `docker compose -f docker-compose.test.yml config` y el job `schema-sql`
   de la CI.
3. PR a `develop` con `Closes #N`.
4. El deploy aplica el schema solo (`scripts/apply-schema.sh`).

### Fase 2 (updates incrementales)

1. Crear `NN-<nombre>.sql` en `database/postgres/updates/`.
2. Probar en base limpia y existente; **ejecutar dos veces** (idempotencia).
3. Verificar con `\d`, conteos y queries de backfill.
4. Commit de ambos archivos en el mismo PR de infra.
5. Cerrar el issue de migración con evidencia.

## Verificación

```bash
# El schema aplica sobre una base limpia
docker compose -f docker-compose.test.yml down -v
docker compose -f docker-compose.test.yml up -d
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test -c "\dt"

# El runner dice si el schema esta al dia (sin tocar nada)
CHECK_ONLY=1 bash scripts/apply-schema.sh
```

En la CI, el job `schema-sql` aplica `01-init.sql` sobre un Postgres 15
limpio y comprueba que existan las 10 tablas que el backend mapea con Drizzle.

## Referencias

- [Convención de base de datos](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/database.md)
- [data-model.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/architecture/data-model.md)
