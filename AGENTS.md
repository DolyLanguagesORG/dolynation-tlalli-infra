# AGENTS.md — `dolynation-tlalli-infra`

Instrucciones para agentes de código (Claude Code, Codex, OpenCode, Cursor, etc.)
que trabajen en este repositorio.

## Qué es este repo

Es el repo de **infraestructura y schema** de DolyNation. Contiene Docker
Compose, el SQL de PostgreSQL y los workflows de infra/release. **No contiene**
el código del backend ni del frontend: el backend se clona dentro de `./backend`
para producción.

## Skills de este repo

Están en `.agents/skills/` y se cargan bajo demanda:

- **`infra-docker`** — cómo levantar Postgres/backend, puertos, volúmenes y
  troubleshooting de Compose.
- **`schema-migrations`** — regla de dos fases, idempotencia, `01-init.sql` y
  `updates/NN-*.sql`.
- **`ci-cd-release`** — CI, entornos, `rc`, release-please, cascada y deploy.

## Reglas rápidas

- **El schema es la fuente de verdad.** Un cambio de tablas/columnas se hace
  aquí, no en el backend.
- Antes del primer deploy real a prod: mantener `01-init.sql` y `updates/`
  sincronizados. Después: `01-init.sql` se congela y solo se agregan updates.
- Todo update debe ser **idempotente**. PostgreSQL 15 no soporta
  `DROP COLUMN IF EXISTS`.
- No commitear `.env` ni secretos. Usar `.env.example`.
- Rama nueva desde `develop`. **Nunca** push directo a `develop`/`main`.
- PR hacia `develop`, título Conventional, **squash**, 1 aprobación,
  `Closes #N` en su propia línea.
- Antes de cerrar un cambio: `docker compose -f docker-compose.test.yml config`
  y el CI `infra` en verde.

## Otros repos de la organización

- `dolynation-atl-back` — API (NestJS + Drizzle + PostgreSQL).
- `dolynation-tonatiuh-front` — frontend (Next.js).
- `dolynation-ehecatl-docs` — documentación y convenciones.
