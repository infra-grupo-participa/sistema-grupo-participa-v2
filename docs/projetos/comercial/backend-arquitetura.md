# CRM Comercial: arquitetura do backend

> Versão de 05/10/2026. **Nada aqui foi aplicado.** É o desenho para trocar `MockComercialRepository` por um
> `SupabaseComercialRepository` sem mudar tela. Regras seguidas: `docs/manual-banco-de-dados.md` (ritual, 5 perguntas,
> índice com a MESMA expressão, revoke de PUBLIC/anon, RLS provada com `set local role`, migration versionada com
> `_ensaio.sql` + `.explain.md`, kill-switch, casar pessoa por e-mail, não apagar).
> Contrato: `web/modules/comercial/application/ports.ts` + `domain/types.ts`. Regras: `domain/*.ts`. Comportamento
> esperado: `infrastructure/mock-comercial.repository.ts`.

---

## 0. Resumo em 12 linhas

1. **Schema próprio `crm`, NÃO exposto no PostgREST.** O front fala só com RPCs `public.crm_*` (mesmo padrão de
   `pa_*` e `ra_*`). Não mexe em `pgrst.db_schemas` (o painel sobrescreve a lista inteira).
2. **Leitura** das tabelas `crm.*`: RPC `SECURITY INVOKER` + RLS (o filtro de visibilidade mora na policy).
   **Leitura que cruza `fin`/`controle`/`respondi`** (jornada, ofertas): `SECURITY DEFINER` com a MESMA guarda da policy.
3. **Toda escrita** por RPC `SECURITY DEFINER` com guarda `coalesce(..., false)`. Tabelas `crm.*` sem policy de escrita.
4. **Pessoa única = `crm.pessoa`** com chave `email_norm` + `fone_key` (de `controle.fone_key`) e tabela de apelidos
   `crm.pessoa_chave`. Ligação com `fin.identidade` **por chave, nunca por FK** (ela é recalculada toda hora).
5. **Duplicata vira alias** (`canonica_id`), nunca merge destrutivo. CPF não entra no CRM.
6. **Log append-only `crm.log` gravado por TRIGGER** em toda tabela de negócio; UPDATE/DELETE/TRUNCATE barrados por trigger.
7. **Ganho só por pagamento**: só a função que processa evento Hotmart muda `status` para `ganho` (trigger barra o resto).
8. **Produto e oferta nascem na Hotmart.** CRM acrescenta a camada comercial sobre `fin.produtos`/`fin.ofertas` (FK).
9. **`cs.contatos` coexiste** (é o mini-CRM do CS, 1 linha por comprador). O CRM lê dele na jornada; migração só da
   parte comercial (fila Acelera) e só com decisão do Marcio.
10. **Hotmart entra por trigger** em `cs.hotmart_eventos` com dedup pelo id do evento Hotmart (37,9% das linhas são reenvio).
11. **Kill-switch por integração** em `crm.config` (desliga em ~10 s, sem deploy).
12. Fases F0→F7 pequenas e reversíveis; o mock fica vivo atrás de flag para demonstração.

---

## 1. Estado vivo medido (05/10/2026, só SELECT/contagem)

| Fonte | Medida | Leitura para o CRM |
|---|---|---|
| `public.thb_alunos` | 1.896 linhas; 1.272 sem `comprador_id`; 21 sem e-mail | Hub de aluno. Índice de e-mail: `lower(TRIM(BOTH FROM email))` (unique parcial) |
| `public.compradores` | 26.851 linhas; **24.543 (91,4%) sem nenhuma transação** Hotmart pelo e-mail; 310 sem telefone | Na prática é base de leads. Os 24.056 e-mails de `controle.lead_active` estão **todos** em `compradores` |
| `fin.identidade` | 68.204 nós (`e:` 24.002, `u:` 23.634, `d:` 20.568) → 23.177 pessoas | Grafo e-mail/ucode/CPF. Recalculado **de hora em hora** (`fin-identidade-recalcular`, `20 * * * *`): `pessoa_chave` não é estável → sem FK |
| `fin.produtos` / `fin.ofertas` | 97 produtos (57 com `sincroniza`, 91 conta `academy`) / 1.143 ofertas | Catálogo sincronizado (`fin-hotmart-catalogo`, diário 03:31) |
| `fin.hotmart_transacoes` | 57.872 transações, contas `academy` e `escritorio` | **12.194 transações com oferta fora do catálogo, 229 códigos órfãos — mas só 4 nos últimos 90 dias** (é passivo histórico, não sangria atual) |
| `cs.hotmart_eventos` | 2.623 linhas desde 15/07; **1.630 ids Hotmart distintos** → 993 reenvios (37,9%). Payload sempre tem `id` | Dedup pelo `payload->>'id'`. Eventos com sufixo `:PRODUTO_NAO_MAPEADO` existem |
| Volume Hotmart (30 d, únicos) | APPROVED 9/dia, OUT_OF_SHOPPING_CART 5/dia, CANCELED 4,4/dia, COMPLETE 3,3/dia, BILLET_PRINTED 1,9/dia, REFUNDED 0,9/dia | ~25 eventos comerciais/dia: trigger síncrono cabe com folga |
| `cs.contatos` | 26.209 (1:1 com comprador, unique); 2.484 com responsável; 3 opt-out; eventos CNHF 22.962, ACELERA 1.944, HT 930, SEM 373 | Mini-CRM do CS: 1 estágio por pessoa, não multi-negócio |
| `cs.estagios` | 54 (43 ativos) em 5 eventos | Etapas próprias do CS |
| `cs.usuarios` | 22 (8 sem perfil em `public.perfis`); 2 com `carteira_comercial`; tem `senha_hash` | Cadastro paralelo de equipe. CRM **não** usa; vendedor nasce de `public.perfis` |
| `public.perfis` | 43: admin 18, dev 4, operador 1, visualizador 20; **nenhum com área `comercial`**; `cargo` aceita `gestor` (0 hoje) | Papel comercial precisa ser cadastrado |
| `controle.lead_active` (ActiveCampaign) | 24.056 linhas, **1 único `evento_id`** (lista fixa), última entrada 05/10 | Confirma "lista 541 fixa". Índice `lower(btrim(email))` |
| `controle.grupo_evento` (SendFlow) | 37.100 eventos, último 05/10 23:59; índice `controle.fone_key(numero)` parcial (entrada/saída) | Grupo → jornada por telefone |
| `controle.grupo_evento_unificado` | 37.383, índice `fone_key` | Melhor fonte de grupo para a jornada |
| `respondi.respostas` | 22.103, última 04/10; `email` já normalizado (0 fora do padrão), índice em `email` cru | Pesquisa/MQL → jornada |
| `controle.unnichat_evento` | 7.728, **último 08/09** | Unnichat parado há ~4 semanas |
| `cs.lead_mensagens` | 29, último 10/06 | Inbox antigo, irrelevante |
| `controle.mensageria_envio` (Infobip etc.) | 226 linhas agregadas (api, email, ligação, sms), último 28/08 | Só totais, nenhum nível mensagem |
| Clint | 0 tabelas/colunas com "clint" | Nada no banco |
| Schema `crm` | não existe | Livre |
| `pgrst.db_schemas` | `public,graphql_public,sip,gps,ht,controle,workbook,central,rede,metodo` | `cs` e `fin` já não são expostos: CRM segue o mesmo caminho |
| Edge Functions relevantes | `hotmart-events-webhook`, `hotmart-sync`, `ingest-active` (15 min), `ingest-sendflow` (30 min), `sendflow-webhook`, `respondi-sync` (diário), `respondi-hm-webhook`, `report-slack`, `enviar-notificacao`, `ingest-mensageria` | Reaproveitar; nenhuma do CRM ainda |
| Alunos sem transação pelo e-mail | 341 de 1.875 com e-mail; **33 casam só por CPF**; 53 fora de `fin.identidade` | Ver decisão D1 (o "276" do levantamento anterior não reproduziu; o medido hoje é este) |

Autorização existente (lida viva): `gp_is_admin()` (cargo dev/admin, lida por ~50 tabelas: **não mexer**),
`gp_eh_equipe()` (domínio `@advmais.com`), `gp_pode_editar(setor)` (admin/dev, gestor com área, operador com área +
função `setor.*`), `tem_permissao(uid, perm)`, `is_ht_operator()`. Todas `SECURITY DEFINER`.

---

## 2. Decisões de arquitetura

### 2.1 Schema `crm` (não `public`)

| Opção | Prós | Contras | Decisão |
|---|---|---|---|
| `public.crm_*` tabelas | já exposto | mistura com 83 tabelas; RLS errada vaza pela API direta | não |
| **`crm` não exposto + RPCs `public.crm_*`** | API direta não alcança tabela; mesmo padrão de `cs`/`fin`; grants simples | toda leitura é RPC (aceito: é o que o manual pede para evitar `select('*')` + join em JS) | **sim** |
| `crm` exposto | `.schema('crm').from(...)` no front | mexer em `pgrst.db_schemas` (painel sobrescreve a lista); policy vira a única barreira | não |

Mesmo sem exposição, **RLS ligada em toda tabela `crm.*`** (defesa em profundidade e base das RPCs invoker).

### 2.2 O que reaproveita × o que é novo

| Reaproveita (só lê, nunca escreve) | Para quê |
|---|---|
| `fin.produtos`, `fin.ofertas` | catálogo Hotmart (FK da camada comercial) |
| `fin.hotmart_transacoes` | compra, reembolso, `origem_sck` (crédito do vendedor), jornada |
| `fin.identidade` | e-mails irmãos da mesma pessoa (por chave `'e:'||email`) |
| `cs.hotmart_eventos` | gatilho de negócio automático e de ganho |
| `public.thb_alunos`, `public.compradores` | `eh_aluno`, endereço/nome; FK `on delete set null` |
| `controle.lead_active`, `controle.grupo_evento_unificado`, `respondi.respostas`, `cs.contatos` | jornada |
| `public.perfis` | equipe, papel |
| `ops.cron_post`, `ops.rotina` | todo cron HTTP novo |

| Novo (schema `crm`) | |
|---|---|
| pessoa, pessoa_chave, pessoa_sugestao | identidade comercial |
| vendedor, config, distribuicao | equipe e regras |
| linha, produto_comercial, oferta_comercial | camada comercial sobre Hotmart |
| agrupador, funil, etapa_funil, campanha, campo_def, motivo_perda | construtor de funis |
| negocio, atividade, nota | operação |
| numero_whatsapp, template, mensagem, conversa, supressao | conversa |
| fila, fila_item, ficha_disparo, ficha_destinatario, link_rastreavel | recuperação e disparo |
| dashboard, painel, preferencias_notificacao, notificacao | relatórios e avisos |
| log | registro append-only |
| hotmart_processado, integracao_evento, clint_import, mcp_token | integrações |

### 2.3 Pessoa única

- **Chave primária de casamento: e-mail normalizado** `lower(btrim(email))`. Coluna gerada `email_norm`.
  No Postgres, `trim(both from x)` é o mesmo nó que `btrim(x)` (só muda a exibição): o que importa é a **ordem**
  `lower(btrim(...))`, que é a de `compradores`, `controle.*` e (exibida como `lower(TRIM(BOTH FROM email))`)
  `thb_alunos`/`hotmart_transacoes`. **`central.alunos` usa a ordem inversa: não consultar por ela.** Ao buscar nas
  fontes, normalizar o valor numa variável e comparar com a expressão exata do índice de cada tabela (prova no
  `.explain.md` da F0).
- **Chave auxiliar: telefone** via `controle.fone_key(telefone)` (DDD + 8 últimos dígitos; é a função que grava os
  índices de `thb_alunos` e `grupo_evento`). **Divergência com o front:** `chaveTelefone()` em `domain/regras.ts` usa
  só os 8 últimos dígitos. O banco manda: alinhar o front para `fone_key` (decisão D2).
- **Telefone nunca funde sozinho** pessoas com e-mail diferente (sócios e secretárias dividem número): vira
  `crm.pessoa_sugestao` para o gestor decidir. Telefone só casa automático quando a entrada **não tem e-mail**
  e há exatamente 1 pessoa com aquele `fone_key`.
- **Alias, não merge**: duplicata ganha `canonica_id` e `arquivada_em`; negócios e atividades seguem apontando para
  ela, as leituras resolvem a canônica. Desfazer = limpar `canonica_id`.
- **Ligação com `fin.identidade`**: sem FK. A RPC de jornada busca `pessoa_chave` por `'e:'||email_norm` e expande
  para os e-mails irmãos no momento da leitura.
- **CPF não entra no CRM** (casar por e-mail, LGPD). Fica em `fin`/`thb_alunos`.

### 2.4 `cs.contatos` (mini-CRM do CS): coexistir, depois migrar só o comercial

| | Migrar tudo | **Coexistir (recomendado)** | Unificar (CRM vira fonte do CS) |
|---|---|---|---|
| Esforço | alto (26 mil + 54 estágios) | baixo | altíssimo (tela do CS muda) |
| Risco | quebra a operação de ativação | nenhum | alto |
| Modelo | 1 estágio por comprador ≠ N negócios por pessoa | cada um no seu | força modelo errado |

Recomendação: **coexistir**. CS segue com ativação/pós-compra em `cs.*`; o CRM **lê** `cs.contatos` na jornada
(ponto "CS: estágio X, responsável Y"). Migração **só da parte comercial** em F6: ACELERA (1.944, com `score_lead`)
vira `crm.fila`/`crm.fila_item`; `cs.usuarios.carteira_comercial` (2) vira vendedor se tiver perfil. CNHF (22.962) é
lista de leads, não carteira: não migra como negócio. **Decisão do Marcio (D4).**

### 2.5 Produto, linha e oferta

O tipo `ProdutoKey` do front é fixo (`ht|hm|aurum|sv|acelera|ethb`). No banco vira **tabela** `crm.linha` (a "família
comercial", com escada e ticket de referência) para produto novo não exigir migration. Cada produto Hotmart
(`fin.produtos.produto_id`) vincula-se a no máximo uma linha via `crm.produto_comercial`. Cada oferta
(`fin.ofertas.oferta_codigo`) ganha a camada comercial em `crm.oferta_comercial` (vigente, condição, validade, uso).
**Controle de oferta por produto** = `fin.ofertas.produto_id` (já existe) + `oferta_comercial.vigente` + órfãs
calculadas de `fin.hotmart_transacoes`. Front: `ProdutoKey` passa a `string` validada contra `crm.linha` (F1).

---

## 3. Modelo de dados (esboço SQL, não aplicado)

Convenções: `uuid default gen_random_uuid()`, `timestamptz` para instante, `date` + `time` para horário de evento,
`search_path = ''` em toda função, nomes qualificados. Toda tabela: `alter table ... enable row level security;`
`revoke all on ... from public, anon, authenticated;` e depois só `grant select ... to authenticated` onde a leitura
invoker precisar.

### 3.1 Fundação (F0)

```sql
create schema crm;
revoke all on schema crm from public, anon;
grant usage on schema crm to authenticated;   -- necessário para RPC invoker; tabelas continuam sem grant de escrita

-- Kill-switches e parâmetros (1 linha)
create table crm.config (
  id                     boolean primary key default true check (id),
  escrita_ligada         boolean not null default true,   -- desliga TODA RPC de escrita
  hotmart_ligado         boolean not null default false,
  whatsapp_ligado        boolean not null default false,
  activecampaign_ligado  boolean not null default false,
  sendflow_ligado        boolean not null default false,
  respondi_ligado        boolean not null default false,
  clint_import_ligado    boolean not null default false,
  mcp_ligado             boolean not null default false,
  notificacao_cron_ligado boolean not null default false,
  horario_contato        text,
  limite_negocios_abertos int check (limite_negocios_abertos > 0),
  ciclo_distribuicao_desde timestamptz not null default date_trunc('month', now())
);

-- Equipe comercial: atributos do comercial sobre public.perfis. Papel NÃO mora aqui (vem de perfis).
create table crm.vendedor (
  perfil_id    uuid primary key references public.perfis(id) on delete restrict,
  sigla        text not null unique check (sigla ~ '^[a-z0-9]{2,6}$'),
  ativo        boolean not null default true,       -- inativar, nunca apagar
  dispara_api  boolean not null default false,
  criado_em    timestamptz not null default now()
);

create table crm.pessoa (
  id             uuid primary key default gen_random_uuid(),
  nome           text not null check (length(btrim(nome)) between 1 and 200),
  email          text,
  email_norm     text generated always as (nullif(lower(btrim(email)), '')) stored,
  telefone       text check (telefone is null or telefone ~ '^[0-9]{8,15}$'),   -- só dígitos, com DDI
  fone_key       text generated always as (controle.fone_key(telefone)) stored,
  cidade         text,
  uf             text check (uf is null or uf ~ '^[A-Z]{2}$'),
  perfil         text check (perfil in ('advogado','contador','outro')),
  atua_com_holding text check (atua_com_holding in ('sim','nao','comecando')),
  dono_id        uuid references crm.vendedor(perfil_id) on delete restrict,
  tags           text[] not null default '{}',
  utm_primeira   jsonb not null default '{}' check (jsonb_typeof(utm_primeira) = 'object'),
  score          smallint check (score between 0 and 100),
  opt_out        boolean not null default false,          -- mantido por trigger a partir de crm.supressao
  thb_aluno_id   uuid references public.thb_alunos(id) on delete set null,
  comprador_id   uuid references public.compradores(id) on delete set null,
  canonica_id    uuid references crm.pessoa(id) on delete restrict,   -- alias: duplicata aponta para a canônica
  arquivada_em   timestamptz,
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  check (email_norm is not null or fone_key is not null),
  check (canonica_id is null or canonica_id <> id),
  check ((canonica_id is null) or (arquivada_em is not null))
);
create unique index pessoa_email_uidx  on crm.pessoa (email_norm) where email_norm is not null and canonica_id is null;
create index pessoa_fone_idx           on crm.pessoa (fone_key)   where fone_key is not null and canonica_id is null;  -- NÃO unique
create index pessoa_dono_idx           on crm.pessoa (dono_id)    where canonica_id is null;
create index pessoa_nome_trgm          on crm.pessoa using gin (nome gin_trgm_ops);
create index pessoa_aluno_idx          on crm.pessoa (thb_aluno_id) where thb_aluno_id is not null;

-- Todas as chaves conhecidas da pessoa (e-mails extras, telefones, ucode Hotmart). Sem CPF.
create table crm.pessoa_chave (
  tipo      char(1) not null check (tipo in ('e','f','u')),   -- e-mail normalizado, fone_key, ucode
  valor     text not null check (length(valor) between 3 and 320),
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  origem    text not null check (origem in ('crm','hotmart','activecampaign','sendflow','respondi','clint','whatsapp','merge','mcp')),
  criado_em timestamptz not null default now(),
  primary key (tipo, valor, pessoa_id)
);
create unique index pessoa_chave_uidx on crm.pessoa_chave (tipo, valor) where tipo in ('e','u');  -- e-mail e ucode: 1 pessoa
create index pessoa_chave_pessoa_idx on crm.pessoa_chave (pessoa_id);

create table crm.pessoa_sugestao (            -- telefone igual, e-mail diferente: gestor decide
  pessoa_a uuid not null references crm.pessoa(id) on delete restrict,
  pessoa_b uuid not null references crm.pessoa(id) on delete restrict,
  motivo   text not null check (motivo in ('mesmo_telefone','mesmo_nome','identidade_fin')),
  decidida text check (decidida in ('unir','manter_separadas')),
  decidido_por uuid references public.perfis(id),
  decidido_em  timestamptz,
  criado_em timestamptz not null default now(),
  primary key (pessoa_a, pessoa_b),
  check (pessoa_a < pessoa_b)
);
```

**Resolver pessoa** (`crm.resolver_pessoa(p_email text, p_telefone text, p_nome text, p_origem text) returns uuid`,
`SECURITY DEFINER`, sem grant a `authenticated`; usada por RPCs e integrações):

1. `v_email := nullif(lower(btrim(p_email)),'')`; busca `crm.pessoa_chave (tipo='e', valor=v_email)` → segue `canonica_id`.
2. Senão, `fin.identidade` (`no = 'e:'||v_email`) → e-mails irmãos → algum já é pessoa? usa e grava a chave nova (`origem`).
3. Senão, sem e-mail e exatamente 1 pessoa com `fone_key` → usa.
4. Senão cria. Se havia pessoa com mesmo `fone_key` e e-mail diferente → `crm.pessoa_sugestao`.
5. Concorrência: `pg_advisory_xact_lock(hashtext('crm.pessoa:'||coalesce(v_email, controle.fone_key(p_telefone))))`.

### 3.2 Log append-only gravado por trigger (F0)

```sql
create table crm.log (
  id          bigint generated always as identity primary key,
  em          timestamptz not null default clock_timestamp(),
  autor_id    uuid,                         -- null = sistema
  autor_tipo  text not null check (autor_tipo in ('pessoa','sistema','integracao','mcp')),
  canal       text not null default 'tela', -- tela | mcp | hotmart | whatsapp | clint_import | cron ...
  acao        text not null check (acao in ('criou','editou','moveu_etapa','trocou_dono','marcou_perdido','marcou_ganho',
                 'arquivou','excluiu','concluiu','agendou','atribuiu','enviou','aprovou','reprovou','vinculou',
                 'desvinculou','importou','reembolsou','uniu','separou')),
  entidade    text not null check (entidade in ('negocio','contato','atividade','mensagem','nota','funil','etapa',
                 'campanha','agrupador','projeto','motivo','ficha','fila','produto','oferta','distribuicao','link',
                 'dashboard','painel','preferencias','vendedor','config')),
  entidade_id text not null,
  pessoa_id   uuid,                         -- sem FK: o log sobrevive a alias/arquivamento
  resumo      text not null,
  mudancas    jsonb not null default '[]' check (jsonb_typeof(mudancas) = 'array'),
  dados       jsonb not null default '{}',  -- estruturado p/ métricas: {funil_id, papel_de, papel_para, negocio_id}
  txid        bigint not null default txid_current()
);
create index log_em_idx       on crm.log (em desc);
create index log_ent_idx      on crm.log (entidade, entidade_id, em desc);
create index log_pessoa_idx   on crm.log (pessoa_id, em desc) where pessoa_id is not null;
create index log_autor_idx    on crm.log (autor_id, em desc);
create index log_etapa_idx    on crm.log (em) where acao = 'moveu_etapa';   -- fechamento do dia

-- Imutável: nem dono do banco altera sem desligar trigger em migration explícita.
create function crm.tg_log_imutavel() returns trigger language plpgsql set search_path = '' as $$
begin raise exception 'crm.log é append-only (%).', tg_op; end $$;
create trigger log_sem_update before update or delete on crm.log for each row execute function crm.tg_log_imutavel();
create trigger log_sem_truncate before truncate on crm.log for each statement execute function crm.tg_log_imutavel();
revoke all on crm.log from public, anon, authenticated;
grant select on crm.log to authenticated;   -- filtrado por policy (seção 4)
```

Trigger genérico `crm.tg_log()` (`AFTER INSERT OR UPDATE OR DELETE`, `SECURITY DEFINER`, `for each row`,
`TG_ARGV[0]` = entidade). **Sem `OF`** e com `WHEN (old.* is distinct from new.*)` no UPDATE (manual §7):

- `mudancas`: diff campo a campo de `to_jsonb(old)` × `to_jsonb(new)`, ignorando `atualizado_em`, `etapa_desde`,
  `ultima_interacao_em` e colunas geradas.
- `acao` derivada: INSERT→`criou`; status→`perdido`→`marcou_perdido`; →`ganho`→`marcou_ganho`; `etapa_id`
  mudou→`moveu_etapa` (grava `dados.papel_de/papel_para`); `dono_id`→`trocou_dono`; `arquivado_em` preenchido→
  `arquivou`; `concluida_em` preenchida→`concluiu`; DELETE→`excluiu`; resto `editou`.
- `autor_id = coalesce(auth.uid(), nullif(current_setting('crm.autor', true), '')::uuid)`;
  `canal = coalesce(nullif(current_setting('crm.canal', true), ''), case when auth.uid() is null then 'sistema' else 'tela' end)`.
- `resumo`: a RPC grava a frase pronta com `set_config('crm.resumo', '...', true)` antes do write; o trigger lê **e
  limpa** (`set_config('crm.resumo', '', true)`), senão gera "Editou negocio <id>".
- Falha no log **aborta** o write (log é requisito, não acessório). Exceção: trigger em tabela de outra equipe
  (`cs.hotmart_eventos`) nunca derruba a gravação principal (ver 5.1).

Tabelas com trigger de log: `pessoa, negocio, atividade, nota, mensagem (só saída), agrupador, funil, etapa_funil,
campanha, motivo_perda, distribuicao, fila_item, ficha_disparo, produto_comercial, oferta_comercial, link_rastreavel,
dashboard, painel, preferencias_notificacao, vendedor, config`. Fora: `notificacao`, `conversa` (derivadas, ruído).

**Escala do log:** ~25 eventos Hotmart/dia + operação de N vendedores (estimativa: 5 vendedores × 150 ações = 750/dia
→ ~280 mil/ano). Índices acima bastam; partição mensal só se passar de 5 milhões (medir em 90 dias).

### 3.3 Produtos e ofertas (F1)

Ordem de criação na migration da F1: `linha` → `agrupador` (3.4) → `produto_comercial`/`oferta_comercial` → resto.

```sql
create table crm.linha (                    -- substitui o enum ProdutoKey
  chave        text primary key check (chave ~ '^[a-z0-9_]{2,20}$'),
  nome         text not null,
  escada       char(1) not null check (escada in ('A','B')),
  ticket_ref   numeric(12,2) not null check (ticket_ref >= 0),
  ativo        boolean not null default true
);
-- seed: ht, hm, aurum, sv, acelera, ethb (de domain/catalogo.ts)

create table crm.produto_comercial (
  produto_id     text primary key references fin.produtos(produto_id) on delete restrict,
  no_comercial   boolean not null default false,
  nome_comercial text,
  linha          text references crm.linha(chave) on delete restrict,
  agrupador_id   uuid references crm.agrupador(id) on delete set null,
  vinculado_por  uuid references public.perfis(id),
  vinculado_em   timestamptz,
  check (not no_comercial or (nome_comercial is not null and linha is not null))
);
create index produto_comercial_linha_idx on crm.produto_comercial (linha) where no_comercial;

create table crm.oferta_comercial (
  oferta_codigo text primary key references fin.ofertas(oferta_codigo) on delete restrict,
  vigente       boolean not null default false,
  condicao      text check (length(condicao) <= 300),
  valida_ate    date,
  uso           text check (length(uso) <= 200),
  atualizado_por uuid references public.perfis(id),
  atualizado_em timestamptz not null default now()
);
create index oferta_vigente_idx on crm.oferta_comercial (oferta_codigo) where vigente;
-- Regra "vigente só com produto vinculado": cruza tabela → trigger BEFORE INSERT/UPDATE (CHECK não aceita subquery).
```

Nenhuma função SQL do banco apaga `fin.ofertas`/`fin.produtos` (conferido em `pg_proc`), então a FK `restrict` é
segura; se a Edge `hotmart-sync` apagar por API, a FK faz o erro aparecer (melhor que órfão silencioso).
**Conferir o código publicado da `hotmart-sync` antes da F1.**

Leituras (DEFINER, guarda `crm.eh_comercial()`): `crm_produtos_hotmart()` = `fin.produtos` ⟕ `produto_comercial`;
`crm_ofertas(p_produto_id)` = `fin.ofertas` ⟕ `oferta_comercial` + `count/max` de transações por `oferta_codigo`
(índice `hotmart_transacoes_oferta_idx`); `crm_ofertas_orfas()` = códigos em `hotmart_transacoes` fora de
`fin.ofertas` (229 hoje; resultado pequeno, materializar só se medir > 50 ms); `crm_buscar_por_link(texto)` usa a
mesma regex de `extrairCodigoOferta()`.

### 3.4 Construtor de funis (F1)

```sql
create table crm.agrupador (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(btrim(nome)) between 1 and 80),
  linha text references crm.linha(chave) on delete restrict,
  ordem smallint not null default 0,
  arquivado_em timestamptz
);
create unique index agrupador_nome_uidx on crm.agrupador (lower(btrim(nome))) where arquivado_em is null;

create table crm.campo_def (                 -- os campos do negócio (playbook 4.3, máx. 8)
  chave  text primary key check (chave ~ '^[a-z_]{3,40}$'),
  rotulo text not null,
  tipo   text not null check (tipo in ('texto','opcao')),
  opcoes text[]
);
-- seed: perfil_profissional, atua_com_holding, produto_interesse, origem, objecao_principal, forma_pagamento

create table crm.funil (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(btrim(nome)) between 1 and 80),
  icone text not null default 'kanban',
  projeto text check (projeto ~ '^[a-z0-9-]{3,60}$'),   -- chave do projeto (= utm_campaign/ClickUp/Drive)
  agrupador_id uuid not null references crm.agrupador(id) on delete restrict,
  linha text not null references crm.linha(chave) on delete restrict,
  tipo text not null check (tipo in ('manual','hotmart')),
  eventos_hotmart text[] not null default '{}'
    check (eventos_hotmart <@ array['carrinho_abandonado','compra_em_aberto','cartao_recusado','compra_aprovada','expirada','reembolso']),
  distribuicao_propria boolean not null default false,
  ativo boolean not null default true,
  arquivado_em timestamptz,
  criado_por uuid references public.perfis(id),
  criado_em timestamptz not null default now(),
  check (tipo = 'manual' or cardinality(eventos_hotmart) > 0),
  check (ativo = (arquivado_em is null))
);

create table crm.etapa_funil (
  id uuid primary key default gen_random_uuid(),
  funil_id uuid not null references crm.funil(id) on delete restrict,
  ordem smallint not null check (ordem >= 0),
  nome text not null check (length(btrim(nome)) between 1 and 60),
  papel text not null check (papel in ('primeiro_contato','qualificar','apresentar_oferta','negociar','aguardar_pagamento','fechado')),
  cor text not null check (cor in ('neutral','accent','info','cyan','purple','yellow','green','red')),
  sla_atencao_min int check (sla_atencao_min > 0),
  sla_critico_min int,
  campos_obrigatorios text[] not null default '{}',   -- validado contra crm.campo_def na RPC
  criterio text not null default '',
  arquivada_em timestamptz,
  unique (funil_id, id),                               -- alvo da FK composta do negócio
  check ((sla_atencao_min is null) = (sla_critico_min is null)),
  check (sla_critico_min is null or sla_critico_min > sla_atencao_min)
);
create unique index etapa_ordem_uidx on crm.etapa_funil (funil_id, ordem) where arquivada_em is null;
create unique index etapa_nome_uidx  on crm.etapa_funil (funil_id, lower(btrim(nome))) where arquivada_em is null;
create unique index etapa_ganho_uidx on crm.etapa_funil (funil_id) where papel = 'fechado' and arquivada_em is null;
-- "Ganho é a última" e "≥ 2 etapas": constraint trigger DEFERRABLE INITIALLY DEFERRED por funil (espelho de validarFunil).

create table crm.campanha (
  id uuid primary key default gen_random_uuid(),
  funil_id uuid not null references crm.funil(id) on delete restrict,
  nome text not null,
  canal text not null check (canal in ('utm','formulario','disparo','hotmart','webhook','manual')),
  regra text not null default '',          -- legível (o que a tela mostra hoje)
  regra_json jsonb not null default '{}',  -- máquina: {"utm_campaign":"ht33-meteorico"} | {"form_slug":"..."} | {"ofertas":["abc"]}
  ativa boolean not null default true,
  criado_em timestamptz not null default now()
);
create index campanha_utm_idx on crm.campanha ((regra_json->>'utm_campaign')) where ativa and canal = 'utm';
create index campanha_form_idx on crm.campanha ((regra_json->>'form_slug')) where ativa and canal = 'formulario';

create table crm.motivo_perda (
  chave text primary key check (chave ~ '^[a-z0-9_]{3,40}$'),
  rotulo text not null,
  reativa boolean not null default false,
  bloqueia boolean not null default false,
  alerta_gestor boolean not null default false,
  nota text,
  sistema boolean not null default false,
  ativo boolean not null default true,
  ordem smallint not null default 0
);
-- seed: os 9 de fábrica (sistema = true). Trigger: de fábrica só muda nota/ativo.

create table crm.distribuicao (
  funil_id uuid references crm.funil(id) on delete restrict,   -- null = distribuição geral
  vendedor_id uuid not null references crm.vendedor(perfil_id) on delete restrict,
  percentual smallint not null check (percentual between 0 and 100),
  ativo boolean not null default true
);
create unique index distribuicao_uidx on crm.distribuicao (coalesce(funil_id, '00000000-0000-0000-0000-000000000000'::uuid), vendedor_id);
-- soma 100 dos ativos: constraint trigger deferida (espelho de somaPercentuais).
```

Lacuna do front a fechar: `Campanha.regra` é texto livre. Para o lead entrar sozinho no funil certo o backend
precisa de `regra_json`; a tela de campanha ganha 1 campo estruturado (UTM / formulário / ofertas) na F1.

### 3.5 Negócio, atividade, nota (F1)

```sql
create table crm.negocio (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  funil_id uuid not null,
  etapa_id uuid not null,
  campanha_id uuid references crm.campanha(id) on delete set null,
  linha text not null references crm.linha(chave) on delete restrict,
  origem text not null check (origem in ('venda_ativa','carrinho_abandonado','compra_em_aberto','cartao_recusado','compra_aprovada','expirada','reembolso')),
  status text not null default 'aberto' check (status in ('aberto','ganho','perdido')),
  dono_id uuid references crm.vendedor(perfil_id) on delete restrict,
  valor numeric(12,2) not null default 0 check (valor >= 0),
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,
  campos jsonb not null default '{}'
    check (jsonb_typeof(campos) = 'object'
       and (campos - array['perfil_profissional','atua_com_holding','produto_interesse','origem','objecao_principal','forma_pagamento']) = '{}'::jsonb),
  motivo_perda text references crm.motivo_perda(chave) on delete restrict,
  nota_perda text,
  transacao_ganho text,               -- fin.hotmart_transacoes.transacao; sem FK: webhook chega antes da sincronização
  reembolsado_em timestamptz,
  utm jsonb not null default '{}',
  legado_origem text check (legado_origem in ('clint','cs')),
  legado_id text,
  criado_em timestamptz not null default now(),
  etapa_desde timestamptz not null default now(),
  fechado_em timestamptz,
  ultima_interacao_em timestamptz,
  atualizado_em timestamptz not null default now(),
  foreign key (funil_id) references crm.funil(id) on delete restrict,
  foreign key (funil_id, etapa_id) references crm.etapa_funil(funil_id, id) on delete restrict,  -- etapa é do funil
  check ((status = 'perdido') = (motivo_perda is not null)),
  check ((status = 'ganho')   = (transacao_ganho is not null)),
  check ((status = 'aberto')  = (fechado_em is null))
);
create unique index negocio_aberto_uidx    on crm.negocio (pessoa_id, funil_id) where status = 'aberto';  -- 1 aberto por funil + idempotência
create index negocio_dono_aberto_idx       on crm.negocio (dono_id, etapa_id) where status = 'aberto';
create index negocio_funil_aberto_idx      on crm.negocio (funil_id, etapa_id) where status = 'aberto';
create index negocio_sem_dono_idx          on crm.negocio (criado_em) where status = 'aberto' and dono_id is null;
create index negocio_fechado_idx           on crm.negocio (fechado_em) where status <> 'aberto';
create index negocio_pessoa_idx            on crm.negocio (pessoa_id, criado_em desc);
create index negocio_dist_idx              on crm.negocio (funil_id, dono_id, criado_em);   -- contagem do ciclo
create unique index negocio_transacao_uidx on crm.negocio (transacao_ganho) where transacao_ganho is not null;
create unique index negocio_legado_uidx    on crm.negocio (legado_origem, legado_id) where legado_id is not null;
```

Triggers do negócio (`BEFORE UPDATE`, comparam antigo × novo, nunca consultam a própria tabela na policy):

- **Ganho só por pagamento**: `new.status = 'ganho' and old.status <> 'ganho'` exige
  `current_setting('crm.canal', true) = 'hotmart'` (só `crm.processar_evento_hotmart` grava isso). Senão `raise`.
- **Campos obrigatórios ao entrar na etapa**: se `etapa_id` mudou, calcula campos exigidos das etapas de ordem ≤
  destino (espelho de `camposFaltandoNoFunil`) e recusa se faltar. Também barra destino com papel `fechado`.
- **Encerrado não volta**: `old.status <> 'aberto'` → só `reembolsado_em`/`nota_perda` podem mudar.
- `etapa_desde = now()` quando `etapa_id` muda; `atualizado_em = now()` sempre.

Por que `campos jsonb` e não `negocio_campo` (EAV): são ≤ 8 chaves fixas do playbook, lidas sempre juntas; o CHECK
garante as chaves; o log faz diff por chave. Campo personalizado por funil, se vier, ganha `crm.campo_def.funil_id`
sem mudar o negócio.

```sql
create table crm.atividade (
  id uuid primary key default gen_random_uuid(),
  negocio_id uuid references crm.negocio(id) on delete restrict,
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  dono_id uuid not null references crm.vendedor(perfil_id) on delete restrict,
  tipo text not null check (tipo in ('whatsapp','ligacao','email','tarefa','reuniao')),
  titulo text not null check (length(btrim(titulo)) between 1 and 200),
  vence_em timestamptz not null,
  concluida_em timestamptz,
  resultado text,
  cancelada boolean not null default false,
  cadencia_dia smallint check (cadencia_dia between 1 and 5),
  criado_por uuid references public.perfis(id),
  criado_em timestamptz not null default now(),
  check ((concluida_em is null) = (resultado is null))
);
create index atividade_dono_aberta_idx    on crm.atividade (dono_id, vence_em) where concluida_em is null;
create index atividade_negocio_aberta_idx on crm.atividade (negocio_id, vence_em) where concluida_em is null;
create index atividade_concluida_idx      on crm.atividade (concluida_em) where concluida_em is not null;   -- abordados do dia
create index atividade_pessoa_idx         on crm.atividade (pessoa_id, criado_em desc);

create table crm.nota (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  negocio_id uuid references crm.negocio(id) on delete restrict,
  texto text not null check (length(btrim(texto)) between 1 and 5000),
  autor_id uuid references public.perfis(id),
  em timestamptz not null default now()
);
create index nota_pessoa_idx on crm.nota (pessoa_id, em desc);
```

`proximaAtividade` do negócio = `left join lateral (select ... from crm.atividade where negocio_id = n.id and
concluida_em is null order by vence_em limit 1)` (usa `atividade_negocio_aberta_idx`).

`EventoTimeline` = view `crm.vw_evento` sobre `crm.log` (mapa `acao`→`TipoEvento`) **mais** `crm.mensagem` e
`crm.nota`. Uma fonte só: o "Moveu para X" do fechamento sai de `log.dados.papel_para`.

### 3.6 Conversa e mensagem (F4)

```sql
create table crm.numero_whatsapp (
  id uuid primary key default gen_random_uuid(),
  provedor text not null check (provedor in ('infobip','unnichat','meta')),
  numero text not null unique check (numero ~ '^[0-9]{10,15}$'),
  nome text not null,
  waba_id text,
  ativo boolean not null default true
);
create table crm.template (
  id uuid primary key default gen_random_uuid(),
  provedor text not null,
  nome_provedor text not null,
  nome text not null,
  categoria text not null check (categoria in ('marketing','utility')),
  idioma text not null default 'pt_BR',
  texto text not null,
  aprovado boolean not null default false,
  sincronizado_em timestamptz,
  unique (provedor, nome_provedor, idioma)
);
create table crm.mensagem (
  id uuid primary key default gen_random_uuid(),
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  canal text not null check (canal in ('whatsapp','email','nota')),
  direcao text not null check (direcao in ('entrada','saida')),
  texto text not null,
  em timestamptz not null,
  status text check (status in ('enviada','entregue','lida','falhou')),
  status_em timestamptz,
  autor_id uuid references public.perfis(id),
  template_id uuid references crm.template(id) on delete restrict,
  numero_id uuid references crm.numero_whatsapp(id) on delete restrict,
  ficha_id uuid,                       -- disparo que gerou
  provedor text,
  provedor_msg_id text,
  erro text,
  lida_pelo_dono_em timestamptz,
  unique (provedor, provedor_msg_id)   -- idempotência de webhook
);
create index mensagem_pessoa_idx on crm.mensagem (pessoa_id, em desc);
create index mensagem_entrada_nao_lida_idx on crm.mensagem (pessoa_id) where direcao = 'entrada' and lida_pelo_dono_em is null;

-- Derivada, mantida por trigger AFTER INSERT/UPDATE em crm.mensagem (lista de conversas sem varrer mensagens)
create table crm.conversa (
  pessoa_id uuid primary key references crm.pessoa(id) on delete restrict,
  numero_id uuid references crm.numero_whatsapp(id),
  ultima_mensagem_id uuid not null references crm.mensagem(id),
  ultima_em timestamptz not null,
  nao_lidas int not null default 0 check (nao_lidas >= 0),
  janela_ate timestamptz,              -- última entrada + 24 h
  atribuida_a uuid references crm.vendedor(perfil_id)
);
create index conversa_atribuida_idx on crm.conversa (atribuida_a, ultima_em desc);

create table crm.supressao (           -- opt-out por canal; pessoa.opt_out mantido por trigger
  tipo char(1) not null check (tipo in ('e','f')),
  valor text not null,
  canal text not null check (canal in ('todos','whatsapp','email')),
  motivo text not null,
  origem text not null,                -- activecampaign | whatsapp_stop | motivo_perda | gestor
  em timestamptz not null default now(),
  primary key (tipo, valor, canal)
);
```

`rsvp.nao_perturbe` (0 linhas) fica como está; o CRM não escreve nele.

### 3.7 Recuperação, disparo, links (F2/F4)

```sql
create table crm.fila (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  linha text not null references crm.linha(chave),
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,  -- sem oferta vigente não se aborda
  projeto text,
  criada_por uuid references public.perfis(id),
  criada_em timestamptz not null default now(),
  encerrada_em timestamptz
);
create table crm.fila_item (
  id uuid primary key default gen_random_uuid(),
  fila_id uuid not null references crm.fila(id) on delete restrict,
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  score smallint not null check (score between 0 and 100),
  faixa char(1) generated always as (case when score >= 60 then 'A' when score >= 40 then 'B' when score >= 25 then 'C' else 'D' end) stored,
  sinais text[] not null default '{}',
  status text not null default 'a_abordar' check (status in ('a_abordar','tentando_contato','em_conversa','vai_comprar','ganho','sem_resposta','declinou','sem_interesse','numero_invalido')),
  responsavel_id uuid references crm.vendedor(perfil_id),
  alterado_por uuid references public.perfis(id),
  alterado_em timestamptz,
  unique (fila_id, pessoa_id)
);
create index fila_item_faixa_idx on crm.fila_item (fila_id, faixa, status);

create table crm.ficha_disparo (
  id uuid primary key default gen_random_uuid(),
  codigo text not null unique check (codigo ~ '^[A-Z0-9]+-[0-9]{8}-[0-9]{2}$'),  -- = template, log, utm_content
  objetivo text not null,
  linha text not null references crm.linha(chave),
  filtro text not null,
  filtro_json jsonb not null default '{}',
  quantidade int not null check (quantidade > 0),
  supressoes text[] not null default array['em_negociacao','disparo_48h','opt_out','ja_comprou'],
  suprimidos int not null default 0,
  template_id uuid not null references crm.template(id),
  numero_id uuid not null references crm.numero_whatsapp(id),
  agendado_para timestamptz not null,
  operador_id uuid not null references crm.vendedor(perfil_id),
  link text not null,
  status text not null default 'rascunho' check (status in ('rascunho','aguardando_aprovacao','aprovada','reprovada','enviada')),
  aprovado_por uuid references public.perfis(id),
  aprovado_em timestamptz,
  resultado jsonb,
  criado_em timestamptz not null default now(),
  check (status not in ('aprovada','enviada') or aprovado_por is not null)
);
create table crm.ficha_destinatario (
  ficha_id uuid not null references crm.ficha_disparo(id) on delete restrict,
  pessoa_id uuid not null references crm.pessoa(id) on delete restrict,
  suprimido_por text check (suprimido_por in ('em_negociacao','disparo_48h','opt_out','ja_comprou')),
  mensagem_id uuid references crm.mensagem(id),
  primary key (ficha_id, pessoa_id)
);
create index ficha_dest_pessoa_idx on crm.ficha_destinatario (pessoa_id) where suprimido_por is null;  -- regra 48 h

create table crm.link_rastreavel (
  id uuid primary key default gen_random_uuid(),
  vendedor_id uuid not null references crm.vendedor(perfil_id) on delete restrict,
  linha text not null references crm.linha(chave),
  oferta_codigo text references fin.ofertas(oferta_codigo) on delete restrict,   -- link real, não "EXEMPLO"
  acao text not null,
  canal text not null,
  sck text not null unique,
  url text not null,
  criado_em timestamptz not null default now()
);
```

Atribuição da venda: `fin.hotmart_transacoes.origem_sck` ↔ `crm.link_rastreavel.sck` (sem índice hoje em
`origem_sck`; criar `create index on fin.hotmart_transacoes (origem_sck) where origem_sck is not null` **só** se o
`explain` da RPC de desempenho pedir — tabela de outra equipe, combinar antes).

### 3.8 Relatórios, painel, notificações (F1/F2)

```sql
create table crm.dashboard (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(btrim(nome)) between 1 and 80),
  descricao text,
  dono_id uuid not null references public.perfis(id) on delete restrict,
  compartilhado boolean not null default false,
  widgets jsonb not null default '[]' check (jsonb_typeof(widgets) = 'array' and jsonb_array_length(widgets) <= 40),
  criado_em timestamptz not null default now(),
  atualizado_em timestamptz not null default now(),
  arquivado_em timestamptz              -- "excluir" na tela = arquivar
);
create index dashboard_dono_idx on crm.dashboard (dono_id) where arquivado_em is null;
create index dashboard_comp_idx on crm.dashboard (atualizado_em desc) where compartilhado and arquivado_em is null;

create table crm.painel (
  perfil_id uuid primary key references public.perfis(id) on delete restrict,
  widgets jsonb not null check (jsonb_typeof(widgets) = 'array' and jsonb_array_length(widgets) <= 40),
  atualizado_em timestamptz not null default now()
);

create table crm.preferencias_notificacao (
  perfil_id uuid primary key references public.perfis(id) on delete restrict,
  desktop boolean not null default true,
  gatilhos jsonb not null,   -- {lead_novo:true, ...} (6 chaves; CHECK como em negocio.campos)
  silencio_inicio time,
  silencio_fim time
);

create table crm.notificacao (
  id bigint generated always as identity primary key,
  perfil_id uuid not null references public.perfis(id) on delete restrict,
  gatilho text not null check (gatilho in ('lead_novo','lead_respondeu','prazo_estourado','venda_aprovada','ficha_para_aprovar','atividade_vencendo')),
  ref_id text not null,      -- negócio/mensagem/ficha/atividade
  titulo text not null,
  corpo text not null,
  href text not null check (href ~ '^/comercial/'),
  em timestamptz not null default now(),
  lida_em timestamptz,
  unique (perfil_id, gatilho, ref_id)   -- cron e trigger não duplicam aviso
);
create index notificacao_nao_lida_idx on crm.notificacao (perfil_id, em desc) where lida_em is null;
```

**Notificação (por que "não deu certo" no front):** no mock elas são *calculadas* a cada leitura a partir do estado,
não persistidas. No backend nascem gravadas:

| Gatilho | Mecanismo |
|---|---|
| `lead_novo` | trigger AFTER INSERT em `negocio` com `dono_id` |
| `lead_respondeu` | trigger AFTER INSERT em `mensagem` (entrada) para o dono da pessoa |
| `venda_aprovada` | dentro de `processar_evento_hotmart` |
| `ficha_para_aprovar` | trigger em `ficha_disparo` → status `aguardando_aprovacao` (para cada gestor) |
| `prazo_estourado`, `atividade_vencendo` | `pg_cron` a cada 5 min, **SQL puro** (sem HTTP), só insere o que não existe (`on conflict do nothing`), kill-switch `notificacao_cron_ligado`. Frequência = ritmo do SLA mínimo do playbook (5 min) |

Entrega na tela: **Realtime** só em `crm.notificacao`, filtro `perfil_id=eq.<eu>` (RLS vale no Realtime). Nada de
polling por aba (manual §5: egress = frequência de leitura). Desktop: o front já pede permissão; dispara ao receber
o evento Realtime respeitando `preferencias_notificacao`.

**Métricas/dashboards:** hoje o front calcula fechamento e widgets carregando `negocios()`, `atividades()` e
`eventos()` inteiros. Com dado real isso é o anti-padrão "select('*') + join em JS". Proposta: RPC
`crm_metrica(p_metrica, p_periodo, p_agrupar, p_funil_id)` e `crm_desempenho(p_desde, p_ate)` calculadas no banco
com as definições de `domain/metricas.ts` (uma por chave), e **2 métodos novos no port** (`metrica(w)` e
`desempenho(periodo)`). O desempenho por vendedor devolve, por vendedor: abordados, responderam, entraram em contato,
em negociação (n e R$), vendas, receita, reembolsos, conversão, tempo mediano até 1º contato, ciclo médio, perdidos
por motivo, atrasadas, sem próximo passo, carteira aberta. Vendedor vê a própria linha + total do time; gestor vê todos.

---

## 4. Segurança

### 4.1 Papéis (sem mexer em `gp_is_admin`)

| Papel | Regra (em `public.perfis`) | Observação |
|---|---|---|
| Gestor comercial | `status='ativo'` e (`cargo in ('dev','admin')` **ou** (`cargo='gestor'` e `'comercial' = any(areas)`)) | Mesma régua de `gp_pode_editar`. Ver D5: admin = gestor? |
| Vendedor | `status='ativo'`, `'comercial' = any(areas)`, `'comercial.vender' = any(funcoes)` e linha ativa em `crm.vendedor` | `cargo='operador'` |
| Visualizador / resto da equipe | qualquer outro | **não vê nada do CRM** (nem contagem) |

```sql
create function crm.eh_gestor() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo'
       and (p.cargo in ('dev','admin') or (p.cargo = 'gestor' and 'comercial' = any(coalesce(p.areas, '{}'))))
      from public.perfis p where p.id = (select auth.uid())
  ), false)
$$;
create function crm.eh_vendedor() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select p.status = 'ativo' and v.ativo
       and 'comercial' = any(coalesce(p.areas, '{}'))
       and 'comercial.vender' = any(coalesce(p.funcoes, '{}'))
      from public.perfis p join crm.vendedor v on v.perfil_id = p.id
     where p.id = (select auth.uid())
  ), false)
$$;
create function crm.eh_comercial() returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(crm.eh_gestor(), false) or coalesce(crm.eh_vendedor(), false)
$$;
-- Visibilidade da pessoa numa função ÚNICA, usada por todas as policies e RPCs definer.
create function crm.pode_ver_pessoa(p_id uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce(crm.eh_gestor(), false)
      or (coalesce(crm.eh_vendedor(), false)
          and (exists (select 1 from crm.pessoa x
                        where x.id = p_id and (x.dono_id = (select auth.uid()) or x.dono_id is null))
               or exists (select 1 from crm.negocio n
                           where n.pessoa_id = p_id and n.dono_id = (select auth.uid()))))
$$;
revoke execute on function crm.eh_gestor(), crm.eh_vendedor(), crm.eh_comercial(), crm.pode_ver_pessoa(uuid) from public, anon;
grant  execute on function crm.eh_gestor(), crm.eh_vendedor(), crm.eh_comercial(), crm.pode_ver_pessoa(uuid) to authenticated;
```

### 4.2 Visibilidade ("lead que não é seu não se toca")

| Tabela | Gestor | Vendedor lê | Vendedor escreve |
|---|---|---|---|
| `pessoa` | tudo | dono = eu, sem dono, ou tenho negócio com ela | só via RPC, só as suas (sem dono: só o gestor atribui) |
| `negocio` | tudo | `dono_id = eu` ou (`dono_id is null`) | só os seus |
| `atividade`, `nota`, `mensagem`, `conversa` | tudo | da pessoa que `pode_ver_pessoa` | só nas suas pessoas |
| `funil`, `etapa`, `campanha`, `agrupador`, `motivo`, `linha`, `produto/oferta_comercial` | tudo | tudo (é configuração) | nada |
| `distribuicao` | tudo | só a própria linha | nada |
| `fila_item` | tudo | `responsavel_id = eu` ou nulo | os seus |
| `ficha_disparo` | tudo | as suas | cria rascunho; aprovação só gestor |
| `dashboard` | tudo | meus + compartilhados | meus |
| `painel`, `preferencias_notificacao`, `notificacao` | o próprio (gestor lê o painel de vendedor) | o próprio | o próprio |
| `log` | tudo | `autor_id = eu` ou `pode_ver_pessoa(pessoa_id)` | nunca (trigger grava) |

Exemplo de policy (padrão para todas):

```sql
alter table crm.negocio enable row level security;
revoke all on crm.negocio from public, anon, authenticated;
grant select on crm.negocio to authenticated;
create policy negocio_ler on crm.negocio for select to authenticated using (
  (select crm.eh_gestor())
  or ((select crm.eh_vendedor()) and (dono_id = (select auth.uid()) or dono_id is null))
);
-- Nenhuma policy de insert/update/delete: escrita só por RPC SECURITY DEFINER.
```

A policy de `negocio` não consulta `pessoa` e a de `pessoa` usa `crm.pode_ver_pessoa` (definer): sem recursão (42P17).

### 4.3 RPCs de escrita (todas `public.crm_*`, `SECURITY DEFINER`, `search_path = ''`)

Esqueleto comum:

```sql
create function public.crm_mover_etapa(p_negocio uuid, p_etapa uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_eu uuid := auth.uid(); n crm.negocio; e crm.etapa_funil; v_faltam text[];
begin
  if not coalesce((select c.escrita_ligada from crm.config c), false) then
    return jsonb_build_object('ok', false, 'msg', 'CRM em manutenção: escrita desligada.'); end if;
  if not coalesce(crm.eh_comercial(), false) then
    return jsonb_build_object('ok', false, 'msg', 'Sem permissão.'); end if;
  select * into n from crm.negocio where id = p_negocio for update;
  if not found then return jsonb_build_object('ok', false, 'msg', 'Negócio não encontrado.'); end if;
  if not (coalesce(crm.eh_gestor(), false) or n.dono_id = v_eu) then
    return jsonb_build_object('ok', false, 'msg', 'Este negócio não é seu.'); end if;
  -- … mesmas mensagens do mock: encerrado, etapa inexistente, ganho só com pagamento, "Preencha antes: …"
  perform set_config('crm.resumo', format('Moveu %s de %s para %s', ...), true);
  update crm.negocio set etapa_id = p_etapa, ultima_interacao_em = now() where id = p_negocio;  -- trigger valida e loga
  return jsonb_build_object('ok', true);
end $$;
revoke execute on function public.crm_mover_etapa(uuid, uuid) from public, anon;
grant  execute on function public.crm_mover_etapa(uuid, uuid) to authenticated;
```

| RPC | Regra no banco (além da guarda comum) |
|---|---|
| `crm_mover_etapa` | dono ou gestor; etapa do mesmo funil (FK composta); campos obrigatórios (trigger); papel `fechado` recusado |
| `crm_salvar_campos` | dono ou gestor; chaves só de `campo_def` (CHECK) |
| `crm_marcar_perdido` | dono ou gestor; motivo **ativo** do cadastro; cancela atividades abertas; `bloqueia` → `crm.supressao`; `alerta_gestor` → notificação |
| `crm_transferir_dono` | **só gestor**; motivo obrigatório; leva atividades abertas e o dono da pessoa |
| `crm_atribuir_contato` | **só gestor**; motivo obrigatório; negócios abertos sem dono herdam |
| `crm_criar_negocio` | pessoa sem opt-out; funil ativo; 1 aberto por funil (índice único); dono = dono da pessoa ou distribuição (`escolherDono` em SQL, sob `pg_advisory_xact_lock(hashtext('crm.dist:'||funil))`); valor = ticket da linha ou preço da oferta vigente |
| `crm_criar_atividade` / `crm_concluir_atividade` / `crm_adicionar_nota` | pessoa visível e (dono ou gestor) |
| `crm_enviar_mensagem` | dono ou gestor; opt-out; janela 24 h ou template aprovado; grava `mensagem` status `enviada` e enfileira envio (F4); `whatsapp_ligado` |
| `crm_salvar_funil` / `crm_arquivar_funil` / `crm_criar_agrupador` / `crm_criar_projeto` | só gestor; `validarFunil` repetido; etapa removida sem negócio aberto; arquivar bloqueia com aberto |
| `crm_salvar_motivo_perda` | só gestor; de fábrica só `nota`/`ativo` |
| `crm_salvar_distribuicao` | só gestor; soma 100 (constraint trigger) |
| `crm_salvar_ficha` / `crm_decidir_ficha` | `dispara_api`; gestor aprova; supressões calculadas no banco |
| `crm_atualizar_item_fila` | responsável ou gestor; C/D só com A/B zeradas (`faixaLiberada`) |
| `crm_criar_link` | vendedor só para si; oferta real da linha |
| `crm_vincular_produto` / `crm_salvar_oferta` | só gestor; produto tem de existir em `fin.produtos`; vigente só com produto vinculado |
| `crm_salvar_dashboard` / `crm_arquivar_dashboard` | dono ou gestor |
| `crm_salvar_painel` / `crm_salvar_preferencias` / `crm_marcar_notificacoes_lidas` | o próprio (gestor pode o painel de vendedor) |
| `crm_unir_pessoas` / `crm_separar_pessoas` | só gestor; alias reversível |

### 4.4 O que o visualizador (e quem não é do comercial) NÃO vê

Nada do schema `crm` (RPCs devolvem `ok:false` / lista vazia **com erro explícito**, não "zero"), nem telefone/e-mail de
lead, nem conversa, nem valor de negócio, nem log. Hoje `thb_alunos` é legível por qualquer `authenticated`
(policy `read_authenticated`): o CRM não amplia isso, mas também **não devolve** `documento` em nenhuma RPC.
`compradores` segue restrito a `is_ht_operator()`: a jornada lê via definer e devolve só nome/e-mail/telefone da
pessoa que `pode_ver_pessoa`.

### 4.5 Provas obrigatórias por fase

- `has_function_privilege('anon', 'public.crm_x(...)', 'execute') = false` para todas; conferir `proacl`.
- `has_table_privilege('authenticated', 'crm.x', 'insert'|'update'|'delete') = false` para todas.
- Ensaio com `set local role authenticated` + `set local request.jwt.claims` de 3 perfis reais: gestor, vendedor A,
  vendedor B (B não vê o negócio de A; A não move negócio de B; visualizador vê 0 com erro).

---

## 5. Integrações

Regra geral: webhook → Edge Function `verify_jwt=false` com segredo do Vault no header → grava **evento bruto**
idempotente → processa no banco (função definer). Cron HTTP sempre por `ops.cron_post('<job>', ...)`. Cada
integração tem kill-switch em `crm.config` e linha em `ops.rotina`. Tabela comum de bruto para quem não tem:

```sql
create table crm.integracao_evento (
  id bigint generated always as identity primary key,
  fonte text not null check (fonte in ('infobip','unnichat','manychat','activecampaign','respondi','sendflow','clint','slack')),
  fonte_evento_id text not null,
  recebido_em timestamptz not null default now(),
  payload jsonb not null,
  processado_em timestamptz,
  resultado text,
  unique (fonte, fonte_evento_id)
);
create index integracao_pendente_idx on crm.integracao_evento (recebido_em) where processado_em is null;
```

### 5.1 Hotmart (F3)

| Pergunta | Resposta |
|---|---|
| Mecanismo | **Trigger AFTER INSERT em `cs.hotmart_eventos`** (a Edge `hotmart-events-webhook` já grava lá) chamando `crm.processar_evento_hotmart(new.id)` dentro de `begin … exception when others` (nunca derruba a gravação do CS); erro vai para `crm.hotmart_processado.resultado` |
| Idempotência | `crm.hotmart_processado (evento_id text primary key = payload->>'id', processado_em, resultado)`; `insert … on conflict do nothing` antes de processar. Os 993 reenvios medidos viram no-op. Não altera `cs.hotmart_eventos` |
| Chave de identidade | e-mail do comprador → `crm.resolver_pessoa` (+ ucode como `pessoa_chave 'u'`, + telefone) |
| Produto | `payload` produto → `crm.produto_comercial` (linha). Sem vínculo → não cria negócio, registra `resultado='produto_fora_do_comercial'` (o sufixo `:PRODUTO_NAO_MAPEADO` do CS não decide nada no CRM) |
| Mapa de eventos | `PURCHASE_OUT_OF_SHOPPING_CART`→`carrinho_abandonado`; `PURCHASE_BILLET_PRINTED`→`compra_em_aberto`; `PURCHASE_EXPIRED`→`expirada`; `PURCHASE_CANCELED`/`PURCHASE_DELAYED`→`cartao_recusado` **(confirmar no payload: D7)**; `PURCHASE_APPROVED`/`COMPLETE`→ganho; `PURCHASE_REFUNDED`/`CHARGEBACK`→`reembolso` |
| Negócio automático | para cada funil `tipo='hotmart'` ativo da linha cujo `eventos_hotmart` contém a origem: `crm_criar_negocio` (índice único evita duplicar aberto) |
| Ganho | negócio aberto da pessoa na linha (o de interação mais recente; empate → o mais antigo); com `set_config('crm.canal','hotmart',true)` grava `status='ganho'`, `transacao_ganho`, `fechado_em`, `valor` = valor da transação. Sem negócio aberto: cria em funil de `compra_aprovada` já ganho (crédito: dono pelo `origem_sck`→link, senão dono da pessoa, senão ninguém) |
| Reembolso | `reembolsado_em` no negócio ganho (não reabre); métrica de receita desconta no período |
| Notificação/Slack | `venda_aprovada` para o dono; Slack continua com `cs.slack_notificacao_compra` (não duplicar) |
| Frequência | ~25 eventos comerciais/dia (30 d medidos); síncrono no trigger |
| Reversão | `hotmart_ligado = false` → trigger retorna logo no início |
| Catálogo | `fin-hotmart-catalogo` (diário) já atualiza ofertas; oferta nova vendida no dia aparece como órfã em `crm_ofertas_orfas()` com alerta ao gestor (manual §8: catalogar no MESMO dia) |

Backfill (opcional, decisão D8): reprocessar os 1.630 eventos únicos desde 15/07 só para jornada, **sem** criar negócio.

### 5.2 ActiveCampaign (F5)

| | |
|---|---|
| Hoje | `ingest-active` a cada 15 min por `ops.cron_post`; `controle.lead_active` com 24.056 linhas e **1 `evento_id`** (lista fixa). A expansão para outras listas depende de parametrizar a Edge (código fora deste repo: ler a versão publicada antes) |
| Destravar | `controle.lead_active` ganhar `lista_id` + tabela `controle.ac_lista_sincronizada (lista_id, evento_id, ativa)`; a Edge itera as listas ativas. **É mudança do time de marketing/controle: combinar** |
| Para o CRM | jornada lê `controle.lead_active` por `lower(btrim(email))` (índice `ix_lead_active_email_lower`); ponto `inscricao`/`lista` com UTM daquela entrada (`utm_source`, `utm_campaign`, `utm_content`) |
| Webhook | AC → Edge `crm-ac-webhook` (eventos `unsubscribe`, `bounce`, `contact_tag_added`) → `crm.integracao_evento` (id = `contact_id:type:date_time`) → unsubscribe/bounce vira `crm.supressao (e, email, 'email')`; tag configurada como "pediu contato" cria negócio na campanha correspondente |
| Idempotência | unique `(fonte, fonte_evento_id)` |
| Frequência | webhook (tempo real); ingestão de lista segue 15 min |
| Reversão | `activecampaign_ligado` |

### 5.3 SendFlow (F5)

| | |
|---|---|
| Hoje | `sendflow-webhook` + `ingest-sendflow` (30 min) → `controle.grupo_evento` (37.100) → `grupo_evento_unificado` (37.383, por `fone_key`) a cada 20 min |
| Para o CRM | jornada lê `grupo_evento_unificado` por `fone_key` (índice `ix_geu_fone`); ponto `grupo` (entrou/saiu, nome do grupo, lançamento) |
| Identidade | telefone → `crm.pessoa.fone_key`. Sem e-mail no SendFlow: **nunca cria pessoa nem funde**; só anexa à pessoa já existente com aquele `fone_key` (se houver 2+, não anexa) |
| Escrita nova | nenhuma; só leitura |
| Reversão | `sendflow_ligado` (a RPC de jornada pula a fonte) |

### 5.4 Infobip e Unnichat: WhatsApp oficial (F4)

| | Infobip | Unnichat |
|---|---|---|
| Estado medido | só totais agregados (`controle.mensageria_envio`, 226 linhas, último 28/08) | `controle.unnichat_evento` 7.728, **parado desde 08/09** |
| Inbound | webhook Infobip → Edge `crm-whatsapp-webhook` → `crm.mensagem` (entrada) | idem, payload Unnichat |
| Status | webhook de entrega/leitura → `update crm.mensagem set status, status_em` por `(provedor, provedor_msg_id)`, só se `status_em` novo > atual (`greatest`, webhook fora de ordem) | idem |
| Envio | `crm_enviar_mensagem` grava `status='enviada'` e `pg_notify`/fila; Edge `crm-whatsapp-enviar` (cron `ops.cron_post` 1 min **só quando há fila**, ou chamada direta da RPC via `net.http_post` com resultado guardado em coluna própria — manual §9) | idem |
| Identidade | telefone E.164 → `resolver_pessoa(null, fone, nome)`; sem pessoa → cria só com telefone (conversa "não atribuída") | idem |
| Idempotência | `unique (provedor, provedor_msg_id)` | idem |
| Opt-out | palavra "SAIR/PARAR" → `crm.supressao (f, fone_key, 'whatsapp')` | idem |
| Reversão | `whatsapp_ligado` | idem |

Recomendação: **um provedor só para o número oficial do comercial** (D3). O modelo aceita os dois
(`numero_whatsapp.provedor`), mas operar dois para o mesmo número duplica conversa.

### 5.5 Manychat (F5)

Instagram/WhatsApp de captação. Webhook "External Request" do Manychat → `crm.integracao_evento`
(id = `subscriber_id:flow:timestamp`) → pessoa por e-mail/telefone coletado → ponto de jornada `conversa`/`inscricao`;
flow configurado como "quer falar com consultor" cria negócio na campanha `canal='webhook'`. Kill-switch próprio
(`activecampaign_ligado` não serve: adicionar `manychat_ligado` na F5).

### 5.6 Respondi (F5)

| | |
|---|---|
| Hoje | `respondi-sync` diário (09:10) + `respondi-hm-webhook` (só formulários HM) → `respondi.respostas` (22.103) |
| Para o CRM | jornada lê por `email` (já normalizado, índice `respostas_email_idx` com a coluna crua: comparar `email = v_email`) |
| MQL | regra por formulário: `crm.campanha (canal='formulario', regra_json->>'form_slug')` + critério MQL (profissão = advogado/contador e resposta X) → cria negócio no funil "Captação e MQL" |
| Tempo real | diário não serve para "ligar em 15 min". Estender o webhook existente para os formulários de captação (gravar em `respondi.respostas` como hoje) e um trigger AFTER INSERT em `respondi.respostas` chama `crm.processar_resposta(uuid)` com `exception when others` |
| Idempotência | `respondi.respostas.uuid` (PK) + índice único do negócio aberto |
| Reversão | `respondi_ligado` |

### 5.7 Slack (F3)

Só saída: `crm.notificacao` com `alerta_gestor` (motivo de perda de processo, oferta órfã nova, negócio sem dono há
> SLA) → Edge `report-slack` existente (ou `enviar-notificacao`) por `ops.cron_post` de 10 min **só se houver
pendente** (SQL decide antes do HTTP). Não duplicar o aviso de compra (já existe `cs.slack_notificacao_compra`).

### 5.8 Clint: migração (F6)

| | |
|---|---|
| Estado | nenhum dado no banco |
| Fonte | export CSV (contatos, negócios, atividades, notas) + API Elite para o que o CSV não traz (histórico de etapa, donos, conversas se a WABA estiver na Clint) |
| Destino | `crm.clint_import (lote text, tipo text, clint_id text, payload jsonb, importado_em, pessoa_id, negocio_id, erro, primary key (tipo, clint_id))` → função `crm.importar_clint(lote)` que resolve pessoa por e-mail, cria negócio com `legado_origem='clint'`, `legado_id`, funil "Legado Clint" por agrupador (etapas mapeadas por papel numa tabela `crm.clint_mapa_etapa` preenchida pelo gestor) |
| Idempotência | PK `(tipo, clint_id)` + `negocio_legado_uidx` |
| Log | `acao='importou'`, `canal='clint_import'` |
| Paralelo | 2 a 4 semanas: Clint continua sendo onde se trabalha; import incremental diário (`ops.cron_post` 1×/dia) só de alterados; corte com data marcada; depois Clint só leitura |
| Prova | contagem por funil/etapa/dono Clint × CRM igual; amostra de 30 negócios conferida à mão |
| Reversão | `clint_import_ligado`; tudo marcado `legado_origem='clint'` é arquivável em lote |
| Risco | dono da WABA (D9): se o número oficial está na conta Clint, a migração do WhatsApp depende de portabilidade do número |

### 5.9 MCP do Comercial (F7)

> **Atualizado em 06/10/2026:** implementado como Route Handler no Next (`/api/mcp`) chamando as MESMAS RPCs
> `public.crm_*` com um JWT curto do dono do token (sem núcleos `crm._*` nem service role para agir). A tabela abaixo é o
> desenho original; o vigente está em `docs/projetos/comercial/mcp.md` e `infra/supabase/migrations/20261006050132.explain.md`.

| | |
|---|---|
| Forma | Edge Function `crm-mcp` (MCP over HTTP) |
| Autenticação | token pessoal por perfil: `crm.mcp_token (id, perfil_id, hash_sha256, escopo text[], criado_em, expira_em, revogado_em, ultimo_uso_em)`; token mostrado 1 vez, guardado só o hash. Edge valida hash e passa `perfil_id` |
| Escopo | `ler` (buscar_pessoa, jornada, funil, fechamento_do_dia) e `operar` (criar_atividade, mover_etapa, nota). **Nunca**: transferir dono, ganho, disparo, motivo/funil, produto/oferta, exportar lista |
| Núcleo único | cada RPC tem núcleo interno `crm._mover_etapa(p_autor uuid, ...)` (sem grant a `authenticated`, só `service_role`); `public.crm_mover_etapa` chama com `auth.uid()`, o MCP chama com o dono do token. Mesmas regras, mesma visibilidade (`pode_ver_pessoa` recebe `p_autor`) |
| Log | `autor_tipo='mcp'`, `canal='mcp'`, `autor_id` = dono do token |
| Limite | 60 chamadas/min por token (`crm.mcp_uso` por minuto) |
| Dado pessoal | `buscar_pessoa` exige termo ≥ 3 caracteres e devolve no máximo 20; sem documento |
| Reversão | `mcp_ligado`; revogar token |

---

## 6. Plano de migração em fases

Cada fase = migrations `YYYYMMDDx_crm_<fase>.sql` (conferir `ls infra/supabase/migrations | tail` no dia; último hoje:
`20261005l_remocao_marcadores.sql`) com **guarda de premissa** no topo, `_ensaio.sql` em `begin … rollback` com
`lock_timeout '3s'`/`statement_timeout '20s'`, `.explain.md` com `explain (analyze, buffers)` 2× da **RPC inteira**,
prova no dado depois de aplicar, renomear o arquivo para a versão gravada em `supabase_migrations.schema_migrations`,
nota no vault e card no ClickUp.

| Fase | Entra | Guarda de premissa | Como provar | Como desligar |
|---|---|---|---|---|
| **F0 fundação** | schema `crm`, `config`, `vendedor`, `pessoa`, `pessoa_chave`, `pessoa_sugestao`, `log` + triggers, helpers de papel, `resolver_pessoa`; cadastro dos vendedores reais (área `comercial`, função `comercial.vender`) | schema `crm` não existe; `controle.fone_key(text)` existe e é IMMUTABLE; `public.perfis` tem `areas`/`funcoes` | ensaio cria pessoa por e-mail com espaço/maiúscula e acha de novo; e-mail irmão via `fin.identidade`; telefone duplicado vira sugestão; `update`/`delete`/`truncate` em `crm.log` falham; anon sem execute; explain de `resolver_pessoa` com `Index Scan` em `pessoa_chave` e em `fin.identidade_pkey` | nada lê o schema ainda: `escrita_ligada=false`; reversão = `drop schema crm cascade` só nesta fase (vazio) |
| **F1 leitura** | `linha`, `produto_comercial`, `oferta_comercial`, `agrupador`, `campo_def`, `funil`, `etapa_funil`, `campanha`, `motivo_perda`, `distribuicao`, `negocio`, `atividade`, `nota`, `dashboard`, `painel`, `preferencias`, `notificacao`; seeds (linhas, 9 motivos, campos, modelos de funil); RPCs de leitura; `SupabaseComercialRepository` só lendo | F0 aplicada; contagem de `fin.ofertas` ≥ 1.143 e `fin.produtos` ≥ 97 | RLS com 3 JWTs reais (gestor/vendedor A/vendedor B/visualizador); `crm_ofertas_orfas()` = 229 códigos; explain de `crm_negocios()` e `crm_jornada()` < 50 ms com 10× de massa sintética (`generate_series`) | flag `NEXT_PUBLIC_COMERCIAL_FONTE=mock` volta o front em 1 deploy; `escrita_ligada=false` |
| **F2 escrita** | todas as RPCs `crm_*` de escrita; triggers de regra do negócio; constraint triggers de funil e distribuição; notificações por trigger + cron SQL 5 min | F1 aplicada; nenhuma linha em `crm.negocio` (ou contagem exata esperada) | ensaio chama cada RPC como a tela (mesmas mensagens do mock); mover sem campo recusa; mover p/ ganho recusa; vendedor A não toca negócio de B; troca de dono por vendedor recusa; log tem 1 linha por write com resumo e diff; Realtime entrega notificação só ao dono | `escrita_ligada=false` (todas as RPCs devolvem "manutenção"); `notificacao_cron_ligado=false` |
| **F3 Hotmart** | `hotmart_processado`, trigger em `cs.hotmart_eventos`, `processar_evento_hotmart`, Slack de alerta | F2 aplicada; trigger não existe; produtos vinculados ao comercial ≥ 1 | ensaio insere eventos reais copiados (payload anonimizado) 2× → 1 processamento; carrinho abandonado cria negócio no funil hotmart; APPROVED fecha ganho; reembolso marca; erro dentro do processamento **não** impede o insert em `cs.hotmart_eventos` | `hotmart_ligado=false` (trigger sai na 1ª linha) |
| **F4 WhatsApp** | `numero_whatsapp`, `template`, `mensagem`, `conversa`, `supressao`, Edges `crm-whatsapp-webhook`/`crm-whatsapp-enviar`, fichas e destinatários | F3 aplicada; provedor decidido (D3); segredo no Vault | inbound duplicado = 1 mensagem; status fora de ordem não regride; janela 24 h; opt-out; HTTP 200 do provedor ≠ sucesso: conferir `status` real | `whatsapp_ligado=false` |
| **F5 AC/SendFlow/Respondi/Manychat** | `integracao_evento`, webhooks AC/Manychat, trigger em `respondi.respostas`, fontes na jornada | F4 aplicada; mudança da `ingest-active` combinada | unsubscribe do AC vira supressão; resposta MQL cria negócio 1×; SendFlow só anexa por `fone_key` único | flag por fonte |
| **F6 Clint** | `clint_import`, `clint_mapa_etapa`, `importar_clint`, migração da fila ACELERA de `cs.contatos` (se D4 aprovar) | F2 aplicada; lote de teste com contagem conhecida | contagens por funil/etapa/dono batem; reimportar o mesmo lote = 0 novos | `clint_import_ligado=false`; arquivar `legado_origem='clint'` |
| **F7 MCP** | `mcp_token`, `mcp_uso`, núcleos `crm._*`, Edge `crm-mcp` | F2 aplicada | token revogado recusa; escopo `ler` não move etapa; vendedor via MCP não vê lead de outro; log com `autor_tipo='mcp'` | `mcp_ligado=false`; revogar tokens |

Ordem de dependência real: F0 → F1 → F2 → (F3 ∥ F5) → F4 → F6 → F7. Hotmart antes do WhatsApp porque é o gatilho
de dinheiro e já tem a fonte pronta.

---

## 7. Como trocar o front

`web/modules/comercial/ui/repositorio.ts`:

```ts
const FONTE = process.env.NEXT_PUBLIC_COMERCIAL_FONTE ?? 'mock';   // 'mock' | 'supabase'
export const repo: ComercialRepository =
  FONTE === 'supabase' ? new SupabaseComercialRepository(createBrowserSupabase()) : new MockComercialRepository();
export const MODO_DEMONSTRACAO = FONTE !== 'supabase';
```

`SupabaseComercialRepository` (em `infrastructure/`) só chama `db.rpc('crm_*')` e mapeia snake_case → tipos do
domínio. Nunca `.from()` (schema não exposto). `verComo` não é implementado (sessão vem do login).
Erro de RPC vira exceção (tela mostra erro), **nunca lista vazia**.

| Método do port | RPC / origem |
|---|---|
| `sessao()` | `crm_sessao()` → `{vendedorId: auth.uid(), papel}` |
| `vendedores()` | `crm_vendedores()` (vendedor + nome do perfil + papel derivado + percentual da distribuição geral) |
| `config()` | `crm_config()` |
| `agrupadores()`, `funis()` | `crm_agrupadores()`, `crm_funis()` (funil com etapas, campanhas e distribuição em jsonb, 1 chamada) |
| `motivosPerda()` | `crm_motivos_perda()` |
| `contatos()` | `crm_pessoas(p_busca, p_limite)` (paginado; hoje o port não pagina: adicionar parâmetro opcional) |
| `jornada(id)` | `crm_jornada(p_pessoa)` DEFINER: união por fonte com índice (hotmart_transacoes, cs.hotmart_eventos, lead_active, grupo_evento_unificado, respondi, cs.contatos, crm.*), `limit 500` |
| `negocios()` | `crm_negocios(p_funil, p_status)` com `proximaAtividade` por lateral |
| `atividades()` | `crm_atividades(p_desde, p_ate)` |
| `eventos(id?)` | `crm_eventos(p_pessoa, p_dia)` sobre `crm.vw_evento` |
| `conversas()`, `mensagens(id)`, `templates()` | `crm_conversas()`, `crm_mensagens(p_pessoa)`, `crm_templates()` |
| `filas()`, `fichas()`, `links()` | `crm_filas()`, `crm_fichas()`, `crm_links()` |
| escrita (todos) | `crm_<verbo>` da seção 4.3, devolvendo `{ok, msg, ...ids}` igual ao `Resultado` |
| `painel`, `salvarPainel` | `crm_painel(p_perfil)`, `crm_salvar_painel` |
| `notificacoes`, `marcarNotificacoesLidas` | `crm_notificacoes(p_limite)`, `crm_marcar_notificacoes_lidas(p_ids)` + assinatura Realtime |
| `preferenciasNotificacao`, `salvarPreferenciasNotificacao` | `crm_preferencias()`, `crm_salvar_preferencias` |
| `produtosHotmart`, `ofertas`, `ofertasOrfas`, `buscarPorLinkHotmart` | `crm_produtos_hotmart()`, `crm_ofertas(p_produto)`, `crm_ofertas_orfas()`, `crm_buscar_por_link(p_texto)` |
| `vincularProduto`, `salvarOferta` | `crm_vincular_produto`, `crm_salvar_oferta` |
| `dashboards`, `salvarDashboard`, `excluirDashboard` | `crm_dashboards()`, `crm_salvar_dashboard`, `crm_arquivar_dashboard` |
| `log(filtro)` | `crm_log(p_autor, p_entidade, p_entidade_id, p_pessoa, p_desde, p_ate, p_limite ≤ 500)` |
| **novo** `metrica(w)` | `crm_metrica(...)` |
| **novo** `desempenho(periodo)` | `crm_desempenho(p_desde, p_ate)` |

Ajustes de contrato a fazer junto da F1 (pequenos): `ProdutoKey` → `string` (linha do banco); `contatos()` paginado;
`Campanha.regraJson`; `chaveTelefone()` = regra de `controle.fone_key`; `excluirDashboard` passa a arquivar.
O mock ganha os mesmos ajustes para a demonstração continuar fiel.

---

## 8. Riscos e decisões (com recomendação)

| # | Decisão / risco | Quem | Recomendação |
|---|---|---|---|
| D1 | Casar aluno por e-mail × CPF. Medido: 341 alunos sem transação pelo e-mail, **33** casam só por CPF, 53 fora de `fin.identidade` | Marcio | **E-mail** como regra (manual). Os 33 viram `pessoa_sugestao` para o gestor unir por alias; CPF nunca entra no CRM |
| D2 | Chave de telefone: front usa 8 últimos dígitos; banco usa `controle.fone_key` (DDD + 8) | Arthur | Banco manda: front passa a `fone_key`. Telefone nunca funde sozinho quem tem e-mail diferente |
| D3 | Infobip × Unnichat para o WhatsApp oficial do comercial (Unnichat parado desde 08/09; Infobip sem dado por mensagem) | Marcio | Um provedor por número. Recomendo **Infobip** (API oficial, já tem conta e custo medido em `controle`); Unnichat só se for o provedor do número atual |
| D4 | `cs.contatos` (26.209, mini-CRM do CS) | Marcio + CS | **Coexistir**; CRM lê na jornada. Migrar só a fila ACELERA (1.944) e a carteira comercial (2 usuários) na F6 |
| D5 | Admin (18 perfis) = gestor do CRM? | Marcio | Sim para dev/admin (mesma régua de `gp_pode_editar`), mas **logado** com nome; se preferir, só `cargo='gestor'` + área comercial |
| D6 | Vendedor vê leads de colegas? | Jonathan/Marcio | **Não**: vê os seus + os sem dono (leitura). Ranking e totais do time via `crm_desempenho` (agregado) |
| D7 | Qual evento Hotmart é "cartão recusado" (`PURCHASE_CANCELED` 4,4/dia, `PURCHASE_DELAYED` 0,9/dia) | Arthur (olhar payload) | Conferir `payload->'data'->'purchase'->>'status'` numa amostra antes da F3; não inventar |
| D8 | Backfill Hotmart desde 15/07 | Arthur | Só jornada, sem negócio retroativo. Em 06/10/2026 a carga desde 01/01 criou 2.640 ganhos; o Victor decidiu tirá-los e compra direta deixou de criar ganho (`hotmart-sem-retroativo-2026-10-06.md`, migration 20261006191824) |
| D9 | Dono da WABA/número oficial: está na conta Clint? | Marcio | Descobrir antes da F4: se for da Clint, portar o número antes de desligar a Clint |
| D10 | Schema `crm` não exposto (front só por RPC) | Arthur | Sim (seção 2.1) |
| D11 | Mudança na `ingest-active` para múltiplas listas é de outro time e o código publicado não está neste repo | Arthur + marketing | Ler a versão publicada antes; mudança aditiva (`lista_id`), sem reescrever `lead_active` |
| R1 | `fin.identidade` recalculada toda hora (truncate de arestas + update de 68 mil nós): `pessoa_chave` muda | — | Nunca FK; ler por chave no momento. (Observação lateral: `update fin.identidade set calculado_em = now()` reescreve 68.204 linhas por hora; vale um skip no-op — card separado) |
| R2 | `compradores` é base de leads (91,4% sem compra) e não base de compradores | — | CRM não usa `compradores` como "cliente"; compra vem só de `fin.hotmart_transacoes` |
| R3 | Oferta nova vendida fora do catálogo vira órfã (12.194 históricas, 4 nos últimos 90 d) | gestor | Alerta diário de órfã nova; "catalogar no mesmo dia" vira tarefa do gestor na tela de produtos |
| R4 | `cs.usuarios` tem `senha_hash` e 8 usuários sem perfil | — | CRM não lê; não expor. Fora do escopo, registrar |
| R5 | Métricas calculadas no cliente com dado real | — | RPCs `crm_metrica`/`crm_desempenho` na F1 (2 métodos novos no port) |
| R6 | Trigger em tabela de outra equipe (`cs.hotmart_eventos`, `respondi.respostas`) | — | `exception when others` + kill-switch + combinar com o dono da tabela antes de aplicar |
