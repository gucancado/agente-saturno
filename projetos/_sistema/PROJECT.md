# Projeto _sistema (meta-workspace)

Workspace especial reservado pelo agente. Não corresponde a cliente — é onde vivem:

- **Tarefa-mãe de monitoramento** (`<agente>-monitoramento`): perpétua, recebe comentários de resumo de tick (gerados por `scripts/lib/post-tick-summary.sh`).
- **Tarefas de incidente**: criadas automaticamente quando algo falha (cost cap atingido, erro em workspace, etc.).
- **Tarefas de triagem**: mensagens novas de remetentes sem `contact_route` caem aqui com tag `triagem-necessaria` para o agente classificar e mover.
- **Tarefas de provisionamento**: solicitações de novos workspaces, novos contatos, ajustes de policy.
- **Rotinas matinais** (perfil `daily`): round-ups e relatórios consolidados.

## Particularidades

Este projeto **não** representa cliente final. Ações daqui são internas (L0 default) — não enviam WhatsApp/email externamente exceto via tarefas que apontam para projetos específicos.
