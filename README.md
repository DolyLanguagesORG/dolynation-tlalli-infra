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
├── docker-compose.prod.yml    # Postgres + backend (producción, build ./backend)
├── Makefile                   # Clona el backend y levanta el stack
├── .env.example
└── database/
    └── postgres/
        ├── 01-init.sql                 # Schema completo (se aplica al primer arranque)
        └── updates/                    # Cambios post-primer-deploy a prod
            ├── README.md               # Convención de updates (idempotencia, naming)
            └── YYYY-MM-DD_*.sql        # ALTERs cronológicos
```

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

## Desplegar backend en producción

El servicio `backend` de `docker-compose.prod.yml` se construye desde
`./backend`, que es un **clone** de `dolynation-atl-back`. El `Makefile`
se encarga:

```bash
make up      # clona el backend si falta y levanta Postgres + backend
make down     # detiene el stack
make logs     # sigue los logs
make reset    # borra volúmenes (datos) y contenedores
```

O manualmente:

```bash
git clone --depth 1 https://github.com/DolyLanguagesORG/dolynation-atl-back.git backend
docker compose -f docker-compose.prod.yml up -d --build
```

Levanta dos servicios:

- `database-postgres-dolynglish` — Postgres 15 con el schema aplicado (puerto host 57000).
- `backend-dolynglish` — construye desde `./backend/Dockerfile`, expone puerto 3333
  como 57001.

Las variables de entorno del backend se pasan vía `${...}` desde el
`.env`. Ver el
[`.env.example` del backend](https://github.com/DolyLanguagesORG/dolynation-atl-back/blob/develop/.env.example).

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

### Cambios al schema: regla de dos fases

- **Mientras `prod` no se ha desplegado** (estamos en dev puro):
  editar directamente `01-init.sql` con el estado final deseado.
- **Después del primer deploy a `prod`**: NO editar `01-init.sql`;
  crear archivos `updates/YYYY-MM-DD_<nombre>.sql` con `ALTER`s
  idempotentes. Se aplican en orden alfabético (= cronológico).

Detalles completos en
[`database/postgres/updates/README.md`](./database/postgres/updates/README.md)
y en la
[convención de base de datos](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/database.md).
