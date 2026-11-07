# Changelog

Todas las novedades relevantes de este repositorio se registran aquí.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el
versionado es [SemVer](https://semver.org/lang/es/).

La **versión vive en `version.txt`**: el tag de la release y el `CHANGELOG.md`
deben coincidir con ella. El versionado es automático: `release-please` mantiene
un PR de release contra `develop` que sube la versión y escribe esta sección; al
mergearlo se crean el tag anotado y la GitHub Release. Ver
[`conventions/versioning.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md).

## [0.2.2](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.2.1...v0.2.2) (2026-11-07)


### Bug Fixes

* **ci:** enviar el nombre del repositorio en el aviso al manifiesto ([#56](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/56)) ([af9b690](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/af9b6908b695b252ae50599da9e34fab727248f0))

## [0.2.1](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.2.0...v0.2.1) (2026-11-06)


### Bug Fixes

* **ci:** separar el checkout del paso que anota el tag ([#54](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/54)) ([98bea3c](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/98bea3ca377c32603f3c6ffeb6a727b262e92a0e))
* **manifest:** corregir la actualizacion de la fila en el manifiesto ([#53](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/53)) ([82ada34](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/82ada34c66e7602685d3b26c7641c93e7b379d79))

## [0.2.0](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/compare/v0.1.0...v0.2.0) (2026-11-06)


### Features

* **nginx:** anadir el proxy inverso de los entornos ([#37](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/37)) ([358f180](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/358f1803d3d5a8c58ed1ba1a5148a6c989f63a16))


### Bug Fixes

* **ci:** compartir el agente SSH entre todos los pasos del workflow ([#38](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/38)) ([e941a6f](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/e941a6fa5b34b5b12501ffb7bb59d558dd9f74bb))
* **ci:** reportar el estado del deployment a GitHub ([#39](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/39)) ([cc2ae22](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/cc2ae2218bb0f1b516ce0d99fe93289933e590d1))
* **deploy:** preparar el servidor nuevo y desplegar con la llave cifrada ([#36](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/36)) ([5a85760](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/5a8576034a745af69d2bcfdde8a8a96595c80cbc))
* **nginx:** corregir el dominio a yacaterkos.tech ([#41](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/issues/41)) ([956139a](https://github.com/DolyLanguagesORG/dolynation-tlalli-infra/commit/956139af859a5f05efda157e6461fdae7a53a44a))

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
