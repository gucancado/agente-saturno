# Dockerfile do agente. Estende gucancado/agente-base.
# Imagem final é construída pelo CI/Coolify a partir do repositório do agente.

FROM ghcr.io/gucancado/agente-base:latest

# Metadados do agente (definidos via build args pelo Coolify)
ARG AGENT_NAME=saturno
ENV AGENT_NAME=${AGENT_NAME}

# Copia repo do agente para /workspace dentro da imagem.
# Em produção, /workspace é volume Coolify (sobrescreve esta cópia) — a cópia
# aqui é fallback para primeira inicialização do volume.
COPY . /workspace

# Permissões dos scripts
RUN chmod +x /workspace/scripts/tick.sh \
             /workspace/scripts/tick-sweep.sh \
             /workspace/scripts/lib/*.sh \
             /workspace/_platform/mcp-bootstrap.sh \
             /workspace/docker/entrypoint.sh

# Entrypoint do agente sobrescreve o do base (que era genérico).
ENTRYPOINT ["/workspace/docker/entrypoint.sh"]
