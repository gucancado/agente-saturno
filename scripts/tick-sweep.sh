#!/bin/bash
# tick-sweep.sh <profile>
# Runtime de SWEEP (project-driven). Itera os projetos de workspace-map.json,
# aplica gate de mudanca barato por projeto, e roda `claude --print` agentico
# no cwd de cada projeto com novidade. NAO usa fila de tarefas Bloquim.
#
# Testabilidade:
#   WORKSPACE=<dir>     override do /workspace (default /workspace)
#   SWEEP_DRY_RUN=1     nao chama `claude`; ecoa o comando (pra teste local)
# -e omitido de proposito: falha num projeto nao deve abortar o sweep inteiro.
set -uo pipefail

PROFILE="${1:?usage: tick-sweep.sh <profile>}"
WORKSPACE="${WORKSPACE:-/workspace}"
export WORKSPACE
TICK_ID="$(date -u +%Y%m%dT%H%M%SZ)-${PROFILE}-$$"
LOCK_FILE="${WORKSPACE}/.locks/tick.${PROFILE}.lock"
LOG_DIR="${WORKSPACE}/.logs"
COST_DIR="${WORKSPACE}/.cost"
COST_FILE="${COST_DIR}/$(date -u +%F).jsonl"
CADENCIA="${WORKSPACE}/scripts/cadencia.yml"

mkdir -p "$(dirname "$LOCK_FILE")" "$LOG_DIR" "$COST_DIR"

log() { echo "[$(date -u +%FT%TZ)] [$TICK_ID] $*" | tee -a "$LOG_DIR/tick.log"; }

# ── Lock por perfil ──────────────────────────────────────────────────────
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "skip: sweep anterior do perfil $PROFILE ainda rodando"
  exit 0
fi

log "sweep start"

# ── Guarda de custo (soft cap diario) ────────────────────────────────────
COST_CAP_DAY=$(yq -r '.guardrails.cost_cap_usd_per_day // 5.0' "$CADENCIA")
COST_CAP_TICK=$(yq -r '.guardrails.cost_cap_usd_per_tick // 0.5' "$CADENCIA")

if [[ -f "$COST_FILE" ]]; then
  COST_TODAY=$(jq -s '[.[].cost_usd] | add // 0' "$COST_FILE")
else
  COST_TODAY=0
fi
OVER_DAY=$(awk -v c="$COST_TODAY" -v cap="$COST_CAP_DAY" 'BEGIN { print (c >= cap) ? 1 : 0 }')
if [[ "$OVER_DAY" == "1" ]]; then
  log "GUARDA: cost cap diario (\$$COST_CAP_DAY) excedido (\$$COST_TODAY). Pulando sweep."
  exit 0
fi

# ── Perfil ────────────────────────────────────────────────────────────────
ENABLED=$(yq -r ".profiles.$PROFILE.enabled // true" "$CADENCIA")
if [[ "$ENABLED" != "true" ]]; then
  log "perfil $PROFILE desabilitado; encerrando"
  exit 0
fi
MODEL=$(yq -r ".profiles.$PROFILE.model // \"claude-sonnet-4-6\"" "$CADENCIA")
MAX_TURNS=$(yq -r ".profiles.$PROFILE.max_turns_per_workspace // 40" "$CADENCIA")
# Slim de tools: se o perfil define allowed_tools, restringe a superfície oferecida ao
# modelo (corta tokens de schema de ~49 tools p/ ~16). Vazio = sem restrição.
ALLOWED_TOOLS=$(yq -r ".profiles.$PROFILE.allowed_tools // [] | join(\",\")" "$CADENCIA")

# ── Git pull (best-effort) ────────────────────────────────────────────────
git -C "$WORKSPACE" pull --rebase --autostash >/dev/null 2>>"$LOG_DIR/git.log" || log "git pull falhou (continua)"

# ── Lista de projetos a varrer ────────────────────────────────────────────
SLUGS=$("$WORKSPACE/scripts/lib/sweep-projects.sh" 2>>"$LOG_DIR/tick.log")
SLUG_COUNT=$(echo "$SLUGS" | grep -c . || true)
log "projetos no sweep: $SLUG_COUNT"

TOTAL_COST=0
PROCESSED=0
SKIPPED=0

for SLUG in $SLUGS; do
  [[ -z "$SLUG" ]] && continue
  CWD="$WORKSPACE/projetos/$SLUG"
  if [[ ! -d "$CWD" ]]; then
    log "projeto $SLUG sem diretorio em projetos/; pulando"
    continue
  fi

  # ── Gate de mudanca barato ──
  if ! "$WORKSPACE/scripts/lib/has-changes.sh" "$SLUG" 2>>"$LOG_DIR/tick.log"; then
    log "projeto $SLUG sem novidade (gate); pulando tick caro"
    SKIPPED=$((SKIPPED+1))
    continue
  fi

  log "auditando projeto $SLUG"

  if [[ "${SWEEP_DRY_RUN:-0}" == "1" ]]; then
    echo "[DRY_RUN] claude --print --model $MODEL --max-turns $MAX_TURNS (cwd=$CWD) SLUG=$SLUG"
    PROCESSED=$((PROCESSED+1))
    continue
  fi

  # Monta args; --allowedTools (vírgula, 1 arg — não-variádico aqui) só se definido.
  CLAUDE_ARGS=(--print --model "$MODEL" --max-turns "$MAX_TURNS" --output-format json)
  [[ -n "$ALLOWED_TOOLS" ]] && CLAUDE_ARGS+=(--allowedTools "$ALLOWED_TOOLS")
  CLAUDE_ARGS+=(--append-system-prompt "$(cat "$WORKSPACE/scripts/tick-sweep-prompt.md")")

  run_claude() {
    cd "$CWD" || return 1
    claude "${CLAUDE_ARGS[@]}" \
      <<<"TICK_ID=$TICK_ID SLUG=$SLUG R1_VERDICT_DM_TO=${R1_VERDICT_DM_TO:-}" \
      2>>"$LOG_DIR/claude.${TICK_ID}.log"
  }

  CLAUDE_OUT=$(run_claude)
  CLAUDE_EXIT=$?

  # Retry ÚNICO só na assinatura de COLD-START: exit!=0 E stdout sem JSON válido
  # (MCP/npx ainda esquentando logo após deploy → claude morre sem produzir
  # resultado). Resultado JSON válido com erro (ex. error_max_turns) NÃO retenta:
  # é resultado real, re-rodar só queimaria custo.
  if [[ $CLAUDE_EXIT -ne 0 ]] && ! jq -e . >/dev/null 2>&1 <<<"$CLAUDE_OUT"; then
    log "claude exit=$CLAUDE_EXIT sem JSON no projeto $SLUG — assinatura de cold-start; retry em 30s"
    sleep 30
    CLAUDE_OUT=$(run_claude)
    CLAUDE_EXIT=$?
  fi

  if [[ $CLAUDE_EXIT -ne 0 ]]; then
    log "claude falhou no projeto $SLUG (exit=$CLAUDE_EXIT)"
    log "--- claude stdout (CLAUDE_OUT, head) ---"
    echo "${CLAUDE_OUT:0:1200}"
    log "--- claude stderr (tail) ---"
    tail -30 "$LOG_DIR/claude.${TICK_ID}.log" 2>/dev/null || true
    continue
  fi

  # Surface o veredito/resultado do agente no stdout (visibilidade via Coolify).
  # .result = texto final do agente (o veredito, em modo veredito). Em sucesso o
  # .subtype é só "success" e mascarava o veredito → priorizar .result.
  RES_SUMMARY=$(jq -r '.result // .subtype // empty' <<<"$CLAUDE_OUT" 2>/dev/null | head -c 2000 || true)
  log "claude OK projeto $SLUG — resultado: ${RES_SUMMARY:-<sem texto>}"

  # P0 (custo): surface o breakdown de tokens no SUCESSO (antes só na falha) pra
  # atribuir onde o custo do tick mora (schema MCP vs histórico de tool-results vs
  # output). Lê .usage/.modelUsage/.num_turns do CLAUDE_OUT (output-format json).
  USAGE_JSON=$(jq -c '{usage, modelUsage, num_turns, duration_ms, duration_api_ms}' <<<"$CLAUDE_OUT" 2>/dev/null || echo '{}')
  log "usage: $USAGE_JSON"

  TICK_COST=$(jq -r '.total_cost_usd // .cost_usd // 0' <<<"$CLAUDE_OUT" 2>/dev/null || echo 0)
  echo "{\"tick_id\":\"$TICK_ID\",\"project\":\"$SLUG\",\"cost_usd\":$TICK_COST,\"at\":\"$(date -u +%FT%TZ)\"}" \
    >> "$COST_FILE"
  TOTAL_COST=$(awk -v t="$TOTAL_COST" -v c="$TICK_COST" 'BEGIN { print t + c }')
  PROCESSED=$((PROCESSED+1))
  log "projeto $SLUG cost=\$$TICK_COST"

  # Avanca o cursor do gate has-changes.sh: marca que este projeto foi varrido
  # ate agora. Proximos ticks so reprocessam se chegar mensagem mais nova.
  mkdir -p "$CWD/memoria" 2>/dev/null || true
  date -u +%FT%TZ > "$CWD/memoria/.sweep-cursor" 2>/dev/null || true

  # cap por tick → para o sweep. Nota: compara o ACUMULADO do sweep (TOTAL_COST),
  # nao o custo de um projeto isolado — limite de gasto por invocacao do sweep.
  OVER_TICK=$(awk -v c="$TOTAL_COST" -v cap="$COST_CAP_TICK" 'BEGIN { print (c >= cap) ? 1 : 0 }')
  if [[ "$OVER_TICK" == "1" ]]; then
    log "GUARDA: cost cap por tick (\$$COST_CAP_TICK) atingido; projetos restantes ficam pro proximo sweep"
    break
  fi
done

# ── Commit + push de memoria (se houve escrita) ───────────────────────────
if [[ "${SWEEP_DRY_RUN:-0}" != "1" ]]; then
  cd "$WORKSPACE" || { log "cd workspace falhou; pulando commit"; exit 1; }
  if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git -c user.name="agente-${AGENT_NAME:-saturno}" \
        -c user.email="${AGENT_EMAIL:-agent@beeads.com.br}" \
        commit -m "sweep $TICK_ID — $PROCESSED projetos auditados" \
        >>"$LOG_DIR/git.log" 2>&1 || log "nada a committar"
    git push >>"$LOG_DIR/git.log" 2>&1 || log "git push falhou"
  fi
fi

log "sweep end processed=$PROCESSED skipped=$SKIPPED total_cost=\$$TOTAL_COST"
