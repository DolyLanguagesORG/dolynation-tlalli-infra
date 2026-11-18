#!/usr/bin/env python3
"""Ranking de trabajo: quien ha hecho que, y cuando.

Responde a "quien ha estado trabajando en que, en que dias" con datos:

- PRs fusionados por persona (autor del PR).
- Issues cerradas por persona (autora de la issue).
- Commits por persona y dia: el "mapa de calor" de cuando se trabajo.

Sale de la API de busqueda de GitHub y del historial de git: **no necesita
ningun secreto**.

Uso:
    scripts/contributors.py [desde]     # desde = YYYY-MM-DD (por defecto, 30 dias)
"""
import collections
import json
import os
import subprocess
import sys
import urllib.parse

ORG = "DolyLanguagesORG"
REPOS = [
    "dolynation-atl-back",
    "dolynation-tonatiuh-front",
    "dolynation-tlalli-infra",
    "dolynation-ehecatl-docs",
]
BASE = "/home/jxadevp/Work/clases/Desarrollo Web Del Toro/DolyLanguagesORG"


def buscar(consulta):
    """La API de busqueda es mucho mas rapida que listar issue a issue."""
    url = f"search/issues?q={urllib.parse.quote(consulta)}&per_page=100"
    r = subprocess.run(["gh", "api", url], capture_output=True, text=True)
    try:
        return json.loads(r.stdout).get("items", [])
    except Exception:
        return []


def normalizar(autor):
    """Una persona es una, aunque git y GitHub la llamen distinto.

    Los commits hechos con el PAT aparecen como `Jesus Alberto Villarrea
    Perez <167471402+XxjesusalbertoxX@users.noreply.github.com>` y los
    locales como `XxjesusalbertoxX <...gmail.com>`: sin normalizar, la misma
    persona sale partida en dos filas del mapa de calor.
    """
    nombre = autor.split(" <", 1)[0].strip()
    if "<" in autor and "+" in autor and "@users.noreply.github.com" in autor:
        return autor.split("+", 1)[1].split("@", 1)[0]
    return nombre


def commits_por_dia(repo, desde):
    """(autor, dia) -> nº de commits, leyendo el historial local."""
    directorio = os.path.join(BASE, repo)
    if not os.path.isdir(os.path.join(directorio, ".git")):
        return collections.Counter()
    salida = subprocess.run(
        ["git", "-C", directorio, "log", f"--since={desde}",
         "--pretty=%an <%ae>|%ad", "--date=short"],
        capture_output=True, text=True,
    ).stdout
    cuenta = collections.Counter()
    for linea in salida.splitlines():
        if "|" in linea:
            autor, dia = linea.rsplit("|", 1)
            cuenta[(dia, normalizar(autor))] += 1
    return cuenta


def main():
    desde = sys.argv[1] if len(sys.argv) > 1 else "2026-10-20"

    print(f"## Quien ha trabajado en que — desde {desde}")
    print()
    print("### PRs fusionados e issues cerradas")
    print()
    print("| Persona | PRs fusionados | Issues cerradas | Repos |")
    print("| --- | ---: | ---: | --- |")

    prs = collections.Counter()
    issues = collections.Counter()
    donde = collections.defaultdict(set)

    for repo in REPOS:
        for p in buscar(f"repo:{ORG}/{repo} is:pr is:merged merged:>={desde}"):
            autor = (p.get("user") or {}).get("login", "?")
            prs[autor] += 1
            donde[autor].add(repo.replace("dolynation-", ""))
        for i in buscar(f"repo:{ORG}/{repo} is:issue is:closed closed:>={desde}"):
            issues[(i.get("user") or {}).get("login", "?")] += 1

    for nombre in sorted(set(prs) | set(issues), key=lambda n: (-(prs[n] + issues[n]), n)):
        print(f"| {nombre} | {prs[nombre]} | {issues[nombre]} | {', '.join(sorted(donde[nombre])) or '-'} |")

    print()
    print("### Commits por persona y dia")
    print()
    print("```")
    for repo in REPOS:
        dias = commits_por_dia(repo, desde)
        print(repo)
        if not dias:
            print("  (sin commits en el rango)")
            print()
            continue
        columnas = sorted({d for (d, _) in dias})
        autores = sorted({a for (_, a) in dias})
        print("  " + " ".join(f"{d[5:]:>8}" for d in columnas))
        for autor in autores:
            fila = "".join(f"{dias.get((d, autor), 0):>9}" for d in columnas)
            print(f"{autor[:18]:<18}{fila}")
        print()
    print("```")
    print()
    print("_(filas: persona · columnas: dia · numeros: commits)_")
    print()
    print("> Las cifras de PRs e issues son de **autor**: el indice de busqueda de")
    print("> GitHub no expone quien mergéo o cerro cada cosa. Quien mergea es el")
    print("> scrum master, asi que el reparto real se ve mejor en los commits.")


if __name__ == "__main__":
    main()
