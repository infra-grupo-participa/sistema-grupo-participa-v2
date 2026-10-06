# Migração da Clint para o CRM Comercial (F6)

> Versão de 06/10/2026. **Nada foi carregado em produção.** Peças: extração `infra/scripts/clint_extrair.py` (só GET na
> Clint) → staging `arquivo.clint_*` → carga `crm.clint_carregar(...)` (ensaio por padrão). Migration
> `infra/supabase/migrations/20261006d_crm_f6_migracao_clint.sql` (**NÃO APLICADA**), ensaio `20261006d_ensaio.sql`
> (44/44 OK, nada persistiu), medidas e decisões em `20261006d.explain.md`. Regras de base:
> `docs/manual-banco-de-dados.md` (§7 casar por e-mail; §10 alias, não apagar; §3 backups/staging em `arquivo`).
> Arquitetura: `backend-arquitetura.md` §5.8 e §6 (F6). Diferença em relação ao desenho original: o staging fica em
> `arquivo.clint_*` (e não em `crm.clint_import`), e a pessoa é `pessoas.pessoas` (convergência da F0), não `crm.pessoa`.

---

## 1. Volume

**Não medido.** O token da Clint não está no Vault (`vault.secrets` não tem nenhum segredo com "clint") e, como
combinado, não foi pedido nem procurado. Para medir sem gravar nada:

```bash
CLINT_TOKEN=... python3 infra/scripts/clint_extrair.py --contar   # 1 GET por recurso (limit=1), imprime só totalCount
```

Com os números em mãos, ajustar `--rps` e `--historico` (o histórico custa ≥ 1 requisição por negócio).

## 2. O que a API da Clint entrega (documentação pública, `https://clint-api.readme.io`)

| Recurso | Endpoint (GET) | Paginação | Observação |
|---|---|---|---|
| Grupos | `/v1/groups` | `page`/`limit` ≤ 1000, `totalCount`/`hasNext` | "agrupador" (pasta de origens) |
| Origens | `/v1/origins` | idem | = **funil**. Traz `stages[]` (`id`, `label`, `order`, `type`) e `group` |
| Usuários | `/v1/users` | idem | `id`, `email`, `first_name`, `last_name` |
| Motivos de perda | `/v1/lost-status` | idem | `id`, `name` |
| Tags | `/v1/tags` | idem | `id`, `name`, `color` |
| Campos da conta | `/v1/account/fields` | sem paginação | campos personalizados por entidade (`DEAL`, `CONTACT`, `ORGANIZATION`) |
| Contatos | `/v1/contacts` | idem | `name`, `email`, `fullPhone` (+55…), `organization`, `instagram`, `tags[]`, `fields{}`. Sem filtro por atualização |
| Negócios | `/v1/deals` | idem | **padrão `status=OPEN`**: o script varre OPEN, WON e LOST. `origin_id`, `stage_id`, `user{id,full_name}`, `contact{id,name,email,phone}`, `won_at`, `lost_status_id`, `lost_at`, `updated_stage_at`, `fields{}`. Filtro `updated_at_start` (incremental) |
| Histórico | `/v2/deals/{id}/history` | `page`/`limit` ≤ 200 (`has_next`) | linha do tempo: etapa/status/dono, **notas**, tags, e-mails/ligações, atividades concluídas. Cada item: `id`, `category`, `date`, `user`, `body`, `summary` (pt-BR) |
| Atividades | `/v2/activities` | ≤ 200 | exige feature `ACTIVITIES_API` + escopo `activities:read` (o script segue sem elas se der 403). Sem responsável: o dono vem do negócio |
| Conversas | `/v2/chats*`, `/v2/messages*` | — | **fora** (F4/D9) |

Autenticação: header `api-token`. Limite publicado só para SMS/voz (10 mil/min); para leitura não há número →
o script usa 2 req/s por padrão, respeita `Retry-After` e recua em 429/5xx.

## 3. Mapeamento Clint → pessoas/crm

### 3.1 Contato → `pessoas.pessoas` (+ `crm.pessoa_comercial`)

Entrada única: `pessoas.registrar(p, 'importacao', null)` — a mesma cascata da F0, sem regra nova:

| Ordem | Regra | Resultado |
|---|---|---|
| 1 | **E-mail** normalizado (`lower(btrim)`), procurado em `pessoas.identificadores`, `thb_alunos` e `compradores` pelo índice de cada um | casa (aluno/comprador por **referência**, sem cópia) |
| 2 | Sem e-mail: **telefone** pela chave `controle.fone_key` (DDD + 8 últimos; `+55` e 0 tirados por `pessoas.norm_telefone`) | casa só se houver **1** candidato e nome compatível (mesmo primeiro nome); senão pessoa nova + revisão |
| 3 | E-mail novo com telefone de outra pessoa | pessoa nova + `pessoas.revisao` (`telefone_email_diferente`): telefone **nunca** funde sozinho |
| 4 | Só nome (ou nome+CEP) | nunca casa; no máximo revisão (`so_nome`/`nome_cep`) |
| — | Sem e-mail e sem telefone válido | **fica de fora** (`sem_identificador`); o negócio dele vira `ignorado` |

- Dois contatos da Clint com o mesmo e-mail (dedupe da própria Clint) caem na **mesma pessoa** (provado no ensaio:
  `ensaio.f6.c1@…` e `"  ENSAIO.F6.C1@… "`).
- Duplicata antiga da base vira **revisão** (alias reversível em `pessoas.mesclar`), nunca merge destrutivo.
- Contato sem negócio: **não** entra por padrão (`so_contatos_com_negocio=true`) — decisão D-F6-2.
- `tags[].name` → `crm.pessoa_comercial.tags` (união, máximo 30). Campo de contato com destino `tag` idem.
- UTMs de campo de contato confirmados como `utm_*` → `pessoas.origens` (fonte `importacao`).
- CPF/documento: nunca. Campo com rótulo de CPF/CNPJ/RG/documento/senha sai sugerido como `ignorar`.

### 3.2 Origem (funil) e etapas → `crm.funil` / `crm.etapa_funil` (papel `EtapaKey`)

- Cada origem confirmada vira **um funil novo** `Clint · <nome da origem>` (tipo `manual`), na **linha** escolhida pelo
  gestor (`arquivo.clint_mapa_funil.linha`) e no agrupador da linha (ou um agrupador explícito). Funis já existentes do
  CRM não são tocados.
- Cada stage vira uma etapa com o **papel** de `arquivo.clint_mapa_etapa.papel`
  (`primeiro_contato | qualificar | apresentar_oferta | negociar | aguardar_pagamento | fechado`), na mesma ordem, sem
  SLA e sem campo obrigatório (legado não trava). Se nenhum stage for `fechado`, a carga cria a etapa **Fechado**.
- Sugestão automática de papel pelo nome (`crm._clint_papel_sugerido`): "ganho/vendido/matrícula" → fechado;
  "pagamento/boleto/pix/link enviado" → aguardar_pagamento; "negociação/follow" → negociar; "proposta/oferta/reunião/
  call/sessão" → apresentar_oferta; "qualificação/conexão/conversa/diagnóstico" → qualificar; "novo/entrada/lead/base/
  tentativa" ou 1º stage → primeiro_contato. **Só vale depois de `confirmado = true`.**
- Linha sugerida pelo nome do grupo/origem (`aurum`, `hm`, `acelera`, `ethb`, `sv`, `ht`); nada é criado sem confirmação.
- Origem com `importar = false`: negócios dela ficam `ignorado`.

### 3.3 Negócio → `crm.negocio`

| Clint | CRM | Regra |
|---|---|---|
| `status = OPEN` | `status = 'aberto'`, etapa do mapa | 1 aberto por pessoa+funil: o 2º vira **`duplicado`** (não cria; nota/histórico vão para o existente) |
| `status = LOST` | `status = 'perdido'`, `motivo_perda` do mapa, `fechado_em = lost_at`, `nota_perda = "Perdido na Clint: <motivo>"` | motivo não confirmado → **`pendente_motivo`** (não cria) |
| `status = WON` | `status = 'ganho'` **só** se houver exatamente **1** transação Hotmart APPROVED/COMPLETE do e-mail da pessoa, de produto vinculado à **mesma linha** (`crm.produto_comercial`), entre `won_at − 30 d` e `won_at + 7 d`, ainda não usada | sem transação: **`ganho_sem_transacao`** — não vira negócio; vira 1 `pessoas.eventos` (tipo `crm`, fonte `importacao`) na jornada. Respeita "ganho só por pagamento" (o gatilho da F2 continua barrando ganho fora disso — provado) |
| `user` | `dono_id` | e-mail do usuário Clint = `perfis.email` (`lower(btrim)`) **e** vendedor ativo em `crm.vendedor`; senão sem dono (nota registra o dono antigo). Aberto com dono também define o dono do contato comercial se estava vazio |
| `fields{}` | `campos` | destino `campo:<chave>` confirmado e valor aceito por `crm.campo_def` (opções normalizadas sem acento) → `campos`; `utm_*` → `negocio.utm`; o resto → **nota de importação** (nada se perde) |
| `created_at`, `updated_stage_at` | `criado_em`, `etapa_desde` | |
| — | `origem = 'venda_ativa'`, `valor` = valor cobrado da transação no ganho (0 nos demais) | |

Cada negócio criado ganha 1 nota "Importado da Clint (negócio <id>). Funil … Etapa na Clint … Dono na Clint … Status …
Campos da Clint: …".

### 3.4 Histórico, notas e atividades

- Item de histórico com categoria de **nota** → `crm.nota` (autor = perfil do usuário Clint, se houver; data original).
- Demais itens (mudança de etapa/status/dono, tag, e-mail, ligação, atividade concluída) → **1 nota "Histórico na
  Clint"** por negócio com a linha do tempo resumida (`summary` pt-BR da própria API), cortada em 5.000 caracteres.
  O `crm.log` **não** recebe histórico retroativo (é append-only e alimenta métricas de etapa): decisão D-F6-4.
- Atividade **aberta** de negócio **aberto** → `crm.atividade` (tipo: CALL→ligacao, MAIL→email, WHATSAPP→whatsapp,
  MEETING/SCHEDULE→reuniao, resto→tarefa; dono = dono do negócio; sem dono → `pendente_dono`). Concluída → fica no
  histórico. Atividade de negócio encerrado → ignorada.

### 3.5 O que fica de fora

Conversas e mensagens de WhatsApp (F4, depende de D9 — dono da WABA), anexos de contato, organizações, dashboards da
Clint, transcrições, contatos sem negócio (padrão), contatos sem e-mail e sem telefone, CPF/documentos, histórico como
`crm.log`, `cs.contatos` (D4: coexistir; fila ACELERA fica para decisão do Marcio).

## 4. Dedupe e idempotência

- Staging: PK `(tipo, clint_id)` + md5 do payload. Reextrair o mesmo dado = 0 novos, 0 alterados (provado).
- Histórico: `clint_id = <negócio>:<item>` (o mesmo item pode aparecer no histórico de dois negócios do contato).
- Carga: `arquivo.clint_resultado (tipo, clint_id)` guarda o que foi feito (pessoa, negócio, nota, atividade).
  Status finais (`ok`, `duplicado`, `sem_identificador`, `ignorado`) não reprocessam; `pendente_*`, `erro` e
  `ganho_sem_transacao` tentam de novo a cada chamada (o evento de ganho sem transação é gravado 1 vez só).
  Reprocessar = 0 novos (provado).
- Mudança na Clint depois da carga **não é aplicada**: aparece em `crm.clint_relatorio() -> alterados_depois_da_carga`
  (decisão D-F6-5).

## 5. Como rodar (quando a 20261006d estiver aplicada)

1. Medir: `python3 infra/scripts/clint_extrair.py --contar`.
2. Extrair para o staging: `python3 infra/scripts/clint_extrair.py` (lote `clint-AAAAMMDDTHHMMSS`; fecha `completo` só
   se cada recurso trouxe o `totalCount` anunciado).
3. No banco, como postgres: `select crm.clint_preparar_mapas();` → revisar e confirmar
   `arquivo.clint_mapa_funil` (linha, importar), `clint_mapa_etapa` (papel), `clint_mapa_motivo`, `clint_mapa_campo`,
   `clint_mapa_usuario` (perfil à mão se o e-mail da Clint for outro; `confirmado = true` trava).
4. Ensaio: `select crm.clint_carregar('<lote>');` (padrão `p_ensaio = true`: faz tudo, devolve o relatório e desfaz).
5. Real: `update crm.config set clint_import_ligado = true;` e
   `select crm.clint_carregar('<lote>', false, 300);` em laço até `foto.pendentes` parar de cair; conferir
   `crm.clint_relatorio()` e `arquivo.clint_carga`. Depois `clint_import_ligado = false`.
6. Prova (backend-arquitetura §5.8): contagem por funil/etapa/dono Clint × CRM; 30 negócios conferidos à mão.

## 6. Reversão e LGPD

- Kill-switch: `crm.config.clint_import_ligado` (carga real recusa com ele desligado; ensaio não grava nada).
- Tudo o que a carga criou está listado em `arquivo.clint_resultado` (ids) e em `crm.log` (`canal = 'clint_import'`,
  `autor_tipo = 'integracao'`): arquivar os funis "Clint · …" / marcar perdidos, nunca apagar.
- `arquivo.clint_*` tem dado pessoal (payload bruto): schema fechado, sem grant para `anon`/`authenticated`/
  `service_role` (o script só escreve pelas 2 RPCs). Sugestão: expurgar `arquivo.clint_objeto` 180 dias após o corte
  (decisão D-F6-6).
