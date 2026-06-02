#!/bin/bash
# resolve-monitoring-task.sh
#
# Resolve workspaceId + taskId da tarefa-mãe "<AGENT_NAME>-monitoramento" no
# workspace _sistema, cacheando em /workspace/.platform/monitoring-task.json.
#
# Output: emite `<workspace_id> <task_id>` em stdout (separados por espaço).
# Exit 1 se não conseguir resolver.
set -euo pipefail

: "${BLOQUIM_API_URL:?BLOQUIM_API_URL não definida}"
: "${BLOQUIM_TOKEN:?BLOQUIM_TOKEN não definida}"
: "${AGENT_NAME:?AGENT_NAME não definida}"

WORKSPACE=/workspace
CACHE="$WORKSPACE/.platform/monitoring-task.json"
MAP="$WORKSPACE/_platform/workspace-map.json"

mkdir -p "$(dirname "$CACHE")"

# ─── Cache hit ────────────────────────────────────────────────────────────
if [[ -f "$CACHE" ]]; then
  WS=$(jq -r '.workspace_id' "$CACHE")
  TID=$(jq -r '.task_id' "$CACHE")
  if [[ -n "$WS" && -n "$TID" && "$WS" != "null" && "$TID" != "null" ]]; then
    echo "$WS $TID"
    exit 0
  fi
fi

# ─── Resolve workspace _sistema ───────────────────────────────────────────
if [[ ! -f "$MAP" ]]; then
  echo "[resolve-monitoring-task] workspace-map.json ausente" >&2
  exit 1
fi

SISTEMA_WS_ID=$(jq -r '.workspaces[] | select(.slug == "_sistema") | .id' "$MAP" | head -n1)
if [[ -z "$SISTEMA_WS_ID" || "$SISTEMA_WS_ID" == "null" ]]; then
  echo "[resolve-monitoring-task] _sistema ausente em workspace-map.json" >&2
  exit 1
fi

# ─── Busca pela tarefa por título ─────────────────────────────────────────
TITLE_QUERY="${AGENT_NAME}-monitoramento"
URL="${BLOQUIM_API_URL%/}/tasks/search?q=$(jq -rn --arg q "$TITLE_QUERY" '$q|@uri')&workspaceId=${SISTEMA_WS_ID}"

RAW=$(curl -fsS --max-time 30 \
  -H "Authorization: Bearer ${BLOQUIM_TOKEN}" \
  "$URL" 2>/dev/null) || {
    echo "[resolve-monitoring-task] busca falhou em $URL" >&2
    exit 1
  }

TASK_ID=$(jq -r --arg t "$TITLE_QUERY" \
  '[.[] | select(.title == $t)] | .[0].id // empty' <<<"$RAW")

if [[ -z "$TASK_ID" ]]; then
  echo "[resolve-monitoring-task] tarefa '$TITLE_QUERY' não encontrada no workspace _sistema. Crie manualmente antes do primeiro tick." >&2
  exit 1
fi

# Cache + emit
jq -n --arg ws "$SISTEMA_WS_ID" --arg t "$TASK_ID" \
  '{workspace_id: $ws, task_id: $t}' > "$CACHE"

echo "$SISTEMA_WS_ID $TASK_ID"
