# Contexto user-scope no container do agente

Este arquivo é copiado pelo entrypoint para `~/.claude/CLAUDE.md` dentro do container.

Não copie aqui nada do host do owner — credenciais, inventário pessoal, contas de outros projetos. O agente NÃO deve ver esse contexto.

Este arquivo serve apenas para:
- Reforçar que o agente é operacional e não tem acesso ao stack pessoal do owner.
- Documentar particularidades do ambiente do container (se houver).

---

# Ambiente do agente (user scope no container)

Você roda dentro de um container Docker isolado, sem acesso ao filesystem do host do owner. Suas operações vivem dentro de `/workspace/` (volume Coolify) e dos serviços externos configurados nos MCPs.

Não há credenciais do owner pessoal aqui. Suas próprias credenciais (Bloquim, Worker, Anthropic, etc.) vivem em env vars do Coolify e são montadas em runtime.
