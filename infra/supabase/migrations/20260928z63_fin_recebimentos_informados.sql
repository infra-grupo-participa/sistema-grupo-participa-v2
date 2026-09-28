-- 20260928z63 — Contas a Receber, fatia 3: RECEBIMENTOS INFORMADOS (bloco 5 da planilha semanal).
--
-- NÃO APLICADA — coordenador aplica (apply_migration "fin_recebimentos_informados"). Provas no fim, por medir.
-- Depende da z60 e da z61 (aplicadas). A guarda aborta se o corpo VIVO de public.fn_fin_receber_semanal não for o da z61.
-- z62 fica reservada (releitura do espelho, juan).
--
-- Contrato: scratchpad "contrato-bloco5.md" (28/09). A tela do iromar depende dele. Desvios: ver o relatório do Victor.
--
-- O que cria:
--   1) fin.recebimentos_informados — previsão de recebimento que a Hotmart ainda não mostra (renovação Diamante/Aurum,
--      extras do Serviço Diamante, outros). Nada se apaga (trigger barra DELETE/TRUNCATE): arquiva com motivo.
--      Identificador guardado como 'd:<dígitos CPF/CNPJ>' ou 'e:<e-mail minúsculo>' — NUNCA a pessoa_chave (muda a
--      cada recálculo da identidade). produtos chega como NOME digitado pelo Financeiro; é resolvido (sem caixa e sem
--      acento, contra fin.produtos e o nome atual no espelho) para EXATAMENTE 1 produto → produto_ids (a baixa casa
--      pelo código, nunca por nome) e produtos = nomes oficiais. 0 ou 2+ produtos = erro na linha.
--   2) fin.recebimentos_informados_historico — só acréscimo (acao, antes, depois, por, em), por trigger AFTER INSERT/UPDATE.
--   3) Internas (sem grant): fin.informado_mascara, fin.informado_data, fin.informado_chave_nome,
--      fin.informados_catalogo, fin.informado_identificador,
--      fin.informado_normalizar, fin.informados_alvos, fin.informados_situacao(corte), fin.informados_cobertura(corte).
--   4) RPCs (SECURITY DEFINER, search_path '', revoke public/anon, grant authenticated):
--        fn_fin_informados_listar()                              leitura  (gp_pode_ver_financeiro)
--        fn_fin_informado_salvar(jsonb) → uuid                   escrita  (gp_pode_operar_financeiro)
--        fn_fin_informado_baixar(uuid, date)                     escrita
--        fn_fin_informado_arquivar(uuid, text)                   escrita
--        fn_fin_informados_importar(jsonb, boolean default true) escrita  (simular = prévia; senão tudo ou nada; ≤ 500)
--   5) public.fn_fin_receber_semanal — MESMA assinatura e MESMO RETURNS TABLE da z61; ganha:
--        bloco 5 (grupo 'Renovações Diamante' | 'Renovações Aurum' | 'Serviço Diamante extras' |
--                 'Outros recebimentos informados'; ref = id do informado; rotulo = cliente; produto = produtos[1]);
--        bloco 2: cobrança do mesmo contrato (e-mail|oferta) de uma pessoa+produto com informado, com vencimento dentro
--                 do acordo → situacao 'coberta_informado', componente 'cheio', FORA da soma (conflito 6 do plano).
--   6) Premissa 'informados_no_receber' = 1 em fin.premissas_receber: 0 desliga bloco 5 e cobertura, sem deploy.
--
-- Regra da situação (fin.informados_situacao):
--   identificador → fin.identidade → todos os e-mails da pessoa (+ e-mail direto; + documento direto se não estiver na
--   identidade nem em fin.identidade_revisao) → transações PAGAS (APPROVED/COMPLETE, aprovadas até o corte) dos produtos
--   desde acordo_desde; recebido = soma do LÍQUIDO (fin.vw_transacoes.liquido — mesma base de fin.recebimento).
--   acumulado = soma das linhas vivas do mesmo identificador1 + produtos + acordo_desde com data_prevista ≤ a da linha.
--   ordem: arquivado → baixa manual ('baixado_fora') → via Hotmart e recebido ≥ acumulado × (1 − tolerancia_conciliacao)
--   ('realizado_hotmart') → data_prevista + tolerancia_atraso_dias < dia do corte ('em_atraso_cobrar') → 'a_receber'.
--   valor_provisionado = via Hotmart: min(valor, acumulado − recebido) (≥ 0); fora: valor; baixado/realizado/arquivado: 0.
--   caixa: via Hotmart → fin.recebimento(data efetiva, provisionado) (antecipação + garantia); fora → 'cheio' na data
--   efetiva. Data efetiva = greatest(data_prevista, dia do corte + 1).
--
-- REVERSÃO (uma transação; nada se apaga):
--   Desligar sem reverter:  insert into fin.premissas_receber (chave, vigente_de, valor, fonte)
--                           values ('informados_no_receber', current_date, 0, 'desligado: <motivo>');
--   Reverter de verdade:
--   begin;
--   -- a) recolocar o corpo da z61 em public.fn_fin_receber_semanal (20260928z61 linhas 259–293, create or replace;
--   --    a ACL é preservada pelo replace);
--   drop function public.fn_fin_informados_importar(jsonb, boolean);
--   drop function public.fn_fin_informado_arquivar(uuid, text);
--   drop function public.fn_fin_informado_baixar(uuid, date);
--   drop function public.fn_fin_informado_salvar(jsonb);
--   drop function public.fn_fin_informados_listar();
--   drop function fin.informados_cobertura(timestamptz);
--   drop function fin.informados_situacao(timestamptz);
--   drop function fin.informados_alvos();
--   drop function fin.informado_normalizar(jsonb, fin.recebimentos_informados, boolean);
--   drop function fin.informado_identificador(text, text[]);
--   drop function fin.informados_catalogo();
--   drop function fin.informado_chave_nome(text);
--   drop function fin.informado_data(text, text);
--   drop function fin.informado_mascara(text);
--   drop trigger informados_historico on fin.recebimentos_informados;
--   alter table fin.recebimentos_informados rename to recebimentos_informados_arquivada_z63;
--   alter table fin.recebimentos_informados_historico rename to recebimentos_informados_historico_arquivada_z63;
--   -- (os triggers anti-DELETE ficam: as tabelas arquivadas continuam sem apagar)
--   commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_oid oid := to_regprocedure('public.fn_fin_receber_semanal(timestamptz,date)');
  v_src text;
  v_res text;
  e_src text := $esperado$
#variable_conflict use_column
declare
  v_corte timestamptz := coalesce(p_corte, now());
  v_dia   date := (coalesce(p_corte, now()) at time zone 'America/Sao_Paulo')::date;
  v_ate   date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  return query
  select 1::smallint, 'Vendas já realizadas'::text, b.componente, b.data_caixa, b.valor, 'a_receber'::text,
         b.origem_dia, null::text, null::text, null::text, null::int, b.detalhe
    from fin.receber_vendas_realizadas(v_corte) b
  union all
  select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.situacao, c.vencimento,
         c.ref, c.rotulo, c.produto, c.k, null::jsonb
    from fin.cobrancas_previstas(v_corte, v_ate) c
    cross join lateral (
      select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.situacao = 'a_receber'
      union all
      select 'garantia'::text, c.libera_em, c.retido where c.situacao = 'a_receber'
      union all
      select 'cheio'::text, null::date, c.valor where c.situacao <> 'a_receber'
    ) u(componente, data_caixa, valor)
   order by 1, 4 nulls last, 2, 3;
end $esperado$;
  e_res text := 'TABLE(bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, '
             || 'origem_dia date, ref text, rotulo text, produto text, k integer, detalhe jsonb)';
begin
  if v_oid is null or to_regclass('fin.premissas_receber') is null
     or to_regprocedure('fin.cobrancas_previstas(timestamptz,date)') is null
     or to_regprocedure('fin.receber_vendas_realizadas(timestamptz)') is null then
    raise exception 'z63: aplicar a z61 antes (fn_fin_receber_semanal / premissas_receber / internas ausentes)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_receber_semanal' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'z63: há sobrecarga viva de fn_fin_receber_semanal — conferir pg_get_function_arguments';
  end if;
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_oid;
  if regexp_replace(regexp_replace(v_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(e_src, '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_res, '\s+', '', 'g') then
    raise exception 'z63: corpo vivo de fn_fin_receber_semanal diverge da z61. Já aplicada, ou alterada fora do repo? Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_oid and l.lanname = 'plpgsql' and p.provolatile = 's' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z63: atributos vivos de fn_fin_receber_semanal diferentes da z61 (plpgsql/stable/definer/search_path vazio)';
  end if;
  if to_regclass('fin.recebimentos_informados') is not null
     or to_regclass('fin.recebimentos_informados_historico') is not null
     or exists (select 1 from pg_proc
                 where (pronamespace = 'public'::regnamespace and proname like 'fn_fin_informad%')
                    or (pronamespace = 'fin'::regnamespace and proname like 'informad%')) then
    raise exception 'z63: já aplicada (tabela ou função de informados existe) — conferir antes';
  end if;
  if exists (select 1 from fin.premissas_receber where chave = 'informados_no_receber') then
    raise exception 'z63: premissa informados_no_receber já existe — z63 já aplicada?';
  end if;
  if to_regclass('fin.identidade') is null or to_regclass('fin.identidade_revisao') is null
     or to_regprocedure('fin.chave_opaca(text)') is null or to_regprocedure('public.gp_pode_ver_cpf()') is null then
    raise exception 'z63: fin.identidade / identidade_revisao / chave_opaca / gp_pode_ver_cpf ausente';
  end if;
end $guarda$;


-- ─── 1. Tabela e histórico ──────────────────────────────────────────────────────────────────────────────────────────
create table fin.recebimentos_informados (
  id               uuid primary key default gen_random_uuid(),
  data_prevista    date not null check (data_prevista between date '2020-01-01' and date '2036-12-31'),
  cliente          text not null check (btrim(cliente) <> '' and length(cliente) <= 200),
  tipo             text not null check (tipo in ('renovacao_diamante','renovacao_aurum','diamante_extra','outro')),
  valor            numeric(12,2) not null check (valor > 0),
  via_hotmart      boolean not null,
  produtos         text[] not null default '{}',   -- nomes oficiais (fin.produtos.nome), alinhados a produto_ids
  produto_ids      text[] not null default '{}',   -- códigos Hotmart resolvidos: a baixa automática casa por eles
  identificador1   text check (identificador1 ~ '^(d:([0-9]{11}|[0-9]{14})|e:[^@[:space:]]+@[^@[:space:]]+)$'),
  identificador2   text check (identificador2 ~ '^(d:([0-9]{11}|[0-9]{14})|e:[^@[:space:]]+@[^@[:space:]]+)$'),
  acordo_desde     date,
  baixa_manual_em  date,
  baixa_manual_por uuid,
  origem           text not null check (origem in ('manual','importacao')),
  criado_por       uuid,
  criado_em        timestamptz not null default now(),
  atualizado_por   uuid,
  atualizado_em    timestamptz not null default now(),
  arquivado_em     timestamptz,
  arquivado_por    uuid,
  motivo_arquivo   text,
  constraint recebimentos_informados_hotmart_ck
    check (not via_hotmart or (cardinality(produto_ids) >= 1 and acordo_desde is not null)),
  constraint recebimentos_informados_produtos_ck check (cardinality(produtos) = cardinality(produto_ids)),
  constraint recebimentos_informados_acordo_ck check (acordo_desde is null or acordo_desde <= data_prevista),
  constraint recebimentos_informados_arquivo_ck
    check ((arquivado_em is null) = (motivo_arquivo is null) and (motivo_arquivo is null or length(btrim(motivo_arquivo)) >= 3)),
  constraint recebimentos_informados_ids_ck check (identificador2 is null or identificador1 is not null)
);
comment on table fin.recebimentos_informados is
  'Contas a Receber bloco 5 (z63): recebimentos previstos informados pelo Financeiro. Não se apaga: arquiva. '
  'Escrita só pelas RPCs fn_fin_informado_*. identificador = d:<dígitos> | e:<e-mail>, nunca a pessoa_chave.';
alter table fin.recebimentos_informados enable row level security;   -- sem policy: só funções SECURITY DEFINER
revoke all on fin.recebimentos_informados from public, anon, authenticated;

create table fin.recebimentos_informados_historico (
  id            bigint generated always as identity primary key,
  informado_id  uuid not null references fin.recebimentos_informados (id),
  acao          text not null check (acao in ('criado','alterado','baixa','baixa_desfeita','arquivado')),
  antes         jsonb,
  depois        jsonb not null,
  por           uuid,
  em            timestamptz not null default now()
);
create index recebimentos_informados_historico_informado_idx
  on fin.recebimentos_informados_historico (informado_id, em);
comment on table fin.recebimentos_informados_historico is
  'Trilha só-acréscimo de fin.recebimentos_informados (z63). Gravada por trigger; UPDATE/DELETE/TRUNCATE barrados. '
  'Contém identificador em claro (CPF/e-mail): anonimização LGPD tem que passar por aqui também.';
alter table fin.recebimentos_informados_historico enable row level security;
revoke all on fin.recebimentos_informados_historico from public, anon, authenticated;
revoke all on sequence fin.recebimentos_informados_historico_id_seq from public, anon, authenticated;

create function fin.tg_informados_historico()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  insert into fin.recebimentos_informados_historico (informado_id, acao, antes, depois, por)
  values (new.id,
          case when tg_op = 'INSERT' then 'criado'
               when old.arquivado_em is null and new.arquivado_em is not null then 'arquivado'
               when old.baixa_manual_em is distinct from new.baixa_manual_em and new.baixa_manual_em is null then 'baixa_desfeita'
               when old.baixa_manual_em is distinct from new.baixa_manual_em then 'baixa'
               else 'alterado' end,
          case when tg_op = 'UPDATE' then to_jsonb(old) end,
          to_jsonb(new),
          coalesce((select auth.uid()), new.atualizado_por, new.criado_por));
  return null;
end $$;
revoke all on function fin.tg_informados_historico() from public, anon, authenticated;

create function fin.tg_informados_nao_apaga()
returns trigger
language plpgsql set search_path = ''
as $$
begin
  raise exception 'Recebimento informado não se apaga nem se reescreve a trilha: arquive (fn_fin_informado_arquivar).'
    using errcode = '42501';
end $$;
revoke all on function fin.tg_informados_nao_apaga() from public, anon, authenticated;

create trigger informados_historico after insert or update on fin.recebimentos_informados
  for each row execute function fin.tg_informados_historico();
create trigger informados_nao_apaga before delete on fin.recebimentos_informados
  for each row execute function fin.tg_informados_nao_apaga();
create trigger informados_nao_trunca before truncate on fin.recebimentos_informados
  for each statement execute function fin.tg_informados_nao_apaga();
create trigger informados_historico_so_acrescimo before update or delete on fin.recebimentos_informados_historico
  for each row execute function fin.tg_informados_nao_apaga();
create trigger informados_historico_nao_trunca before truncate on fin.recebimentos_informados_historico
  for each statement execute function fin.tg_informados_nao_apaga();


-- ─── 2. Premissa (kill-switch do bloco 5) ───────────────────────────────────────────────────────────────────────────
insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
  ('informados_no_receber', date '2000-01-01', 1,
   'z63: 1 = bloco 5 e cobertura do bloco 2 ligados; nova vigência com 0 desliga sem deploy');


-- ─── 3. Internas: máscara, datas, identificador, normalização ──────────────────────────────────────────────────────
-- Máscara da 0819g: CPF ···1234 / CNPJ ···1234; e-mail a***@dominio.
create function fin.informado_mascara(p text)
returns text
language sql immutable set search_path = ''
as $$
  select case when p is null then null
              when p like 'd:%' then case when length(p) = 16 then 'CNPJ ···' else 'CPF ···' end || right(p, 4)
              when p like 'e:%' then left(substr(p, 3), 1) || '***@' || split_part(p, '@', 2)
         end
$$;
revoke all on function fin.informado_mascara(text) from public, anon, authenticated;

-- Só AAAA-MM-DD: "05/09/2026" com DateStyle MDY viraria 9 de maio.
create function fin.informado_data(p text, p_rotulo text)
returns date
language plpgsql stable set search_path = ''
as $$
declare v text := btrim(p);
begin
  if v is null or v = '' then return null; end if;
  if v !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
    raise exception '% deve vir como AAAA-MM-DD (veio "%").', p_rotulo, v using errcode = 'P0001';
  end if;
  begin
    return v::date;
  exception when others then
    raise exception '% inválida: "%".', p_rotulo, v using errcode = 'P0001';
  end;
end $$;
revoke all on function fin.informado_data(text, text) from public, anon, authenticated;

-- Chave de comparação de nome de produto: sem caixa, sem acento, espaços colapsados. translate (não unaccent) para
-- não depender de extensão nem da collation; maiúsculas acentuadas entram no translate antes do lower.
create function fin.informado_chave_nome(p text)
returns text
language sql immutable set search_path = ''
as $$
  select lower(translate(btrim(regexp_replace(coalesce(p, ''), '\s+', ' ', 'g')),
                         'ÁÀÂÃÄÅÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇÑáàâãäåéèêëíìîïóòôõöúùûüçñ',
                         'AAAAAAEEEEIIIIOOOOOUUUUCNaaaaaaeeeeiiiiooooouuuucn'))
$$;
revoke all on function fin.informado_chave_nome(text) from public, anon, authenticated;

-- Catálogo para resolver o nome digitado: nome de fin.produtos (catálogo inteiro da Hotmart, z28w) e o nome mais
-- recente do produto no espelho (produto renomeado na Hotmart). Uma busca por produto em hotmart_transacoes_produto_idx.
create function fin.informados_catalogo()
returns table (produto_id text, nome text, chave text)
language sql stable set search_path = ''
as $$
  select p.produto_id, p.nome, fin.informado_chave_nome(p.nome) from fin.produtos p
  union
  select p.produto_id, p.nome, fin.informado_chave_nome(t.produto_nome)
    from fin.produtos p
    cross join lateral (select h.produto_nome from fin.hotmart_transacoes h
                         where h.produto_id = p.produto_id and h.aprovado_em is not null and h.produto_nome is not null
                         order by h.aprovado_em desc limit 1) t
$$;
revoke all on function fin.informados_catalogo() from public, anon, authenticated;

-- Aceita CPF/CNPJ com ou sem pontuação, e-mail, ou já prefixado (d:/e:). Valor MASCARADO (a tela de quem não vê CPF
-- devolve o que recebeu) só passa se for a máscara de um identificador atual — aí mantém o atual.
create function fin.informado_identificador(p_valor text, p_atuais text[])
returns text
language plpgsql stable set search_path = ''
as $$
declare
  v     text := btrim(p_valor);
  v_dig text;
  a     text;
begin
  if v is null or v = '' then return null; end if;
  if position('···' in v) > 0 or position('*' in v) > 0 then
    foreach a in array coalesce(p_atuais, '{}'::text[]) loop
      if a is not null and fin.informado_mascara(a) = v then return a; end if;
    end loop;
    raise exception 'Identificador mascarado: para trocar, digite o CPF, CNPJ ou e-mail completo.'
      using errcode = 'P0001';
  end if;
  if v ~* '^[de]:' then v := btrim(substr(v, 3)); end if;
  if position('@' in v) > 0 then
    v := lower(v);
    if v !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
      raise exception 'Identificador com e-mail inválido.' using errcode = 'P0001';
    end if;
    return 'e:' || v;
  end if;
  v_dig := regexp_replace(v, '\D', '', 'g');
  if length(v_dig) in (11, 14) then return 'd:' || v_dig; end if;
  raise exception 'Identificador não é CPF (11 dígitos), CNPJ (14) nem e-mail — tem % dígitos (zero à esquerda perdido na planilha?).',
    length(v_dig) using errcode = 'P0001';
end $$;
revoke all on function fin.informado_identificador(text, text[]) from public, anon, authenticated;

-- A validação verdadeira. p_criando = true: campo ausente = vazio. false: campo ausente = mantém o atual (nunca
-- "reseta ao padrão" o que a tela não mandou). Campos só de leitura da listagem são aceitos e ignorados; campo
-- desconhecido é erro (chave digitada errada não pode virar silêncio). Erro = exception com texto para a tela.
create function fin.informado_normalizar(p jsonb, p_atual fin.recebimentos_informados, p_criando boolean)
returns fin.recebimentos_informados
language plpgsql stable set search_path = ''
as $$
declare
  r      fin.recebimentos_informados;
  k      text;
  v_txt  text;
  v_prod text;
  v_cand text[];
  v_ids  text[];
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Linha inválida: esperava um objeto com os campos do lançamento.' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(p) loop
    if k <> all (array['id','data_prevista','cliente','tipo','valor','via_hotmart','produtos','identificador1',
                       'identificador2','acordo_desde','baixa_manual_em','situacao','recebido_hotmart',
                       'acumulado_acordo','valor_provisionado','arquivado_em','motivo_arquivo','atualizado_em']) then
      raise exception 'Campo desconhecido: "%".', k using errcode = 'P0001';
    end if;
  end loop;
  if not p_criando then r := p_atual; end if;

  if p_criando or p ? 'data_prevista' then
    r.data_prevista := fin.informado_data(p ->> 'data_prevista', 'Data prevista');
  end if;
  if r.data_prevista is null then raise exception 'Informe a data prevista.' using errcode = 'P0001'; end if;
  if r.data_prevista not between date '2020-01-01' and date '2036-12-31' then
    raise exception 'Data prevista fora do intervalo (2020 a 2036): %.', r.data_prevista using errcode = 'P0001';
  end if;

  if p_criando or p ? 'cliente' then r.cliente := nullif(btrim(p ->> 'cliente'), ''); end if;
  if r.cliente is null then raise exception 'Informe o cliente.' using errcode = 'P0001'; end if;
  if length(r.cliente) > 200 then
    raise exception 'Nome do cliente longo demais (até 200 caracteres).' using errcode = 'P0001';
  end if;

  if p_criando or p ? 'tipo' then r.tipo := nullif(btrim(p ->> 'tipo'), ''); end if;
  if r.tipo is null or r.tipo not in ('renovacao_diamante','renovacao_aurum','diamante_extra','outro') then
    raise exception 'Tipo inválido: "%". Use renovacao_diamante, renovacao_aurum, diamante_extra ou outro.',
      coalesce(r.tipo, '') using errcode = 'P0001';
  end if;

  if p_criando or p ? 'valor' then
    v_txt := btrim(p ->> 'valor');
    if v_txt is null or v_txt = '' then
      r.valor := null;
    elsif v_txt !~ '^[0-9]+(\.[0-9]{1,2})?$' then
      raise exception 'Valor inválido: "%". Use número positivo com ponto e até 2 casas (ex.: 1234.56).', v_txt
        using errcode = 'P0001';
    else
      r.valor := v_txt::numeric;
    end if;
  end if;
  if r.valor is null or r.valor <= 0 then raise exception 'Valor deve ser maior que zero.' using errcode = 'P0001'; end if;
  if r.valor >= 100000000 then
    raise exception 'Valor fora do intervalo (até R$ 99.999.999,99).' using errcode = 'P0001';
  end if;

  if p_criando or p ? 'via_hotmart' then
    if jsonb_typeof(p -> 'via_hotmart') is distinct from 'boolean' then
      raise exception 'Informe via_hotmart como verdadeiro ou falso.' using errcode = 'P0001';
    end if;
    r.via_hotmart := (p ->> 'via_hotmart')::boolean;
  end if;

  if p_criando or p ? 'produtos' then
    if p -> 'produtos' is null or jsonb_typeof(p -> 'produtos') = 'null' then
      r.produtos := '{}';
    elsif jsonb_typeof(p -> 'produtos') <> 'array' then
      raise exception 'Produtos deve ser uma lista.' using errcode = 'P0001';
    else
      v_ids := '{}';
      for v_prod in select btrim(x) from jsonb_array_elements_text(p -> 'produtos') x loop
        continue when v_prod is null or v_prod = '';
        -- nome sem caixa e sem acento (catálogo + nome atual no espelho), ou o código; casar com EXATAMENTE 1 produto
        select array_agg(distinct c.produto_id order by c.produto_id) into v_cand
          from fin.informados_catalogo() c
         where c.produto_id = v_prod or c.chave = fin.informado_chave_nome(v_prod);
        if coalesce(cardinality(v_cand), 0) = 0 then
          raise exception 'Produto "%" não encontrado na Hotmart', v_prod using errcode = 'P0001';
        elsif cardinality(v_cand) > 1 then
          raise exception 'Produto "%" é ambíguo: %', v_prod,
            (select string_agg(pr.nome || ' (' || pr.produto_id || ')', ', ' order by pr.produto_id)
               from fin.produtos pr where pr.produto_id = any (v_cand[1:3])) using errcode = 'P0001';
        end if;
        v_ids := v_ids || v_cand[1];
      end loop;
      r.produto_ids := array(select distinct x from unnest(v_ids) x order by 1);
      r.produtos := array(select pr.nome from unnest(r.produto_ids) with ordinality u(pid, o)
                            join fin.produtos pr on pr.produto_id = u.pid order by u.o);
    end if;
  end if;
  r.produtos := coalesce(r.produtos, '{}');
  r.produto_ids := coalesce(r.produto_ids, '{}');

  if p_criando or p ? 'identificador1' then
    r.identificador1 := fin.informado_identificador(p ->> 'identificador1',
                          case when p_criando then null else array[p_atual.identificador1, p_atual.identificador2] end);
  end if;
  if p_criando or p ? 'identificador2' then
    r.identificador2 := fin.informado_identificador(p ->> 'identificador2',
                          case when p_criando then null else array[p_atual.identificador1, p_atual.identificador2] end);
  end if;
  if r.identificador1 is null and r.identificador2 is not null then
    r.identificador1 := r.identificador2;
    r.identificador2 := null;
  end if;
  if r.identificador2 = r.identificador1 then r.identificador2 := null; end if;

  if p_criando or p ? 'acordo_desde' then
    r.acordo_desde := fin.informado_data(p ->> 'acordo_desde', 'Início do acordo');
  end if;
  if r.acordo_desde is not null and r.acordo_desde > r.data_prevista then
    raise exception 'Início do acordo (%) depois da data prevista (%).', r.acordo_desde, r.data_prevista
      using errcode = 'P0001';
  end if;
  if r.via_hotmart and cardinality(r.produto_ids) = 0 then
    raise exception 'Via Hotmart: informe o(s) produto(s) — é por eles que o pagamento é reconhecido.' using errcode = 'P0001';
  end if;
  if r.via_hotmart and r.acordo_desde is null then
    raise exception 'Via Hotmart: informe o início do acordo — os pagamentos contam a partir dele.' using errcode = 'P0001';
  end if;

  if p_criando or p ? 'baixa_manual_em' then
    r.baixa_manual_em := fin.informado_data(p ->> 'baixa_manual_em', 'Data da baixa');
    if r.baixa_manual_em is not null
       and (r.baixa_manual_em > v_hoje or r.baixa_manual_em < date '2020-01-01') then
      raise exception 'Data da baixa fora do intervalo (de 2020 até hoje): %.', r.baixa_manual_em using errcode = 'P0001';
    end if;
    if p_criando or r.baixa_manual_em is distinct from p_atual.baixa_manual_em then
      r.baixa_manual_por := case when r.baixa_manual_em is not null then (select auth.uid()) end;
    end if;
  end if;
  return r;
end $$;
revoke all on function fin.informado_normalizar(jsonb, fin.recebimentos_informados, boolean) from public, anon, authenticated;


-- ─── 4. Internas: pessoa, situação, cobertura ───────────────────────────────────────────────────────────────────────
-- E-mails e documentos com que cada informado vivo via Hotmart casa no espelho.
--   e-mail: todos os e-mails da pessoa na identidade (identidade_pkey → identidade_pessoa_idx) + o e-mail direto;
--   documento: direto, SÓ se não estiver na identidade (lá ele já trouxe os e-mails) nem em identidade_revisao
--   (documento bloqueado ou de escritório: casaria o dinheiro de outras pessoas).
create function fin.informados_alvos()
returns table (id uuid, emails text[], docs text[])
language sql stable set search_path = ''
as $$
  select r.id, e.emails, d.docs
    from fin.recebimentos_informados r
    cross join lateral (
      select coalesce(array_agg(distinct x.email), '{}'::text[]) emails
        from (select substr(i2.no, 3) email
                from unnest(array[r.identificador1, r.identificador2]) u(ident)
                join fin.identidade i1 on i1.no = u.ident
                join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
               where i2.no like 'e:%'
              union
              select substr(u.ident, 3)
                from unnest(array[r.identificador1, r.identificador2]) u(ident)
               where u.ident like 'e:%') x
    ) e
    cross join lateral (
      select coalesce(array_agg(distinct substr(u.ident, 3)), '{}'::text[]) docs
        from unnest(array[r.identificador1, r.identificador2]) u(ident)
       where u.ident like 'd:%'
         and not exists (select 1 from fin.identidade i where i.no = u.ident)
         and not exists (select 1 from fin.identidade_revisao rv where rv.no = u.ident)
    ) d
   where r.via_hotmart and r.arquivado_em is null
$$;
revoke all on function fin.informados_alvos() from public, anon, authenticated;

create function fin.informados_situacao(p_corte timestamptz)
returns table (id uuid, situacao text, recebido_hotmart numeric, acumulado_acordo numeric,
               valor_provisionado numeric, data_efetiva date)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dia  date;
  v_tol  int;
  v_conc numeric;
begin
  if p_corte is null then
    raise exception 'fin.informados_situacao: corte obrigatório' using errcode = 'P0001';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor into v_conc from fin.premissas_receber pr
   where pr.chave = 'tolerancia_conciliacao' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null or v_conc is null then
    raise exception 'fin.informados_situacao: premissa de tolerância ausente em fin.premissas_receber' using errcode = 'P0002';
  end if;

  return query
  with viva as (
    select r.id, r.data_prevista, r.valor, r.via_hotmart, r.produto_ids, r.acordo_desde, r.baixa_manual_em,
           sum(r.valor) over (partition by coalesce(r.identificador1, r.id::text), r.produto_ids, r.acordo_desde
                              order by r.data_prevista range between unbounded preceding and current row) acum
      from fin.recebimentos_informados r
     where r.arquivado_em is null
  ), rec as (
    select a.id, s.recebido
      from fin.informados_alvos() a
      join viva v on v.id = a.id
      cross join lateral (
        select coalesce(sum(t.liquido), 0) recebido
          from fin.vw_transacoes t
         where t.transacao = any (array(   -- e-mail e documento em ramos separados: cada um pelo seu índice
                 select h.transacao from fin.hotmart_transacoes h
                  where lower(trim(h.comprador_email)) = any (a.emails)
                    and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)
                 union
                 select h.transacao from fin.hotmart_transacoes h
                  where regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs)
                    and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)))
           and t.aprovado_em <= p_corte
           and t.dia_aprovado >= v.acordo_desde
      ) s
  ), sit as (
    select v.id, v.data_prevista, v.valor, v.via_hotmart, v.acum, rec.recebido,
           case when v.baixa_manual_em is not null then 'baixado_fora'
                when v.via_hotmart and coalesce(rec.recebido, 0) >= v.acum * (1 - v_conc) then 'realizado_hotmart'
                when v.data_prevista + v_tol < v_dia then 'em_atraso_cobrar'
                else 'a_receber' end s
      from viva v
      left join rec on rec.id = v.id
  )
  select sit.id, sit.s,
         case when sit.via_hotmart then coalesce(sit.recebido, 0) end,
         sit.acum,
         case when sit.s in ('baixado_fora','realizado_hotmart') then 0::numeric
              when sit.via_hotmart then greatest(0::numeric, least(sit.valor, sit.acum - coalesce(sit.recebido, 0)))
              else sit.valor end,
         case when sit.s = 'a_receber' then greatest(sit.data_prevista, v_dia + 1) end
    from sit
  union all
  select r.id, 'arquivado'::text, null::numeric, null::numeric, 0::numeric, null::date
    from fin.recebimentos_informados r
   where r.arquivado_em is not null;
end $$;
comment on function fin.informados_situacao(timestamptz) is
  'Contas a Receber bloco 5 (z63): situação, recebido, acumulado e provisionado de cada recebimento informado no corte.';
revoke all on function fin.informados_situacao(timestamptz) from public, anon, authenticated;

-- Conflito 6: contratos (ref opaca e-mail|oferta, a MESMA de fin.cobrancas_previstas) da pessoa+produto de um informado
-- vivo via Hotmart, com a janela do acordo: [acordo_desde, última data prevista do acordo + tolerância de atraso].
-- Só contratos que podem estar no bloco 2 (recorrência paga nos 120 dias até o corte) — poupa chamadas ao Vault.
create function fin.informados_cobertura(p_corte timestamptz)
returns table (ref text, de date, ate date)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_dia date;
  v_tol int;
begin
  if p_corte is null then
    raise exception 'fin.informados_cobertura: corte obrigatório' using errcode = 'P0001';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  select pr.valor::int into v_tol from fin.premissas_receber pr
   where pr.chave = 'tolerancia_atraso_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_tol is null then
    raise exception 'fin.informados_cobertura: premissa tolerancia_atraso_dias ausente' using errcode = 'P0002';
  end if;

  return query
  with g as (
    select r.id, r.produto_ids, r.acordo_desde de,
           max(r.data_prevista) over (partition by coalesce(r.identificador1, r.id::text), r.produto_ids, r.acordo_desde)
             + v_tol ate
      from fin.recebimentos_informados r
     where r.via_hotmart and r.arquivado_em is null
  ), par as materialized (
    select distinct o.email, o.oferta_codigo, g.de, g.ate
      from g
      join fin.informados_alvos() a on a.id = g.id
      cross join lateral (
        select lower(trim(h.comprador_email)) email, h.oferta_codigo
          from fin.hotmart_transacoes h
         where lower(trim(h.comprador_email)) = any (a.emails)
           and h.produto_id = any (g.produto_ids)
           and h.recorrencia is not null and h.oferta_codigo is not null
           and h.status in ('APPROVED','COMPLETE')
           and h.aprovado_em > p_corte - interval '120 days' and h.aprovado_em <= p_corte
        union
        select lower(trim(h.comprador_email)), h.oferta_codigo
          from fin.hotmart_transacoes h
         where regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs)
           and h.produto_id = any (g.produto_ids)
           and h.recorrencia is not null and h.oferta_codigo is not null and h.comprador_email is not null
           and h.status in ('APPROVED','COMPLETE')
           and h.aprovado_em > p_corte - interval '120 days' and h.aprovado_em <= p_corte
      ) o
  ), chave as materialized (
    select x.email, x.oferta_codigo, fin.chave_opaca('rc:' || x.email || '|' || x.oferta_codigo) ref
      from (select distinct par.email, par.oferta_codigo from par) x
  )
  select chave.ref, par.de, par.ate
    from par join chave on chave.email = par.email and chave.oferta_codigo = par.oferta_codigo;
end $$;
comment on function fin.informados_cobertura(timestamptz) is
  'Contas a Receber (z63): refs de contrato do bloco 2 cobertas por recebimento informado, com a janela do acordo.';
revoke all on function fin.informados_cobertura(timestamptz) from public, anon, authenticated;


-- ─── 5. RPCs ────────────────────────────────────────────────────────────────────────────────────────────────────────
create function public.fn_fin_informados_listar()
returns table (id uuid, data_prevista date, cliente text, tipo text, valor numeric, via_hotmart boolean,
               produtos text[], identificador1 text, identificador2 text, acordo_desde date, baixa_manual_em date,
               situacao text, recebido_hotmart numeric, acumulado_acordo numeric, valor_provisionado numeric,
               arquivado_em timestamptz, motivo_arquivo text, atualizado_em timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_cpf boolean;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- LGPD (regra da 0819g): identificador completo só para gp_pode_ver_cpf(); o resto vê CPF ···1234 / a***@dominio.
  v_cpf := coalesce(public.gp_pode_ver_cpf(), false);
  return query
  select r.id, r.data_prevista, r.cliente, r.tipo, r.valor::numeric, r.via_hotmart, r.produtos,
         case when v_cpf then substr(r.identificador1, 3) else fin.informado_mascara(r.identificador1) end,
         case when v_cpf then substr(r.identificador2, 3) else fin.informado_mascara(r.identificador2) end,
         r.acordo_desde, r.baixa_manual_em,
         s.situacao, s.recebido_hotmart, s.acumulado_acordo, s.valor_provisionado,
         r.arquivado_em, r.motivo_arquivo, r.atualizado_em
    from fin.recebimentos_informados r
    join fin.informados_situacao(now()) s on s.id = r.id
   order by r.arquivado_em nulls first, r.data_prevista, r.cliente, r.id;
end $$;
comment on function public.fn_fin_informados_listar() is
  'Contas a Receber (z63): recebimentos informados com situação no agora. Identificador mascarado sem gp_pode_ver_cpf().';
revoke all on function public.fn_fin_informados_listar() from public, anon;
grant execute on function public.fn_fin_informados_listar() to authenticated;

create function public.fn_fin_informado_salvar(p jsonb)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_id    uuid;
  v_atual fin.recebimentos_informados;
  r       fin.recebimentos_informados;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Envie o lançamento como objeto.' using errcode = 'P0001';
  end if;
  begin
    v_id := nullif(btrim(p ->> 'id'), '')::uuid;
  exception when others then
    raise exception 'Identificação do lançamento inválida.' using errcode = 'P0001';
  end;

  if v_id is null then
    r := fin.informado_normalizar(p, null::fin.recebimentos_informados, true);
    insert into fin.recebimentos_informados as x
      (data_prevista, cliente, tipo, valor, via_hotmart, produtos, produto_ids, identificador1, identificador2, acordo_desde,
       baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por)
    values (r.data_prevista, r.cliente, r.tipo, r.valor, r.via_hotmart, r.produtos, r.produto_ids, r.identificador1, r.identificador2,
            r.acordo_desde, r.baixa_manual_em, r.baixa_manual_por, 'manual', v_uid, v_uid)
    returning x.id into v_id;
    return v_id;
  end if;

  select * into v_atual from fin.recebimentos_informados x where x.id = v_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'P0001'; end if;
  if v_atual.arquivado_em is not null then
    raise exception 'Lançamento arquivado não se altera.' using errcode = 'P0001';
  end if;
  r := fin.informado_normalizar(p, v_atual, false);
  if (r.data_prevista, r.cliente, r.tipo, r.valor, r.via_hotmart, r.produto_ids, r.identificador1, r.identificador2,
      r.acordo_desde, r.baixa_manual_em)
     is not distinct from
     (v_atual.data_prevista, v_atual.cliente, v_atual.tipo, v_atual.valor, v_atual.via_hotmart, v_atual.produto_ids,
      v_atual.identificador1, v_atual.identificador2, v_atual.acordo_desde, v_atual.baixa_manual_em) then
    return v_id;   -- nada mudou: sem escrita, sem linha de histórico
  end if;
  update fin.recebimentos_informados x
     set data_prevista = r.data_prevista, cliente = r.cliente, tipo = r.tipo, valor = r.valor,
         via_hotmart = r.via_hotmart, produtos = r.produtos, produto_ids = r.produto_ids,
         identificador1 = r.identificador1,
         identificador2 = r.identificador2, acordo_desde = r.acordo_desde,
         baixa_manual_em = r.baixa_manual_em, baixa_manual_por = r.baixa_manual_por,
         atualizado_por = v_uid, atualizado_em = now()
   where x.id = v_id;
  return v_id;
end $$;
comment on function public.fn_fin_informado_salvar(jsonb) is
  'Contas a Receber (z63): cria (sem id) ou altera um recebimento informado. Campo ausente mantém o atual.';
revoke all on function public.fn_fin_informado_salvar(jsonb) from public, anon;
grant execute on function public.fn_fin_informado_salvar(jsonb) to authenticated;

create function public.fn_fin_informado_baixar(p_id uuid, p_data date)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_atual fin.recebimentos_informados;
  v_hoje  date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'Informe o lançamento.' using errcode = 'P0001'; end if;
  if p_data is not null and (p_data > v_hoje or p_data < date '2020-01-01') then
    raise exception 'Data da baixa fora do intervalo (de 2020 até hoje): %.', p_data using errcode = 'P0001';
  end if;
  select * into v_atual from fin.recebimentos_informados x where x.id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'P0001'; end if;
  if v_atual.arquivado_em is not null then
    raise exception 'Lançamento arquivado não se altera.' using errcode = 'P0001';
  end if;
  if v_atual.baixa_manual_em is not distinct from p_data then return; end if;
  update fin.recebimentos_informados x
     set baixa_manual_em = p_data, baixa_manual_por = case when p_data is not null then v_uid end,
         atualizado_por = v_uid, atualizado_em = now()
   where x.id = p_id;
end $$;
comment on function public.fn_fin_informado_baixar(uuid, date) is
  'Contas a Receber (z63): baixa manual (recebido fora da Hotmart ou confirmado à mão). Data nula desfaz.';
revoke all on function public.fn_fin_informado_baixar(uuid, date) from public, anon;
grant execute on function public.fn_fin_informado_baixar(uuid, date) to authenticated;

create function public.fn_fin_informado_arquivar(p_id uuid, p_motivo text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  v_uid   uuid := (select auth.uid());
  v_atual fin.recebimentos_informados;
  v_mot   text := btrim(p_motivo);
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_id is null then raise exception 'Informe o lançamento.' using errcode = 'P0001'; end if;
  if v_mot is null or length(v_mot) < 3 or length(v_mot) > 500 then
    raise exception 'Motivo do arquivamento obrigatório (3 a 500 caracteres).' using errcode = 'P0001';
  end if;
  select * into v_atual from fin.recebimentos_informados x where x.id = p_id for update;
  if not found then raise exception 'Lançamento não encontrado.' using errcode = 'P0001'; end if;
  if v_atual.arquivado_em is not null then
    raise exception 'Lançamento já arquivado.' using errcode = 'P0001';
  end if;
  update fin.recebimentos_informados x
     set arquivado_em = now(), arquivado_por = v_uid, motivo_arquivo = v_mot,
         atualizado_por = v_uid, atualizado_em = now()
   where x.id = p_id;
end $$;
comment on function public.fn_fin_informado_arquivar(uuid, text) is
  'Contas a Receber (z63): arquiva um recebimento informado (sai da projeção; nunca é apagado).';
revoke all on function public.fn_fin_informado_arquivar(uuid, text) from public, anon;
grant execute on function public.fn_fin_informado_arquivar(uuid, text) to authenticated;

-- Colar da planilha. Simular (padrão) = prévia, nada grava. Gravar = tudo ou nada: qualquer linha com erro → nada grava
-- e volta a lista de erros. Linha igual (data, cliente, valor, tipo) a um lançamento vivo ou a outra linha do lote é
-- erro: colar a mesma planilha duas vezes dobraria a projeção.
create function public.fn_fin_informados_importar(p_linhas jsonb, p_simular boolean default true)
returns table (linha int, ok boolean, erro text, id uuid)
language plpgsql security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid    uuid := (select auth.uid());
  v_n      int;
  i        int;
  v_el     jsonb;
  r        fin.recebimentos_informados;
  v_rows   fin.recebimentos_informados[] := '{}';
  v_err    text[] := '{}';
  v_chaves text[] := '{}';
  v_chave  text;
  v_erros  int := 0;
  v_id     uuid;
begin
  if v_uid is null or not coalesce(public.gp_pode_operar_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_simular is null then raise exception 'Informe se é simulação.' using errcode = 'P0001'; end if;
  if p_linhas is null or jsonb_typeof(p_linhas) <> 'array' then
    raise exception 'Envie a lista de linhas.' using errcode = 'P0001';
  end if;
  v_n := jsonb_array_length(p_linhas);
  if v_n = 0 or v_n > 500 then
    raise exception 'Entre 1 e 500 linhas por importação (vieram %).', v_n using errcode = 'P0001';
  end if;

  for i in 1 .. v_n loop
    v_el := p_linhas -> (i - 1);
    begin
      if jsonb_typeof(v_el) = 'object' and nullif(btrim(v_el ->> 'id'), '') is not null then
        raise exception 'Importação só cria lançamentos novos: tire o id.' using errcode = 'P0001';
      end if;
      r := fin.informado_normalizar(v_el, null::fin.recebimentos_informados, true);
      v_chave := concat_ws('|', r.data_prevista, lower(r.cliente), r.valor, r.tipo);
      if v_chave = any (v_chaves) then
        raise exception 'Linha repetida nesta importação (mesma data, cliente, valor e tipo).' using errcode = 'P0001';
      end if;
      if exists (select 1 from fin.recebimentos_informados x
                  where x.arquivado_em is null and x.data_prevista = r.data_prevista
                    and lower(x.cliente) = lower(r.cliente) and x.valor = r.valor and x.tipo = r.tipo) then
        raise exception 'Já cadastrado (mesma data, cliente, valor e tipo).' using errcode = 'P0001';
      end if;
      v_chaves := v_chaves || v_chave;
      v_rows   := v_rows || r;
      v_err    := v_err || null::text;
    exception when others then
      v_chaves := v_chaves || null::text;
      v_rows   := v_rows || null::fin.recebimentos_informados;
      v_err    := v_err || sqlerrm;
      v_erros  := v_erros + 1;
    end;
  end loop;

  if p_simular or v_erros > 0 then
    return query select g.n, v_err[g.n] is null, v_err[g.n], null::uuid from generate_series(1, v_n) g(n);
    return;
  end if;

  for i in 1 .. v_n loop
    r := v_rows[i];
    insert into fin.recebimentos_informados as x
      (data_prevista, cliente, tipo, valor, via_hotmart, produtos, produto_ids, identificador1, identificador2, acordo_desde,
       baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por)
    values (r.data_prevista, r.cliente, r.tipo, r.valor, r.via_hotmart, r.produtos, r.produto_ids, r.identificador1, r.identificador2,
            r.acordo_desde, r.baixa_manual_em, r.baixa_manual_por, 'importacao', v_uid, v_uid)
    returning x.id into v_id;
    linha := i; ok := true; erro := null; id := v_id;
    return next;
  end loop;
end $$;
comment on function public.fn_fin_informados_importar(jsonb, boolean) is
  'Contas a Receber (z63): importa até 500 recebimentos informados. Simular = prévia; gravar = tudo ou nada.';
revoke all on function public.fn_fin_informados_importar(jsonb, boolean) from public, anon;
grant execute on function public.fn_fin_informados_importar(jsonb, boolean) to authenticated;


-- ─── 6. A RPC da aba ganha o bloco 5 (mesma assinatura, mesmo RETURNS TABLE, mesma ACL) ────────────────────────────
create or replace function public.fn_fin_receber_semanal(p_corte timestamptz default null, p_ate date default null)
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_corte timestamptz := coalesce(p_corte, now());
  v_dia   date := (coalesce(p_corte, now()) at time zone 'America/Sao_Paulo')::date;
  v_ate   date;
  v_max   int;
  v_inf   boolean;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  select pr.valor::int into v_max from fin.premissas_receber pr
   where pr.chave = 'atraso_max_projetado_dias' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  select pr.valor > 0 into v_inf from fin.premissas_receber pr
   where pr.chave = 'informados_no_receber' and pr.vigente_de <= v_dia order by pr.vigente_de desc limit 1;
  if v_max is null or v_inf is null then
    raise exception 'Premissa do contas a receber ausente (atraso_max_projetado_dias / informados_no_receber).'
      using errcode = 'P0002';
  end if;
  return query
  with cob as materialized (
    select cb.ref, cb.de, cb.ate from fin.informados_cobertura(v_corte) cb where v_inf
  ), b2 as (
    select c.grupo, c.vencimento, c.ref, c.rotulo, c.produto, c.k, c.valor, c.entra_em, c.entra_rapido,
           c.libera_em, c.retido,
           case when c.situacao in ('a_receber','em_atraso_fora')
                     and exists (select 1 from cob where cob.ref = c.ref and c.vencimento between cob.de and cob.ate)
                then 'coberta_informado' else c.situacao end sit
      from fin.cobrancas_previstas(v_corte, v_ate) c
  ), inf as materialized (
    select r.id, r.tipo, r.cliente, r.produtos, r.via_hotmart, r.data_prevista, r.valor,
           s.situacao sit, s.valor_provisionado prov, s.data_efetiva efetiva
      from fin.informados_situacao(v_corte) s
      join fin.recebimentos_informados r on r.id = s.id
     where v_inf and s.situacao <> 'arquivado' and r.data_prevista <= v_ate
       and (s.situacao = 'a_receber' or r.data_prevista >= v_dia - v_max)
  )
  select 1::smallint, 'Vendas já realizadas'::text, b.componente, b.data_caixa, b.valor, 'a_receber'::text,
         b.origem_dia, null::text, null::text, null::text, null::int, b.detalhe
    from fin.receber_vendas_realizadas(v_corte) b
  union all
  select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.sit, c.vencimento,
         c.ref, c.rotulo, c.produto, c.k, null::jsonb
    from b2 c
    cross join lateral (
      select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.sit = 'a_receber'
      union all
      select 'garantia'::text, c.libera_em, c.retido where c.sit = 'a_receber'
      union all
      select 'cheio'::text, null::date, c.valor where c.sit <> 'a_receber'
    ) u(componente, data_caixa, valor)
  union all
  select 5::smallint,
         case i.tipo when 'renovacao_diamante' then 'Renovações Diamante'
                     when 'renovacao_aurum'    then 'Renovações Aurum'
                     when 'diamante_extra'     then 'Serviço Diamante extras'
                     else 'Outros recebimentos informados' end,
         u.componente, u.data_caixa, u.valor, u.sit, i.data_prevista,
         i.id::text, i.cliente, i.produtos[1], null::int, null::jsonb
    from inf i
    left join lateral fin.recebimento(i.efetiva, i.prov) f on i.via_hotmart and i.sit = 'a_receber'
    cross join lateral (
      select 'antecipacao'::text, f.entra_em, f.entra_rapido, 'a_receber'::text
       where i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'garantia'::text, f.libera_em, f.retido, 'a_receber'::text
       where i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'cheio'::text, i.efetiva, i.prov, 'a_receber'::text
       where not i.via_hotmart and i.sit = 'a_receber'
      union all
      select 'cheio'::text, null::date, i.prov, 'em_atraso_fora'::text
       where i.sit = 'em_atraso_cobrar'
      union all
      select 'cheio'::text, null::date, i.valor::numeric, 'realizada'::text
       where i.sit in ('realizado_hotmart','baixado_fora')
    ) u(componente, data_caixa, valor, sit)
   order by 1, 4 nulls last, 2, 3;
end $$;
comment on function public.fn_fin_receber_semanal(timestamptz, date) is
  'Aba Contas a Receber (z61 + z63): blocos 1, 2 e 5. Soma só situacao = a_receber (coberta_informado, realizada e '
  'em_atraso_fora não somam). Sem e-mail/documento: ref opaca ou id do informado, nome próprio/cliente.';
revoke all on function public.fn_fin_receber_semanal(timestamptz, date) from public, anon;
grant execute on function public.fn_fin_receber_semanal(timestamptz, date) to authenticated;


-- ─── 7. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_dia   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_ate   date := (date_trunc('month', (now() at time zone 'America/Sao_Paulo')::date::timestamp)
                   + interval '4 months' - interval '1 day')::date;
  v_adm   uuid;
  v_prod  text;
  v_ok    boolean;
  v_esp   text;
  v_obt   text;
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_n     int;
  v_s     numeric;
  f       text;
  t       text;
begin
  -- 7.1 grants: tabelas e internas fechadas; RPCs só para authenticated; ACL sem PUBLIC e nunca nula
  foreach t in array array['fin.recebimentos_informados','fin.recebimentos_informados_historico'] loop
    if has_table_privilege('anon', t, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', t, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception 'z63: grant aberto em % (conferir relacl)', t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z63: RLS desligada em %', t;
    end if;
  end loop;
  if has_sequence_privilege('authenticated', 'fin.recebimentos_informados_historico_id_seq', 'usage,select,update')
     or has_sequence_privilege('anon', 'fin.recebimentos_informados_historico_id_seq', 'usage,select,update') then
    raise exception 'z63: sequência do histórico aberta';
  end if;
  foreach f in array array['fin.tg_informados_historico()','fin.tg_informados_nao_apaga()','fin.informado_mascara(text)',
                           'fin.informado_data(text,text)','fin.informado_identificador(text,text[])',
                           'fin.informado_chave_nome(text)','fin.informados_catalogo()',
                           'fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)',
                           'fin.informados_alvos()','fin.informados_situacao(timestamptz)',
                           'fin.informados_cobertura(timestamptz)'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z63: interna % executável por anon/authenticated', f;
    end if;
  end loop;
  foreach f in array array['public.fn_fin_informados_listar()','public.fn_fin_informado_salvar(jsonb)',
                           'public.fn_fin_informado_baixar(uuid,date)','public.fn_fin_informado_arquivar(uuid,text)',
                           'public.fn_fin_informados_importar(jsonb,boolean)',
                           'public.fn_fin_receber_semanal(timestamptz,date)'] loop
    if has_function_privilege('anon', f, 'execute') then
      raise exception 'z63: % executável por anon', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z63: authenticated sem execute em %', f;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                      and p.proconfig = array['search_path=""']) then
      raise exception 'z63: % sem SECURITY DEFINER ou sem search_path vazio', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
              where ((p.pronamespace = 'public'::regnamespace and p.proname like 'fn_fin_informad%')
                     or (p.pronamespace = 'fin'::regnamespace and (p.proname like 'informad%' or p.proname like 'tg_informados%'))
                     or p.oid = 'public.fn_fin_receber_semanal(timestamptz,date)'::regprocedure)
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z63: função com EXECUTE para PUBLIC (ou proacl nulo = padrão público)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fn_fin_informad%') <> 5 then
    raise exception 'z63: esperava 5 RPCs fn_fin_informad* (sobrecarga?)';
  end if;

  -- 7.2 sem sessão → 42501 nas 6 RPCs (e nada gravado)
  foreach f in array array[
      'select * from public.fn_fin_informados_listar()',
      'select public.fn_fin_informado_salvar(''{"data_prevista":"2026-12-01","cliente":"z63","tipo":"outro","valor":1,"via_hotmart":false}''::jsonb)',
      'select public.fn_fin_informado_baixar(gen_random_uuid(), null)',
      'select public.fn_fin_informado_arquivar(gen_random_uuid(), ''teste'')',
      'select * from public.fn_fin_informados_importar(''[{"data_prevista":"2026-12-01","cliente":"z63","tipo":"outro","valor":1,"via_hotmart":false}]''::jsonb, false)',
      'select * from public.fn_fin_receber_semanal(null, null)'] loop
    v_ok := false;
    begin
      execute f;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z63: RPC respondeu sem sessão: %', f; end if;
  end loop;
  if exists (select 1 from fin.recebimentos_informados) then
    raise exception 'z63: RPC gravou sem sessão';
  end if;

  -- 7.3 blocos 1 e 2 não mudaram: RPC nova (tabela vazia) = corpo da z61 rodado direto nas internas.
  --     Precisa de sessão: usa um perfil admin ativo SÓ nesta conferência (claims locais, limpos logo depois).
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z63: nenhum perfil admin ativo para conferir a RPC'; end if;
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_esp from (
    select 1::smallint, 'Vendas já realizadas'::text, b.componente, b.data_caixa, b.valor, 'a_receber'::text,
           b.origem_dia, null::text, null::text, null::text, null::int, b.detalhe
      from fin.receber_vendas_realizadas(now()) b
    union all
    select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.situacao, c.vencimento,
           c.ref, c.rotulo, c.produto, c.k, null::jsonb
      from fin.cobrancas_previstas(now(), v_ate) c
      cross join lateral (
        select 'antecipacao'::text, c.entra_em, c.entra_rapido where c.situacao = 'a_receber'
        union all
        select 'garantia'::text, c.libera_em, c.retido where c.situacao = 'a_receber'
        union all
        select 'cheio'::text, null::date, c.valor where c.situacao <> 'a_receber'
      ) u(componente, data_caixa, valor)) x;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  select md5(coalesce(string_agg(x::text, '|' order by x::text), '')) into v_obt
    from public.fn_fin_receber_semanal(null, null) x;
  perform set_config('request.jwt.claims', '', true);
  if v_esp is distinct from v_obt then
    raise exception 'z63: blocos 1/2 da RPC nova diferem do corpo da z61 com a tabela vazia';
  end if;

  -- 7.4 comportamento com linhas de teste (tudo desfeito no fim do bloco)
  select min(pr.produto_id) into v_prod from fin.produtos pr;
  begin
    insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, produtos, origem)
    values (v_dia + 10, 'z63 teste A', 'outro', 1000, false, '{}', 'manual') returning id into v_a;
    insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, produtos, origem)
    values (v_dia - 20, 'z63 teste B', 'renovacao_diamante', 500, false, '{}', 'manual') returning id into v_b;
    insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, produtos, produto_ids,
                                             identificador1, acordo_desde, origem)
    values (v_dia + 12, 'z63 teste C', 'renovacao_aurum', 900, true, array['teste'], array[v_prod], 'e:z63-teste@invalido.example',
            v_dia - 30, 'manual') returning id into v_c;

    if (select string_agg(s.situacao || ':' || s.valor_provisionado, ',' order by r.cliente)
          from fin.informados_situacao(now()) s join fin.recebimentos_informados r on r.id = s.id)
       is distinct from 'a_receber:1000.00,em_atraso_cobrar:500.00,a_receber:900.00' then
      raise exception 'z63: situação das linhas de teste errada: %',
        (select string_agg(r.cliente || '=' || s.situacao || ':' || s.valor_provisionado, ',' order by r.cliente)
           from fin.informados_situacao(now()) s join fin.recebimentos_informados r on r.id = s.id);
    end if;

    update fin.recebimentos_informados set baixa_manual_em = v_dia where id = v_b;
    update fin.recebimentos_informados set arquivado_em = now(), motivo_arquivo = 'teste z63' where id = v_a;
    if (select string_agg(s.situacao, ',' order by r.cliente)
          from fin.informados_situacao(now()) s join fin.recebimentos_informados r on r.id = s.id)
       is distinct from 'arquivado,baixado_fora,a_receber' then
      raise exception 'z63: baixa/arquivo não mudaram a situação';
    end if;
    if (select string_agg(h.acao, ',' order by h.id) from fin.recebimentos_informados_historico h)
       is distinct from 'criado,criado,criado,baixa,arquivado' then
      raise exception 'z63: histórico errado: %',
        (select string_agg(h.acao, ',' order by h.id) from fin.recebimentos_informados_historico h);
    end if;

    v_ok := false;
    begin
      delete from fin.recebimentos_informados where id = v_c;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z63: DELETE em recebimentos_informados não foi barrado'; end if;
    v_ok := false;
    begin
      update fin.recebimentos_informados_historico set acao = 'alterado';
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z63: UPDATE no histórico não foi barrado'; end if;

    -- RPC com as linhas: C (via Hotmart) = antecipação + garantia + custo = 900; B baixado = realizada cheio 500
    perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
    select count(*), sum(x.valor) filter (where x.ref = v_c::text) into v_n, v_s
      from public.fn_fin_receber_semanal(null, null) x where x.bloco = 5;
    if v_n <> 3
       or v_s + (select r.custo_antecipacao from fin.recebimento(v_dia + 12, 900) r) <> 900
       or not exists (select 1 from public.fn_fin_receber_semanal(null, null) x
                       where x.bloco = 5 and x.ref = v_b::text and x.situacao = 'realizada' and x.componente = 'cheio'
                         and x.valor = 500 and x.data_caixa is null and x.grupo = 'Renovações Diamante')
       or exists (select 1 from public.fn_fin_receber_semanal(null, null) x
                   where (x.bloco = 5 and (x.situacao not in ('a_receber','realizada','em_atraso_fora')
                                            or (x.situacao = 'a_receber' and x.data_caixa <= v_dia)
                                            or x.ref is null or x.rotulo is null))
                      or (x.bloco = 2 and x.situacao not in ('a_receber','em_atraso_fora','realizada','coberta_informado'))) then
      raise exception 'z63: bloco 5 fora do contrato (linhas %, soma C %)', v_n, v_s;
    end if;
    -- listagem: identificador mascarado para quem não vê CPF é regra da 0819g; aqui o admin vê em claro
    if (select l.identificador1 from public.fn_fin_informados_listar() l where l.id = v_c)
       is distinct from 'z63-teste@invalido.example' then
      raise exception 'z63: listar não devolveu o identificador em claro para admin';
    end if;
    perform set_config('request.jwt.claims', '', true);
    if fin.informado_mascara('e:z63-teste@invalido.example') <> 'z***@invalido.example'
       or fin.informado_mascara('d:12345678901') <> 'CPF ···8901'
       or fin.informado_mascara('d:12345678000199') <> 'CNPJ ···0199' then
      raise exception 'z63: máscara fora do padrão 0819g';
    end if;

    raise exception using errcode = 'P0001', message = 'z63_desfaz_teste';
  exception when raise_exception then
    if sqlerrm <> 'z63_desfaz_teste' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  if exists (select 1 from fin.recebimentos_informados) or exists (select 1 from fin.recebimentos_informados_historico) then
    raise exception 'z63: linhas de teste não foram desfeitas';
  end if;
end $chk$;


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit) ════════════════
-- explain: rodar 2× e usar a 2ª (1ª é cache frio). <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro;
-- <UUID_OPERA> = que OPERA; <UUID_SO_VE> = que vê mas não opera e não vê CPF (se existir).
/*
-- E4) Casamento pessoa → pagamentos (corpo de fin.informados_alvos + recebido de fin.informados_situacao), com linhas
--     reais. Enquanto a tabela estiver vazia, rodar DEPOIS da importação das 80 linhas (ou dentro do bloco P-IMP).
--     Esperado: Index Scan em identidade_pkey (i1 / "i.no = u.ident"), Index Scan/Bitmap em identidade_pessoa_idx (i2),
--     Index/Bitmap Scan em hotmart_transacoes_email_idx (ramo do e-mail) e em hotmart_transacoes_documento_idx (ramo do
--     documento), Index/Bitmap Scan em hotmart_transacoes_pkey pelo transacao = ANY. "Seq Scan on hotmart_transacoes",
--     ou "Bitmap Index Scan on hotmart_transacoes_produto_idx" com "Rows Removed by Filter" alto (varre o produto inteiro
--     por linha) = índice do e-mail ignorado → avisar o Victor. Teto: ≤ 50 ms para 100 linhas.
explain (analyze, buffers)
select a.id, s.recebido
  from fin.informados_alvos() a
  join fin.recebimentos_informados v on v.id = a.id
  cross join lateral (
    select coalesce(sum(t.liquido), 0) recebido
      from fin.vw_transacoes t
     where t.transacao = any (array(
             select h.transacao from fin.hotmart_transacoes h
              where lower(trim(h.comprador_email)) = any (a.emails)
                and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)
             union
             select h.transacao from fin.hotmart_transacoes h
              where regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs)
                and h.status in ('APPROVED','COMPLETE') and h.produto_id = any (v.produto_ids)))
       and t.aprovado_em <= now() and t.dia_aprovado >= v.acordo_desde) s;
-- o corpo de fin.informados_alvos (é SQL; o explain acima o mostra só como Function Scan):
explain (analyze, buffers)
select r.id, e.emails, d.docs
  from fin.recebimentos_informados r
  cross join lateral (
    select coalesce(array_agg(distinct x.email), '{}'::text[]) emails
      from (select substr(i2.no, 3) email
              from unnest(array[r.identificador1, r.identificador2]) u(ident)
              join fin.identidade i1 on i1.no = u.ident
              join fin.identidade i2 on i2.pessoa_chave = i1.pessoa_chave
             where i2.no like 'e:%'
            union
            select substr(u.ident, 3) from unnest(array[r.identificador1, r.identificador2]) u(ident)
             where u.ident like 'e:%') x) e
  cross join lateral (
    select coalesce(array_agg(distinct substr(u.ident, 3)), '{}'::text[]) docs
      from unnest(array[r.identificador1, r.identificador2]) u(ident)
     where u.ident like 'd:%'
       and not exists (select 1 from fin.identidade i where i.no = u.ident)
       and not exists (select 1 from fin.identidade_revisao rv where rv.no = u.ident)) d
 where r.via_hotmart and r.arquivado_em is null;
-- a cobertura (chama o Vault 1× por contrato):
explain (analyze, buffers) select * from fin.informados_cobertura(now());
select count(*) contratos_cobertos from fin.informados_cobertura(now());

-- E5) A RPC inteira e a listagem, com o usuário do Financeiro. Teto: RPC ≤ 300 ms; listar ≤ 100 ms (2ª execução).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_semanal(null, null);
explain (analyze, buffers) select * from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31');
explain (analyze, buffers) select * from public.fn_fin_informados_listar();
select count(*), pg_size_pretty(sum(pg_column_size(x))::bigint) tamanho from public.fn_fin_informados_listar() x;
rollback;

-- P-IMP) Importação e escrita com quem OPERA — tudo em begin…rollback NA MESMA chamada (grava de verdade senão).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_OPERA>","role":"authenticated"}', true);
set local role authenticated;
-- prévia com 1 linha boa, 1 ruim e 1 repetida → ok,false,false
select * from public.fn_fin_informados_importar('[
  {"data_prevista":"2026-10-15","cliente":"Prova Z63","tipo":"outro","valor":1000,"via_hotmart":false},
  {"data_prevista":"15/10/2026","cliente":"Prova Z63 b","tipo":"outro","valor":1000,"via_hotmart":false},
  {"data_prevista":"2026-10-15","cliente":"prova z63","tipo":"outro","valor":1000,"via_hotmart":false}]'::jsonb, true);
-- gravar com erro → nada grava; depois só a boa → 1 id
select * from public.fn_fin_informados_importar('[{"data_prevista":"2026-10-15","cliente":"Prova Z63","tipo":"outro","valor":1000,"via_hotmart":false},{"cliente":""}]'::jsonb, false);
select count(*) deve_ser_0 from public.fn_fin_informados_listar();
explain (analyze, buffers)
select * from public.fn_fin_informados_importar('[{"data_prevista":"2026-10-15","cliente":"Prova Z63","tipo":"outro","valor":1000,"via_hotmart":false}]'::jsonb, false);
select l.cliente, l.situacao, l.valor_provisionado from public.fn_fin_informados_listar() l;
reset role;
select acao, por is not null tem_autor from fin.recebimentos_informados_historico;
rollback;

-- P-LGPD) Quem vê o financeiro mas NÃO vê CPF: identificador mascarado (CPF ···1234 / a***@dominio). Só se existir
--         esse perfil (select id from perfis where status='ativo' and cargo in ('gestor','operador') and
--         'financeiro' = any(areas) and pode_ver_cpf_completo is not true).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_SO_VE>","role":"authenticated"}', true);
set local role authenticated;
select l.identificador1, l.identificador2 from public.fn_fin_informados_listar() l limit 5;
select public.fn_fin_informado_salvar('{"data_prevista":"2026-12-01","cliente":"x","tipo":"outro","valor":1,"via_hotmart":false}'::jsonb);  -- 42501 se não opera
rollback;

-- CONF-SOMA) Bloco 5 fecha com a listagem: caixa a receber (antecipação + garantia + custo de antecipação, ou cheio)
--            = soma do valor_provisionado das linhas a_receber no horizonte. Esperado: diferenca = 0.
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
with rpc as (
  select x.ref, sum(x.valor) caixa from public.fn_fin_receber_semanal(null, null) x
   where x.bloco = 5 and x.situacao = 'a_receber' group by 1
), lst as (
  select l.id::text ref, l.via_hotmart, l.valor_provisionado, l.data_prevista
    from public.fn_fin_informados_listar() l
   where l.situacao = 'a_receber'
     and l.data_prevista <= (date_trunc('month', current_date) + interval '4 months' - interval '1 day')::date
)
select count(*) linhas,
       round(sum(lst.valor_provisionado), 2) provisionado,
       round(sum(rpc.caixa + case when lst.via_hotmart
                                  then (select r.custo_antecipacao
                                          from fin.recebimento(greatest(lst.data_prevista, current_date + 1), lst.valor_provisionado) r)
                                  else 0 end), 2) caixa_mais_custo,
       round(sum(lst.valor_provisionado) - sum(rpc.caixa + case when lst.via_hotmart
                                  then (select r.custo_antecipacao
                                          from fin.recebimento(greatest(lst.data_prevista, current_date + 1), lst.valor_provisionado) r)
                                  else 0 end), 2) diferenca
  from lst left join rpc using (ref);
-- por semana (seg–dom cortada no mês, a partir de 24/09) — comparar com o bloco 5 da aba Fluxo Semanal:
select x.grupo,
       greatest(date_trunc('week', x.data_caixa)::date, date_trunc('month', x.data_caixa)::date, date '2026-09-24') semana,
       round(sum(x.valor), 2) caixa
  from public.fn_fin_receber_semanal('2026-09-25 23:59:59-03', '2026-12-31') x
 where x.bloco = 5 and x.situacao = 'a_receber' group by rollup (1, 2) order by 1, 2;
-- cobertura do bloco 2 (conflito 6): quanto saiu da soma por estar coberto
select x.grupo, count(*) cobrancas, round(sum(x.valor), 2) fora_da_soma
  from public.fn_fin_receber_semanal(null, null) x where x.situacao = 'coberta_informado' group by rollup (1);
rollback;

-- P-GRANTS) Vivo.
select p.oid::regprocedure, p.proacl, p.prosecdef, p.proconfig from pg_proc p
 where (p.pronamespace = 'public'::regnamespace and (p.proname like 'fn_fin_informad%' or p.proname = 'fn_fin_receber_semanal'))
    or (p.pronamespace = 'fin'::regnamespace and (p.proname like 'informad%' or p.proname like 'tg_informados%'))
 order by 1::text;
select relname, relacl, relrowsecurity from pg_class
 where oid in ('fin.recebimentos_informados'::regclass, 'fin.recebimentos_informados_historico'::regclass);
*/
