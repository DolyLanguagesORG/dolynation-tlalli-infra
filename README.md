# Infrastructure — `dolynation-tlalli-infra`

Servicios dockerizados para DolyNation: PostgreSQL en dev/test/prod, el
backend en producción y el **schema SQL** (fuente de verdad de la base de
datos).

> El backend vive en
> [`dolynation-atl-back`](https://github.com/DolyLanguagesORG/dolynation-atl-back).
> Este repo lo **clona y builda**; no contiene su código.

## Archivos

```
.
├── docker-compose.test.yml    # Postgres standalone (tests + dev local)
├── docker-compose.dev.yml     # Stack de DESARROLLO (codigo montado, modo watch)
├── docker-compose.env.yml     # Stack de STAGING / PRODUCCION / REHEARSAL (por imagen)
├── docker-compose.prod.yml    # (obsoleto) Postgres + backend compilado en el host
├── versions.yml               # Manifiesto: que version de cada repo compone la app
├── scripts/
│   ├── apply-schema.sh          # Deja la base con el schema actual (hash + recreacion)
│   ├── deploy-dev-back.sh     # Autodespliegue del backend a desarrollo
│   ├── deploy-dev-front.sh    # Autodespliegue del frontend a desarrollo
│   ├── deploy-env.sh          # Despliegue por imagen de staging / produccion
│   └── smoke-test.sh          # Verifica que el ambiente cumple el contrato
├── .env.example
└── database/
    └── postgres/
        └── 01-init.sql                 # El schema completo (un solo archivo)
```

## Los tres ambientes

| Ambiente | Directorio | Puertos | Como se despliega |
| --- | --- | --- | --- |
| Desarrollo | `/srv/doly/dev` | 57010-57012 | codigo montado, modo watch |
| Rehearsal | `/srv/doly/rehearsal` | 57040-57042 | **por imagen** |
| Staging | `/srv/doly/staging` | 57020-57022 | **por imagen** |
| Produccion | `/srv/doly/prod` | 57030-57032 | **por imagen** |

Staging, produccion y rehearsal usan el **mismo** `docker-compose.env.yml`,
parametrizado por puertos. Los tres se despliegan **por imagen**: el servidor
nunca compila. Si dos maquinas compilaran el mismo commit, no serian el mismo
binario; una imagen es inmutable y se puede volver atras.

`rehearsal` existe para probar el tren completo (develop → rc → despliegue →
healthcheck → smoke test) sin tocar staging ni produccion.


## Levantar Postgres para desarrollo / tests

```bash
docker compose -f docker-compose.test.yml up -d
```

El contenedor expone Postgres en `localhost:57000` (puerto host) →
`5432` (puerto container). El schema se aplica automáticamente al primer
arranque desde `01-init.sql`.

Variables en [`.env.example`](./.env.example):

```env
DB_USER=postgres
DB_PASSWORD=postgres
DB_DATABASE=dolynglish_test
DB_PORT=57000
```

## Desplegar staging / producción

El despliegue lo hace `scripts/deploy-env.sh`, que lee `versions.yml` y
despliega **exactamente** las versiones declaradas: baja las imágenes ya
construidas desde GHCR y levanta el stack. Nunca compila en el servidor.

```bash
# En el servidor, con el .env del ambiente ya escrito por el workflow:
COMPOSE_PROJECT_NAME=doly-staging \
DB_HOST_PORT=57020 BACKEND_HOST_PORT=57021 FRONTEND_HOST_PORT=57022 \
  bash scripts/deploy-env.sh
```

El manifiesto dice qué versión de cada repositorio compone la app publicada:

```yaml
app_version: 0.2.1
repositories:
  dolynation-atl-back:
    version: 0.2.1
    tag: v0.2.1
    commit: a8525a278b81eb37b19f9f289e5b87128f9079fc
```

El **backend** se despliega por SHA (inmutable: es lo que corre y lo que
permite el rollback) y el **frontend** por versión.

### Rollback

Cambiar la etiqueta de la imagen es el rollback:

```bash
COMPOSE_PROJECT_NAME=doly-staging IMAGE_TAG=<sha-anterior> \
  bash scripts/deploy-env.sh
```

### Smoke test

```bash
bash scripts/smoke-test.sh <url-api> <url-frontend> <version-esperada>
```

Verifica que el ambiente cumple el contrato y **falla** si algo no cuadra.

## Verificar

```bash
# Estado de los contenedores
docker compose -f docker-compose.test.yml ps

# Conectar a la BD
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test

# Ver tablas
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test -c "\dt"

# Logs
docker compose -f docker-compose.test.yml logs -f postgres
```

## Reset completo

Para empezar de cero (incluyendo los datos):

```bash
docker compose -f docker-compose.test.yml down -v
docker compose -f docker-compose.test.yml up -d
```

El `-v` borra los volúmenes (datos persistidos). El contenedor recreará
el schema al arrancar.

## Schema SQL

El schema completo vive en
[`database/postgres/01-init.sql`](./database/postgres/01-init.sql). Se
aplica automáticamente al primer arranque del contenedor de Postgres
(vía `/docker-entrypoint-initdb.d/`). En arranques posteriores no se
vuelve a aplicar.

> **Este repo es el dueño del schema.** El CI del backend
> (`dolynation-atl-back`) hace checkout de este repositorio para aplicar
> `01-init.sql` en sus tests e2e.

### Cambios al schema: un solo archivo

El schema completo vive en **un solo archivo**,
[`database/postgres/01-init.sql`](./database/postgres/01-init.sql). **No hay
carpeta `updates/`**: mientras producción no tenga datos, un cambio de schema
se hace ahí y nada más.

El detalle que lo hace funcionar: Postgres solo ejecuta
`/docker-entrypoint-initdb.d/` **cuando el volumen de datos está vacío**. En
un ambiente que ya existe, cambiar el archivo **no** cambia la base, y el
backend nuevo falla con HTTP 500 en cuanto toca una tabla nueva.

Por eso `scripts/apply-schema.sh` (que ejecutan todos los deploys) compara
el hash de `01-init.sql` con el hash guardado **dentro de la base**:

| Situación | Qué hace |
| --- | --- |
| El schema no cambió | No toca nada (el caso normal de cada deploy) |
| El schema cambió y la base **no** tiene datos | Recrea la base: Postgres aplica el schema solo |
| El schema cambió y la base **sí** tiene datos | **No borra nada** y el deploy se detiene: hay que migrar a mano |

Es decir: **un cambio de schema y un deploy son la misma operación**.

### Fase 2: cuando producción tenga datos

En cuanto producción tenga datos reales, recrear la base deja de ser una
opción. Ahi:

- `01-init.sql` **se congela**: ya no se edita.
- Los cambios van en `database/postgres/updates/NN-<nombre>.sql`, en orden
  numérico, **idempotentes** (`IF NOT EXISTS`, `ON CONFLICT`, backfills con
  `WHERE ... IS NULL`).
- `apply-schema.sh` pasa a aplicar los updates sobre la base existente.

El cambio de fase se hace **a mano y con un PR propio**.

Detalles completos en la
[convención de base de datos](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/database.md).
