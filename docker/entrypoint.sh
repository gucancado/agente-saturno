#!/bin/bash
# Entrypoint do container do agente. Roda na inicialização do container Coolify.
# Sequência:
#   1. Prepara ~/.claude com stub user-scope (NÃO espelha host do owner)
#   2. Symlinks de skills (_base + obsidian)
#   3. Registra MCPs user-scope
#   4. Gera crontab a partir de scripts/cadencia.yml
#   5. Exec supercronic
set -euo pipefail

log() { echo "[entrypoint $(date -u +%FT%TZ)] $*"; }

# Diagnóstico/resiliência: se qualquer passo falhar (set -e), loga a linha e
# mantém o container vivo (tail -f) em vez de crash-loop cego — assim os logs
# do Coolify ficam inspecionáveis. Remover o tail quando o boot estabilizar.
trap 'rc=$?; echo "[entrypoint ERRO] rc=$rc na linha ${LINENO} — mantendo container vivo p/ diagnóstico"; exec tail -f /dev/null' ERR

WORKSPACE=/workspace
HOME_DIR="${HOME:-/home/agent}"
CLAUDE_HOME="${HOME_DIR}/.claude"

log "AGENT_NAME=${AGENT_NAME:-unknown}"

# ─── 1. User-scope no container ────────────────────────────────────────────
mkdir -p "$CLAUDE_HOME/skills"
cp "$WORKSPACE/_platform/user-claude.md" "$CLAUDE_HOME/CLAUDE.md"
cp "$WORKSPACE/_platform/user-settings.json" "$CLAUDE_HOME/settings.json"
log "user-scope files copied"

# ─── 2. Symlinks de skills compartilhadas ──────────────────────────────────
ln -sfn "$WORKSPACE/_base/skills" "$CLAUDE_HOME/skills/_base"
if [[ -d /opt/skills/obsidian-skills ]]; then
  ln -sfn /opt/skills/obsidian-skills "$CLAUDE_HOME/skills/obsidian"
fi
log "skills symlinks created"

# ─── 3. MCPs user-scope ────────────────────────────────────────────────────
if [[ -x "$WORKSPACE/_platform/mcp-bootstrap.sh" ]]; then
  "$WORKSPACE/_platform/mcp-bootstrap.sh" || log "mcp-bootstrap encontrou problemas (continuing)"
fi

# ─── 4. Gerar crontab a partir de cadencia.yml ─────────────────────────────
# Crontab num path gravável pelo usuário de runtime (agent, não-root). Antes era
# /etc/crontabs/agent → mkdir falhava com Permission denied. supercronic aceita
# qualquer path como argumento.
CRONTAB="${HOME_DIR}/crontab"
mkdir -p "$(dirname "$CRONTAB")"
: > "$CRONTAB"

# Para cada perfil habilitado, emite uma linha por entry de cron.
PROFILES=$(yq -r '.profiles | keys | .[]' "$WORKSPACE/scripts/cadencia.yml")
for PROFILE in $PROFILES; do
  ENABLED=$(yq -r ".profiles.$PROFILE.enabled // true" "$WORKSPACE/scripts/cadencia.yml")
  if [[ "$ENABLED" != "true" ]]; then
    log "perfil $PROFILE desabilitado"
    continue
  fi
  TZ=$(yq -r ".profiles.$PROFILE.timezone // \"UTC\"" "$WORKSPACE/scripts/cadencia.yml")
  RUNNER=$(yq -r ".profiles.$PROFILE.runner // \"tick.sh\"" "$WORKSPACE/scripts/cadencia.yml")
  CRONS=$(yq -r ".profiles.$PROFILE.crons[]" "$WORKSPACE/scripts/cadencia.yml")
  while IFS= read -r CRON_EXPR; do
    [[ -z "$CRON_EXPR" ]] && continue
    # CRON_TZ tem que ficar em LINHA PRÓPRIA — supercronic não aceita o prefixo
    # inline na mesma linha do schedule (invalida o crontab e o supercronic sai
    # imediatamente, causando crash-loop do container).
    echo "CRON_TZ=$TZ" >> "$CRONTAB"
    echo "$CRON_EXPR /workspace/scripts/$RUNNER $PROFILE >> /workspace/.logs/supercronic.log 2>&1" \
      >> "$CRONTAB"
  done <<< "$CRONS"
done

log "crontab gerado:"
cat "$CRONTAB" | sed 's/^/  /'

# ─── 5. Volumes esperados ──────────────────────────────────────────────────
mkdir -p "$WORKSPACE/.logs" "$WORKSPACE/.cost" "$WORKSPACE/.locks"

# ─── 6. Configura identity para git commits ────────────────────────────────
git config --global user.name "agente-${AGENT_NAME:-unknown}"
git config --global user.email "${AGENT_EMAIL:-agent@beeads.com.br}"
git config --global pull.rebase true

# ─── 7. Exec supercronic ───────────────────────────────────────────────────
log "starting supercronic"
# Sem `exec`: se o supercronic sair (ex.: crontab inválido), logamos o código e
# mantemos o container vivo (tail -f) em vez de crash-loop cego — assim os logs
# do Coolify ficam inspecionáveis. Em operação normal supercronic bloqueia aqui.
if ! supercronic "$CRONTAB"; then
  rc=$?
  log "ERRO: supercronic saiu (código $rc). Crontab logado acima. Mantendo container vivo p/ diagnóstico."
  exec tail -f /dev/null
fi
