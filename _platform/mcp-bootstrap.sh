#!/bin/bash
# Registra MCPs user-scope dentro do container.
# Chamado pelo entrypoint do container; idempotente (claude mcp add é safe contra duplicatas).
#
# Tokens vêm de env vars do Coolify (BLOQUIM_TOKEN, WORKER_TOKEN, etc.).
set -euo pipefail

require() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "[mcp-bootstrap] env var $var não definida — pulando MCP que depende dela" >&2
    return 1
  fi
}

# Bloquim MCP — fila de tarefas
if require BLOQUIM_TOKEN; then
  claude mcp add --scope user bloquim \
    --transport stdio \
    -- npx -y bloquim-mcp \
    --env "BLOQUIM_TOKEN=${BLOQUIM_TOKEN}"
fi

# Semente Platform Worker MCP — contact routes + plataforma
if require WORKER_TOKEN && require WORKER_URL; then
  claude mcp add --scope user platform \
    --transport http \
    --url "${WORKER_URL}/mcp" \
    --header "X-Agent-Token: ${WORKER_TOKEN}"
fi

# Evolution WhatsApp MCP — envio de mensagens
if require EVOLUTION_API_URL && require EVOLUTION_API_KEY && require EVOLUTION_INSTANCE; then
  claude mcp add --scope user whatsapp \
    --transport stdio \
    -- npx -y @aiteks-ltda/mcp-evolution-whatsapp-api \
    --env "EVOLUTION_API_URL=${EVOLUTION_API_URL}" \
    --env "EVOLUTION_API_KEY=${EVOLUTION_API_KEY}" \
    --env "EVOLUTION_INSTANCE=${EVOLUTION_INSTANCE}"
fi

# GitHub MCP — opcional, agentes que tocam repos
if require GITHUB_TOKEN; then
  claude mcp add --scope user github \
    --transport stdio \
    -- npx -y @modelcontextprotocol/server-github \
    --env "GITHUB_TOKEN=${GITHUB_TOKEN}"
fi

# Google MCPs (Gmail, Drive, Calendar) — agentes que precisam
# OAuth credentials montadas via env GOOGLE_CREDENTIALS_JSON
if require GOOGLE_CREDENTIALS_JSON; then
  : # TODO: registrar MCPs Google conforme padrão oficial. Confirmar transport/comando.
fi

echo "[mcp-bootstrap] MCPs user-scope registrados."
