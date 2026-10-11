-- 20261011120000: planilha de mensageria puxando sozinha para mkt_mensageria.disparos (sync da planilha do ATM)
--
-- STATUS: ver 20261011120000.explain.md.
-- POR QUE: pedido do Victor (11/10/2026): "preciso q ao adicionar disparos e custos na planilha, puxe pro banco da forma
--   correta e va pro dash do atm". O custo do "3 AO CUBO" (API, 09/10, R$ 314,88) estava só na planilha
--   [SEMATM OUT/26] MENSAGERIA e o dashboard do ATM mostrava o custo sem ele. Não havia sync planilha → banco: o cron
--   antigo ingest-mensageria-hourly (controle-de-eventos, outra tabela) está desligado desde a 20261005o.
-- O QUE FAZ:
--   1. mkt_mensageria.planilhas: qual planilha alimenta qual projeto, a partir de que data, e o mapa de cada aba
--      (canal, ferramenta, coluna de cada campo e o texto esperado no cabeçalho). ativa = kill-switch.
--   2. mkt_mensageria.planilha_linhas: vínculo chave estável da linha → disparo. A chave é aba + data + hora + campanha
--      + lista (não o número da linha, que muda quando o time insere linha). Os CHECKs da disparos só deixam
--      origem_sistema/id_externo em origem 'api', por isso o vínculo mora em tabela própria.
--   3. mkt_mensageria.planilha_execucoes: uma linha por rodada, com o resumo e as recusas (aba, linha, motivo).
--   4. mkt_mensageria.planilha_sync_receber(planilha, abas): recebe as abas cruas (valores formatados) que a Edge
--      mensageria-planilha leu, confere o cabeçalho, filtra as linhas que valem, valida pela mesma regra da importação
--      da tela (mkt_mensageria.importar_linha) e grava: vínculo existente atualiza o mesmo disparo; disparo igual sem
--      vínculo (mesmo projeto, canal, data/hora e lista, origem manual/planilha) é ADOTADO; senão insere com origem
--      'planilha'. Célula vazia mantém o valor gravado. Linha que sumiu da planilha arquiva o disparo (nunca apaga);
--      se voltar, desarquiva.
--   5. Chave do Vault mkt_msg_planilha_chave (gerada no banco) e o job mensageria-planilha-sync a cada 10 min
--      (minutos 2,12,22...), pelo ops.cron_post, como os outros.
--   6. Disparo 40293 (ActiveCampaign, "SEMATMOUT -3 ao cubo 09/10", lista "SEM ATM - Base fria") ligado ao projeto 75.
-- REGRA DA LINHA QUE ENTRA: data >= planilhas.desde (e <= ate, se houver) E (STATUS começa com ENVIAD, ou ENVIADOS > 0,
--   ou custo > 0). Linha de planejamento sem nada disso não entra. ENVIADOS vazio grava tamanho_lista 0 (a coluna é
--   NOT NULL) e o próximo sync troca pelo número quando o time preencher.
-- AS 5 PERGUNTAS: escala = 1 planilha, ~90 linhas lidas, hoje 5 qualificadas; índice: PK (planilha_id, chave) e unique
--   (disparo_id); disparos por PK e por disparos_projeto_enviado_idx; frequência 144 rodadas/dia (1 leitura batchGet
--   do Google por rodada); repetição: upsert pela chave, rodar 2x não duplica (provado no ensaio); reversão:
--   20261011120000_reversao.sql (tira o job e a config; os disparos gravados ficam, rastreáveis pelo vínculo).
-- SEGURANÇA: nada novo em API. Tabelas e funções só para postgres (a Edge entra como postgres via SUPABASE_DB_URL,
--   igual à trafego-meta); revoke de public/anon/authenticated/service_role. A planilha não tem dado pessoal.
-- IDEMPOTENTE: create if not exists, insert on conflict do nothing, create or replace nas funções, cron.schedule com o
--   mesmo nome substitui o job, update do 40293 só se ainda sem projeto.

set local lock_timeout = '5s';
set local statement_timeout = '60s';

do $g$
begin
  if not exists (select 1 from mkt.projetos where id = 75 and sigla = 'ATMEL126') then
    raise exception '20261011120000: projeto 75 não é o ATMEL126';
  end if;
  if (select count(*) from mkt_mensageria.ferramentas where id in (1, 8, 10) and ativa) <> 3 then
    raise exception '20261011120000: ferramentas 1 (SendFlow), 8 (Infobip) e 10 (Ligue Lead) precisam existir ativas';
  end if;
  -- A validação reaproveitada: se mudar, a regra da planilha muda junto. Conferir antes de reaplicar.
  if (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.importar_linha(jsonb,integer)'::regprocedure)
     <> 'faa7f839e19cc281972c6d8c6ca7272d' then
    raise exception '20261011120000: mkt_mensageria.importar_linha mudou desde 11/10/2026; reler antes de aplicar';
  end if;
  if to_regprocedure('vault.create_secret(text,text,text,uuid)') is null
     or to_regprocedure('extensions.gen_random_bytes(integer)') is null then
    raise exception '20261011120000: vault.create_secret / extensions.gen_random_bytes ausente';
  end if;
  if not exists (select 1 from mkt_mensageria.disparos
                  where id = 40293 and canal = 'email' and origem = 'api' and origem_sistema = 'activecampaign'
                    and campanha = 'SEMATMOUT -3 ao cubo 09/10' and (projeto_id is null or projeto_id = 75)) then
    raise exception '20261011120000: disparo 40293 não está como medido em 11/10 (e-mail AC sem projeto)';
  end if;
end
$g$;

-- 1. Configuração ----------------------------------------------------------------------------------------------------
create table if not exists mkt_mensageria.planilhas (
  id          bigint generated always as identity primary key,
  planilha_id text not null unique check (planilha_id ~ '^[A-Za-z0-9_-]{20,100}$'),
  nome        text not null check (length(btrim(nome)) between 1 and 200),
  projeto_id  bigint not null references mkt.projetos(id) on delete restrict,
  desde       date not null,
  ate         date,
  abas        jsonb not null check (jsonb_typeof(abas) = 'array'),
  ativa       boolean not null,
  criado_em   timestamptz not null default now(),
  constraint planilhas_periodo check (ate is null or ate >= desde)
);
comment on table mkt_mensageria.planilhas is
  'Planilha de mensageria que alimenta disparos de um projeto (20261011120000). ativa = kill-switch do sync. abas: '
  '[{aba, canal, ferramenta_id, cabecalho_linha, colunas{campo: letra}, cabecalho{letra: texto esperado}}].';

-- 2. Vínculo linha da planilha → disparo -------------------------------------------------------------------------------
create table if not exists mkt_mensageria.planilha_linhas (
  planilha_id bigint not null references mkt_mensageria.planilhas(id) on delete restrict,
  chave       text not null check (length(chave) between 1 and 700),
  aba         text not null check (length(aba) between 1 and 100),
  disparo_id  bigint not null unique references mkt_mensageria.disparos(id) on delete restrict,
  linha       integer,
  visto_em    timestamptz not null,
  primary key (planilha_id, chave)
);

-- 3. Registro de cada rodada --------------------------------------------------------------------------------------------
create table if not exists mkt_mensageria.planilha_execucoes (
  id          bigint generated always as identity primary key,
  planilha_id bigint not null references mkt_mensageria.planilhas(id) on delete restrict,
  em          timestamptz not null default now(),
  ok          boolean not null,
  resumo      jsonb not null,
  erro        text check (erro is null or length(erro) <= 500)
);
create index if not exists planilha_execucoes_em_idx on mkt_mensageria.planilha_execucoes (planilha_id, em desc);

alter table mkt_mensageria.planilhas enable row level security;
alter table mkt_mensageria.planilha_linhas enable row level security;
alter table mkt_mensageria.planilha_execucoes enable row level security;
revoke all on mkt_mensageria.planilhas, mkt_mensageria.planilha_linhas, mkt_mensageria.planilha_execucoes
  from public, anon, authenticated, service_role;

-- 4. Funções -------------------------------------------------------------------------------------------------------------
-- Letra da coluna (A, X, AC) → posição 0-based no array de valores.
create or replace function mkt_mensageria.planilha_coluna(p_letra text) returns integer
language sql immutable set search_path = '' as $$
  select case when p_letra ~ '^[A-Z]{1,2}$' then
    (select sum((ascii(substr(p_letra, i, 1)) - 64) * power(26, length(p_letra) - i))::int
       from generate_series(1, length(p_letra)) i) - 1 end;
$$;

-- "18:50", "18:35h", "19h58", "12h", "9h" → "HH:MM". Outro formato ("-", vazio) → null.
create or replace function mkt_mensageria.planilha_hora(p text) returns text
language sql immutable set search_path = '' as $$
  select case when m is not null and m[1]::int < 24 and coalesce(m[2], '00')::int < 60
              then lpad(m[1], 2, '0') || ':' || coalesce(m[2], '00') end
    from (select regexp_match(lower(btrim(coalesce(p, ''))), '^([0-9]{1,2})\s*[h:]\s*([0-9]{2})?\s*h?$') as m) t;
$$;

-- Texto de cabeçalho comparável: sem acento, maiúsculas, espaços e quebras de linha num espaço só.
create or replace function mkt_mensageria.planilha_texto(p text) returns text
language sql immutable set search_path = '' as $$
  select upper(mkt.sem_acento(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g'))));
$$;

create or replace function mkt_mensageria.planilha_sync_chave() returns text
language sql stable set search_path = '' as $$
  select decrypted_secret from vault.decrypted_secrets where name = 'mkt_msg_planilha_chave';
$$;

-- O que a Edge precisa ler: planilhas ativas e o nome de cada aba.
create or replace function mkt_mensageria.planilha_sync_config() returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'planilha_id', p.planilha_id, 'nome', p.nome,
           'abas', (select jsonb_agg(a ->> 'aba') from jsonb_array_elements(p.abas) a)) order by p.id), '[]'::jsonb)
    from mkt_mensageria.planilhas p where p.ativa;
$$;

-- p_abas: [{aba, valores: [[...], ...]} | {aba, erro}]. valores = a aba inteira (valores formatados), da linha 1.
create or replace function mkt_mensageria.planilha_sync_receber(p_planilha bigint, p_abas jsonb) returns jsonb
language plpgsql set search_path = '' as $$
declare
  c_motivo constant text := 'Sync da planilha: a linha saiu da planilha ou deixou de valer';
  c_max_poda constant int := 5;
  -- Tetos contra colagem errada ou abuso de quem edita a planilha (achado MÉDIO 1 do pentester, 11/10/2026):
  -- mais de 20 disparos novos numa aba de uma vez suspende a aba inteira na rodada; custo acima de R$ 50.000,00
  -- numa linha é recusado (o maior lançado até hoje no ATM é R$ 1.032,08).
  c_max_ins constant int := 20;
  c_max_custo constant bigint := 5000000;
  p mkt_mensageria.planilhas;
  v_sigla text;
  v_cfg jsonb;
  v_aba jsonb;
  v_nome text;
  v_ferr text;
  v_hdr int;
  v_vals jsonb;
  v_cab_ok boolean;
  v_row jsonb;
  v_n int;
  v_get jsonb;
  v_data text; v_hora text; v_status text; v_tam text; v_custo text; v_camp text; v_lista text; v_copy text; v_link text;
  v_dia date;
  v_chave text;
  v_chaves text[];
  v_r jsonb;
  v_v jsonb;
  v_id bigint;
  v_d mkt_mensageria.disparos;
  v_upd int;
  v_poda bigint[];
  v_abas_res jsonb := '[]'::jsonb;
  v_recusas jsonb := '[]'::jsonb;
  v_lidas int := 0; v_qualif int := 0; v_ins int := 0; v_ado int := 0; v_atu int := 0; v_inal int := 0;
  v_desarq int := 0; v_arq int := 0; v_ign int := 0;
  v_ins_aba int;
  v_salvo int[];
  v_recusas_salvo jsonb;
  v_ok boolean := true;
  v_erro text;
  v_resumo jsonb;
begin
  select * into p from mkt_mensageria.planilhas where id = p_planilha;
  if p.id is null then raise exception 'planilha % não cadastrada', p_planilha; end if;
  if not p.ativa then return jsonb_build_object('ok', true, 'desligada', true); end if;
  perform pg_advisory_xact_lock(hashtext('mkt_mensageria.planilha_sync'), p.id::int);
  perform set_config('mkt_mensageria.autor_api', 'api:planilha', true);
  select pr.sigla into v_sigla from mkt.projetos pr where pr.id = p.projeto_id;

  for v_cfg in select * from jsonb_array_elements(p.abas) loop
    v_nome := v_cfg ->> 'aba';
    select a into v_aba from jsonb_array_elements(coalesce(p_abas, '[]'::jsonb)) a where a ->> 'aba' = v_nome limit 1;
    v_hdr := coalesce((v_cfg ->> 'cabecalho_linha')::int, 1);
    v_vals := v_aba -> 'valores';
    -- Cabeçalho tem de bater coluna a coluna: se o time mexer no layout, a aba para (e não poda) até alguém ajustar o
    -- mapa. Foi o deslocamento de colunas que zerou a aba API do CNHF em 13/08/2026 no ingest antigo.
    v_cab_ok := v_aba is not null and v_aba ? 'valores' and jsonb_typeof(v_vals) = 'array'
                and jsonb_array_length(v_vals) >= v_hdr
                and not exists (select 1 from jsonb_each_text(v_cfg -> 'cabecalho') h
                                 where mkt_mensageria.planilha_texto(v_vals -> (v_hdr - 1) ->> mkt_mensageria.planilha_coluna(h.key))
                                       is distinct from mkt_mensageria.planilha_texto(h.value));
    if not v_cab_ok then
      v_ok := false;
      v_abas_res := v_abas_res || jsonb_build_object('aba', v_nome, 'cabecalho_ok', false,
                      'erro', coalesce(left(v_aba ->> 'erro', 200), case when v_aba is null then 'aba não veio' else 'cabeçalho diferente do mapa' end));
      continue;
    end if;
    select f.nome into v_ferr from mkt_mensageria.ferramentas f where f.id = (v_cfg ->> 'ferramenta_id')::bigint;
    v_chaves := '{}';
    v_ins_aba := 0;
    v_salvo := array[v_lidas, v_qualif, v_ins, v_ado, v_atu, v_inal, v_desarq, v_ign];
    v_recusas_salvo := v_recusas;

    begin  -- bloco da aba: estourou o teto de inserções, tudo desta aba nesta rodada é desfeito
    for v_row, v_n in select r, n::int from jsonb_array_elements(v_vals) with ordinality t(r, n) where n > v_hdr loop
      v_lidas := v_lidas + 1;
      -- Valor da célula pelo campo do mapa (null se o campo não está no mapa ou a célula não veio).
      v_get := (select coalesce(jsonb_object_agg(c.key, nullif(btrim(v_row ->> mkt_mensageria.planilha_coluna(c.value)), '')), '{}'::jsonb)
                  from jsonb_each_text(v_cfg -> 'colunas') c);
      v_data := v_get ->> 'data'; v_status := mkt_mensageria.planilha_texto(v_get ->> 'status');
      v_tam := v_get ->> 'tamanho_lista'; v_custo := v_get ->> 'custo';
      v_dia := case when v_data ~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$'
                    then (select make_date(m[3]::int, m[2]::int, m[1]::int) from regexp_match(v_data, '^([0-9]+)/([0-9]+)/([0-9]+)$') m) end;
      -- Regra da linha que entra.
      if v_dia is null or v_dia < p.desde or (p.ate is not null and v_dia > p.ate)
         or not (v_status like 'ENVIAD%'
                 or coalesce(mkt_mensageria.inteiro_br(v_tam), 0) > 0
                 or coalesce(mkt_mensageria.centavos_br(v_custo), 0) > 0) then
        v_ign := v_ign + 1;
        continue;
      end if;
      v_qualif := v_qualif + 1;
      v_hora := coalesce(mkt_mensageria.planilha_hora(v_get ->> 'hora'), v_get ->> 'hora');
      v_camp := left(v_get ->> 'campanha', 300);
      v_lista := v_get ->> 'lista';
      v_link := v_get ->> 'link';
      -- "copy" é o texto-modelo que a planilha traz na coluna COPY UTILIZADA: não é copy.
      v_copy := case when lower(coalesce(v_get ->> 'copy', '')) in ('', 'copy') then null else v_get ->> 'copy' end;
      v_chave := v_nome || '|' || btrim(v_data) || '|' || coalesce(v_hora, '') || '|'
                 || mkt_mensageria.planilha_texto(v_camp) || '|' || mkt_mensageria.planilha_texto(v_lista);
      -- Duas linhas iguais na mesma aba: a 2ª vira chave#2 (na ordem da planilha).
      if v_chave = any(v_chaves) then
        v_chave := v_chave || '#' || (select count(*) + 1 from unnest(v_chaves) k
                                          where k = v_chave or left(k, length(v_chave) + 1) = v_chave || '#');
      end if;
      v_chaves := array_append(v_chaves, v_chave);

      begin
        v_r := mkt_mensageria.importar_linha(jsonb_build_object(
          'data', v_data, 'hora', v_hora, 'ferramenta', v_ferr, 'canal', v_cfg ->> 'canal', 'tipo', v_get ->> 'tipo',
          'projeto', v_sigla, 'copy_texto', v_copy, 'copy_link', v_link, 'publico_lista', v_lista,
          'tamanho_lista', coalesce(v_tam, '0'), 'entregues', v_get ->> 'entregues', 'lidas', v_get ->> 'lidas',
          'cliques', v_get ->> 'cliques', 'falhas', v_get ->> 'falhas', 'custo', v_custo,
          'disparado_por', 'planilha mensageria'), v_n);
        if jsonb_typeof(v_r -> 'v') <> 'object' then
          v_recusas := v_recusas || jsonb_build_object('aba', v_nome, 'linha', v_n,
                         'motivo', (select string_agg(e ->> 'campo' || ': ' || (e ->> 'msg'), '; ') from jsonb_array_elements(v_r -> 'erros') e));
          continue;
        end if;
        v_v := v_r -> 'v';
        if (v_v ->> 'custo_centavos')::bigint > c_max_custo then
          v_recusas := v_recusas || jsonb_build_object('aba', v_nome, 'linha', v_n,
                         'motivo', 'custo acima de R$ 50.000,00 numa linha: conferir na planilha');
          continue;
        end if;

        select pl.disparo_id into v_id from mkt_mensageria.planilha_linhas pl where pl.planilha_id = p.id and pl.chave = v_chave;
        if v_id is null then
          -- Adoção: o mesmo disparo já lançado à mão ou por importação, ainda sem vínculo.
          select d.id into v_id from mkt_mensageria.disparos d
           where d.projeto_id = p.projeto_id and d.canal = v_v ->> 'canal'
             and d.enviado_em = (v_v ->> 'enviado_em')::timestamptz and d.publico_lista = v_v ->> 'publico_lista'
             and d.origem in ('manual', 'planilha') and d.arquivado_em is null and d.anonimizado_em is null
             and not exists (select 1 from mkt_mensageria.planilha_linhas x where x.disparo_id = d.id)
           order by d.id limit 1;
          if v_id is not null then
            insert into mkt_mensageria.planilha_linhas (planilha_id, chave, aba, disparo_id, linha, visto_em)
            values (p.id, v_chave, v_nome, v_id, v_n, now());
            v_ado := v_ado + 1;
          else
            insert into mkt_mensageria.disparos (enviado_em, projeto_id, canal, ferramenta_id, tipo, copy_texto, copy_link,
                   publico_lista, tamanho_lista, entregues, lidas, cliques, falhas, custo_centavos, disparado_por,
                   retorno_em, origem, campanha)
            values ((v_v ->> 'enviado_em')::timestamptz, p.projeto_id, v_v ->> 'canal', (v_v ->> 'ferramenta_id')::bigint,
                    v_v ->> 'tipo', v_v ->> 'copy_texto', v_v ->> 'copy_link', v_v ->> 'publico_lista',
                    (v_v ->> 'tamanho_lista')::int, (v_v ->> 'entregues')::int, (v_v ->> 'lidas')::int,
                    (v_v ->> 'cliques')::int, (v_v ->> 'falhas')::int, (v_v ->> 'custo_centavos')::int, v_v ->> 'disparado_por',
                    case when coalesce(v_v ->> 'entregues', v_v ->> 'lidas', v_v ->> 'cliques', v_v ->> 'falhas',
                                       v_v ->> 'custo_centavos') is not null then now() end,
                    'planilha', v_camp)
            returning id into v_id;
            insert into mkt_mensageria.planilha_linhas (planilha_id, chave, aba, disparo_id, linha, visto_em)
            values (p.id, v_chave, v_nome, v_id, v_n, now());
            v_ins := v_ins + 1;
            v_ins_aba := v_ins_aba + 1;
            if v_ins_aba > c_max_ins then raise exception 'mkt_planilha_limite_insercao'; end if;
            continue;
          end if;
        end if;

        select * into v_d from mkt_mensageria.disparos where id = v_id for update;
        update mkt_mensageria.planilha_linhas set linha = v_n, visto_em = now() where planilha_id = p.id and chave = v_chave;
        if v_d.anonimizado_em is not null or (v_d.arquivado_em is not null and v_d.arquivado_motivo <> c_motivo) then
          v_inal := v_inal + 1;   -- anonimizado ou arquivado por alguém: o sync não mexe
          continue;
        end if;
        if v_d.arquivado_em is not null then v_desarq := v_desarq + 1; end if;
        -- Célula vazia mantém o gravado; preenchida vence (a planilha é a fonte destes disparos).
        update mkt_mensageria.disparos d set
               arquivado_em = null, arquivado_motivo = null,
               campanha = coalesce(v_camp, d.campanha),
               tipo = coalesce(v_v ->> 'tipo', d.tipo),
               copy_texto = coalesce(v_v ->> 'copy_texto', d.copy_texto),
               copy_link = coalesce(v_v ->> 'copy_link', d.copy_link),
               tamanho_lista = coalesce(case when v_tam is not null then (v_v ->> 'tamanho_lista')::int end, d.tamanho_lista),
               entregues = coalesce((v_v ->> 'entregues')::int, d.entregues),
               lidas = coalesce((v_v ->> 'lidas')::int, d.lidas),
               cliques = coalesce((v_v ->> 'cliques')::int, d.cliques),
               falhas = coalesce((v_v ->> 'falhas')::int, d.falhas),
               custo_centavos = coalesce((v_v ->> 'custo_centavos')::int, d.custo_centavos),
               retorno_em = coalesce(d.retorno_em,
                              case when coalesce(v_v ->> 'entregues', v_v ->> 'lidas', v_v ->> 'cliques', v_v ->> 'falhas',
                                                 v_v ->> 'custo_centavos') is not null then now() end)
         where d.id = v_id
           and (d.arquivado_em, d.campanha, d.tipo, d.copy_texto, d.copy_link, d.tamanho_lista, d.entregues, d.lidas,
                d.cliques, d.falhas, d.custo_centavos)
               is distinct from
               (null::timestamptz, coalesce(v_camp, d.campanha), coalesce(v_v ->> 'tipo', d.tipo),
                coalesce(v_v ->> 'copy_texto', d.copy_texto), coalesce(v_v ->> 'copy_link', d.copy_link),
                coalesce(case when v_tam is not null then (v_v ->> 'tamanho_lista')::int end, d.tamanho_lista),
                coalesce((v_v ->> 'entregues')::int, d.entregues), coalesce((v_v ->> 'lidas')::int, d.lidas),
                coalesce((v_v ->> 'cliques')::int, d.cliques), coalesce((v_v ->> 'falhas')::int, d.falhas),
                coalesce((v_v ->> 'custo_centavos')::int, d.custo_centavos));
        get diagnostics v_upd = row_count;
        if v_upd > 0 then v_atu := v_atu + 1; else v_inal := v_inal + 1; end if;
      exception when others then
        if sqlerrm = 'mkt_planilha_limite_insercao' then raise; end if;
        v_recusas := v_recusas || jsonb_build_object('aba', v_nome, 'linha', v_n, 'motivo', left(sqlerrm, 200));
      end;
    end loop;

    -- Poda: disparo vinculado a esta aba cuja linha não veio mais (ou deixou de valer) vai para o arquivo.
    select coalesce(array_agg(pl.disparo_id), '{}') into v_poda
      from mkt_mensageria.planilha_linhas pl join mkt_mensageria.disparos d on d.id = pl.disparo_id
     where pl.planilha_id = p.id and pl.aba = v_nome and not (pl.chave = any(v_chaves))
       and d.arquivado_em is null and d.anonimizado_em is null;
    if cardinality(v_poda) > c_max_poda then
      -- Muitas de uma vez parece leitura quebrada, não decisão do time: não arquiva e acusa.
      v_ok := false;
      v_abas_res := v_abas_res || jsonb_build_object('aba', v_nome, 'cabecalho_ok', true,
                      'erro', 'poda suspensa: ' || cardinality(v_poda) || ' disparos sairiam de uma vez (limite ' || c_max_poda || ')');
    else
      update mkt_mensageria.disparos set arquivado_em = now(), arquivado_motivo = c_motivo where id = any(v_poda);
      v_arq := v_arq + cardinality(v_poda);
      v_abas_res := v_abas_res || jsonb_build_object('aba', v_nome, 'cabecalho_ok', true, 'arquivados', cardinality(v_poda));
    end if;
    exception when raise_exception then
      if sqlerrm <> 'mkt_planilha_limite_insercao' then raise; end if;
      select v_salvo[1], v_salvo[2], v_salvo[3], v_salvo[4], v_salvo[5], v_salvo[6], v_salvo[7], v_salvo[8]
        into v_lidas, v_qualif, v_ins, v_ado, v_atu, v_inal, v_desarq, v_ign;
      v_recusas := v_recusas_salvo;
      v_ok := false;
      v_abas_res := v_abas_res || jsonb_build_object('aba', v_nome, 'cabecalho_ok', true,
                      'erro', 'aba suspensa: mais de ' || c_max_ins || ' disparos novos de uma vez; nada desta aba foi gravado');
    end;
  end loop;

  v_erro := (select left(string_agg((a ->> 'aba') || ': ' || (a ->> 'erro'), '; '), 500)
               from jsonb_array_elements(v_abas_res) a where a ? 'erro');
  v_resumo := jsonb_build_object('lidas', v_lidas, 'ignoradas', v_ign, 'qualificadas', v_qualif, 'inseridos', v_ins,
                'adotados', v_ado, 'atualizados', v_atu, 'inalterados', v_inal, 'desarquivados', v_desarq,
                'arquivados', v_arq, 'recusadas', jsonb_array_length(v_recusas),
                'recusas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_recusas) x limit 100) s),
                'abas', v_abas_res);
  insert into mkt_mensageria.planilha_execucoes (planilha_id, ok, resumo, erro) values (p.id, v_ok, v_resumo, v_erro);
  return jsonb_build_object('ok', v_ok, 'planilha', p.nome) || v_resumo;
end
$$;

revoke all on function mkt_mensageria.planilha_coluna(text), mkt_mensageria.planilha_hora(text),
  mkt_mensageria.planilha_texto(text), mkt_mensageria.planilha_sync_chave(), mkt_mensageria.planilha_sync_config(),
  mkt_mensageria.planilha_sync_receber(bigint, jsonb)
  from public, anon, authenticated, service_role;

-- 5. Planilha do ATM OUT/26 ---------------------------------------------------------------------------------------------
-- Abas: API (Infobip, como o lançamento 40087), GRUPO (SendFlow), SMS e LIGAÇÃO (Ligue Lead, a ferramenta de SMS da
-- tabela de preços e de voz no ingest antigo). EMAIIL fica de fora: o e-mail do ATM já chega pela integração do
-- ActiveCampaign (fonte activecampaign) e entraria em dobro.
insert into mkt_mensageria.planilhas (planilha_id, nome, projeto_id, desde, ate, abas, ativa)
values ('16OpTLTYBTlfaZZx93O6w-XUpQHhqOWIlWagTwiwqhP0', '[SEMATM OUT/26] MENSAGERIA', 75, date '2026-10-07', null, $j$[
  {"aba": "API", "canal": "whatsapp_api", "ferramenta_id": 8, "cabecalho_linha": 1,
   "colunas": {"data": "B", "hora": "C", "campanha": "D", "link": "E", "lista": "F", "copy": "G", "status": "J",
               "tamanho_lista": "K", "lidas": "L", "cliques": "P", "falhas": "R", "tipo": "T", "custo": "X"},
   "cabecalho": {"B": "DATA", "C": "HORÁRIO", "D": "EVENTO/CAMPANHA", "E": "LINKS", "F": "LISTA/SEGMENTO",
                 "G": "COPY UTILIZADA", "J": "STATUS", "K": "ENVIADOS", "L": "LIDAS", "P": "CLIQUES", "R": "FALHAS",
                 "T": "TIPO", "X": "Custo (R$)"}},
  {"aba": "GRUPO", "canal": "grupo", "ferramenta_id": 1, "cabecalho_linha": 1,
   "colunas": {"data": "B", "hora": "C", "campanha": "D", "link": "E", "copy": "F", "lista": "G", "status": "I",
               "tamanho_lista": "J", "entregues": "K", "lidas": "M", "cliques": "O", "falhas": "Q"},
   "cabecalho": {"B": "DATA DO ENVIO", "C": "HORA DO ENVIO", "D": "ASSUNTO", "E": "LINK", "F": "COPY", "G": "GRUPO",
                 "I": "STATUS", "J": "ENVIADOS", "K": "ENTREGUES", "M": "ABERTOS", "O": "CLIQUES", "Q": "FALHAS"}},
  {"aba": "SMS", "canal": "sms", "ferramenta_id": 10, "cabecalho_linha": 1,
   "colunas": {"data": "B", "hora": "C", "link": "D", "lista": "E", "campanha": "F", "copy": "F", "status": "I",
               "tamanho_lista": "J", "entregues": "K", "cliques": "O", "falhas": "Q", "custo": "V"},
   "cabecalho": {"B": "DATA", "C": "HORÁRIO", "D": "LINK", "E": "LISTA/SEGMENTO", "F": "COPY UTILIZADA", "I": "STATUS",
                 "J": "ENVIADOS", "K": "ENTREGUES", "O": "CLIQUES", "Q": "FALHAS", "V": "Custo (R$)"}},
  {"aba": "LIGAÇÃO", "canal": "ligacao", "ferramenta_id": 10, "cabecalho_linha": 1,
   "colunas": {"data": "B", "hora": "C", "campanha": "D", "link": "E", "lista": "F", "copy": "G", "status": "J",
               "tamanho_lista": "K", "entregues": "L", "cliques": "P", "falhas": "R", "custo": "X"},
   "cabecalho": {"B": "DATA", "C": "HORÁRIO", "D": "EVENTO/CAMPANHA", "E": "LINK", "F": "LISTA/SEGMENTO",
                 "G": "COPY UTILIZADA", "J": "STATUS", "K": "ENVIADOS", "L": "ENTREGUES", "P": "CLIQUES", "R": "FALHAS",
                 "X": "Custo (R$)"}}
]$j$::jsonb, true)
on conflict (planilha_id) do nothing;

-- 6. Chave do Edge e job ------------------------------------------------------------------------------------------------
do $v$
begin
  if not exists (select 1 from vault.secrets where name = 'mkt_msg_planilha_chave') then
    perform vault.create_secret(encode(extensions.gen_random_bytes(32), 'hex'), 'mkt_msg_planilha_chave',
                                'Chave do cron para a Edge mensageria-planilha (20261011120000; gerada no banco)');
  end if;
end
$v$;

select cron.schedule('mensageria-planilha-sync', '2-59/10 * * * *', $c$
  select ops.cron_post('mensageria-planilha-sync',
    url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/mensageria-planilha',
    body := '{}'::jsonb,
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-sync-chave', (select decrypted_secret from vault.decrypted_secrets where name = 'mkt_msg_planilha_chave')),
    timeout_milliseconds := 60000)
$c$);

-- 7. E-mail do "3 ao cubo" no ATM ----------------------------------------------------------------------------------------
-- A integração do ActiveCampaign gravou sem projeto (a campanha não tem [SIGLA]). Nome e lista são do ATM OUT/26.
update mkt_mensageria.disparos set projeto_id = 75
 where id = 40293 and projeto_id is null and campanha = 'SEMATMOUT -3 ao cubo 09/10';

do $c$
begin
  if not exists (select 1 from cron.job where jobname = 'mensageria-planilha-sync' and active and schedule = '2-59/10 * * * *') then
    raise exception '20261011120000: job não ficou agendado';
  end if;
  if not exists (select 1 from mkt_mensageria.disparos where id = 40293 and projeto_id = 75) then
    raise exception '20261011120000: 40293 não ficou no projeto 75';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'mkt_mensageria' and p.proname like 'planilha%'
                and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute')
                     or has_function_privilege('service_role', p.oid, 'execute'))) then
    raise exception '20261011120000: função planilha_* executável fora do postgres';
  end if;
end
$c$;
