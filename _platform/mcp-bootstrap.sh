#!/bin/bash
# Registra MCPs user-scope dentro do container.
# Chamado pelo entrypoint do container; idempotente (claude mcp add é safe contra duplicatas).
#
# Tokens vêm de env vars do Coolify (BLOQUIM_TOKEN, WORKER_TOKEN, etc.).
#
# Sintaxe `claude mcp add [options] <name> <commandOrUrl> [args...]`.
# IMPORTANTE: `-e/--env` e `-H/--header` são VARIÁDICOS — se vierem ANTES do
# nome, engolem o <name>/<url> ("missing required argument 'name'"). Por isso
# nome e url vêm PRIMEIRO; --header vem por último; -e vem antes do `--`.
#   http : claude mcp add -s user -t http  <nome> <url> --header "H: V"
#   stdio: claude mcp add -s user <nome> -e "K=V" -- <cmd> <args>
set -euo pipefail

require() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "[mcp-bootstrap] env var $var não definida — pulando MCP que depende dela" >&2
    return 1
  fi
}

# Bloquim MCP — fila de tarefas. No modo stdio o bloquim-mcp MINTA o JWT
# internamente a partir de JWT_SECRET + BLOQUIM_USER_ID/EMAIL (não usa um token
# pronto). Chama a API em BLOQUIM_API_BASE_URL.
if require JWT_SECRET && require BLOQUIM_USER_ID && require BLOQUIM_USER_EMAIL && require BLOQUIM_API_BASE_URL; then
  claude mcp add -s user bloquim \
    -e "JWT_SECRET=${JWT_SECRET}" \
    -e "BLOQUIM_USER_ID=${BLOQUIM_USER_ID}" \
    -e "BLOQUIM_USER_EMAIL=${BLOQUIM_USER_EMAIL}" \
    -e "BLOQUIM_API_BASE_URL=${BLOQUIM_API_BASE_URL}" \
    -- npx -y bloquim-mcp
fi

# Semente Platform Worker MCP — contact routes + plataforma (inbox)
if require WORKER_TOKEN && require WORKER_URL; then
  claude mcp add -s user -t http \
    platform "${WORKER_URL}/mcp" \
    --header "X-Agent-Token: ${WORKER_TOKEN}"
fi

# Evolution WhatsApp MCP — envio de mensagens
if require EVOLUTION_API_URL && require EVOLUTION_API_KEY && require EVOLUTION_INSTANCE; then
  claude mcp add -s user whatsapp \
    -e "EVOLUTION_API_URL=${EVOLUTION_API_URL}" \
    -e "EVOLUTION_API_KEY=${EVOLUTION_API_KEY}" \
    -e "EVOLUTION_INSTANCE=${EVOLUTION_INSTANCE}" \
    -- npx -y @aiteks-ltda/mcp-evolution-whatsapp-api
fi

# GitHub MCP — opcional, agentes que tocam repos
if require GITHUB_TOKEN; then
  claude mcp add -s user github \
    -e "GITHUB_TOKEN=${GITHUB_TOKEN}" \
    -- npx -y @modelcontextprotocol/server-github
fi

# Google MCPs (Gmail, Drive, Calendar) — agentes que precisam
# OAuth credentials montadas via env GOOGLE_CREDENTIALS_JSON
if require GOOGLE_CREDENTIALS_JSON; then
  : # TODO: registrar MCPs Google conforme padrão oficial. Confirmar transport/comando.
fi

echo "[mcp-bootstrap] MCPs user-scope registrados."
