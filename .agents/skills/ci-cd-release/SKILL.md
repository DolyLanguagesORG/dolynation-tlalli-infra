---
name: ci-cd-release
description: Cómo funcionan CI, entornos, ramas rc y releases en DolyNation (repo dolynation-tlalli-infra). Cubre ci-infra, pr-title, pr-labels, release, despliegue por SSH, versionado y cascada. Úsala al tocar workflows, preparar una release o diagnosticar un deploy.
---

# CI/CD y releases — DolyNation

## Ramas

- `develop` — integración diaria; default.
- `main` — producción; solo recibe merges de `develop`/hotfix.
- `rc-<version>` — rama efímera de release candidate, **single-flight**.
- `rc` **no es un entorno**; es una rama que dispara staging.

## Workflows del repo

| Workflow | Qué hace |
| --- | --- |
| `ci-infra.yml` | Valida `docker-compose.test.yml` y `prod.yml` (clona `./backend` para el contexto de build) |
| `pr-title.yml` | Valida Conventional Commits en el título del PR |
| `pr-labels.yml` | Aplica labels por área/sprint |
| `release.yml` | Calcula el bump y crea tag/release al llegar a `main` |

## Entornos y secretos

Planificado en `infra#6`-`infra#9`:

- **desarrollo** — deploy automático en merge a `develop`.
- **staging** — deploy al crear/actualizar `rc-<version>`.
- **producción** — deploy al mergear a `main`.
- Secretos de org/environments: IA, DB, PAT y SSH. Nunca en el repo.

## Versionado y cascada

- `infra#7`: release-please + `versions.yml` + guard `rc-*`.
- `infra#8`: cascada infra → back/front con PAT y deploy a staging.
- `infra#4`: PR final `develop` → `main`, tag `v1.0.0`, deploy y rollback.
- `back#18` y `front#13` bloquean el release final.

## Comandos útiles

```bash
gh run list --repo DolyLanguagesORG/dolynation-tlalli-infra --limit 10
gh workflow run release.yml --repo DolyLanguagesORG/dolynation-tlalli-infra
gh release list --repo DolyLanguagesORG/dolynation-tlalli-infra
```

## Reglas

- No push directo a `develop`/`main`.
- Un PR de release no se mergea si un issue bloqueante sigue abierto.
- No crear tags manuales si release-please está activo; usa el PR de release.
- Verifica healthchecks después de cada deploy y documenta el rollback.

## Referencias

- [CI-CD-Y-VERSIONADO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/CI-CD-Y-VERSIONADO.md)
- [FLUJO-DE-TRABAJO.md](https://github.com/DolyLanguagesORG/dolynation-ehecatl-docs/blob/develop/operations/FLUJO-DE-TRABAJO.md)
- [release.yml](../../../.github/workflows/release.yml)
- [ci-infra.yml](../../../.github/workflows/ci-infra.yml)
