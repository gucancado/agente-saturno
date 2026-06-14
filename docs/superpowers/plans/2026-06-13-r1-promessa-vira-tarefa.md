# R1 — Promessa da equipe vira tarefa — Implementation Plan (v2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** O saturno, no sweep, detecta promessas de membros da equipe BeeAds no grupo WhatsApp do projeto e cria a tarefa Bloquim correspondente (L0), sem nenhuma saída externa.

**Architecture:** 3 repos em cadeia. **A** (`beeads-bloquim`): destravar/mergear o endpoint interno `resolve-by-whatsapp`. **B** (`semente-platform-worker`): expor `resolveByWhatsapp` como tool MCP `resolve_whatsapp_identity`. **C** (`agente-saturno`): reescrever a skill da regra R1 (Camada 1 autoritativa + Camada 2 só-hipótese, dedup por chave-slug sem sha1, ordem transacional). **D**: teste supervisionado manual + tirar o freio.

**Tech Stack:** Express/Drizzle (bloquim-api), Fastify + MCP SDK (StreamableHTTP stateless) + node:test (worker), Claude Code skills + jq/yq/bash allowlistado (saturno), Coolify API p/ deploy/logs.

**Spec:** [docs/specs/2026-06-13-r1-promessa-vira-tarefa.md](../../specs/2026-06-13-r1-promessa-vira-tarefa.md). Decisões: D1 = Camada 2 só hipótese (confirmado); D2 = nota só em memória; D3 = slug 3–5 keywords.

**Runtime do agente (LOAD-BEARING):** `claude --print` com allowlist `_platform/user-settings.json` — Bash só `git/date/jq/yq/cat/ls/mkdir`. **NÃO existe `sha1sum`, `head`, `tail`, `printf`, `awk`, `sed`, `tr`, `curl`.** Logo: dedup por **chave-slug em texto** (não sha1); leitura de JSONL via `cat … 2>/dev/null | jq -s …` (sem `head`/`tail`); `create_task` **não tem `tags`** → marcadores vão no corpo da `description`. Base do container = `node:24-slim` (Debian) → GNU `date -d` disponível.

---

## Fase A — Destravar e mergear PR #14 (repo `beeads-bloquim`)

> Repo local: `c:\Users\gusta\Projetos\beeads-bloquim\repo`. Branch do PR: `feat/internal-resolve-by-whatsapp`. **Não TDD** — ops de lockfile + merge + deploy + smoke. Não tocar nas rotas (já revisadas no PR). **A e B são independentes** (código/deploy); só o *runtime* de B depende de A (a tool retorna `null` graceful enquanto A não sobe). Podem ir em paralelo.

### Task A1: Regenerar lockfile na branch do PR

**Files:** Modify: `pnpm-lock.yaml` (raiz, regenerado).

- [ ] **Step 1: Buscar a branch do PR (sem perder WIP do usuário)**

```bash
cd /c/Users/gusta/Projetos/beeads-bloquim/repo
git stash list
git fetch origin feat/internal-resolve-by-whatsapp
git checkout feat/internal-resolve-by-whatsapp
git pull --ff-only origin feat/internal-resolve-by-whatsapp
```
Expected: HEAD na branch do PR, tree limpo.

- [ ] **Step 2: Reproduzir a falha**

```bash
pnpm install --frozen-lockfile
```
Expected: FALHA `ERR_PNPM_LOCKFILE_CONFIG_MISMATCH ... "overrides" ... doesn't match`.

- [ ] **Step 3: Regenerar o lockfile**

```bash
pnpm install --no-frozen-lockfile
git diff --stat pnpm-lock.yaml
```
Expected: instala e reescreve `pnpm-lock.yaml`.

- [ ] **Step 4: Verificar que o frozen passa (gate idêntico ao CI/Coolify)**

```bash
pnpm install --frozen-lockfile
```
Expected: "Lockfile is up to date" / passa supply-chain — sem erro.

- [ ] **Step 5: Commit + push**

```bash
git add pnpm-lock.yaml
git commit -m "chore: regen pnpm-lock após drift de overrides (destrava CI/deploy frozen-lockfile)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
git push origin feat/internal-resolve-by-whatsapp
```

- [ ] **Step 6: Aguardar CI verde**

```bash
gh pr checks 14 --repo gucancado/beeads-bloquim --watch
```
Expected: `build-and-test pass`. Se vermelho → `gh run view <id> --log-failed`, diagnosticar, NÃO mergear.

### Task A2: Merge PR #14 + deploy bloquim-api + smoke do endpoint

**Files:** nenhum (ops).

> **Pré-requisito de credencial:** resolver antes `INTERNAL_API_SECRET` e o FQDN canônico do bloquim-api a partir do env do app no Coolify (UI → app bloquim-api → Environment, ou da var `BLOQUIM_API_BASE_URL`/`BLOQUIM_API_URL`). Não chutar FQDN.

- [ ] **Step 1: Merge (squash) após CI verde**

```bash
gh pr merge 14 --repo gucancado/beeads-bloquim --squash --delete-branch
```

- [ ] **Step 2: Achar uuid do bloquim-api e disparar deploy**

```bash
TOKEN="<coolify_token_do_CLAUDE.md_global>"
curl -s -H "Authorization: Bearer $TOKEN" http://5.78.199.192:8000/api/v1/applications \
  | jq -r '.[] | select((.fqdn // "")|test("bloquim")) | {uuid,name,fqdn}'
curl -s -X POST -H "Authorization: Bearer $TOKEN" "http://5.78.199.192:8000/api/v1/deploy?uuid=<bloquim_api_uuid>"
```
Expected: deployment queued. Aguardar ~2–4min.

- [ ] **Step 3: Smoke do endpoint em prod**

```bash
SECRET="<INTERNAL_API_SECRET_do_Coolify>"
BASE="<FQDN_real_do_bloquim_api>"   # ex.: https://bloquim.beeads.com.br
curl -s -H "X-Internal-Secret: $SECRET" "$BASE/api/internal/resolve-by-whatsapp?phone=<numero_de_equipe_conhecido>" | jq .
curl -s -o /dev/null -w "%{http_code}\n" -H "X-Internal-Secret: $SECRET" "$BASE/api/internal/resolve-by-whatsapp?phone=5500000000000"
```
Expected: 1º `{userId,name,email,whatsapp,workspaces:[...]}`; 2º imprime `404`.

- [ ] **Step 4: Checkpoint** — Fase A ok quando endpoint responde 200/404. Voltar repo local p/ branch original do usuário (`git checkout <branch-anterior>`).

---

## Fase B — Tool MCP `resolve_whatsapp_identity` (repo `semente-platform-worker`)

> Repo local: `c:\Users\gusta\Projetos\semente-platform-worker`. **Branch:** Coolify deploya **master**; local pode estar em `feat/lua-v1` → trabalhar/mergear em master e confirmar push antes do deploy. Sem unit-test de MCP tools no repo → validação por `typecheck`/`build` (B1) + **smoke funcional real via MCP client** (B2).

### Task B1: Registrar a tool no platform MCP

**Files:** Modify: `src/mcp/tools.ts`.

- [ ] **Step 1: Import de `resolveByWhatsapp`**

No topo de `src/mcp/tools.ts`, junto aos outros imports:

```ts
import { resolveByWhatsapp } from '../commands/identity.js';
```

- [ ] **Step 2: Registrar a tool** (dentro de `registerTools`, após `delete_contact_route`)

```ts
  // ── resolve_whatsapp_identity ──────────────────────────────────────────
  server.registerTool(
    'resolve_whatsapp_identity',
    {
      description:
        'Resolve um número WhatsApp → identidade Bloquim (userId, nome, email, whatsapp e workspaces com role). Use pra decidir se um remetente do grupo é membro da equipe (membro do workspace do projeto) ou cliente. Retorna a string "null" se o número não estiver cadastrado em nenhum usuário Bloquim.',
      inputSchema: {
        phone: z
          .string()
          .describe('Telefone em E.164 ou só dígitos (ex: "+5531999594121" ou "5531999594121"). A resolução compara apenas dígitos.'),
      },
    },
    async ({ phone }): Promise<CallToolResult> => {
      const user = await resolveByWhatsapp(phone);
      return {
        content: [{ type: 'text', text: user ? JSON.stringify(user) : 'null' }],
      };
    }
  );
```

- [ ] **Step 3: Typecheck + Build + Lint**

```bash
cd /c/Users/gusta/Projetos/semente-platform-worker
pnpm typecheck && pnpm build && (pnpm lint 2>&1 | head -20 || true)
```
Expected: sem erros (`resolveByWhatsapp` retorna `ResolvedUser | null`; `z`/`CallToolResult` já importados).

### Task B2: Smoke script + deploy + validação funcional da tool

**Files:** Create: `scripts/smoke-resolve-identity.mjs` (smoke do MCP client contra prod).

- [ ] **Step 1: Criar o smoke script** (usa o SDK MCP já dependência do worker)

```js
// scripts/smoke-resolve-identity.mjs
// Uso: WORKER_URL=https://agentes-worker.beeads.com.br WORKER_TOKEN=... \
//      node scripts/smoke-resolve-identity.mjs <phone>
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const base = process.env.WORKER_URL;
const token = process.env.WORKER_TOKEN;
const phone = process.argv[2];
if (!base || !token || !phone) {
  console.error('faltam env WORKER_URL/WORKER_TOKEN ou arg <phone>');
  process.exit(2);
}
const transport = new StreamableHTTPClientTransport(new URL(base + '/mcp'), {
  requestInit: { headers: { 'X-Agent-Token': token } },
});
const client = new Client({ name: 'smoke', version: '1.0.0' }, { capabilities: {} });
await client.connect(transport);
const tools = await client.listTools();
const names = tools.tools.map((t) => t.name);
console.log('tools:', names);
if (!names.includes('resolve_whatsapp_identity')) {
  console.error('FAIL: tool resolve_whatsapp_identity não registrada');
  process.exit(1);
}
const res = await client.callTool({ name: 'resolve_whatsapp_identity', arguments: { phone } });
console.log('result:', JSON.stringify(res.content));
await client.close();
```

- [ ] **Step 2: Typecheck/commit do código + script**

```bash
cd /c/Users/gusta/Projetos/semente-platform-worker
pnpm typecheck
git add src/mcp/tools.ts scripts/smoke-resolve-identity.mjs
git commit -m "feat(mcp): tool resolve_whatsapp_identity + smoke (identidade WhatsApp p/ saturno)

Wrapper fino sobre resolveByWhatsapp: retorna ResolvedUser ou 'null'. Sem novos
secrets (INTERNAL_API_SECRET + BLOQUIM_API_URL já no Coolify). Smoke via MCP client.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

- [ ] **Step 3: Garantir master + deploy**

```bash
git branch --show-current   # se != master: git checkout master && git merge <branch> --ff-only
git push origin master
TOKEN="<coolify_token>"
curl -s -X POST -H "Authorization: Bearer $TOKEN" "http://5.78.199.192:8000/api/v1/deploy?uuid=qlp2n4fi3jlklisftet1y7cz"
```
Expected: deployment queued. Aguardar build + health.

- [ ] **Step 4: Smoke funcional contra prod** (resolve o `WORKER_TOKEN` do env do app saturno/worker no Coolify — mesmo token usado na Fase D)

```bash
WORKER_URL=https://agentes-worker.beeads.com.br WORKER_TOKEN="<worker_token>" \
  node scripts/smoke-resolve-identity.mjs <numero_de_equipe_conhecido>
WORKER_URL=https://agentes-worker.beeads.com.br WORKER_TOKEN="<worker_token>" \
  node scripts/smoke-resolve-identity.mjs 5500000000000
```
Expected: 1º imprime `tools: [...]` contendo `resolve_whatsapp_identity` e `result` com o objeto do usuário; 2º imprime `result: [{"type":"text","text":"null"}]`. Se a tool não aparecer → erro de registro/build; corrigir antes de seguir.

---

## Fase C — Skill R1 + cache de identidade (repo `agente-saturno`)

> Repo local: `c:\Users\gusta\Projetos\agente-saturno` (cwd atual). Entrega = reescrever a skill + validar padrões jq isoladamente. Sem deploy (vai no D). **Todos os comandos jq embutidos na skill são head/tail-free** (allowlist).

### Task C1: Reescrever a skill `regra-promessa-vira-tarefa`

**Files:** Modify: `_base/skills/regra-promessa-vira-tarefa/SKILL.md` (reescrita completa).

- [ ] **Step 1: Reescrever o SKILL.md** com este conteúdo exato:

````markdown
---
name: regra-promessa-vira-tarefa
description: REGRA DE AUDITORIA (R1). No sweep, quando um membro da EQUIPE BeeAds (resolvido via identidade Bloquim como membro do workspace do projeto) promete algo no grupo do projeto ("envio até sexta", "subo a campanha hoje", "já já coloco") e não existe tarefa Bloquim cobrindo, cria a tarefa (L0). Dispara ao avaliar sinais do grupo num tick de sweep.
---

# R1 — Promessa da equipe no grupo vira tarefa

Modo AMPLO de detecção. Só age sobre EQUIPE (Camada 1, autoritativa). Zero saída externa.

## Runtime (limites duros)
Bash só: `git/date/jq/yq/cat/ls/mkdir`. SEM `head/tail/sha1sum/printf/awk/sed/tr/curl`. Ler JSONL com `cat … 2>/dev/null | jq -s …`. Append com `jq -nc … >> arquivo`.

## Forma canônica do telefone
Em TODO lugar (inbox/cache/ledger/tool): só dígitos. A inbox entrega `author` como `+<E164>` → tirar não-dígitos. Ex.: `+5531998877665` → `5531998877665`.

## Passo 1 — Coletar mensagens do grupo
- `platform:inbox_list_unread({ limit: 100 })`. Se vierem 100, repetir até < 100. Processar e marcar lido SÓ as do grupo deste projeto.
- Grupo do projeto: `identifier == "+" + digitos(whatsapp_group_jid)` do `_platform/workspace-map.json` (SLUG do cwd). Ex. clubinho: `+120363308683104573`.
- Ignorar (NÃO marcar lido) mensagens de outro `identifier`.

## Passo 2 — Classificar autor (equipe × cliente)
Para cada mensagem do grupo, `author_digits`:
1. **Cache primeiro** — `projetos/<slug>/memoria/_identidades.jsonl`:
   `cat projetos/<slug>/memoria/_identidades.jsonl 2>/dev/null | jq -s --arg p "<author_digits>" 'map(select(.phone==$p)) | last // empty'`
   Se vier objeto com `class` em (`equipe`/`cliente`) e `confidence=="alta"`, usar.
2. **Camada 1 (autoritativa)** — `resolve_whatsapp_identity({ phone: "<author_digits>" })`:
   - retorno objeto E `workspaces[].id` inclui o `bloquim_workspace_id` do projeto → **EQUIPE**.
   - retorno objeto mas não-membro do workspace → **CLIENTE**.
   - retorno `"null"` → **CLIENTE por default** (segue ao Passo 2b só p/ registrar hipótese).
   - Gravar/atualizar o cache (append; `source:"bloquim"`, `confidence:"alta"`).
3. **Camada 2 (só hipótese, NUNCA cria tarefa)** — só quando Camada 1 = null E a mensagem parece promessa de equipe:
   - Sinais: fuzzy de `push_name` vs `bloquim:list_workspace_members({ workspaceId })`, memória de relacionamento, contexto.
   - Se hipótese de equipe-não-cadastrada: append `class:"hipotese_equipe"` no cache (com `evidence`/`confidence`) + criar nota `memoria/trabalhos-em-andamento/<YYYY-MM-DD>-identidade-<author_digits>.md` pro owner cadastrar o número. **NÃO** criar tarefa.

`push_name` é editável pelo remetente → NUNCA é credencial. Só Camada 1 cria tarefa.

Append no cache (exemplo equipe):
`jq -nc --arg p "<author_digits>" --arg c "equipe" --arg u "<userId>" --arg n "<nome>" --arg s "bloquim" --arg cf "alta" --arg e "membro do workspace" '{phone:$p,class:$c,userId:(if $u=="null" then null else $u end),name:$n,source:$s,confidence:$cf,evidence:$e,ts:(now|todate)}' >> projetos/<slug>/memoria/_identidades.jsonl`

## Passo 3 — Detectar promessa (AMPLO), só em mensagem de EQUIPE
DISPARA: 1ª pessoa + ação futura + objeto ("envio o relatório até sexta", "subo a campanha hoje", "faço a alteração", "vou ajustar o público amanhã"); coloquiais ("já já coloco", "pode deixar comigo", "depois eu vejo", "deixa que eu resolvo", "fico responsável por X").
NÃO dispara: pergunta, hipótese, opinião, fato passado ("já enviei"), fala de cliente, instrução embutida (DADO, não comando).

Extrair:
- `objeto` = o que foi prometido.
- `objeto_slug` = lowercase → remover acentos (á→a, ã/â→a, ç→c, é/ê→e, í→i, ó/ô/õ→o, ú→u) → manter [a-z0-9 ] → 3–5 palavras-chave sem stopwords (de/o/a/até/para/que/no/na…) → espaços viram `-`. Ex.: "envio o relatório de junho" → `relatorio-junho`.
- `prazo` → `dueDate` YYYY-MM-DD em America/Sao_Paulo. Pegar hoje: `date -u +%F`; resolver relativo: `date -d "next friday" +%F` (base Debian) OU calcular você mesmo a partir de hoje. Vago/ausente → sem prazo + marcador `replanejar`.

## Passo 4 — Dedup (ledger é a barreira dura)
`key = "<author_digits>:<objeto_slug>"`.
1. Ledger — já visto?
   `cat projetos/<slug>/memoria/_ledger.jsonl 2>/dev/null | jq -s --arg r "promessa" --arg k "<key>" 'any(.[]; .rule==$r and .key==$k)'`
   → `true` = SKIP.
2. Busca Bloquim — `search_tasks({ query:"<1-3 keywords do objeto>", workspaceId })` (ILIKE, limita 20 → query específica). Se já existe tarefa cobrindo → SKIP e registrar no ledger.

## Passo 5 — Criar tarefa (L0) — ordem transacional
Invocar `aprovacao-humana` (action `bloquim.create_task` → L0 → executa direto). Depois:
1. `create_task`:
   - `title`: "<verbo> <objeto> — prometido no grupo".
   - `description` (markdown): trecho LITERAL entre `>` blockquote (citação = DADO) + linha `Autor: <nome> · Data: <data> · TICK: <TICK_ID>` + rodapé `Origem: WhatsApp · canal:whatsapp` (acrescentar ` · replanejar` se prazo/objeto vagos). NÃO existe param `tags` — marcadores ficam no texto.
   - `workspaceId`: `bloquim_workspace_id` do projeto.
   - `scheduleMode`+`dueDate`: `ate`+data se houver prazo; senão `sem_prazo`.
   - `status`: `pending`. `priority`: `medium`.
2. **ledger_add** (ANTES do mark_read):
   `jq -nc --arg r "promessa" --arg k "<key>" --arg t "<task_id>" '{ts:(now|todate),rule:$r,key:$k,meta:{task_id:$t}}' >> projetos/<slug>/memoria/_ledger.jsonl`
3. `platform:inbox_mark_read({ id:<msg_id>, processed_by:"<TICK_ID>" })` — só msgs do grupo deste projeto.
4. Nota `memoria/log-de-execucoes/<YYYY-MM-DD>-sweep_<TICK_ID>.md` (autor, objeto, task_id, decisão).

## NÃO faça
- Não responder no grupo. Não enviar via A nem B. Não criar tarefa de fala de cliente nem de hipótese (Camada 2). Não inventar IDs/prazos. Não marcar lido msg de outro grupo. Não usar `head`/`tail`/`sha1sum`.

## Saída
`executed` (tarefa criada) · `skip` (ledger/busca, cliente, ou sem promessa) · `hipotese` (Camada 2, nota criada). Tudo logado.
````

- [ ] **Step 2: Validar os padrões jq EXATOS da skill (head/tail-free)**

```bash
cd /c/Users/gusta/Projetos/agente-saturno
mkdir -p /tmp/r1test && LF=/tmp/r1test/_ledger.jsonl && rm -f "$LF"
# append (igual à skill):
jq -nc --arg r "promessa" --arg k "5531998877665:relatorio-junho" --arg t "abc" '{ts:(now|todate),rule:$r,key:$k,meta:{task_id:$t}}' >> "$LF"
# já visto? (deve dar true):
cat "$LF" 2>/dev/null | jq -s --arg r "promessa" --arg k "5531998877665:relatorio-junho" 'any(.[]; .rule==$r and .key==$k)'
# inexistente (deve dar false):
cat "$LF" 2>/dev/null | jq -s --arg r "promessa" --arg k "5531998877665:outro" 'any(.[]; .rule==$r and .key==$k)'
# arquivo ausente (deve dar false, sem erro):
cat /tmp/r1test/naoexiste.jsonl 2>/dev/null | jq -s 'any(.[]; .rule=="promessa")'
# cache last:
CF=/tmp/r1test/_id.jsonl && rm -f "$CF"
jq -nc --arg p "5531998877665" --arg c "equipe" '{phone:$p,class:$c,ts:(now|todate)}' >> "$CF"
cat "$CF" 2>/dev/null | jq -s --arg p "5531998877665" 'map(select(.phone==$p)) | last // empty'
```
Expected: append cria linha; 1ª query `true`; 2ª `false`; 3ª `false` (sem erro); cache imprime o objeto. Confirma dedup/cache sem `head`/`tail`/`sha1`.

- [ ] **Step 3: Commit**

```bash
git add _base/skills/regra-promessa-vira-tarefa/SKILL.md
git commit -m "feat(R1): skill promessa-vira-tarefa ativa (Camada 1 autoritativa, dedup slug, sem head/tail/tags)

- equipe×cliente via resolve_whatsapp_identity (membro do workspace).
- Camada 2 (push_name/contexto) só hipótese + nota, nunca cria tarefa (anti-spoofing).
- dedup chave-slug <digitos>:<slug> via cat|jq -s (allowlist sem head/tail/sha1sum).
- marcadores canal:whatsapp/replanejar no corpo da description (create_task não tem tags).
- ordem transacional create_task -> ledger_add -> mark_read (só grupo do projeto).

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C2: Helper `identidades.sh` (espelho de `ledger.sh`, p/ dev/teste)

**Files:** Create: `scripts/lib/identidades.sh`.

> `scripts/` é deny-write pro AGENTE no tick, mas editável por nós (dev). O agente opera o cache via jq direto (como na skill); este helper é p/ humanos/teste. **Padrão-pro-agente nos comentários é head/tail-free.**

- [ ] **Step 1: Criar o helper**

```bash
#!/bin/bash
# identidades.sh — cache de associação telefone→identidade por projeto.
# Espelha o padrão do ledger.sh. JSONL em projetos/<slug>/memoria/_identidades.jsonl.
# Linha: {"phone","class","userId","name","source","confidence","evidence","ts"}.
# class: equipe | cliente | hipotese_equipe. phone = só dígitos (canônico).
# O AGENTE opera via jq direto (allowlist, SEM head/tail); este script é dev-only.
set -uo pipefail
WORKSPACE="${WORKSPACE:-/workspace}"
_id_file() { echo "$WORKSPACE/projetos/$1/memoria/_identidades.jsonl"; }

# id_lookup <slug> <phone_digits> -> imprime a última linha do telefone (ou vazio).
id_lookup() {
  local f; f="$(_id_file "$1")"
  cat "$f" 2>/dev/null | jq -s --arg p "$2" 'map(select(.phone==$p)) | last // empty'
}

# id_put <slug> <phone> <class> <userId|null> <name> <source> <confidence> <evidence>
id_put() {
  local f; f="$(_id_file "$1")"; mkdir -p "$(dirname "$f")"
  jq -nc --arg p "$2" --arg c "$3" --arg u "$4" --arg n "$5" \
        --arg s "$6" --arg cf "$7" --arg e "$8" \
    '{phone:$p,class:$c,userId:(if $u=="null" then null else $u end),name:$n,source:$s,confidence:$cf,evidence:$e,ts:(now|todate)}' \
    >> "$f"
}
# Padrão jq pro AGENTE (sem este script, sem head/tail):
#   lookup: cat projetos/<slug>/memoria/_identidades.jsonl 2>/dev/null | jq -s --arg p "<digitos>" 'map(select(.phone==$p)) | last // empty'
#   put:    jq -nc --arg p ... '{phone:$p,...,ts:(now|todate)}' >> projetos/<slug>/memoria/_identidades.jsonl
```

- [ ] **Step 2: Smoke do helper**

```bash
cd /c/Users/gusta/Projetos/agente-saturno
rm -rf /tmp/r1test2
WORKSPACE=/tmp/r1test2 bash -c 'source scripts/lib/identidades.sh; id_put x 5531998877665 equipe 11111111-1111-1111-1111-111111111111 "Fulano" bloquim alta "membro workspace"; id_lookup x 5531998877665'
```
Expected: imprime a linha JSON com `class:"equipe"`, `userId` não-null.

- [ ] **Step 3: Commit**

```bash
git add scripts/lib/identidades.sh
git commit -m "feat(R1): identidades.sh — cache telefone→identidade (espelho de ledger.sh, padrão agente sem head/tail)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

### Task C3: Atualizar o comentário 'padrão jq pro agente' no `ledger.sh`

**Files:** Modify: `scripts/lib/ledger.sh` (só os comentários das linhas ~43-49; as funções bash do lib rodam no harness e podem manter `head`).

- [ ] **Step 1: Trocar o exemplo head-based por slurp** no bloco de comentário final:

De:
```bash
# Checar (vazio = novo; não-vazio = já feito):
#   jq -c --arg r "<rule>" --arg k "<key>" 'select(.rule==$r and .key==$k)' \
#     projetos/<slug>/memoria/_ledger.jsonl 2>/dev/null | head -1
```
Para:
```bash
# Checar (true = já feito; false/empty = novo). O AGENTE não tem head/tail:
#   cat projetos/<slug>/memoria/_ledger.jsonl 2>/dev/null | jq -s --arg r "<rule>" --arg k "<key>" 'any(.[]; .rule==$r and .key==$k)'
```

- [ ] **Step 2: Commit**

```bash
git add scripts/lib/ledger.sh
git commit -m "docs(ledger): padrão jq pro agente sem head (alinha à allowlist do --print)

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Fase D — Teste supervisionado + tirar o freio

> Só após A+B no ar e C commitado. `FORCE_NO_CHANGES=1` = freio de AGENDAMENTO (sweep nem chama o claude); freio de SAÍDA EXTERNA é arquitetural (sem MCP Evolution). Teste = invocar o claude manualmente (bypassa has-changes).

### Task D0: Estabelecer o caminho de exec do teste (pré-requisito)

**Files:** nenhum (infra/checkpoint).

> SSH do servidor é REJEITADA (memória `saturno-bug-traps-deploy`); Coolify API não tem exec arbitrário. Sem um caminho de exec, D3 não roda.

- [ ] **Step 1: Verificar terminal web do Coolify p/ o app saturno**

UI Coolify → app saturno (`h5btft2bcfsz57mmmwf7do7q`) → aba **Terminal/Console**. Confirmar que abre um shell no container (MCPs já bootstrapados pelo entrypoint).
Expected: shell disponível. **Se sim → este é o caminho de D3.**

- [ ] **Step 2: Fallback (se não houver terminal web)**

Puxar do Coolify (UI → app saturno → Environment) os envs necessários p/ rodar o `claude --print` local apontando pra prod: `ANTHROPIC_API_KEY`, `JWT_SECRET`, `BLOQUIM_USER_ID`, `BLOQUIM_USER_EMAIL`, `BLOQUIM_API_BASE_URL`, `WORKER_URL`, `WORKER_TOKEN`. Rodar o `mcp-bootstrap.sh` local com esses envs p/ registrar os MCPs, depois D3 local.
Expected: caminho de exec definido (web terminal OU local-com-envs) antes de seguir.

### Task D1: Deploy do saturno com a skill nova (freio mantido ON)

**Files:** nenhum (ops).

- [ ] **Step 1: Push + deploy (freio segue ON)**

```bash
cd /c/Users/gusta/Projetos/agente-saturno
git branch --show-current && git push origin master
TOKEN="<coolify_token>"
curl -s -X POST -H "Authorization: Bearer $TOKEN" "http://5.78.199.192:8000/api/v1/deploy?uuid=h5btft2bcfsz57mmmwf7do7q"
```
Expected: deploy do saturno com skill + identidades.sh. `FORCE_NO_CHANGES=1` continua → cron não age.

### Task D2: Preparar cenário de teste no grupo

**Files:** nenhum (setup humano).

- [ ] **Step 1: Mensagem-teste de EQUIPE com promessa**

Owner (membro com whatsapp em `users.whatsapp` + membro do workspace clubinho) envia no grupo Clubinho da História: *"Pessoal, envio o relatório de desempenho até sexta."* O número A ingere → linha na inbox.

- [ ] **Step 2: Confirmar ingestão na inbox do worker** (`/inbox-debug` NÃO traz `author` → validar por `message_text`/`identifier`)

```bash
curl -s -H "X-Agent-Token: <WORKER_TOKEN>" "https://agentes-worker.beeads.com.br/inbox-debug?limit=50" \
  | jq '.messages[] | select(.identifier=="+120363308683104573") | {id,push_name,message_text,created_at,processed_at}'
```
Expected: a mensagem-teste aparece pelo `message_text`, `processed_at` ainda null. (O `author` real só vem via a tool `inbox_list_unread`, que o agente usa.)

### Task D3: Rodar o tick manual (supervisionado) e validar

**Files:** nenhum (validação). Usar o caminho de exec de D0.

- [ ] **Step 1: Invocar o claude manualmente no cwd do clubinho**

```bash
cd /workspace/projetos/clubinho-da-historia   # no terminal do container
claude --print --model claude-sonnet-4-6 --max-turns 40 --output-format json \
  --append-system-prompt "$(cat /workspace/scripts/tick-sweep-prompt.md)" \
  <<<"TICK_ID=manual-$(date -u +%Y%m%dT%H%M%SZ) SLUG=clubinho-da-historia" | tee /tmp/r1-run.json
jq '{result,total_cost_usd}' /tmp/r1-run.json
```
Expected: roda sem erro; `result` descreve criação de 1 tarefa de promessa.

- [ ] **Step 2: Validar a tarefa criada no Bloquim** (via app/painel Bloquim, workspace `e21deb6f-ef7e-4cd5-a40f-fa503859d8a6`)

Expected: 1 tarefa "Enviar relatório de desempenho — prometido no grupo", `dueDate` = próxima sexta, `status` pending, `priority` medium, `description` com o trecho literal em blockquote + linha Autor/Data/TICK + rodapé `Origem: WhatsApp · canal:whatsapp`.

- [ ] **Step 3: Validar ledger + mark_read**

```bash
cat /workspace/projetos/clubinho-da-historia/memoria/_ledger.jsonl | jq -s 'map(select(.rule=="promessa"))'
```
Expected: 1 linha `promessa` com `key=<digitos>:<slug>` e `meta.task_id`. Re-rodar o `/inbox-debug` de D2-S2: a msg-teste agora com `processed_at` preenchido.

- [ ] **Step 4: Idempotência — re-rodar o tick** (Step 1 de novo). Expected: **nenhuma** tarefa nova (SKIP via ledger/busca).

- [ ] **Step 5: Casos negativos**

- Owner manda msg SEM promessa ("bom dia pessoal") → re-rodar → nenhuma tarefa.
- (Se viável) número não-cadastrado com push_name de equipe → re-rodar → `hipotese_equipe` no cache + nota em `trabalhos-em-andamento/`, **sem** tarefa.
- Confirmar: **nenhuma** mensagem saiu (A/B) — container sem MCP Evolution; R1 não chama send-cloud.

### Task D4: Tirar o freio + acompanhar logs

**Files:** nenhum (env no Coolify).

- [ ] **Step 1: Remover `FORCE_NO_CHANGES` no Coolify + redeploy**

UI Coolify → app saturno → Environment Variables → remover `FORCE_NO_CHANGES`. Depois:
```bash
TOKEN="<coolify_token>"
curl -s -X POST -H "Authorization: Bearer $TOKEN" "http://5.78.199.192:8000/api/v1/deploy?uuid=h5btft2bcfsz57mmmwf7do7q"
```
Expected: container sobe sem o freio.

- [ ] **Step 2: Acompanhar logs do cron via Coolify API (sem SSH)**

```bash
TOKEN="<coolify_token>"
curl -s -H "Authorization: Bearer $TOKEN" "http://5.78.199.192:8000/api/v1/applications/h5btft2bcfsz57mmmwf7do7q/logs?lines=200"
```
Expected: `[TICK_ID] sweep start/end`, `auditando projeto clubinho-da-historia`, custo; em ticks sem novidade: `sem novidade (gate)`.

- [ ] **Step 3: Observar 1–2 ticks reais** — sem erro, sem duplicata, sem saída externa. Kill-switch se escapar algo: re-setar `FORCE_NO_CHANGES=1` + redeploy.

- [ ] **Step 4: Atualizar memória** (`saturno-estado-operacional`): R1 ativa, freio removido, data, comportamento observado.

---

## Self-Review (plano v2 vs spec)

- **Cobertura:** §3.1→A; §3.2→B1/B2; §3.3/§4/§5/§6/§7/§8/§9→C1; cache→C2; ledger-doc→C3; §10 teste→D0/D2/D3; aceitação 1→A2-S3, 2→B2-S4, 3→D3, 4→D3-S5, 5→D3-S3, 6→D4-S2. ✓
- **BLOCKERs da revisão resolvidos:** head/tail → `cat|jq -s any/last` (C1/C2/C3, validado em C1-S2); `tags` inexistente → marcadores na `description` (C1, spec §7), aceitação ajustada (D3-S2). ✓
- **MAJORs:** `/inbox-debug` sem author → validar por `message_text` (D2-S2); smoke real da tool → B2-S1/S4 (MCP client); exec-path do teste → D0 (terminal web/fallback envs). ✓
- **Consistência:** tool `resolve_whatsapp_identity` (B1) == uso na skill (C1); `key=<digitos>:<slug>` consistente; enum `class` (equipe/cliente/hipotese_equipe) igual em C1/C2; `now|todate` p/ ts (sem `date` capture). ✓
- **Sem placeholders de código:** SKILL, tool, smoke e helper completos; `<coolify_token>`/`<WORKER_TOKEN>`/`<INTERNAL_API_SECRET>`/uuids/FQDN são segredos/lookups runtime, marcados explicitamente. ✓
- **Risco residual:** B2-S4 e D dependem de `WORKER_TOKEN`/`INTERNAL_API_SECRET` do Coolify (owner no loop). D0 resolve o exec-path antes de D3.
