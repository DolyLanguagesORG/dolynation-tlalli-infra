# Changelog

Todas las novedades relevantes de este repositorio se registran aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado es [SemVer](https://semver.org/lang/es/).

La **versión se declara en el `CHANGELOG.md`**: el workflow `release.yml` exige
que exista la sección de la versión que se va a publicar antes de crear el tag.

## [No publicado]

### Añadido
- `versions.yml`: manifiesto con la versión publicada de cada repositorio del
  proyecto.
- Job `schema-sql` en el CI: aplica `01-init.sql` y `updates/*.sql` sobre una
  base PostgreSQL limpia, para que un SQL roto falle en el PR.
- Devcontainer con Docker, Compose y `gh`.
- Skills `infra-docker`, `schema-migrations` y `ci-cd-release`, más `AGENTS.md`.

## [0.1.0] - 2026-10-12

### Añadido
- Estructura inicial del repositorio con los compose de desarrollo, prueba y
  producción, y el schema inicial de PostgreSQL.

[No publicado]: https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/releases/tag/v0.1.0
