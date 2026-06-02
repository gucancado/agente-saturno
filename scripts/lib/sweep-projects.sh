#!/bin/bash
# sweep-projects.sh — emite (uma por linha) os slugs de projeto a auditar no sweep.
# Fonte: _platform/workspace-map.json (campo .workspaces[].slug).
# Exclui slugs meta (prefixo "_": _sistema, _template, _base).
#
# Override de path para teste: WORKSPACE_MAP=/caminho/fixture.json
set -euo pipefail

WORKSPACE="${WORKSPACE:-/workspace}"
MAP="${WORKSPACE_MAP:-$WORKSPACE/_platform/workspace-map.json}"

if [[ ! -f "$MAP" ]]; then
  echo "sweep-projects: $MAP nao existe" >&2
  exit 1
fi

# grep pode filtrar tudo (exit 1); || true evita quebrar sob set -e/pipefail.
jq -r '.workspaces[].slug' "$MAP" | { grep -v '^_' || true; }
