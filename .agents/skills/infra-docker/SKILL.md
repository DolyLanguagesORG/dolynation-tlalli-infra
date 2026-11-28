---
name: infra-docker
description: Cómo levantar y operar los servicios Docker de DolyNation (repo dolynation-tlalli-infra). Cubre PostgreSQL 15, el backend clonado en ./backend, docker-compose.test.yml, docker-compose.prod.yml, puertos, volúmenes, variables de entorno y troubleshooting. Úsala al preparar el entorno local, levantar la BD, revisar contenedores o desplegar el stack.
---

# Infra Docker — DolyNation

## Archivos

```
.
├── docker-compose.test.yml    # Postgres standalone (dev/test)
├── docker-compose.prod.yml    # Postgres + backend (build ./backend)
├── Makefile                   # up/down/logs/reset
├── .env.example
└── database/postgres/         # schema y updates
```

## Comandos

```bash
# Postgres para desarrollo/tests
docker compose -f docker-compose.test.yml up -d

# Estado / logs / reset
docker compose -f docker-compose.test.yml ps
docker compose -f docker-compose.test.yml logs -f postgres
docker compose -f docker-compose.test.yml down -v   # borra datos

# Stack de producción (clona el backend si falta)
make up
make logs
make down
make reset                                           # borra volúmenes

# Validar Compose (lo que corre el CI)
docker compose -f docker-compose.test.yml config
docker compose -f docker-compose.prod.yml config
```

## Puertos y variables

- Postgres test/dev: host **57000** → contenedor `5432`.
- Backend prod: host **57001** → contenedor `3333`.
- `docker-compose.test.yml` lee `DB_USER`, `DB_PASSWORD`, `DB_DATABASE` y
  `DB_PORT` del `.env` (o del entorno).
- `docker-compose.prod.yml` espera `POSTGRES_USER`, `POSTGRES_PASSWORD`,
  `POSTGRES_DB` y las variables del backend.
- Copia `.env.example` a `.env`; **nunca** commitees `.env`.

## Verificación

```bash
docker exec -it dolynglish_postgres psql -U postgres -d dolynglish_test -c "\dt"
curl -s http://localhost:57001/api/v1/health/ready
```

## Errores comunes

- **`ECONNREFUSED :5432`:** el contenedor no está arriba o el puerto host no
  coincide. Revisa `docker compose ... ps`.
- **Tablas faltantes:** el volumen ya existía y `01-init.sql` no se re-aplicó.
  Usa `down -v` y vuelve a levantar.
- **`docker compose config` falla en prod:** falta el clone `./backend` o las
  variables `POSTGRES_*`.
- **El backend no arranca:** revisa que el `.env` del backend tenga
  `DB_HOST`, `DB_DATABASE` y `JWT_SECRET`.

## Referencias

- [README del repo](../../../README.md)
- [schema-migrations](../schema-migrations/SKILL.md)
- [ci-cd-release](../ci-cd-release/SKILL.md)
