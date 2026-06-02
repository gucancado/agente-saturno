#!/bin/bash
# resolve-slug.sh <workspace_id>
# Retorna o slug do diretório (em projetos/) para um workspace Bloquim.
# Lê _platform/workspace-map.json. Retorna string vazia se não encontra.
set -euo pipefail

WS_ID="${1:?usage: resolve-slug.sh <workspace_id>}"
MAP="/workspace/_platform/workspace-map.json"

if [[ ! -f "$MAP" ]]; then
  echo ""
  exit 0
fi

jq -r --arg id "$WS_ID" \
  '.workspaces[] | select(.id == $id) | .slug' "$MAP" | head -n1
