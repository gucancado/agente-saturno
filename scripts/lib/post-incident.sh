#!/bin/bash
# post-incident.sh <tick_id> <type> <detail>
#
# Posta comentário em <agente>-monitoramento (workspace _sistema) descrevendo
# incidente. Não falha o tick se o Bloquim estiver indisponível — sempre tenta
# também gravar log local em /workspace/.logs/incidents.log.
set -euo pipefail

TICK_ID="${1:?}"
TYPE="${2:?}"
DETAIL="${3:-}"

WORKSPACE=/workspace
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Log local sempre acontece (independente do Bloquim)
mkdir -p "$WORKSPACE/.logs"
echo "[$(date -u +%FT%TZ)] INCIDENT tick=$TICK_ID type=$TYPE detail=$DETAIL" \
  >> "$WORKSPACE/.logs/incidents.log"

# Resolve monitoring task
if ! IFS=' ' read -r WS_ID TASK_ID < <("$LIB/resolve-monitoring-task.sh" 2>/dev/null); then
  exit 0  # silenciosamente — o log local cobriu
fi

CONTENT=$(cat <<EOF
[INCIDENT $TICK_ID]
- type: $TYPE
- detail: $DETAIL
- at: $(date -u +%FT%TZ)
EOF
)

"$LIB/bloquim-comment.sh" "$WS_ID" "$TASK_ID" "$CONTENT" 2>/dev/null || true
