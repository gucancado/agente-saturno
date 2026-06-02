#!/bin/bash
# post-tick-summary.sh <tick_id> <task_count> [claude_log]
#
# Posta resumo do tick na tarefa-mãe <agente>-monitoramento (workspace _sistema).
# Extrai métricas (turnos, custo) do output JSON do Claude Code, se disponível.
set -euo pipefail

TICK_ID="${1:?}"
TASK_COUNT="${2:-0}"
CLAUDE_LOG="${3:-}"

WORKSPACE=/workspace
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ─── Extrai métricas do log do Claude ─────────────────────────────────────
TURNS="?"
COST="?"
DURATION="?"

if [[ -f "$CLAUDE_LOG" ]]; then
  # O log pode conter múltiplos JSONs (uma invocação por workspace). Pegamos
  # o último como amostra representativa, e somamos custos com jq se possível.
  if jq -e . "$CLAUDE_LOG" >/dev/null 2>&1; then
    TURNS=$(jq -r '.num_turns // "?"' "$CLAUDE_LOG")
    COST=$(jq -r '.total_cost_usd // .cost_usd // "?"' "$CLAUDE_LOG")
    DURATION=$(jq -r '.duration_ms // empty | if . then (./1000|tostring + "s") else "?" end' "$CLAUDE_LOG")
  else
    # tenta extrair por regex (fallback se múltiplos JSONs concatenados)
    TURNS=$(grep -oP '"num_turns"\s*:\s*\K\d+' "$CLAUDE_LOG" | tail -n1 || echo "?")
    COST=$(grep -oP '"total_cost_usd"\s*:\s*\K[0-9.]+' "$CLAUDE_LOG" | tail -n1 || echo "?")
  fi
fi

# ─── Log local ────────────────────────────────────────────────────────────
mkdir -p "$WORKSPACE/.logs"
echo "[$(date -u +%FT%TZ)] SUMMARY tick=$TICK_ID tasks=$TASK_COUNT turns=$TURNS cost=\$$COST" \
  >> "$WORKSPACE/.logs/summaries.log"

# ─── Resolve tarefa-mãe e comenta ─────────────────────────────────────────
if ! IFS=' ' read -r WS_ID TASK_ID < <("$LIB/resolve-monitoring-task.sh" 2>/dev/null); then
  exit 0
fi

CONTENT=$(cat <<EOF
[TICK $TICK_ID]
- tarefas processadas: $TASK_COUNT
- turnos consumidos: $TURNS
- custo: \$$COST
- duração: $DURATION
- at: $(date -u +%FT%TZ)
EOF
)

"$LIB/bloquim-comment.sh" "$WS_ID" "$TASK_ID" "$CONTENT" 2>/dev/null || true
