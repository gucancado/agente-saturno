---
name: regra-promessa-vira-tarefa
description: REGRA DE AUDITORIA (R1). Durante o sweep, quando um membro da equipe BeeAds promete algo no grupo do projeto ("vou fazer X", "envio até sexta", "já já coloco") e NÃO existe tarefa Bloquim correspondente, cria a tarefa pra não cair no esquecimento. Dispara ao avaliar sinais do grupo num tick de sweep. STATUS: RASCUNHO — revisar gatilhos/thresholds antes de ativar.
---

# R1 — Promessa no grupo vira tarefa

> **RASCUNHO pra revisão.** Ajustar os itens ⚙️ CONFIGURAR antes de ativar (tirar `FORCE_NO_CHANGES`).

## Condição

Numa mensagem **de membro da equipe BeeAds** (não do cliente) no grupo do projeto, há um **compromisso futuro**: verbos de promessa + prazo/objeto. Ex.: "vou colocar já já", "envio o relatório até sexta", "faço a alteração hoje", "amanhã subo a campanha".

E **não existe** tarefa Bloquim no workspace do projeto que já cubra esse compromisso (checar via `bloquim:search_tasks` / `list_workspace_tasks`).

⚙️ CONFIGURAR:
- Lista de verbos/padrões que contam como promessa (evitar falso-positivo com conversa fiada).
- Janela de lookback (só mensagens desde o último sweep — depende do `has-changes`/ledger).
- Como distinguir "membro da equipe" de "cliente" (usar identidade resolvida: telefone → user Bloquim membro do workspace; cliente = não-membro ou role externa).

## Ação

`bloquim.create_task` (**L0**, autônomo) no workspace do projeto:
- título: resumo do compromisso ("Enviar relatório — prometido no grupo").
- descrição: trecho literal + autor + data + `TICK_ID`.
- prazo: inferido do texto (sexta, hoje, amanhã); se ausente, sem prazo + tag `replanejar`.
- tags: `canal:whatsapp`.

Passa por `aprovacao-humana` (classifica `bloquim.create_task` = L0 → executa direto).

**NÃO** responde no grupo. **NÃO** envia nada via A. Se quiser avisar o autor, é DM via **B** (ver R8/R14 — depende de envio-B, ainda não plugado).

## Dedup (ledger)

Chave: `(grupo, "promessa", sha1(autor + objeto_normalizado))`. Não recriar tarefa pra promessa já registrada. Registrar no ledger após criar.

## Fonte

Inbox do grupo via `platform` MCP (mensagens ingeridas pelo número A). Filtra pelo `whatsapp_group_jid` do projeto (`_platform/workspace-map.json`).

## Saída esperada

`executed` (tarefa criada) ou skip (já existia / já no ledger). Logar em `memoria/log-de-execucoes/`.
