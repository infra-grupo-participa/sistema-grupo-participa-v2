-- 20260928z71 — Financeiro, F5: tipo de relatório 'receber' no protocolo de PDF (fin.relatorios_emitidos).
--
-- APLICADA em produção em 28/09/2026 (fin_relatorio_receber; md5 = arquivo). CHECK = tipo = ANY (fin.relatorio_tipos()); tipos {board,pessoas,conciliacao,identidade,acelera,prorata,receber}.
-- ou conferência que falhe desfaz tudo. (A parte F8, "dinheiro já contratado", saiu daqui e foi para a z72.)
--
-- O que faz:
--   1) fin.relatorio_tipos() (imutável, interna): a ÚNICA lista de tipos de relatório, agora com 'receber'.
--   2) CHECK relatorios_emitidos_tipo_check passa a ler fin.relatorio_tipos(). O CHECK vivo é conferido ANTES com
--      pg_get_constraintdef (filtrado por conname): se tiver qualquer valor além dos 6 da z50, aborta — reescrever de
--      memória apagaria o valor. Troca num só ALTER (não há instante sem CHECK).
--   3) fn_fin_relatorio_emitir: replace com guarda de corpo vivo (z50). Única linha que muda: a do tipo, que passa a
--      ler fin.relatorio_tipos(). Nível: 'receber' aceita os 3 níveis (só 'identidade' é restrito, inalterado).
--   ATENÇÃO para quem mexer depois: CHECK com função não revalida linhas antigas quando a função muda. Só ACRESCENTAR
--   tipo em fin.relatorio_tipos(); remover exige conferir as linhas existentes primeiro.
--
-- 5 perguntas: zero consulta nova (1 chamada de função imutável por emissão); tabela de dezenas de linhas (o ALTER
--   valida todas sob lock, instantâneo); frequência = emissões de PDF; a lista mora num lugar só; reversão abaixo.
--
-- REVERSÃO (uma transação; nada se apaga):
--   begin;
--   -- recolocar o corpo da z50 em fn_fin_relatorio_emitir (20260928z50 linhas 102–152, create or replace; a ACL é
--   -- preservada) — a partir daí nenhuma emissão nova de 'receber'. O CHECK com fin.relatorio_tipos() pode FICAR
--   -- (aceita a mais, não a menos). Voltar o CHECK para a lista literal só se não houver linha 'receber':
--   --   select count(*) from fin.relatorios_emitidos where tipo = 'receber';   -- tem que dar 0
--   --   alter table fin.relatorios_emitidos drop constraint relatorios_emitidos_tipo_check,
--   --     add constraint relatorios_emitidos_tipo_check
--   --     check (tipo in ('board','pessoas','conciliacao','identidade','acelera','prorata'));
--   commit;
--
-- PROVAS (rodar e colar; SELECT, seguras):
--   select conname, pg_get_constraintdef(oid) from pg_constraint
--    where conrelid = 'fin.relatorios_emitidos'::regclass and conname = 'relatorios_emitidos_tipo_check';
--   select fin.relatorio_tipos();
--   select p.oid::regprocedure, a::text from pg_proc p, unnest(p.proacl) a
--    where p.oid in ('fin.relatorio_tipos()'::regprocedure,
--                    'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure) order by 1, 2;
--   explain (analyze, buffers) select * from fin.relatorios_emitidos where tipo = any (fin.relatorio_tipos());


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare
  v_emi  oid := to_regprocedure('public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)');
  v_src  text;
  v_res  text;
  v_def  text;
  v_n    int;
  e_emi  text := $esperado$
#variable_conflict use_column
declare
  v_uid     uuid  := auth.uid();
  v_recorte jsonb := coalesce(p_recorte, '{}'::jsonb);
  v_totais  jsonb := coalesce(p_totais,  '{}'::jsonb);
  v_nome    text;
  v_agora   timestamptz := now();
  v_proto   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_tipo is null or p_tipo not in ('board','pessoas','conciliacao','identidade','acelera','prorata') then
    raise exception 'Tipo de relatório inválido.' using errcode = '22023';
  end if;
  if p_nivel is null or p_nivel not in ('completo','sem_dado_pessoal','so_numeros') then
    raise exception 'Nível de dado pessoal inválido.' using errcode = '22023';
  end if;
  if p_tipo = 'identidade' and p_nivel <> 'completo' then
    raise exception 'O relatório de identidade só existe no nível completo.' using errcode = '22023';
  end if;
  if not fin.relatorio_recorte_valido(v_recorte) then
    raise exception 'Recorte inválido: precisa ser objeto até 4 KB e sem texto de busca ou dado pessoal.'
      using errcode = '22023';
  end if;
  if p_linhas is null or p_linhas < 0 then
    raise exception 'Quantidade de linhas inválida.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_totais) <> 'object' or octet_length(v_totais::text) > 8192 then
    raise exception 'Totais inválidos: precisa ser objeto até 8 KB.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p.nome), ''), p.email) into v_nome
    from public.perfis p where p.id = v_uid;
  if v_nome is null then
    raise exception 'Perfil sem nome.' using errcode = '42501';
  end if;

  v_proto := 'GP-REL-' || to_char(v_agora at time zone 'America/Sao_Paulo', 'YYYY') || '-'
             || lpad(nextval('fin.relatorios_emitidos_protocolo_seq')::text, 6, '0');

  return query
  insert into fin.relatorios_emitidos (protocolo, tipo, nivel, recorte, linhas, totais, gerado_por, gerado_por_nome, emitido_em)
  values (v_proto, p_tipo, p_nivel, v_recorte, p_linhas, v_totais, v_uid, v_nome, v_agora)
  returning protocolo, emitido_em, gerado_por_nome;
end
$esperado$;
  e_emi_res text := 'TABLE(protocolo text, emitido_em timestamp with time zone, gerado_por_nome text)';
  e_check text := $$CHECK ((tipo = ANY (ARRAY['board'::text, 'pessoas'::text, 'conciliacao'::text, 'identidade'::text, 'acelera'::text, 'prorata'::text])))$$;
begin
  if to_regprocedure('fin.relatorio_tipos()') is not null then
    raise exception 'z71: já aplicada (fin.relatorio_tipos existe)';
  end if;
  if v_emi is null or to_regclass('fin.relatorios_emitidos') is null then
    raise exception 'z71: aplicar a z50 antes (fin.relatorios_emitidos / fn_fin_relatorio_emitir ausentes)';
  end if;
  if (select count(*) from pg_proc where proname = 'fn_fin_relatorio_emitir' and pronamespace = 'public'::regnamespace) <> 1 then
    raise exception 'z71: sobrecarga viva de fn_fin_relatorio_emitir — conferir pg_get_function_arguments';
  end if;
  -- corpo vivo = z50 (sem espaço, sem comentário, sem o texto das mensagens de erro)
  select prosrc, pg_get_function_result(oid) into v_src, v_res from pg_proc where oid = v_emi;
  if regexp_replace(regexp_replace(regexp_replace(v_src, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                   '--[^\n]*', '', 'g'), '\s+', '', 'g')
     <> regexp_replace(regexp_replace(regexp_replace(e_emi, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                      '--[^\n]*', '', 'g'), '\s+', '', 'g')
     or regexp_replace(v_res, '\s+', '', 'g') <> regexp_replace(e_emi_res, '\s+', '', 'g') then
    raise exception 'z71: corpo vivo de fn_fin_relatorio_emitir diverge da z50. Mandar pg_get_functiondef ao Victor.';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = v_emi and l.lanname = 'plpgsql' and p.provolatile = 'v' and p.prosecdef
                    and p.proconfig = array['search_path=""']) then
    raise exception 'z71: atributos vivos de fn_fin_relatorio_emitir diferentes da z50 (plpgsql/volatile/definer/search_path vazio)';
  end if;
  -- CHECK vivo, pelo nome: exatamente os 6 valores da z50
  select count(*), min(pg_get_constraintdef(c.oid)) into v_n, v_def
    from pg_constraint c
   where c.conrelid = 'fin.relatorios_emitidos'::regclass and c.conname = 'relatorios_emitidos_tipo_check' and c.contype = 'c';
  if v_n <> 1 or regexp_replace(v_def, '\s+', '', 'g') <> regexp_replace(e_check, '\s+', '', 'g') then
    raise exception 'z71: CHECK vivo relatorios_emitidos_tipo_check diferente do da z50: % — não reescrever de memória', coalesce(v_def, '(ausente)');
  end if;
  select string_agg(distinct re.tipo, ', ') into v_def from fin.relatorios_emitidos re
   where re.tipo not in ('board','pessoas','conciliacao','identidade','acelera','prorata');
  if v_def is not null then
    raise exception 'z71: fin.relatorios_emitidos tem tipo fora da lista da z50: %', v_def;
  end if;
end $guarda$;


-- ─── 1. A lista num lugar só ────────────────────────────────────────────────────────────────────────────────────────
-- ÚNICA lista de tipos de relatório (CHECK da tabela + fn_fin_relatorio_emitir). Só ACRESCENTAR: o CHECK não revalida
-- linhas antigas quando esta função muda.
create function fin.relatorio_tipos()
returns text[] language sql immutable set search_path = ''
as $$ select array['board','pessoas','conciliacao','identidade','acelera','prorata','receber']::text[] $$;
comment on function fin.relatorio_tipos() is
  'Tipos de relatório PDF aceitos (z50 + receber na z71). Lida pelo CHECK relatorios_emitidos_tipo_check e por '
  'fn_fin_relatorio_emitir. Só acrescentar: remover exige conferir as linhas de fin.relatorios_emitidos antes.';
revoke all on function fin.relatorio_tipos() from public, anon, authenticated;

-- ─── 2. CHECK: um só ALTER, não há instante sem CHECK. Valida as linhas existentes (dezenas) sob o lock da tabela ────
alter table fin.relatorios_emitidos
  drop constraint relatorios_emitidos_tipo_check,
  add constraint relatorios_emitidos_tipo_check check (tipo = any (fin.relatorio_tipos()));

-- ─── 3. Emitir ──────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function public.fn_fin_relatorio_emitir(
  p_tipo text, p_nivel text, p_recorte jsonb, p_linhas int, p_totais jsonb)
returns table (protocolo text, emitido_em timestamptz, gerado_por_nome text)
language plpgsql volatile security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_uid     uuid  := auth.uid();
  v_recorte jsonb := coalesce(p_recorte, '{}'::jsonb);
  v_totais  jsonb := coalesce(p_totais,  '{}'::jsonb);
  v_nome    text;
  v_agora   timestamptz := now();
  v_proto   text;
begin
  if v_uid is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_tipo is null or not (p_tipo = any (fin.relatorio_tipos())) then   -- z71: a lista mora em fin.relatorio_tipos()
    raise exception 'Tipo de relatório inválido.' using errcode = '22023';
  end if;
  if p_nivel is null or p_nivel not in ('completo','sem_dado_pessoal','so_numeros') then
    raise exception 'Nível de dado pessoal inválido.' using errcode = '22023';
  end if;
  if p_tipo = 'identidade' and p_nivel <> 'completo' then
    raise exception 'O relatório de identidade só existe no nível completo.' using errcode = '22023';
  end if;
  if not fin.relatorio_recorte_valido(v_recorte) then
    raise exception 'Recorte inválido: precisa ser objeto até 4 KB e sem texto de busca ou dado pessoal.'
      using errcode = '22023';
  end if;
  if p_linhas is null or p_linhas < 0 then
    raise exception 'Quantidade de linhas inválida.' using errcode = '22023';
  end if;
  if jsonb_typeof(v_totais) <> 'object' or octet_length(v_totais::text) > 8192 then
    raise exception 'Totais inválidos: precisa ser objeto até 8 KB.' using errcode = '22023';
  end if;

  select coalesce(nullif(btrim(p.nome), ''), p.email) into v_nome
    from public.perfis p where p.id = v_uid;
  if v_nome is null then
    raise exception 'Perfil sem nome.' using errcode = '42501';
  end if;

  v_proto := 'GP-REL-' || to_char(v_agora at time zone 'America/Sao_Paulo', 'YYYY') || '-'
             || lpad(nextval('fin.relatorios_emitidos_protocolo_seq')::text, 6, '0');

  return query
  insert into fin.relatorios_emitidos (protocolo, tipo, nivel, recorte, linhas, totais, gerado_por, gerado_por_nome, emitido_em)
  values (v_proto, p_tipo, p_nivel, v_recorte, p_linhas, v_totais, v_uid, v_nome, v_agora)
  returning protocolo, emitido_em, gerado_por_nome;
end $$;
revoke all on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) from public, anon;
grant execute on function public.fn_fin_relatorio_emitir(text, text, jsonb, int, jsonb) to authenticated;


-- ─── 4. Conferência (falha → rollback de tudo) ──────────────────────────────────────────────────────────────────────
do $conf$
declare
  v_txt text;
begin
  if fin.relatorio_tipos() is distinct from array['board','pessoas','conciliacao','identidade','acelera','prorata','receber']::text[] then
    raise exception 'z71: conferência — fin.relatorio_tipos() inesperada';
  end if;
  select pg_get_constraintdef(c.oid) into v_txt from pg_constraint c
   where c.conrelid = 'fin.relatorios_emitidos'::regclass and c.conname = 'relatorios_emitidos_tipo_check' and c.contype = 'c';
  if v_txt is null or v_txt !~ 'relatorio_tipos\(\)' or v_txt ~ 'prorata' then
    raise exception 'z71: conferência — CHECK novo não lê fin.relatorio_tipos(): %', v_txt;
  end if;
  select prosrc into v_txt from pg_proc where oid = 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure;
  if v_txt !~ 'fin\.relatorio_tipos\(\)' or v_txt ~ '''prorata''' or v_txt ~ '''board''' then
    raise exception 'z71: conferência — fn_fin_relatorio_emitir ainda tem lista própria de tipos';
  end if;
  if exists (select 1 from fin.relatorios_emitidos re where not (re.tipo = any (fin.relatorio_tipos()))) then
    raise exception 'z71: conferência — linha de fin.relatorios_emitidos fora da lista';
  end if;
  -- ACL: PUBLIC e anon fora; authenticated só na RPC; a lista é interna; tabela continua fechada
  if has_function_privilege('anon', 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)', 'execute')
     or has_function_privilege('anon', 'fin.relatorio_tipos()', 'execute')
     or has_function_privilege('authenticated', 'fin.relatorio_tipos()', 'execute')
     or exists (select 1 from pg_proc p, unnest(p.proacl) a
                 where p.oid in ('fin.relatorio_tipos()'::regprocedure,
                                 'public.fn_fin_relatorio_emitir(text,text,jsonb,int,jsonb)'::regprocedure)
                   and a::text like '=%')
     or has_table_privilege('authenticated', 'fin.relatorios_emitidos', 'insert')
     or has_table_privilege('anon', 'fin.relatorios_emitidos', 'select') then
    raise exception 'z71: conferência — ACL errada (PUBLIC/anon com execute, lista exposta ou tabela gravável)';
  end if;
end $conf$;
