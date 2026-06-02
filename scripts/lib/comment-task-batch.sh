#!/bin/bash
# comment-task-batch.sh <workspace_id> <comment_text>
#
# Adiciona o mesmo comentário em todas as tarefas pending/in_progress de um
# workspace que estejam visíveis ao agente. Usado quando o tick processou via
# fallback (workspace sem provisionamento no agente).
set -euo pipefail

WS_ID="${1:?usage: comment-task-batch.sh <workspace_id> <comment_text>}"
COMMENT="${2:?}"

WORKSPACE=/workspace
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

: "${BLOQUIM_API_URL:?BLOQUIM_API_URL não definida}"
: "${BLOQUIM_TOKEN:?BLOQUIM_TOKEN não definida}"

# Log local sempre
mkdir -p "$WORKSPACE/.logs"
echo "[$(date -u +%FT%TZ)] BATCH-COMMENT ws=$WS_ID text=$COMMENT" \
  >> "$WORKSPACE/.logs/comment-batch.log"

# Lista tarefas do workspace, filtrando para pending/in_progress
URL="${BLOQUIM_API_URL%/}/my-tasks/?workspaceId=${WS_ID}&status=pending,in_progress"

TASKS=$(curl -fsS --max-time 30 \
  -H "Authorization: Bearer ${BLOQUIM_TOKEN}" \
  "$URL" 2>/dev/null) || {
    echo "[comment-task-batch] falhou listar tarefas em $URL" >&2
    exit 0  # não derruba tick
  }

COUNT=$(jq 'length' <<<"$TASKS")
if [[ "$COUNT" == "0" ]]; then
  exit 0
fi

# Comenta em cada uma. Falhas individuais não interrompem o batch.
echo "$TASKS" | jq -r '.[].id' | while read -r TID; do
  "$LIB/bloquim-comment.sh" "$WS_ID" "$TID" "$COMMENT" 2>/dev/null || true
done
