#!/bin/bash
# tick.sh <profile>
# Entry point chamado pelo supercronic. Roda um tick do perfil especificado.
# Documentação: SPEC §4.2 da plataforma Semente.

set -euo pipefail

# ─── 0. Setup ──────────────────────────────────────────────────────────────
PROFILE="${1:?usage: tick.sh <profile>}"
WORKSPACE=/workspace
TICK_ID="$(date -u +%Y%m%dT%H%M%SZ)-${PROFILE}-$$"
LOCK_FILE="${WORKSPACE}/.locks/tick.${PROFILE}.lock"
LOG_DIR="${WORKSPACE}/.logs"
COST_DIR="${WORKSPACE}/.cost"
COST_FILE="${COST_DIR}/$(date -u +%F).jsonl"
CADENCIA="${WORKSPACE}/scripts/cadencia.yml"

mkdir -p "$(dirname "$LOCK_FILE")" "$LOG_DIR" "$COST_DIR"

log() { echo "[$(date -u +%FT%TZ)] [$TICK_ID] $*" >> "$LOG_DIR/tick.log"; }

# ─── 0a. Lock por perfil ───────────────────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "skip: tick anterior do perfil $PROFILE ainda rodando"
  exit 0
fi

log "start"

# ─── 0b. Guarda de custo (soft cap) ────────────────────────────────────────
COST_CAP_DAY=$(yq -r '.guardrails.cost_cap_usd_per_day // 5.0' "$CADENCIA")
COST_CAP_TICK=$(yq -r '.guardrails.cost_cap_usd_per_tick // 0.5' "$CADENCIA")
ALERT_PCT=$(yq -r '.guardrails.alert_threshold_pct // 80' "$CADENCIA")

if [[ -f "$COST_FILE" ]]; then
  COST_TODAY=$(jq -s '[.[].cost_usd] | add // 0' "$COST_FILE")
else
  COST_TODAY=0
fi

OVER_DAY=$(awk -v c="$COST_TODAY" -v cap="$COST_CAP_DAY" 'BEGIN { print (c >= cap) ? 1 : 0 }')
ALERT_LEVEL=$(awk -v c="$COST_TODAY" -v cap="$COST_CAP_DAY" -v pct="$ALERT_PCT" \
  'BEGIN { print (c >= cap * pct / 100) ? 1 : 0 }')

if [[ "$OVER_DAY" == "1" ]]; then
  log "GUARDA INTERNA: cost cap diário (\$$COST_CAP_DAY) excedido (\$$COST_TODAY). Pulando tick."
  "${WORKSPACE}/scripts/lib/post-incident.sh" "$TICK_ID" "cost-cap-daily" "$COST_TODAY/$COST_CAP_DAY" || true
  exit 0
fi

if [[ "$ALERT_LEVEL" == "1" ]]; then
  log "ALERTA: gasto hoje \$$COST_TODAY (>= $ALERT_PCT% do cap \$$COST_CAP_DAY)"
  "${WORKSPACE}/scripts/lib/post-incident.sh" "$TICK_ID" "cost-alert" "$COST_TODAY/$COST_CAP_DAY" || true
fi

# ─── 1. Git pull com retry ─────────────────────────────────────────────────
for i in 1 2 3; do
  if git -C "$WORKSPACE" pull --rebase --autostash >/dev/null 2>>"$LOG_DIR/git.log"; then
    break
  fi
  log "git pull falhou (tentativa $i/3)"
  [[ $i -lt 3 ]] && sleep $((i*2))
done

# ─── 2. Carregar perfil ────────────────────────────────────────────────────
PROFILE_JSON=$(yq -o=json ".profiles.$PROFILE" "$CADENCIA")
ENABLED=$(jq -r '.enabled // true' <<<"$PROFILE_JSON")

if [[ "$ENABLED" != "true" ]]; then
  log "perfil $PROFILE desabilitado em cadencia.yml; encerrando"
  exit 0
fi

LIST_FILTER=$(jq -c '.list_filter' <<<"$PROFILE_JSON")
ROTINA=$(jq -r '.rotina // empty' <<<"$PROFILE_JSON")
MAX_TURNS=$(jq -r '.max_turns_per_workspace // 50' <<<"$PROFILE_JSON")

# ─── 3. Verificar aprovações (passo 0 do agente) ───────────────────────────
log "verificar-aprovacoes"
(
  cd "$WORKSPACE/projetos/_sistema"
  claude --print \
    --model claude-sonnet-4-6 \
    --max-turns 20 \
    --append-system-prompt "$(cat "$WORKSPACE/scripts/tick-prompt.md")" \
    <<<"TICK_ID=$TICK_ID TASKS=[] ROTINA=$WORKSPACE/_base/skills/verificar-aprovacoes/SKILL.md" \
    >>"$LOG_DIR/claude.${TICK_ID}.log" 2>&1
) || log "verificar-aprovacoes falhou (continua tick mesmo assim)"

# ─── 4. Consultar fila no Bloquim ──────────────────────────────────────────
TASKS_JSON=$("${WORKSPACE}/scripts/lib/bloquim-list-tasks.sh" "$LIST_FILTER" 2>>"$LOG_DIR/bloquim.log")
TASK_COUNT=$(jq 'length' <<<"$TASKS_JSON")
log "TASK_COUNT=$TASK_COUNT"

# ─── 5. Tick barato ────────────────────────────────────────────────────────
if [[ "$TASK_COUNT" == "0" && -z "$ROTINA" ]]; then
  date -u +%FT%TZ > "$WORKSPACE/.last-tick"
  log "cheap-tick (fila vazia, sem rotina)"
  exit 0
fi

# ─── 6. Loop por workspace ─────────────────────────────────────────────────
WORKSPACES=$(jq -r '[.[].workspaceId] | unique | .[]' <<<"$TASKS_JSON")

for WS_ID in $WORKSPACES; do
  SLUG=$("${WORKSPACE}/scripts/lib/resolve-slug.sh" "$WS_ID")
  CWD="$WORKSPACE/projetos/${SLUG:-_base}"

  if [[ ! -d "$CWD" ]]; then
    log "workspace $WS_ID sem diretório (slug=$SLUG); roteando para _base"
    CWD="$WORKSPACE/projetos/_base"
    "${WORKSPACE}/scripts/lib/comment-task-batch.sh" "$WS_ID" \
      "Workspace sem provisionamento no agente. Tarefa processada em _base; provisionar diretório dedicado para evitar fallback."
  fi

  WS_TASKS=$(jq --arg w "$WS_ID" '[.[] | select(.workspaceId==$w)]' <<<"$TASKS_JSON")

  log "workspace=$WS_ID slug=$SLUG tasks=$(jq 'length' <<<"$WS_TASKS")"

  CLAUDE_OUT=$(
    cd "$CWD" || exit 1
    claude --print \
      --model claude-sonnet-4-6 \
      --max-turns "$MAX_TURNS" \
      --output-format json \
      --append-system-prompt "$(cat "$WORKSPACE/scripts/tick-prompt.md")" \
      <<<"TICK_ID=$TICK_ID TASKS=$WS_TASKS ROTINA=" \
      2>>"$LOG_DIR/claude.${TICK_ID}.log"
  )
  CLAUDE_EXIT=$?

  if [[ $CLAUDE_EXIT -ne 0 ]]; then
    log "claude falhou em workspace $WS_ID (exit=$CLAUDE_EXIT)"
    "${WORKSPACE}/scripts/lib/post-incident.sh" "$TICK_ID" "claude-fail" "$WS_ID/$CLAUDE_EXIT" || true
    continue
  fi

  # parse custo e turnos do output JSON (estrutura confirmada empiricamente)
  TICK_COST=$(jq -r '.total_cost_usd // .cost_usd // 0' <<<"$CLAUDE_OUT" 2>/dev/null || echo 0)
  TICK_TURNS=$(jq -r '.num_turns // 0' <<<"$CLAUDE_OUT" 2>/dev/null || echo 0)

  echo "{\"tick_id\":\"$TICK_ID\",\"workspace\":\"$WS_ID\",\"cost_usd\":$TICK_COST,\"turns\":$TICK_TURNS,\"at\":\"$(date -u +%FT%TZ)\"}" \
    >> "$COST_FILE"

  log "workspace=$WS_ID cost=\$$TICK_COST turns=$TICK_TURNS"

  # cost cap por tick → para de processar workspaces restantes
  OVER_TICK=$(awk -v c="$TICK_COST" -v cap="$COST_CAP_TICK" 'BEGIN { print (c >= cap) ? 1 : 0 }')
  if [[ "$OVER_TICK" == "1" ]]; then
    log "GUARDA INTERNA: cost cap por tick (\$$COST_CAP_TICK) excedido em $WS_ID. Pulando workspaces restantes."
    "${WORKSPACE}/scripts/lib/post-incident.sh" "$TICK_ID" "cost-cap-tick" "$TICK_COST/$COST_CAP_TICK" || true
    break
  fi
done

# ─── 7. Rotina obrigatória sem tarefas ─────────────────────────────────────
if [[ -n "$ROTINA" && "$TASK_COUNT" == "0" ]]; then
  log "rotina sem tarefas: $ROTINA"
  (
    cd "$WORKSPACE/projetos/_sistema"
    claude --print \
      --model claude-sonnet-4-6 \
      --max-turns 30 \
      --append-system-prompt "$(cat "$WORKSPACE/scripts/tick-prompt.md")" \
      <<<"TICK_ID=$TICK_ID TASKS=[] ROTINA=$WORKSPACE/scripts/$ROTINA" \
      >>"$LOG_DIR/claude.${TICK_ID}.log" 2>&1
  ) || log "rotina falhou (continua tick)"
fi

# ─── 8. Commit + push consolidado ──────────────────────────────────────────
cd "$WORKSPACE"
if [[ -n "$(git status --porcelain)" ]]; then
  git add -A
  git -c user.name="agente-${AGENT_NAME:-unknown}" \
      -c user.email="${AGENT_EMAIL:-agent@beeads.com.br}" \
      commit -m "tick $TICK_ID — $TASK_COUNT tarefas, $(echo "$WORKSPACES" | wc -w) workspaces" \
      >>"$LOG_DIR/git.log" 2>&1 || log "nada a committar (status mudou após check)"

  for i in 1 2 3; do
    if git push >>"$LOG_DIR/git.log" 2>&1; then
      break
    fi
    log "git push falhou (tentativa $i/3)"
    [[ $i -lt 3 ]] && sleep $((i*2))
  done
fi

# ─── 9. Resumo na tarefa-mãe ───────────────────────────────────────────────
"${WORKSPACE}/scripts/lib/post-tick-summary.sh" "$TICK_ID" "$TASK_COUNT" "$LOG_DIR/claude.${TICK_ID}.log" || true

date -u +%FT%TZ > "$WORKSPACE/.last-tick"
log "end OK"
