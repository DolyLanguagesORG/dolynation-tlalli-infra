# DB updates

Esta carpeta contiene los cambios incrementales al schema. Desde S2 se
mantienen **aunque producción todavía no se haya desplegado**, para probar la
ruta de migración y preparar el primer deploy real.

> **¿Por qué existen los updates?**
>
> Una base nueva se crea desde `01-init.sql`. Una base existente (prod, staging
> o una BD de desarrollo con datos) no vuelve a ejecutar `initdb.d/`, así que
> los cambios llegan como scripts `ALTER` idempotentes en esta carpeta.

## Convención de nombres

```
NN-<short-kebab-name>.sql
```

- `NN` es un número secuencial de dos dígitos (`02`, `03`, `04`, …).
- El orden de aplicación es numérico.
- No renombrar un archivo después de aplicarlo a un entorno persistente.

Ejemplos actuales:

- `02-sprint2-study-config.sql`
- `03-sprint3-evaluations-vocabulary.sql`
- `04-sprint4-admin-role.sql`

## Regla de idempotencia (obligatoria)

Todos los statements deben poder ejecutarse más de una vez sin romper la BD:

```sql
CREATE TABLE IF NOT EXISTS categories (...);
CREATE INDEX IF NOT EXISTS idx_readings_prompt_hash ON readings(user_id, prompt_hash);
ALTER TABLE readings ADD COLUMN IF NOT EXISTS language VARCHAR(10) NOT NULL DEFAULT 'en';
```

En PostgreSQL 15 **no** uses `ALTER TABLE ... DROP COLUMN IF EXISTS` (es de
Postgres 16+). Si necesitas eliminar una columna, documenta el script como
ejecución única.

## Workflow

1. Crear `NN-<nombre>.sql` con el cambio idempotente.
2. Actualizar `01-init.sql` para que una base nueva tenga el mismo estado final.
3. Probar el script en una base limpia y en una base existente.
4. Commit de ambos archivos en el mismo PR de infra.
5. Los cambios de código backend van en su repo y en commits/PRs separados.

## Regla de dos fases

- **Antes del primer deploy real a prod:** `01-init.sql` y `updates/` se
  mantienen sincronizados; las bases nuevas usan `01-init.sql` y los updates
  se prueban aparte.
- **Después del primer deploy real a prod:** `01-init.sql` se congela y todo
  cambio va solo en un nuevo update.

Detalle completo en la
[convención de base de datos](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/database.md).
