#!/bin/bash
# bloquim-list-tasks.sh <filter_json>
#
# Lista tarefas visíveis ao usuário do agente no Bloquim, conforme filtro.
#
# Input: JSON do `.list_filter` do perfil (de cadencia.yml). Ex:
#   { "status": ["pending","in_progress"] }
#   { "status": ["pending"], "scheduleMode": "urgente" }
#   { "status": ["pending","in_progress"], "scope": "today" }
#
# Output (stdout): JSON array de tarefas. Cada tarefa tem ao menos:
#   id, workspaceId, title, status, priority, scheduleMode, dueDate, ...
#
# Env vars esperadas:
#   BLOQUIM_API_URL  — ex: https://bloquim.beeads.com.br/api/v1
#   BLOQUIM_TOKEN    — JWT Bearer válido (expira em 7d; rotacionar)
#
# Detalhes:
#   - Endpoint usado: GET /my-tasks/?status=...
#   - Retorna tarefas pessoais E de workspaces dos quais o agente é membro
#     (server-side filter por ownership; já é o que queremos).
#   - Filtros suportados pelo server: workspaceId, status, assignedTo.
#   - Filtros aplicados client-side (jq): scheduleMode, scope=today.
set -euo pipefail

FILTER="${1:?usage: bloquim-list-tasks.sh <filter_json>}"

: "${BLOQUIM_API_URL:?BLOQUIM_API_URL não definida}"
: "${BLOQUIM_TOKEN:?BLOQUIM_TOKEN não definida}"

# ─── Constrói query string a partir do filter ─────────────────────────────
STATUSES=$(jq -r '.status // [] | join(",")' <<<"$FILTER")

QS=""
if [[ -n "$STATUSES" ]]; then
  QS="?status=${STATUSES}"
fi

# ─── Faz request com retry leve ───────────────────────────────────────────
URL="${BLOQUIM_API_URL%/}/my-tasks/${QS}"

RAW=""
for i in 1 2 3; do
  RAW=$(curl -fsS --max-time 30 \
    -H "Authorization: Bearer ${BLOQUIM_TOKEN}" \
    -H "Accept: application/json" \
    "$URL" 2>/dev/null) && break
  [[ $i -lt 3 ]] && sleep $((i*2))
done

if [[ -z "$RAW" ]]; then
  echo "[bloquim-list-tasks] falhou após 3 tentativas em $URL" >&2
  echo "[]"
  exit 0
fi

# ─── Filtros client-side ──────────────────────────────────────────────────
RESULT="$RAW"

# scheduleMode (ex: "urgente")
SCHEDULE_MODE=$(jq -r '.scheduleMode // empty' <<<"$FILTER")
if [[ -n "$SCHEDULE_MODE" ]]; then
  RESULT=$(jq --arg sm "$SCHEDULE_MODE" '[.[] | select(.scheduleMode == $sm)]' <<<"$RESULT")
fi

# scope == today: dueDate cai na janela [00:00 hoje, 00:00 amanhã) no fuso local
SCOPE=$(jq -r '.scope // empty' <<<"$FILTER")
if [[ "$SCOPE" == "today" ]]; then
  START=$(date -u +%FT00:00:00Z)
  END=$(date -u -d "tomorrow" +%FT00:00:00Z 2>/dev/null || date -u -v+1d +%FT00:00:00Z)
  RESULT=$(jq --arg s "$START" --arg e "$END" \
    '[.[] | select(.dueDate != null and .dueDate >= $s and .dueDate < $e)]' <<<"$RESULT")
fi

# Saída: sempre JSON array (mesmo que vazio)
echo "$RESULT" | jq -c '.'
