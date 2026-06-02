@../../_base/CLAUDE.md
@PROJECT.md

# Overrides do projeto _sistema

## Foco

- Ler comentários da tarefa-mãe de monitoramento e identificar padrões/incidentes recorrentes.
- Processar tarefas de triagem: ler conteúdo da mensagem, decidir workspace correto, mover (`bloquim:move_task`) + adicionar route via `platform:add_contact_route`.
- Executar rotinas (perfil `daily`) — round-up matinal: listar pendências do dia em todos os workspaces, postar resumo na tarefa-mãe.

## Não fazer

- Não responder mensagens externas a partir daqui — sempre mova primeiro para o workspace correto.
- Não criar tarefas em outros workspaces a partir daqui sem motivo claro (use somente para provisionamento ou triagem).
