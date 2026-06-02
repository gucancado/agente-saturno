# Contexto compartilhado entre projetos

> Importado via `@../../_base/CLAUDE.md` na primeira linha de cada `projetos/<slug>/CLAUDE.md`.

## Princípios operacionais aplicáveis a todos os projetos

### Antes de qualquer ação externa

Consulte `~/.claude/skills/_base/aprovacao-humana/SKILL.md`. A skill classifica a ação em L0/L1/L2 conforme `_base/policies/approval.yml` e gerencia o protocolo de aprovação.

### Verificação de aprovações no início do tick

Skill `verificar-aprovacoes` roda como passo 0 do tick (antes do loop por workspace). Atualiza o cache de aprovações em `_platform/approval-cache.json` mas não executa as ações ali — execução acontece quando você reconsiderar a ação durante processamento da tarefa-pai.

### Continuidade entre ticks

- Concluiu trabalho integral em uma tarefa: comente `[CONCLUÍDO TICK_<id>] <resumo>`.
- Atingiu limite de turnos: comente `[LIMITE TURNOS TICK_<id>] continuarei no próximo` em tarefas inacabadas.
- Ao começar a processar uma tarefa: leia o histórico de comentários para identificar o estado de continuidade.

### Memória

Cada projeto tem `memoria/` próprio (vault Obsidian). Aprendizados generalizáveis entre projetos vão em `_base/memoria/learnings/`.

Convenções:

- `memoria/log-de-execucoes/YYYY-MM-DD-task_<id>.md` — uma nota por tarefa processada
- `memoria/relacionamento/<contato>.md` — interações e contexto por contato
- `memoria/referencias/` — material externo (briefings, docs)
- `memoria/learnings/` — generalizações
- `memoria/trabalhos-em-andamento/` — rascunhos, hipóteses

### Tags-set padrão (Bloquim)

| Tag | Uso |
|---|---|
| `type:aprovacao` | Tarefa-filha de pedido de aprovação L2 |
| `triagem-necessaria` | Mensagem nova de remetente sem `contact_route` |
| `canal:whatsapp` | Tarefa originada de WhatsApp |
| `canal:email` | Tarefa originada de email |
| `expired` | Pedido de aprovação que esgotou 24h |
| `replanejar` | Tarefa que precisa ser repensada no próximo tick |

### Não faça (cross-projeto)

- Não acesse filesystem de outro projeto. Cross-workspace só via tools do `bloquim-mcp`.
- Não envie mensagens externas sem passar pela skill `aprovacao-humana`.
- Não modifique `_platform/`, `_base/policies/`, ou `scripts/` durante um tick.
