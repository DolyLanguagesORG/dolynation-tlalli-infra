---
name: ci-cd-release
description: Cómo funcionan CI, entornos, ramas rc y releases en DolyNation (repo dolynation-tlalli-infra). Cubre ci-infra, pr-title, pr-labels, release-please, sync-versions, despliegue por SSH, versionado y cascada. Úsala al tocar workflows, preparar una release o diagnosticar un deploy.
---

# CI/CD y releases — DolyNation

## Ramas

- `develop` — integración diaria; default. **Aquí nace el versionado.**
- `main` — producción. Recibe merges desde `develop` o `hotfix/*`.
- `rc-<version>` — rama efímera de release candidate, **single-flight**, y
  **solo en este repo** (el manifiesto ya lleva el pin exacto de los cuatro).

## Workflows del repo

| Workflow | Qué hace |
| --- | --- |
| `ci-infra.yml` | Valida `docker-compose.test.yml` y `prod.yml` (clona `./backend` para el contexto de build) |
| `pr-title.yml` | Valida Conventional Commits en el título del PR y la rama base/origen (`pr-title` + `pr-target`) |
| `pr-labels.yml` | Copia al PR las etiquetas de contexto del issue que cierra |
| `release-please.yml` | Versionado automático en `develop`: PR de release acumulativo; al mergearlo crea el **tag anotado** y la **GitHub Release** (*Pre-release* si es `0.x`), y **avisa al manifiesto** con un `repository_dispatch` |
| `sync-versions.yml` | Recibe el aviso de cada repo que publica y **abre el PR** que actualiza su fila en `versions.yml` |
| `deploy-dev.yml` | Autodespliegue a desarrollo por SSH al mergear a `develop` |

## Entornos y secretos

| Entorno | Estado | Puerto DB / Back / Front |
| --- | --- | --- |
| desarrollo | ✅ funciona | 57010 / 57011 / 57012 |
| staging | 🔶 pendiente (`infra#43`) | 57020 / 57021 / 57022 |
| producción | 🔶 pendiente (`infra#15`) | 57030 / 57031 / 57032 |

- Secretos de org/environments: IA, DB, PAT y SSH. Nunca en el repo.
- El gate de producción (GitHub Environment `produccion` con *required
  reviewers*) está pendiente: `infra#45`.

## Versionado y cascada

- `release-please` publica en `develop`, **no** en `main`. Ver
  [`conventions/versioning.md`](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md).
- `versions.yml` es el manifiesto del proyecto: `app_version` + versión, tag y
  commit por repositorio. Lo actualizan el propio release-please (su fila) y
  `sync-versions` (las demás).
- `infra#8`: cascada infra → back/front con PAT.
- `infra#14`: deploy a staging desde `rc-<version>` disparado por `versions.yml`.
- `infra#4`: PR final `develop` → `main`, tag `v1.0.0`, deploy y rollback.
- `back#18` y `front#13` bloquean el release final.

## Comandos útiles

```bash
gh run list --repo DolyLanguagesORG/dolynation-tlalli-infra --limit 10
gh workflow run release-please.yml --repo DolyLanguagesORG/dolynation-tlalli-infra
gh workflow run sync-versions.yml --repo DolyLanguagesORG/dolynation-tlalli-infra \
  -f repository=dolynation-atl-back -f version=v0.2.1 -f sha=<sha>
gh release list --repo DolyLanguagesORG/dolynation-tlalli-infra
```

## Reglas

- No push directo a `develop`/`main`.
- Un PR de release no se mergea si un issue bloqueante sigue abierto.
- No crear tags manuales: los crea release-please.
- No editar `versions.yml` a mano: lo actualiza `sync-versions`.
- Verifica healthchecks después de cada deploy y documenta el rollback.

## Referencias

- [CI-CD-Y-VERSIONADO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/CI-CD-Y-VERSIONADO.md)
- [versioning.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/conventions/versioning.md)
- [FLUJO-DE-TRABAJO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/FLUJO-DE-TRABAJO.md)
- [release-please.yml](../../../.github/workflows/release-please.yml)
- [sync-versions.yml](../../../.github/workflows/sync-versions.yml)
- [ci-infra.yml](../../../.github/workflows/ci-infra.yml)
