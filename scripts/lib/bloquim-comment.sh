#!/bin/bash
# bloquim-comment.sh <workspace_id> <task_id> <content>
#
# Adiciona um comentário a uma tarefa do Bloquim via REST.
# Endpoint: POST /workspaces/<wId>/tasks/<tId>/comments  body: {"content":"..."}
#
# Auth: Authorization: Bearer ${BLOQUIM_TOKEN}
# Falhas: imprime no stderr; exit 1.
set -euo pipefail

WS_ID="${1:?usage: bloquim-comment.sh <workspace_id> <task_id> <content>}"
TASK_ID="${2:?}"
CONTENT="${3:?}"

: "${BLOQUIM_API_URL:?BLOQUIM_API_URL não definida}"
: "${BLOQUIM_TOKEN:?BLOQUIM_TOKEN não definida}"

URL="${BLOQUIM_API_URL%/}/workspaces/${WS_ID}/tasks/${TASK_ID}/comments"
BODY=$(jq -n --arg c "$CONTENT" '{content: $c}')

for i in 1 2 3; do
  if curl -fsS --max-time 30 -X POST \
       -H "Authorization: Bearer ${BLOQUIM_TOKEN}" \
       -H "Content-Type: application/json" \
       -d "$BODY" \
       "$URL" >/dev/null 2>&1; then
    exit 0
  fi
  [[ $i -lt 3 ]] && sleep $((i*2))
done

echo "[bloquim-comment] falhou após 3 tentativas (ws=$WS_ID task=$TASK_ID)" >&2
exit 1
