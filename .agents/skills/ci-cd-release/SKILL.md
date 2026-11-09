---
name: ci-cd-release
description: Cómo funcionan CI, entornos, ramas rc y releases en DolyNation (repo dolynation-tlalli-infra). Cubre ci-infra, pr-title, pr-labels, release-please, sync-versions, despliegue por SSH, versionado y cascada. Úsala al tocar workflows, preparar una release o diagnosticar un deploy.
---

# CI/CD y releases — DolyNation

## Ramas

- `develop` — integración diaria; default. **Aquí nace el versionado.**
- `main` — producción. Recibe merges desde `develop`, `hotfix/*` o `rc-*`.
- `rc-<app_version>` — rama efímera de release candidate, **single-flight**.
  Se corta en **los cuatro repos** (en el commit de su tag). El manifiesto
  lleva el pin exacto de la versión de cada uno.

## Workflows del repo

| Workflow | Qué hace |
| --- | --- |
| `ci-infra.yml` | Valida `docker-compose.test.yml` y `prod.yml` (clona `./backend` para el contexto de build) |
| `pr-title.yml` | Valida Conventional Commits en el título del PR y la rama base/origen (`pr-title` + `pr-target`) |
| `pr-labels.yml` | Copia al PR las etiquetas de contexto del issue que cierra |
| `release-please.yml` | Versionado automático en `develop`: PR de release acumulativo; al mergearlo crea el **tag anotado** y la **GitHub Release** (*Pre-release* si es `0.x`), y **avisa al manifiesto** con un `repository_dispatch` |
| `sync-versions.yml` | Recibe el aviso de cada repo que publica y **abre el PR** que actualiza su fila en `versions.yml` |
| `versions-manifest.yml` | Valida el manifiesto (version, tag y commit con el formato correcto; la coherencia es aviso) |
| `release-guard.yml` | Single-flight: **una sola `rc` a la vez** en los cuatro repos (consulta las ramas públicas con `git ls-remote`, sin SSH) |
| `promote-rc.yml` | Abre el PR `rc -> main` y, al mergearlo, los PRs `rc -> main` de back y front (cascada con PAT) |
| `deploy-dev.yml` | Autodespliegue a desarrollo por SSH al mergear a `develop` |
| `deploy-rehearsal.yml` | Despliega el ambiente de **simulación** (5704x) al empujar la `rc` |
| `deploy-staging.yml` | Despliega staging (5702x) **solo si el ambiente de simulación pasó su smoke test** |
| `deploy-prod.yml` | Despliega producción (5703x) **a mano** (`workflow_dispatch`) y con 2 revisores |
| `smoke-test.yml` | 8 comprobaciones contra el ambiente recién desplegado; se dispara solo (`workflow_run`) si el deploy terminó bien |

## Entornos y secretos

| Entorno | Estado | Puerto DB / Back / Front |
| --- | --- | --- |
| desarrollo | ✅ funciona | 57010 / 57011 / 57012 |
| rehearsal (simulación) | ✅ funciona | 57040 / 57041 / 57042 |
| staging | ✅ funciona | 57020 / 57021 / 57022 |
| producción | 🔶 pendiente (`infra#15`) | 57030 / 57031 / 57032 |

- Secretos de org/environments: IA, DB, PAT y SSH. Nunca en el repo.
- El gate de producción es el environment **`prod`** con *required reviewers*
  (2 revisores, sin self-review) y `deploy-prod` es manual: **nada llega a
  producción sin que alguien lo dispare y lo apruebe**.
- Cada environment tiene sus **propios** secretos (`JWT_SECRET`,
  `POSTGRES_PASSWORD`, `DB_PASSWORD`): el de staging no vale en producción.

## Gates

| Regla | Alcance |
| --- | --- |
| 1 aprobación + CI en verde | `develop` (el scrum master tiene bypass) |
| 2 aprobaciones + code owner + **deployment de staging** | `main` (sin bypass) |
| 2 revisores, sin self-review | environment `prod` |

## Versionado y cascada

- `release-please` publica en `develop`, **no** en `main`. Ver
  [`conventions/versioning.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md).
- `versions.yml` es el manifiesto del proyecto: `app_version` + versión, tag y
  commit por repositorio. Lo actualizan el propio release-please (su fila) y
  `sync-versions` (las demás).
- `app_version` sigue a la versión más alta entre **backend y frontend** (los
  componentes que forman la app); infra y docs versionan su propio software.
- El **servidor nunca compila**: se bajan imágenes de GHCR por **SHA**
  (inmutable, rollback exacto). Las imágenes se construyen **multi-arquitectura**
  (amd64 + arm64).

## Comandos útiles

```bash
gh run list --repo DolyLanguagesORG/dolynation-tlalli-infra --limit 10
gh workflow run release-please.yml --repo DolyLanguagesORG/dolynation-tlalli-infra
gh workflow run sync-versions.yml --repo DolyLanguagesORG/dolynation-tlalli-infra \
  -f repository=dolynation-atl-back -f version=v0.2.1 -f sha=<sha>
gh release list --repo DolyLanguagesORG/dolynation-tlalli-infra
gh pr list --repo DolyLanguagesORG/dolynation-tlalli-infra --base main
```

## Reglas

- No push directo a `develop`/`main`.
- Un PR de release no se mergea si un issue bloqueante sigue abierto.
- No crear tags manuales: los crea release-please.
- No editar `versions.yml` a mano: lo actualiza `sync-versions`.
- Verifica healthchecks después de cada deploy y documenta el rollback.

## Referencias

- [FLUJO-DE-RELEASE.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/FLUJO-DE-RELEASE.md)
- [CI-CD-Y-VERSIONADO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/CI-CD-Y-VERSIONADO.md)
- [FLUJO-DE-TRABAJO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/FLUJO-DE-TRABAJO.md)
- [versioning.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md)
- [release-please.yml](../../../.github/workflows/release-please.yml)
- [sync-versions.yml](../../../.github/workflows/sync-versions.yml)
- [ci-infra.yml](../../../.github/workflows/ci-infra.yml)
