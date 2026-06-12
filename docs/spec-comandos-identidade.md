# Spec — Comandos `!`, identidade WhatsApp↔Bloquim e topologia A/B

> Padrão do ecossistema de agentes (saturno, mercurio, futuros). Comandos em **pt-BR**.

## 1. Topologia de canais

| Nº | Transporte | Papel | Direção |
|----|-----------|-------|---------|
| **A** | Evolution/QR (membro de grupos) | **READ-ONLY**: intake de grupos. Ingestão feita pelo **worker** (webhook Evolution → `webhook_logs`). | inbound |
| **B** | WhatsApp Cloud API (não está em grupo) | DM com indivíduos. **Única saída** (alertas + respostas de comando). | in/out |

**Regras invioláveis:**
- Saturno **nunca envia via A**. O container do saturno **não registra o MCP Evolution** (não precisa: lê via worker/platform MCP). Isso torna "postar em grupo de cliente" **impossível por arquitetura**, não por instrução.
- Toda saída do saturno = **B** (`POST /send-cloud` no worker).
- Resposta de comando só é texto-livre dentro da **janela de 24h** (a pessoa precisa ter dado DM no B). Logo o **canal de comando = DM no B**. Comando dito em grupo (via A) → no máximo notifica owner via B; não responde no grupo.

## 2. Formato de comando

- Prefixo **`!`** (1 caractere, fácil no teclado mobile, discrimina de conversa, convenção de bot).
- Parse: `trim → lower → remove acento → exige '!' inicial → 1º token = comando → resto = args`.
- Case-insensitive. Nomes em **pt-BR**.

### Registry inicial (genérico, todos agentes)

| Comando | Aliases | Escopo | Efeito |
|---------|---------|--------|--------|
| `!oi` | `!status` | público | Status: "Olá[, <nome>]! Estou ativo, tudo certo." |
| `!ajuda` | `!comandos` | público | Lista comandos disponíveis ao usuário. |

### Específicos por agente (próxima fase)
- **mercurio**: `!zerar` (alias legado `zerar-conversa`) — reset de conversa.
- **saturno**: `!resumo [projeto]`, `!pendencias [projeto]`, `!silenciar <projeto> [tempo]` — **escopo workspace** (exigem permissão).

## 3. Identidade WhatsApp ↔ Bloquim

- Fonte: coluna `users.whatsapp` (E.164) no Bloquim + `workspace_members.role`.
- Resolução: telefone do remetente → `{userId, name, email, workspaces:[{id,role}]}`.
- Implementação: endpoint interno no bloquim-api `GET /api/internal/resolve-by-whatsapp?phone=` (gated por secret compartilhado), consumido pelo worker. Read-only.

## 4. Permissões (gate por CÓDIGO, não instrução)

| Escopo | Quem pode | Telefone desconhecido |
|--------|-----------|----------------------|
| público (`!oi`,`!ajuda`) | qualquer um | responde genérico |
| workspace (`!silenciar`...) | membro do workspace alvo com role suficiente (editor/admin) | **recusa** |
| owner | só o owner | recusa |

- Dispatch determinístico (regex), **sem LLM** → custo zero, confiável.
- Resposta sempre via **B**.

## 5. Multimodelo (camada de inferência, não cérebro)

- Cérebro do tick = Claude Code (Anthropic). Por ora `ANTHROPIC_API_KEY`.
- Sub-tarefas (classificar/resumir/redigir) → `@beeads/agent-kernel` `complete()`: Anthropic + Gemini (API key), OpenAI = **delegado via Codex CLI** (plano de assinatura, não API).
- "Cérebro agnóstico" (gateway / loop próprio) **fora de escopo agora** — caro/frágil; ganho real está na inferência agnóstica (kernel). Detalhe e prós/contras: ver histórico de decisão.
- Comandos **não usam modelo**.
