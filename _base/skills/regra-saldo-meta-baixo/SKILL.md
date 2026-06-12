---
name: regra-saldo-meta-baixo
description: REGRA DE AUDITORIA (R8). Durante o sweep, quando o saldo da conta Meta Ads do projeto está abaixo do limite (via meta_alerts do painel), cria tarefa pra repor saldo e alerta o owner via número B. Evita campanha parar por falta de verba. STATUS: RASCUNHO — revisar threshold/owner e depende de fontes ainda não plugadas.
---

# R8 — Saldo Meta baixo → tarefa + aviso ao owner

> **RASCUNHO pra revisão.** ⚙️ CONFIGURAR antes de ativar. **Depende** de: (a) fonte `meta_alerts` plugada, (b) envio via B implementado.

## Condição

Há alerta de **saldo baixo** pra conta Meta Ads do projeto: saldo < threshold OU `meta_alerts` do painel marca `low_balance`.

⚙️ CONFIGURAR:
- Threshold de saldo (R$) — por projeto ou global.
- Fonte: tabela `meta_alerts` no Supabase `base-relacional` (ainda **não plugada** ao sweep) OU MCP `meta-mcp` `get_balance`.
- Quem é o **owner** do projeto a avisar (telefone p/ B) — hoje vazio no PROJECT.md.

## Ação

Dois efeitos:

1. `bloquim.create_task` (**L0**) — "Repor saldo Meta — projeto X" com o valor atual + `TICK_ID`. Tag `canal:whatsapp` não; usar tag de mídia se houver.
2. **Aviso ao owner via B** (`whatsapp.send`, **L1** se contato conhecido/janela; senão template L1 ou L2) — DM ao owner: "Saldo Meta do projeto X em R$ <valor>, abaixo do limite. Tarefa criada."

⚠️ **PRÉ-REQUISITO do efeito 2:** capacidade de envio via **B** (skill/tool chamando `/send-cloud` do worker). Enquanto não existir, o efeito 2 vira **comentário na tarefa** (L0) marcando o owner, em vez de DM. Saturno **nunca** posta no grupo nem envia via A.

Tudo via `aprovacao-humana`.

## Dedup (ledger)

Chave: `(projeto, "saldo_baixo", YYYY-MM-DD)`. Um aviso por dia por projeto (não spammar a cada tick de 10min). Registrar no ledger.

## Fonte

`meta_alerts` (Supabase) ou `meta-mcp:get_balance`. Resolver a conta Meta do projeto.

## Saída esperada

`executed` (tarefa + aviso) / `pending` (se aviso cair em L2) / skip (já avisado hoje). Log em `memoria/log-de-execucoes/`.
