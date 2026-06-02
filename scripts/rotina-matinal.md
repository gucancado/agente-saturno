# Rotina matinal (perfil `daily`)

Executar em todo tick `daily` (`0 8 * * 1-5`), independente de a fila estar vazia ou cheia.

## Sequência

1. **Round-up de pendências do dia**:
   - `bloquim:list_my_tasks(scope: today, status: [pending, in_progress])`
   - Agrupar por workspace
   - Compor resumo: "<N> tarefas pendentes hoje em <M> projetos"

2. **Identificar urgências**:
   - Tarefas com `scheduleMode: urgente` ou tag `replanejar`
   - Tarefas sem atualização há >24h (potencial loop interrompido)

3. **Aprovações pendentes**:
   - `bloquim:search_tasks(tag: type:aprovacao, status: pending)` em todos workspaces
   - Listar quantas estão aguardando, quantas estão prestes a expirar (>20h)

4. **Postar resumo na tarefa-mãe** `<agente>-monitoramento`:
   ```markdown
   # Round-up matinal TICK_<id>

   ## Hoje
   - Total pendente: <N> tarefas em <M> projetos
   - Urgentes: <K>
   - Antigas (>24h sem update): <L>

   ## Aprovações
   - Aguardando: <X>
   - Quase expiram: <Y>

   ## Por projeto
   - clinica-cbv: <a>
   - vem-curtir: <b>
   - ...
   ```

5. **Disparar replano** para tarefas antigas inacabadas (adiciona tag `replanejar` ou comentário).

6. (Opcional) Enviar **bom-dia interno** para o owner via tarefa específica no `_sistema` se houver decisões pendentes que precisam de atenção dele.

## NÃO fazer na rotina matinal

- Não enviar mensagens externas. Rotina é interna.
- Não processar tarefas individuais — isso é trabalho do loop por workspace.
