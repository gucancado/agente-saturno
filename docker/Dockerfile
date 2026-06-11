# Dockerfile do agente. Estende gucancado/agente-base.
# Imagem final é construída pelo CI/Coolify a partir do repositório do agente.

FROM ghcr.io/gucancado/agente-base:latest

# Metadados do agente (definidos via build args pelo Coolify)
ARG AGENT_NAME=saturno
ENV AGENT_NAME=${AGENT_NAME}

# Copia repo do agente para /workspace dentro da imagem.
# Em produção, /workspace é volume Coolify (sobrescreve esta cópia) — a cópia
# aqui é fallback para primeira inicialização do volume.
# Build steps como root: a base termina em `USER agent`, e o COPY traz os
# arquivos owned por root → `chmod` rodando como agent dá "Operation not permitted".
USER root

COPY . /workspace

# Normaliza line endings (scripts vindos do Windows podem ter CRLF e quebrar o
# shebang em runtime) + bit de execução + ownership pro usuário de runtime.
RUN find /workspace -name '*.sh' -type f -exec sed -i 's/\r$//' {} \; \
    && chmod +x /workspace/scripts/tick.sh \
                /workspace/scripts/tick-sweep.sh \
                /workspace/scripts/lib/*.sh \
                /workspace/_platform/mcp-bootstrap.sh \
                /workspace/docker/entrypoint.sh \
    && chown -R agent:agent /workspace

USER agent

# Entrypoint do agente sobrescreve o do base (que era genérico).
ENTRYPOINT ["bash", "/workspace/docker/entrypoint.sh"]
