-- 20260929z73 — Contas a Receber, F9 (parte dos contratos): CONTRATOS HOLDING FAMILIAR (CSM Soluções, fora da Hotmart)
--               como BLOCO 7 da previsão. Catálogo A.3 P38–P40 (P42: sem assinatura a 50% no conservador).
--
-- APLICADA em produção em 29/09/2026 (fin_receber_contratos_solucoes; ensaio + conferência 9.x verdes; md5 dos 7 corpos = arquivo sem comentários). Kirad APROVADO (sem achados).
-- mudanças → conferência 9.x; qualquer falha desfaz tudo.
-- Ordem: z63, z66, z67, z69 aplicadas (z60–z72 aplicadas em 28/09). Guarda de CORPO VIVO: md5 do corpo normalizado
-- (sem espaço, sem comentário, sem o texto das mensagens de "raise exception" — a mesma normalização da z67/z69) de cada
-- função substituída tem que ser o do arquivo de origem; conferido também contra os .min.sql aplicados (md5 igual).
-- As vendas Hotmart da Soluções (P35–P37) ficam FORA: dependem da conta do escritório. Só os contratos entram agora.
--
-- O que faz:
--   1) fin.recebimentos_informados (reaproveitada, F9):
--      · tipo novo 'contrato_holding_familiar' (CHECK recebimentos_informados_tipo_check conferido por
--        pg_get_constraintdef ANTES de reescrever; a guarda aborta se o vivo não for o da z63);
--      · colunas parcela_n int, parcela_de int, contrato_assinado boolean (nulas nos outros tipos);
--      · CHECK recebimentos_informados_contrato_ck: no contrato, via_hotmart = false, contrato_assinado obrigatório,
--        parcela_n e parcela_de juntas (ou nenhuma) com 1 ≤ n ≤ de ≤ 60; nos outros tipos, as três nulas.
--      Trilha (fin.tg_informados_historico) NÃO muda: to_jsonb(new) já leva as colunas novas; identificador continua
--      mascarado (conferência 9.5).
--   2) Premissas (catálogo da z66): recebimento_contrato:assinado e recebimento_contrato:sem_assinatura — percentual,
--      0 a 1, aceita cenário. Carga desde 2000-01-01: assinado 1 (100%), sem_assinatura 1 (100%),
--      sem_assinatura@conservador 0,5 (50%). Otimista sem vigência própria = a base.
--   3) RPCs de informados (z63), mesma assinatura:
--      · fin.informado_normalizar: aceita parcela_n, parcela_de, contrato_assinado (chave ausente = mantém o atual);
--        contrato sem via_hotmart → false; contrato com via_hotmart true → erro.
--      · fn_fin_informado_salvar / fn_fin_informados_importar: gravam as colunas novas; a importação passa a usar a
--        parcela na chave de duplicata (nula fora do contrato → a chave dos outros tipos não muda).
--      · fn_fin_informados_listar: drop + create (RETURNS muda) com parcela_n, parcela_de, contrato_assinado NO FIM;
--        revoke public/anon + grant authenticated repetidos (o drop perde a ACL).
--      Situação: a mesma regra de fin.informados_situacao (inalterada): baixa → 'baixado_fora'; vencida há mais que a
--      tolerância (tolerancia_atraso_dias, 5 dias) e não baixada → 'em_atraso_cobrar'; senão 'a_receber'.
--   4) fin.receber_posicao: create or replace (mesma assinatura, mesmo RETURNS, mesma ACL) = corpo vivo da z67 +
--      · a situação dos informados sai UMA vez (CTE infs) e alimenta o bloco 5 e o bloco 7;
--      · o bloco 5 deixa de ver o tipo contrato_holding_familiar (não conta duas vezes);
--      · bloco 7 (ver CONTRATO). Sem kill-switch próprio: arquivar o contrato ou gravar a premissa 0 (decisão do
--        coordenador); o bloco 7 NÃO depende de informados_no_receber.
--   5) Fotos (z69): fin.receber_fotografar NÃO muda — grava tudo de fin.receber_posicao menos o bloco 8, então o
--      bloco 7 entra nas fotos (ref = id do informado, como o bloco 5; sem nome, sem tratamento).
--      fn_fin_receber_mudancas: create or replace — o item do bloco 7 é o informado (sem dia-chave, como o bloco 5: a
--      data de caixa da parcela vencida anda com o corte); sumir sem baixa = 'saiu_outro'.
--      fn_fin_receber_previsto_realizado: create or replace — realizado do bloco 7 = valor cheio da baixa manual na
--      data da baixa (a regra do bloco 5 fora da Hotmart).
--
-- CONTRATO do bloco 7 em public.fn_fin_receber_semanal / fin.receber_posicao (as mesmas 18 colunas; soma de caixa: só
-- situacao = 'a_receber', inalterado):
--   bloco 7 · grupo 'Contratos Holding Familiar — assinados' | 'Contratos Holding Familiar — sem contrato assinado'
--   componente 'cheio' · ref = id (uuid) do informado · rotulo = cliente · produto = produtos[1] (normalmente NULL)
--   origem_dia = vencimento (data_prevista) · k NULL · detalhe NULL
--   situacao 'a_receber'      → data_caixa = max(vencimento, dia do corte + 1); valor_bruto = valor da parcela;
--                               fator = % de recebimento do cenário (premissa por situação); valor = round(bruto × fator, 2)
--                               (fator 1 → valor = bruto exato);
--            'em_atraso_fora' → vencida há mais que a tolerância e não baixada ("Sim, cobrar"): data_caixa NULL, fator 1,
--                               FORA da soma;
--            'realizada'      → baixada: data_caixa NULL, valor = valor cheio, fator 1, FORA da soma.
--   certeza 'certo' (assinado) | 'estimado' (sem assinatura) · centro_custo '4. Receita de vendas (Direta de clientes)'
--   tratamento = 'Parcela 2 de 5 · contrato assinado · 100%' (+ ' · Vencida e não paga: cobrar (entra no dia seguinte
--   ao corte)' quando vencida dentro da tolerância) | 'Parcela 4 de 5 · contrato assinado · Em atraso: cobrar (vencido há
--   mais de 5 dias)' | 'contrato assinado · Baixado fora da Hotmart' (sem parcela, a 1ª parte some). Sem premissa
--   vigente: fator 1 e 'Sem premissa de recebimento (100%)'.
--   Tabela sem contratos (hoje): a saída é idêntica à de antes, linha a linha e ao centavo (conferência 9.3).
--
-- 5 perguntas:
--   escala: contratos são cadastro humano (a aba "Contratos Soluções" tem dezenas de linhas por ano). Custo novo por
--           chamada: 2 leituras de premissa (PK de premissas_receber) + 1 linha por contrato no horizonte. A situação dos
--           informados continua saindo UMA vez (antes: 1 chamada a fin.informados_situacao; agora: a mesma 1).
--   índice: nenhum filtro novo em tabela grande; recebimentos_informados tem centenas de linhas (Seq Scan é o plano
--           certo); premissa pela PK (chave, vigente_de). Provas P1–P4 com explain (analyze, buffers) abaixo.
--   frequência: a mesma RPC da aba e o cron semanal da foto (inalterados); nenhuma RPC nova.
--   repetição: regra do bloco 7 (data de caixa, %, certeza, tratamento) só no SQL; a tela só exibe.
--   reversão (nada se apaga):
--     Desligar um contrato: fn_fin_informado_arquivar(id, motivo). Zerar o esperado de uma situação:
--       select * from public.fn_fin_premissa_receber_salvar('recebimento_contrato:sem_assinatura', 0, current_date, 'base');
--     Reverter de verdade (uma transação):
--     begin;
--     -- a) arquivar todo contrato vivo (senão o bloco 5 antigo os mostraria como 'Outros recebimentos informados'):
--     --    update fin.recebimentos_informados set arquivado_em = now(), motivo_arquivo = 'reversão z73'
--     --     where tipo = 'contrato_holding_familiar' and arquivado_em is null;
--     -- b) create or replace com o corpo de origem (ACL preservada):
--     --    fin.receber_posicao ← 20260928z67 linhas 917–1087; fn_fin_receber_mudancas e
--     --    fn_fin_receber_previsto_realizado ← 20260928z69; fin.informado_normalizar, fn_fin_informado_salvar,
--     --    fn_fin_informados_importar ← 20260928z63;
--     -- c) drop function public.fn_fin_informados_listar(); + create com o corpo da z63 (linhas 693–723) + revoke/grant;
--     -- d) FICAM: colunas novas (nulas fora do contrato), CHECKs (o tipo novo não quebra leitor antigo), catálogo e
--     --    vigências recebimento_contrato:* (nenhum leitor antigo as lê).
--     commit;


-- ─── 0. Guarda ──────────────────────────────────────────────────────────────────────────────────────────────────────
create or replace function pg_temp.z73_norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(p, 'raise exception ''([^'']|'''')*''', 'raise exception', 'g'),
                                       '--[^\n]*', '', 'g'), '\s+', '', 'g')
$$;

do $guarda$
declare
  v_sig  text;
  v_md5  text;
  v_ori  text;
  v_obt  text;
  v_src  text;
  e_ck   text := 'CHECK ((tipo = ANY (ARRAY[''renovacao_diamante''::text, ''renovacao_aurum''::text, '
               || '''diamante_extra''::text, ''outro''::text])))';
  e_pos  text := 'TABLE(bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text, '
              || 'origem_dia date, ref text, rotulo text, produto text, k integer, detalhe jsonb, valor_bruto numeric, '
              || 'fator numeric, certeza text, centro_custo text, tratamento text, cenario text)';
  e_lis  text := 'TABLE(id uuid, data_prevista date, cliente text, tipo text, valor numeric, via_hotmart boolean, '
              || 'produtos text[], identificador1 text, identificador2 text, acordo_desde date, baixa_manual_em date, '
              || 'situacao text, recebido_hotmart numeric, acumulado_acordo numeric, valor_provisionado numeric, '
              || 'arquivado_em timestamp with time zone, motivo_arquivo text, atualizado_em timestamp with time zone)';
begin
  if to_regclass('fin.recebimentos_informados') is null or to_regclass('fin.recebimentos_informados_historico') is null
     or to_regclass('fin.premissas_receber_catalogo') is null or to_regclass('fin.receber_fotos') is null
     or to_regprocedure('fin.premissa(text,date,text)') is null or to_regprocedure('fin.receber_pct(numeric)') is null
     or to_regprocedure('fin.informados_situacao(timestamptz)') is null
     or to_regprocedure('fin.receber_projecao(timestamptz,date,text)') is null then
    raise exception 'z73: aplicar z63, z66, z67 e z69 antes (tabela ou função ausente)';
  end if;
  if exists (select 1 from information_schema.columns
              where table_schema = 'fin' and table_name = 'recebimentos_informados'
                and column_name in ('parcela_n','parcela_de','contrato_assinado'))
     or exists (select 1 from fin.premissas_receber_catalogo where chave like 'recebimento_contrato:%')
     or exists (select 1 from pg_constraint where conrelid = 'fin.recebimentos_informados'::regclass
                   and conname = 'recebimentos_informados_contrato_ck') then
    raise exception 'z73: já aplicada (coluna de contrato, chave recebimento_contrato:* ou CHECK do contrato existe)';
  end if;
  -- sobrecarga: create or replace com assinatura diferente criaria uma 2ª função viva
  select string_agg(x.n || '=' || x.c, ', ') into v_obt
    from (select p.proname n, count(*) c from pg_proc p
           where (p.pronamespace = 'fin'::regnamespace
                  and p.proname in ('receber_posicao','receber_fotografar','informado_normalizar'))
              or (p.pronamespace = 'public'::regnamespace
                  and p.proname in ('fn_fin_informado_salvar','fn_fin_informados_importar','fn_fin_informados_listar',
                                    'fn_fin_receber_mudancas','fn_fin_receber_previsto_realizado'))
           group by p.proname) x;
  if (select count(*) from pg_proc p
       where (p.pronamespace = 'fin'::regnamespace
              and p.proname in ('receber_posicao','receber_fotografar','informado_normalizar'))
          or (p.pronamespace = 'public'::regnamespace
              and p.proname in ('fn_fin_informado_salvar','fn_fin_informados_importar','fn_fin_informados_listar',
                                'fn_fin_receber_mudancas','fn_fin_receber_previsto_realizado'))) <> 8 then
    raise exception 'z73: sobrecarga viva ou função ausente (%) — conferir pg_get_function_arguments', v_obt;
  end if;

  -- corpo vivo = arquivo de origem (md5 do corpo normalizado; fin.receber_fotografar não muda, mas o bloco 7 só entra
  -- na foto porque ela grava tudo menos o bloco 8 — por isso é conferida também)
  for v_sig, v_md5, v_ori in
    select * from (values
      ('fin.receber_posicao(timestamptz,date,text)',                         '8dbc5277db16caa3f59829efe02e0dd6', 'z67'),
      ('fin.receber_fotografar(text,timestamptz)',                           'f1ad57c1c933bb14723aed468ae0b1ba', 'z69'),
      ('public.fn_fin_receber_mudancas(timestamptz,timestamptz)',            '125d3dc076b0190704272fa4b91ac495', 'z69'),
      ('public.fn_fin_receber_previsto_realizado(integer)',                  '4fbc0950444a44c7f40d8f9fe38a067a', 'z69'),
      ('fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)', '91deb5768bb9629cd9554f45e1f254bc', 'z63'),
      ('public.fn_fin_informado_salvar(jsonb)',                              'fd50549f5803ab900d99aa3fdb84df57', 'z63'),
      ('public.fn_fin_informados_importar(jsonb,boolean)',                   'a5c6f9b8bdb47f69032daa7449fa3c0c', 'z63'),
      ('public.fn_fin_informados_listar()',                                  '1d9538505c0f21023510abdfedd8b2aa', 'z63')
    ) x(sig, h, ori)
  loop
    select md5(pg_temp.z73_norm(p.prosrc)) into v_obt from pg_proc p where p.oid = to_regprocedure(v_sig);
    if v_obt is distinct from v_md5 then
      raise exception 'z73: corpo vivo de % diverge da % (md5 normalizado %, esperado %). Mandar pg_get_functiondef ao Victor.',
        v_sig, v_ori, coalesce(v_obt, 'ausente'), v_md5;
    end if;
  end loop;
  if regexp_replace(pg_get_function_result('fin.receber_posicao(timestamptz,date,text)'::regprocedure), '\s+', '', 'g')
     <> regexp_replace(e_pos, '\s+', '', 'g')
     or regexp_replace(pg_get_function_result('public.fn_fin_informados_listar()'::regprocedure), '\s+', '', 'g')
        <> regexp_replace(e_lis, '\s+', '', 'g') then
    raise exception 'z73: RETURNS vivo de fin.receber_posicao ou fn_fin_informados_listar diferente do esperado';
  end if;
  if not exists (select 1 from pg_proc p join pg_language l on l.oid = p.prolang
                  where p.oid = 'fin.receber_posicao(timestamptz,date,text)'::regprocedure and l.lanname = 'plpgsql'
                    and p.provolatile = 's' and not p.prosecdef and p.proconfig = array['search_path=""'])
     or not exists (select 1 from pg_proc p
                     where p.oid = 'fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)'::regprocedure
                       and p.provolatile = 's' and not p.prosecdef and p.proconfig = array['search_path=""']) then
    raise exception 'z73: atributos vivos de fin.receber_posicao / fin.informado_normalizar diferentes (plpgsql/stable/invoker/search_path vazio)';
  end if;

  -- CHECK do tipo: reescrito abaixo; conferir o vivo antes (CHECK de memória apaga valor em silêncio)
  select pg_get_constraintdef(c.oid) into v_src
    from pg_constraint c
   where c.conrelid = 'fin.recebimentos_informados'::regclass and c.conname = 'recebimentos_informados_tipo_check';
  if v_src is null or regexp_replace(v_src, '\s+', '', 'g') <> regexp_replace(e_ck, '\s+', '', 'g') then
    raise exception 'z73: CHECK recebimentos_informados_tipo_check vivo diferente do esperado: %', coalesce(v_src, 'ausente');
  end if;
  -- nenhum outro CHECK da tabela menciona tipo (senão o tipo novo seria barrado por ele)
  if exists (select 1 from pg_constraint c
              where c.conrelid = 'fin.recebimentos_informados'::regclass and c.contype = 'c'
                and c.conname <> 'recebimentos_informados_tipo_check' and pg_get_constraintdef(c.oid) ~ '\mtipo\M') then
    raise exception 'z73: outro CHECK de fin.recebimentos_informados menciona tipo — conferir antes';
  end if;
  if not exists (select 1 from fin.receber_fotos_cabecalho) then
    raise exception 'z73: nenhuma foto em fin.receber_fotos_cabecalho (a z69 grava a 1ª) — a conferência 9.3 compara mudanças';
  end if;
end $guarda$;


-- ─── 1. Foto ANTES (para a conferência 9.3: saída idêntica com a tabela sem contratos) ──────────────────────────────
do $foto$
declare
  v_adm uuid;
begin
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  if v_adm is null then raise exception 'z73: nenhum perfil admin ativo para a foto das RPCs'; end if;
  create temp table z73_pos_antes on commit drop as
    select 'passado'::text foto, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'base') x
    union all
    select 'passado_c'::text, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x
    union all
    select 'agora'::text, x.* from fin.receber_posicao(now(), null, 'base') x
    union all
    select 'agora_c'::text, x.* from fin.receber_posicao(now(), null, 'conservador') x
    union all
    select 'agora_o'::text, x.* from fin.receber_posicao(now(), null, 'otimista') x;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  create temp table z73_lis_antes on commit drop as select * from public.fn_fin_informados_listar();
  create temp table z73_pr_antes on commit drop as select * from public.fn_fin_receber_previsto_realizado(8);
  create temp table z73_mud_antes on commit drop as
    select * from public.fn_fin_receber_mudancas((select min(c.foto_em) from fin.receber_fotos_cabecalho c),
                                                 (select max(c.foto_em) from fin.receber_fotos_cabecalho c));
  perform set_config('request.jwt.claims', '', true);
  create temp table z73_cont on commit drop as
    select (select count(*) from fin.recebimentos_informados) inf,
           (select count(*) from fin.recebimentos_informados_historico) hist,
           (select count(*) from fin.receber_fotos_cabecalho) cab,
           (select count(*) from fin.receber_fotos) fotos,
           (select count(*) from fin.premissas_receber) prem;
end $foto$;


-- ─── 2. Tabela: tipo novo e colunas do contrato ─────────────────────────────────────────────────────────────────────
alter table fin.recebimentos_informados
  add column parcela_n int,
  add column parcela_de int,
  add column contrato_assinado boolean;
alter table fin.recebimentos_informados drop constraint recebimentos_informados_tipo_check;
alter table fin.recebimentos_informados
  add constraint recebimentos_informados_tipo_check
    check (tipo in ('renovacao_diamante','renovacao_aurum','diamante_extra','outro','contrato_holding_familiar')),
  add constraint recebimentos_informados_contrato_ck
    check (case when tipo = 'contrato_holding_familiar'
                then not via_hotmart
                     and contrato_assinado is not null
                     and (parcela_n is null) = (parcela_de is null)
                     and (parcela_n is null or (parcela_n >= 1 and parcela_n <= parcela_de and parcela_de <= 60))
                else parcela_n is null and parcela_de is null and contrato_assinado is null end);
comment on column fin.recebimentos_informados.parcela_n is
  'z73: contrato Holding Familiar — nº da parcela ("2" de "2 de 5"). Só no tipo contrato_holding_familiar.';
comment on column fin.recebimentos_informados.parcela_de is
  'z73: contrato Holding Familiar — total de parcelas ("5" de "2 de 5"), até 60. Só no tipo contrato_holding_familiar.';
comment on column fin.recebimentos_informados.contrato_assinado is
  'z73: contrato Holding Familiar — true = assinado, false = sem contrato assinado. Obrigatório no contrato; nulo nos outros.';
comment on table fin.recebimentos_informados is
  'Contas a Receber bloco 5 (z63) e bloco 7 (z73: tipo contrato_holding_familiar, fora da Hotmart): recebimentos '
  'previstos informados pelo Financeiro. Não se apaga: arquiva. Escrita só pelas RPCs fn_fin_informado_*. '
  'identificador = d:<dígitos> | e:<e-mail>, nunca a pessoa_chave.';


-- ─── 3. Premissas: % de recebimento do contrato por situação ────────────────────────────────────────────────────────
insert into fin.premissas_receber_catalogo (chave, rotulo, unidade, minimo, maximo, grupo_tela, ajuda, aceita_cenario) values
  ('recebimento_contrato:assinado', 'Recebimento — contrato Holding Familiar assinado', 'percentual', 0, 1,
   'Contratos Holding Familiar',
   'Parte do valor da parcela que entra na previsão quando o contrato está assinado. Esperado = valor × percentual, na data max(vencimento, dia seguinte ao corte).', true),
  ('recebimento_contrato:sem_assinatura', 'Recebimento — contrato Holding Familiar sem assinatura', 'percentual', 0, 1,
   'Contratos Holding Familiar',
   'Parte do valor da parcela que entra na previsão quando o contrato ainda não foi assinado (estimado). Planilha: 100% no base, 50% no conservador.', true);

insert into fin.premissas_receber (chave, vigente_de, valor, fonte) values
  ('recebimento_contrato:assinado',                   date '2000-01-01', 1,
   'planilha Contas a Receber Semanal, aba Premissas (catálogo P40)'),
  ('recebimento_contrato:sem_assinatura',             date '2000-01-01', 1,
   'planilha Contas a Receber Semanal, aba Premissas (catálogo P40)'),
  ('recebimento_contrato:sem_assinatura@conservador', date '2000-01-01', 0.5,
   'planilha Contas a Receber Semanal, aba Premissas (catálogo P40/P42: sem assinatura a 50% no conservador)');


-- ─── 4. RPCs de informados (z63 + campos do contrato) ───────────────────────────────────────────────────────────────
create or replace function fin.informado_normalizar(p jsonb, p_atual fin.recebimentos_informados, p_criando boolean)
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
  v_int  int;
  v_campo text;
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if p is null or jsonb_typeof(p) <> 'object' then
    raise exception 'Linha inválida: esperava um objeto com os campos do lançamento.' using errcode = 'P0001';
  end if;
  for k in select jsonb_object_keys(p) loop
    if k <> all (array['id','data_prevista','cliente','tipo','valor','via_hotmart','produtos','identificador1',
                       'identificador2','acordo_desde','baixa_manual_em','situacao','recebido_hotmart',
                       'acumulado_acordo','valor_provisionado','arquivado_em','motivo_arquivo','atualizado_em',
                       'parcela_n','parcela_de','contrato_assinado']) then   -- z73: campos do contrato
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
  if r.tipo is null
     or r.tipo not in ('renovacao_diamante','renovacao_aurum','diamante_extra','outro','contrato_holding_familiar') then
    raise exception 'Tipo inválido: "%". Use renovacao_diamante, renovacao_aurum, diamante_extra, outro ou contrato_holding_familiar.',
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
    if r.tipo = 'contrato_holding_familiar' and coalesce(jsonb_typeof(p -> 'via_hotmart'), 'null') = 'null' then
      r.via_hotmart := false;   -- z73: contrato Holding Familiar é sempre fora da Hotmart; a planilha não traz a coluna
    elsif jsonb_typeof(p -> 'via_hotmart') is distinct from 'boolean' then
      raise exception 'Informe via_hotmart como verdadeiro ou falso.' using errcode = 'P0001';
    else
      r.via_hotmart := (p ->> 'via_hotmart')::boolean;
    end if;
  end if;

  -- z73: contrato Holding Familiar (bloco 7). parcela "n de N" (as duas juntas ou nenhuma) e contrato assinado
  -- (obrigatório). Chave ausente mantém o atual. Em outro tipo os três não se aplicam: vir preenchido na chamada é erro;
  -- herdado da linha (troca de tipo) é limpo.
  foreach v_campo in array array['parcela_n','parcela_de'] loop
    if p_criando or p ? v_campo then
      v_txt := btrim(p ->> v_campo);
      if v_txt is null or v_txt = '' then
        v_int := null;
      elsif v_txt !~ '^[0-9]{1,2}$' then
        raise exception '% inválido: "%". Use número inteiro de 1 a 60.',
          case v_campo when 'parcela_n' then 'Número da parcela' else 'Total de parcelas' end, v_txt using errcode = 'P0001';
      else
        v_int := v_txt::int;
      end if;
      if v_campo = 'parcela_n' then r.parcela_n := v_int; else r.parcela_de := v_int; end if;
    end if;
  end loop;
  if p_criando or p ? 'contrato_assinado' then
    if coalesce(jsonb_typeof(p -> 'contrato_assinado'), 'null') = 'null' then
      r.contrato_assinado := null;
    elsif jsonb_typeof(p -> 'contrato_assinado') <> 'boolean' then
      raise exception 'Informe contrato_assinado como verdadeiro ou falso.' using errcode = 'P0001';
    else
      r.contrato_assinado := (p ->> 'contrato_assinado')::boolean;
    end if;
  end if;
  if r.tipo = 'contrato_holding_familiar' then
    if r.via_hotmart then
      raise exception 'Contrato Holding Familiar é recebido fora da Hotmart: via_hotmart deve ser falso.' using errcode = 'P0001';
    end if;
    if r.contrato_assinado is null then
      raise exception 'Contrato Holding Familiar: informe se o contrato está assinado (contrato_assinado).' using errcode = 'P0001';
    end if;
    if (r.parcela_n is null) <> (r.parcela_de is null) then
      raise exception 'Informe a parcela e o total de parcelas juntos (ex.: parcela 1 de 5).' using errcode = 'P0001';
    end if;
    if r.parcela_n is not null and (r.parcela_n < 1 or r.parcela_n > r.parcela_de or r.parcela_de > 60) then
      raise exception 'Parcela fora do intervalo: % de % (1 ≤ parcela ≤ total ≤ 60).', r.parcela_n, r.parcela_de
        using errcode = 'P0001';
    end if;
  else
    if (p ? 'parcela_n' and r.parcela_n is not null) or (p ? 'parcela_de' and r.parcela_de is not null)
       or (p ? 'contrato_assinado' and r.contrato_assinado is not null) then
      raise exception 'Parcela e contrato assinado só valem para o tipo contrato_holding_familiar.' using errcode = 'P0001';
    end if;
    r.parcela_n := null;
    r.parcela_de := null;
    r.contrato_assinado := null;
  end if;

  if p_criando or p ? 'produtos' then
    if p -> 'produtos' is null or jsonb_typeof(p -> 'produtos') = 'null' then
      r.produtos := '{}';
    elsif jsonb_typeof(p -> 'produtos') <> 'array' then
      raise exception 'Produtos deve ser uma lista.' using errcode = 'P0001';
    elsif jsonb_array_length(p -> 'produtos') > 10 then
      raise exception 'No máximo 10 produtos por lançamento.' using errcode = 'P0001';
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
                          case when p_criando then null else array[p_atual.identificador1] end);   -- só a mesma posição
  end if;
  if p_criando or p ? 'identificador2' then
    r.identificador2 := fin.informado_identificador(p ->> 'identificador2',
                          case when p_criando then null else array[p_atual.identificador2] end);   -- só a mesma posição
  end if;
  if r.identificador1 is null and r.identificador2 is not null then
    r.identificador1 := r.identificador2;
    r.identificador2 := null;
  end if;
  if r.identificador2 = r.identificador1 then r.identificador2 := null; end if;
  -- CPF/e-mail só grava quem pode vê-lo (regra da 0819g). Máscara devolvida sem mudança não é escrita.
  if (r.identificador1, r.identificador2) is distinct from (p_atual.identificador1, p_atual.identificador2)
     and not coalesce(public.gp_pode_ver_cpf(), false) then
    raise exception 'Sem permissão para informar CPF/e-mail.' using errcode = 'P0001';
  end if;

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

create or replace function public.fn_fin_informado_salvar(p jsonb)
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
  -- serializa as escritas de informados (mesma chave da importação): checagem de duplicata sem corrida
  perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
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
       baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado)
    values (r.data_prevista, r.cliente, r.tipo, r.valor, r.via_hotmart, r.produtos, r.produto_ids, r.identificador1, r.identificador2,
            r.acordo_desde, r.baixa_manual_em, r.baixa_manual_por, 'manual', v_uid, v_uid, r.parcela_n, r.parcela_de,
            r.contrato_assinado)
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
      r.acordo_desde, r.baixa_manual_em, r.parcela_n, r.parcela_de, r.contrato_assinado)
     is not distinct from
     (v_atual.data_prevista, v_atual.cliente, v_atual.tipo, v_atual.valor, v_atual.via_hotmart, v_atual.produto_ids,
      v_atual.identificador1, v_atual.identificador2, v_atual.acordo_desde, v_atual.baixa_manual_em,
      v_atual.parcela_n, v_atual.parcela_de, v_atual.contrato_assinado) then
    return v_id;   -- nada mudou: sem escrita, sem linha de histórico
  end if;
  update fin.recebimentos_informados x
     set data_prevista = r.data_prevista, cliente = r.cliente, tipo = r.tipo, valor = r.valor,
         via_hotmart = r.via_hotmart, produtos = r.produtos, produto_ids = r.produto_ids,
         identificador1 = r.identificador1,
         identificador2 = r.identificador2, acordo_desde = r.acordo_desde,
         baixa_manual_em = r.baixa_manual_em, baixa_manual_por = r.baixa_manual_por,
         parcela_n = r.parcela_n, parcela_de = r.parcela_de, contrato_assinado = r.contrato_assinado,
         atualizado_por = v_uid, atualizado_em = now()
   where x.id = v_id;
  return v_id;
end $$;
comment on function public.fn_fin_informado_salvar(jsonb) is
  'Contas a Receber (z63; contrato z73): cria (sem id) ou altera um recebimento informado. Campo ausente mantém o atual. '
  'Contrato Holding Familiar: tipo contrato_holding_familiar + parcela_n, parcela_de, contrato_assinado.';
revoke all on function public.fn_fin_informado_salvar(jsonb) from public, anon;
grant execute on function public.fn_fin_informado_salvar(jsonb) to authenticated;

create or replace function public.fn_fin_informados_importar(p_linhas jsonb, p_simular boolean default true)
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
  -- serializa as escritas de informados (mesma chave de fn_fin_informado_salvar): duas importações simultâneas da
  -- mesma planilha não passam juntas pela checagem "Já cadastrado". A prévia (simular) é leitura: não trava.
  if not p_simular then
    perform pg_advisory_xact_lock(hashtext('fin.recebimentos_informados:escrita'));
  end if;
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
      -- z73: parcela entra na chave (nula fora do contrato: a chave dos outros tipos não muda)
      v_chave := concat_ws('|', r.data_prevista, lower(r.cliente), r.valor, r.tipo, r.parcela_n);
      if v_chave = any (v_chaves) then
        raise exception 'Linha repetida nesta importação (mesma data, cliente, valor e tipo%).',
          coalesce(', parcela ' || r.parcela_n, '') using errcode = 'P0001';
      end if;
      if exists (select 1 from fin.recebimentos_informados x
                  where x.arquivado_em is null and x.data_prevista = r.data_prevista
                    and lower(x.cliente) = lower(r.cliente) and x.valor = r.valor and x.tipo = r.tipo
                    and x.parcela_n is not distinct from r.parcela_n) then
        raise exception 'Já cadastrado (mesma data, cliente, valor e tipo%).',
          coalesce(', parcela ' || r.parcela_n, '') using errcode = 'P0001';
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
       baixa_manual_em, baixa_manual_por, origem, criado_por, atualizado_por, parcela_n, parcela_de, contrato_assinado)
    values (r.data_prevista, r.cliente, r.tipo, r.valor, r.via_hotmart, r.produtos, r.produto_ids, r.identificador1, r.identificador2,
            r.acordo_desde, r.baixa_manual_em, r.baixa_manual_por, 'importacao', v_uid, v_uid, r.parcela_n, r.parcela_de,
            r.contrato_assinado)
    returning x.id into v_id;
    linha := i; ok := true; erro := null; id := v_id;
    return next;
  end loop;
end $$;
comment on function public.fn_fin_informados_importar(jsonb, boolean) is
  'Contas a Receber (z63; contrato z73): importa até 500 recebimentos informados. Simular = prévia; gravar = tudo ou nada. '
  'Colunas do contrato: parcela_n, parcela_de, contrato_assinado (a parcela entra na chave de duplicata).';
revoke all on function public.fn_fin_informados_importar(jsonb, boolean) from public, anon;
grant execute on function public.fn_fin_informados_importar(jsonb, boolean) to authenticated;

drop function public.fn_fin_informados_listar();
create function public.fn_fin_informados_listar()
returns table (id uuid, data_prevista date, cliente text, tipo text, valor numeric, via_hotmart boolean,
               produtos text[], identificador1 text, identificador2 text, acordo_desde date, baixa_manual_em date,
               situacao text, recebido_hotmart numeric, acumulado_acordo numeric, valor_provisionado numeric,
               arquivado_em timestamptz, motivo_arquivo text, atualizado_em timestamptz,
               parcela_n int, parcela_de int, contrato_assinado boolean)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_cpf boolean;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  -- LGPD (regra da 0819g): identificador completo só para gp_pode_ver_cpf(); o resto vê CPF ···1234 / a***@dominio.
  -- recebido_hotmart (quanto a pessoa identificada pagou na Hotmart) também só para quem vê CPF; senão NULL.
  v_cpf := coalesce(public.gp_pode_ver_cpf(), false);
  return query
  select r.id, r.data_prevista, r.cliente, r.tipo, r.valor::numeric, r.via_hotmart, r.produtos,
         case when v_cpf then substr(r.identificador1, 3) else fin.informado_mascara(r.identificador1) end,
         case when v_cpf then substr(r.identificador2, 3) else fin.informado_mascara(r.identificador2) end,
         r.acordo_desde, r.baixa_manual_em,
         s.situacao, case when v_cpf then s.recebido_hotmart end, s.acumulado_acordo, s.valor_provisionado,
         r.arquivado_em, r.motivo_arquivo, r.atualizado_em,
         r.parcela_n, r.parcela_de, r.contrato_assinado   -- z73
    from fin.recebimentos_informados r
    join fin.informados_situacao(now()) s on s.id = r.id
   order by r.arquivado_em nulls first, r.data_prevista, r.cliente, r.id;
end $$;
comment on function public.fn_fin_informados_listar() is
  'Contas a Receber (z63; contrato z73): recebimentos informados com situação no agora. Identificador mascarado sem '
  'gp_pode_ver_cpf(). parcela_n, parcela_de, contrato_assinado no fim (nulos fora do contrato Holding Familiar).';
revoke all on function public.fn_fin_informados_listar() from public, anon;
grant execute on function public.fn_fin_informados_listar() to authenticated;


-- ─── 5. A previsão: corpo da z67 + bloco 7 ──────────────────────────────────────────────────────────────────────────
create or replace function fin.receber_posicao(p_corte timestamptz, p_ate date, p_cenario text)
returns table (bloco smallint, grupo text, componente text, data_caixa date, valor numeric, situacao text,
               origem_dia date, ref text, rotulo text, produto text, k int, detalhe jsonb,
               valor_bruto numeric, fator numeric, certeza text, centro_custo text, tratamento text, cenario text)
language plpgsql stable set search_path = ''
as $$
#variable_conflict use_column
declare
  v_corte timestamptz := p_corte;
  v_cen   text := p_cenario;
  v_dia   date;
  v_ate   date;
  v_max   int;
  v_tol   int;
  v_inf   boolean;
  v_proj  boolean;
begin
  if p_corte is null then
    raise exception 'fin.receber_posicao: corte obrigatório' using errcode = '22023';
  end if;
  if v_cen is null or v_cen not in ('base','conservador','otimista') then
    raise exception 'Cenário inválido (base, conservador ou otimista).' using errcode = '22023';
  end if;
  v_dia := (p_corte at time zone 'America/Sao_Paulo')::date;
  v_ate := coalesce(p_ate, (date_trunc('month', v_dia::timestamp) + interval '4 months' - interval '1 day')::date);
  if v_ate < v_dia or v_ate > v_dia + 400 then
    raise exception 'Horizonte fora do intervalo (do corte até 400 dias depois).' using errcode = '22023';
  end if;
  v_max := fin.premissa('atraso_max_projetado_dias', v_dia, 'base')::int;
  v_tol := fin.premissa('tolerancia_atraso_dias', v_dia, 'base')::int;
  v_inf := fin.premissa('informados_no_receber', v_dia, 'base') > 0;
  if v_max is null or v_tol is null or v_inf is null then
    raise exception 'Premissa do contas a receber ausente (atraso_max_projetado_dias / tolerancia_atraso_dias / informados_no_receber).'
      using errcode = 'P0002';
  end if;
  -- z67: kill-switch da projeção (blocos 3, 4, 6 e 8). Sem vigência = desligada.
  v_proj := coalesce(fin.premissa('projecao_no_receber', v_dia, 'base') > 0, false);

  return query
  with vig as materialized (
    -- texto do caixa por vigência de fin.premissas_recebimento (as mesmas premissas de fin.recebimento)
    select pr.vigente_de de, lead(pr.vigente_de) over (order by pr.vigente_de) ate,
           'Antecipação D+' || pr.dias_ate_entrar || case when pr.dias_uteis then ' útil' else '' end
             || ' (' || fin.receber_pct(1 - pr.pct_retido) || ' − ' || fin.receber_pct(pr.taxa_antecipacao) || ')' t_ant,
           'Retido ' || fin.receber_pct(pr.pct_retido) || ' volta em D+' || pr.dias_retencao t_ret
      from fin.premissas_recebimento pr
  ), perda as materialized (
    select m.bloco, m.grupo, x.p,
           case when x.p > 0 then 'Perda ' || fin.receber_pct(x.p) || '/mês' end t_perda
      from (values (2::smallint, 'Assinaturas Serviço Diamante'::text,         'perda_mensal:servico_diamante'::text),
                   (2::smallint, 'Assinaturas Holding - Holding Masters'::text, 'perda_mensal:holding_hm'::text),
                   (2::smallint, 'Outras assinaturas'::text,                    'perda_mensal:outras_assinaturas'::text),
                   (2::smallint, 'Parcelas a vencer HM'::text,                  'perda_mensal:parcelas_hm'::text),
                   (2::smallint, 'Parcelas a vencer Aurum'::text,               'perda_mensal:parcelas_aurum'::text),
                   (2::smallint, 'Parcelas a vencer outros'::text,              'perda_mensal:parcelas_outros'::text),
                   (5::smallint, null::text,                                    'perda_mensal:informados'::text)
           ) m(bloco, grupo, chave)
      cross join lateral (select fin.premissa(m.chave, v_dia, v_cen) p) x
  ), cob as materialized (
    select cb.ref, cb.de, cb.ate from fin.informados_cobertura(v_corte) cb where v_inf
  ), b2 as (
    select c.grupo, c.vencimento, c.ref, c.rotulo, c.produto, c.k, c.valor, c.entra_em, c.entra_rapido,
           c.libera_em, c.retido, c.data_efetiva, c.detalhe,
           case when c.situacao in ('a_receber','em_atraso_fora')
                     and exists (select 1 from cob where cob.ref = c.ref and c.vencimento between cob.de and cob.ate)
                then 'coberta_informado' else c.situacao end sit
      from fin.cobrancas_previstas(v_corte, v_ate) c
  ), infs as materialized (
    -- z73: a situação dos informados sai UMA vez; o bloco 5 e o bloco 7 (contratos Holding Familiar) leem daqui
    select r.id, r.tipo, r.cliente, r.produtos, r.via_hotmart, r.data_prevista, r.valor,
           r.parcela_n, r.parcela_de, r.contrato_assinado,
           s.situacao sit, s.valor_provisionado prov, s.data_efetiva efetiva
      from fin.informados_situacao(v_corte) s
      join fin.recebimentos_informados r on r.id = s.id
     where s.situacao <> 'arquivado' and r.data_prevista <= v_ate
       and (s.situacao = 'a_receber' or r.data_prevista >= v_dia - v_max)
  ), inf as materialized (
    select x.id, x.tipo, x.cliente, x.produtos, x.via_hotmart, x.data_prevista, x.valor, x.sit, x.prov, x.efetiva
      from infs x
     where v_inf and x.tipo <> 'contrato_holding_familiar'   -- z73: o contrato é do bloco 7 (não conta duas vezes)
  ), c7 as materialized (
    select x.* from infs x where x.tipo = 'contrato_holding_familiar'
  ), pct7 as materialized (
    -- z73: % de recebimento por situação do contrato, vigente no dia do corte, no cenário (senão a base)
    select a.assinado,
           fin.premissa(case when a.assinado then 'recebimento_contrato:assinado'
                             else 'recebimento_contrato:sem_assinatura' end, v_dia, v_cen) p
      from (values (true), (false)) a(assinado)
  ), linhas as (
    select 1::smallint bl, 'Vendas já realizadas'::text gr, b.componente comp, b.data_caixa dc, b.valor bruto,
           'a_receber'::text sit, b.origem_dia od, null::text rf, null::text rot, null::text prod, null::int kk,
           b.detalhe det, b.origem_dia dia_regra, null::int k_perda, true via, null::text trat
      from fin.receber_vendas_realizadas(v_corte) b
    union all
    select 2::smallint, c.grupo, u.componente, u.data_caixa, u.valor, c.sit, c.vencimento,
           c.ref, c.rotulo, c.produto, c.k,
           case when u.componente <> 'garantia' then c.detalhe end,   -- 1× por cobrança (a garantia é a mesma cobrança)
           c.data_efetiva, c.k, true,
           case c.sit when 'em_atraso_fora'    then 'Fora da projeção: atraso > ' || v_tol || ' dias'
                      when 'realizada'         then 'Paga: sai da previsão'
                      when 'coberta_informado' then 'Coberta por recebimento informado'
                      when 'a_receber' then case when c.vencimento <= v_dia
                                                 then 'Atraso dentro da tolerância: entra no dia seguinte ao corte' end
           end
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
           i.id::text, i.cliente, i.produtos[1], null::int, null::jsonb,
           i.efetiva,
           case when u.sit = 'a_receber'
                then ((extract(year from i.efetiva) - extract(year from v_dia)) * 12
                      + extract(month from i.efetiva) - extract(month from v_dia))::int + 1 end,
           i.via_hotmart, u.trat
      from inf i
      left join lateral fin.recebimento(i.efetiva, i.prov) f on i.via_hotmart and i.sit = 'a_receber'
      cross join lateral (
        select 'antecipacao'::text, f.entra_em, f.entra_rapido, 'a_receber'::text, null::text
         where i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'garantia'::text, f.libera_em, f.retido, 'a_receber'::text, null::text
         where i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'cheio'::text, i.efetiva, i.prov, 'a_receber'::text, 'Fora da Hotmart: entra cheio na data'::text
         where not i.via_hotmart and i.sit = 'a_receber'
        union all
        select 'cheio'::text, null::date, i.prov, 'em_atraso_fora'::text,
               'Em atraso: cobrar (vencido há mais de ' || v_tol || ' dias)'
         where i.sit = 'em_atraso_cobrar'
        union all
        select 'cheio'::text, null::date, i.valor::numeric, 'realizada'::text,
               case i.sit when 'baixado_fora' then 'Baixado fora da Hotmart' else 'Realizado na Hotmart' end
         where i.sit in ('realizado_hotmart','baixado_fora')
      ) u(componente, data_caixa, valor, sit, trat)
  )
  select l.bl, l.gr, l.comp, l.dc,
         case when f.fator = 1 then l.bruto else round(l.bruto * f.fator, 2) end,
         l.sit, l.od, l.rf, l.rot, l.prod, l.kk,
         case when l.bl <> 2 then l.det
              when row_number() over (partition by l.bl, l.rf
                                      order by (l.sit = 'a_receber') desc, l.od nulls last, l.comp, l.sit,
                                               l.dc nulls last) = 1
              then l.det end,   -- z67: detalhe do bloco 2 UMA vez por contrato (1ª a_receber por vencimento)
         l.bruto, f.fator,
         case when l.bl in (1, 2, 5) then 'certo' else 'estimado' end,
         case when l.via then '1. Receita de vendas (Hotmart)' else '4. Receita de vendas (Direta de clientes)' end,
         concat_ws(' · ',
           case when l.sit = 'a_receber' and l.comp = 'antecipacao' then coalesce(v.t_ant, 'Antecipação')
                when l.sit = 'a_receber' and l.comp = 'garantia'    then coalesce(v.t_ret, 'Retido')
           end,
           l.trat,
           case when l.sit = 'a_receber' and l.k_perda is not null then
                  case when pe.p is null then 'Sem premissa de perda do grupo (fator 1)'
                       when pe.p > 0 then pe.t_perda || ' × ' || l.k_perda
                                          || case when l.k_perda = 1 then ' mês' else ' meses' end
                  end
           end),
         v_cen
    from linhas l
    left join perda pe on pe.bloco = l.bl and (pe.grupo = l.gr or pe.grupo is null)
    left join vig v on l.comp in ('antecipacao','garantia') and l.dia_regra >= v.de and (v.ate is null or l.dia_regra < v.ate)
    cross join lateral (
      select case when l.sit = 'a_receber' and l.k_perda is not null and pe.p > 0
                  then pg_catalog.trim_scale(round(power(1 - pe.p, l.k_perda), 10)) else 1::numeric end fator
    ) f
  union all
  select pj.* from fin.receber_projecao(v_corte, v_ate, v_cen) pj where v_proj   -- z67
  union all
  -- z73: bloco 7 — contratos Holding Familiar (CSM Soluções, fora da Hotmart). Cheio na data de caixa
  -- max(vencimento, dia do corte + 1); esperado = valor × % de recebimento (premissa por situação, com cenário).
  select 7::smallint,
         case when c.contrato_assinado then 'Contratos Holding Familiar — assinados'
              else 'Contratos Holding Familiar — sem contrato assinado' end,
         'cheio'::text, u.dc,
         case when u.fat = 1 then u.bruto else round(u.bruto * u.fat, 2) end,
         u.sit, c.data_prevista, c.id::text, c.cliente, c.produtos[1], null::int, null::jsonb,
         u.bruto, u.fat,
         case when c.contrato_assinado then 'certo' else 'estimado' end,
         '4. Receita de vendas (Direta de clientes)'::text,
         concat_ws(' · ',
           case when c.parcela_n is not null then 'Parcela ' || c.parcela_n || ' de ' || c.parcela_de end,
           case when c.contrato_assinado then 'contrato assinado' else 'sem contrato assinado' end,
           u.trat),
         v_cen
    from c7 c
    left join pct7 pc on pc.assinado = c.contrato_assinado
    cross join lateral (
      select c.efetiva, c.prov, 'a_receber'::text, pg_catalog.trim_scale(coalesce(pc.p, 1::numeric)),
             concat_ws(' · ',
               case when pc.p is null then 'Sem premissa de recebimento (100%)' else fin.receber_pct(pc.p) end,
               case when c.data_prevista < v_dia then 'Vencida e não paga: cobrar (entra no dia seguinte ao corte)' end)
       where c.sit = 'a_receber'
      union all
      select null::date, c.prov, 'em_atraso_fora'::text, 1::numeric,
             'Em atraso: cobrar (vencido há mais de ' || v_tol || ' dias)'
       where c.sit = 'em_atraso_cobrar'
      union all
      select null::date, c.valor::numeric, 'realizada'::text, 1::numeric, 'Baixado fora da Hotmart'::text
       where c.sit in ('realizado_hotmart','baixado_fora')
    ) u(dc, bruto, sit, fat, trat)
   order by 1, 4 nulls last, 2, 3;
end $$;
comment on function fin.receber_posicao(timestamptz, date, text) is
  'Contas a Receber (z66; projeção z67; contratos z73): a previsão inteira no corte — blocos 1, 2, 5 (certo), 7 '
  '(contratos Holding Familiar: certo se assinado, estimado sem assinatura) e, com a premissa projecao_no_receber > 0, '
  'os blocos 3, 4, 6 (estimado) e 8 (informativo, fora da soma). Interna: sem guarda de sessão. Soma só situacao = a_receber.';
revoke all on function fin.receber_posicao(timestamptz, date, text) from public, anon, authenticated;

comment on function public.fn_fin_receber_semanal(timestamptz, date, text) is
  'Aba Contas a Receber (z61 + z63 + z66 + z67 + z73): blocos 1, 2, 5, 7 e, com a projeção ligada, 3, 4, 6 e 8. '
  'valor = esperado (bruto × fator); valor_bruto = sem perda. Soma só situacao = a_receber. Sem e-mail/documento.';


-- ─── 6. Fotos: mudanças e previsto × realizado com o bloco 7 ────────────────────────────────────────────────────────
comment on table fin.receber_fotos is
  'Contas a Receber (z69; bloco 7 z73): as linhas de fin.receber_posicao no corte da foto, agregadas por (bloco, grupo, '
  'ref, data_caixa, componente, origem_dia, situacao). Sem nome, e-mail, documento, rótulo, produto, detalhe ou '
  'tratamento. ref: bloco 2 HMAC do contrato; 5 e 7 id do informado; 3/4/6 chaves da projeção; 1 nulo. Só acréscimo.';

create or replace function public.fn_fin_receber_mudancas(p_foto_a timestamptz, p_foto_b timestamptz)
returns table (bloco smallint, grupo text, valor_a numeric, valor_b numeric, delta numeric, motivos jsonb)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_cen_a text;
  v_cen_b text;
  v_dia_b date;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_foto_a is null or p_foto_b is null then
    raise exception 'Informe as duas fotos.' using errcode = '22023';
  end if;
  select c.cenario into v_cen_a from fin.receber_fotos_cabecalho c where c.foto_em = p_foto_a;
  select c.cenario, c.dia into v_cen_b, v_dia_b from fin.receber_fotos_cabecalho c where c.foto_em = p_foto_b;
  if v_cen_a is null or v_cen_b is null then
    raise exception 'Foto não encontrada (use fn_fin_receber_fotos_listar).' using errcode = '22023';
  end if;

  return query
  with a as materialized (
    select f.bloco, f.grupo, coalesce(f.ref, '') r,
           coalesce(case when f.bloco in (1, 2) then f.origem_dia when f.bloco in (5, 7) then null else f.data_caixa end,
                    date '0001-01-01') kd,
           f.componente, f.situacao, f.data_caixa, f.origem_dia, f.valor, f.valor_bruto
      from fin.receber_fotos f where f.foto_em = p_foto_a
  ), b as materialized (
    select f.bloco, f.grupo, coalesce(f.ref, '') r,
           coalesce(case when f.bloco in (1, 2) then f.origem_dia when f.bloco in (5, 7) then null else f.data_caixa end,
                    date '0001-01-01') kd,
           f.componente, f.situacao, f.data_caixa, f.origem_dia, f.valor, f.valor_bruto
      from fin.receber_fotos f where f.foto_em = p_foto_b
  ), ia as (
    select a.bloco, a.r, a.kd, a.componente, max(a.grupo) grupo, sum(a.valor) v, sum(a.valor_bruto) vb, max(a.data_caixa) dc
      from a where a.situacao = 'a_receber' group by 1, 2, 3, 4
  ), ib as (
    select b.bloco, b.r, b.kd, b.componente, max(b.grupo) grupo, sum(b.valor) v, sum(b.valor_bruto) vb
      from b where b.situacao = 'a_receber' group by 1, 2, 3, 4
  ), sb as (
    select b.bloco, b.r, b.kd, bool_or(b.situacao = 'realizada') pago, bool_or(b.situacao = 'em_atraso_fora') atraso,
           bool_or(b.situacao = 'coberta_informado') coberta
      from b where b.situacao <> 'a_receber' group by 1, 2, 3
  ), b2n as (
    select distinct b.r from b where b.bloco = 2 and b.situacao = 'realizada' and b.origem_dia is null
  ), j as (
    select coalesce(ib.bloco, ia.bloco) bloco, coalesce(ib.grupo, ia.grupo) grupo,
           coalesce(ib.r, ia.r) || '|' || coalesce(ib.kd, ia.kd) item, ia.v va, ib.v vb,
           case when ia.v is null and ib.v is null then null
                when ia.bloco is null then 'entrou'
                when ib.bloco is null then
                  case when sb.pago then 'saiu_pagamento'
                       when sb.atraso then 'saiu_atraso'
                       when sb.coberta then 'saiu_outro'
                       when ia.bloco = 2 and exists (select 1 from b2n where b2n.r = ia.r) then 'saiu_pagamento'
                       when ia.bloco = 7 then 'saiu_outro'   -- z73: contrato só sai pago por baixa (sb.pago); sumir = arquivado
                       when ia.dc <= v_dia_b then case when ia.bloco in (1, 2, 5) then 'saiu_pagamento' else 'saiu_periodo' end
                       else 'saiu_outro' end
                when ia.v = ib.v then null
                when ia.bloco in (3, 4, 6) or v_cen_a <> v_cen_b or ia.vb = ib.vb then 'mudou_premissa'
                else 'mudou_valor' end motivo
      from ia
      full join ib on ib.bloco = ia.bloco and ib.r = ia.r and ib.kd = ia.kd and ib.componente = ia.componente
      left join sb on ib.bloco is null and sb.bloco = ia.bloco and sb.r = ia.r and sb.kd = ia.kd
  ), k as (
    select j.bloco, j.grupo, j.motivo, count(distinct j.item)::int itens, sum(coalesce(j.vb, 0) - coalesce(j.va, 0)) valor
      from j where j.motivo is not null group by 1, 2, 3
  ), t as (
    select j.bloco, j.grupo, coalesce(sum(j.va), 0) va, coalesce(sum(j.vb), 0) vb from j group by 1, 2
  )
  select t.bloco, t.grupo, t.va, t.vb, t.vb - t.va,
         coalesce((select jsonb_agg(jsonb_build_object('motivo', k.motivo, 'itens', k.itens, 'valor', k.valor)
                                    order by array_position(array['entrou','saiu_pagamento','saiu_atraso','saiu_periodo',
                                                                  'saiu_outro','mudou_valor','mudou_premissa'], k.motivo))
                     from k where k.bloco = t.bloco and k.grupo is not distinct from t.grupo), '[]'::jsonb)
    from t
   order by 1, 2;
end $$;
revoke all on function public.fn_fin_receber_mudancas(timestamptz, timestamptz) from public, anon;
grant execute on function public.fn_fin_receber_mudancas(timestamptz, timestamptz) to authenticated;

create or replace function public.fn_fin_receber_previsto_realizado(p_semanas int default 8)
returns table (linha text, semana_de date, semana_ate date, janela_de date, janela_ate date, foto_em timestamptz,
               bloco smallint, grupo text, previsto numeric, previsto_bruto numeric, realizado numeric, desvio numeric,
               acerto_pct numeric, chave_premissa text, perda_medida numeric, premissa_atual numeric,
               cobrancas_resolvidas int, cobrancas_perdidas int, valor_resolvido numeric, valor_perdido numeric,
               nota text)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_seg  date;
  v_tol  int;
begin
  if (select auth.uid()) is null or not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if p_semanas is null or p_semanas < 1 or p_semanas > 52 then
    raise exception 'Semanas: de 1 a 52.' using errcode = '22023';
  end if;
  v_seg := (date_trunc('week', v_hoje::timestamp))::date;
  v_tol := fin.premissa('tolerancia_atraso_dias', v_hoje, 'base')::int;
  if v_tol is null then
    raise exception 'Premissa tolerancia_atraso_dias ausente.' using errcode = 'P0002';
  end if;

  return query
  with fw as materialized (
    -- a semana, a foto base do início dela e a janela que a foto consegue prever
    select s.de, s.de + 6 ate, c.foto_em, c.corte, c.dia,
           case when c.foto_em is not null then greatest(s.de, c.dia + 1) end j0, s.de + 6 j1,
           (c.foto_em at time zone 'America/Sao_Paulo')::date > c.dia reconstruida
      from (select v_seg - 7 * g.n de from generate_series(1, p_semanas) g(n)) s
      left join lateral (
        select c.foto_em, c.corte, c.dia from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia <= s.de and c.dia > s.de - 7
         order by c.dia desc, c.foto_em desc limit 1
      ) c on true
  ), itens as materialized (
    select fw.de, f.bloco, f.grupo, f.ref, f.origem_dia, f.componente, f.data_caixa, f.valor, f.valor_bruto
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.situacao = 'a_receber'
  ), prev as (
    select i.de, i.bloco, i.grupo, sum(i.valor) previsto, sum(i.valor_bruto) previsto_bruto
      from itens i join fw on fw.de = i.de
     where i.data_caixa between fw.j0 and fw.j1
     group by 1, 2, 3
  ), r1 as (
    -- bloco 1: as vendas pagas até o corte (status de AGORA), pela mesma função da previsão
    select fw.de, 1::smallint bloco, 'Vendas já realizadas'::text grupo, sum(v.valor) realizado
      from fw cross join lateral fin.receber_vendas_realizadas(fw.corte) v
     where fw.foto_em is not null and v.data_caixa between fw.j0 and fw.j1
     group by fw.de
  ), tx as materialized (
    -- vendas pagas DEPOIS do corte até o fim da janela (predicado literal do índice parcial aprovado_pago_idx)
    select fw.de, t.transacao, t.email, t.oferta_codigo, t.oferta_modo, t.produto_id, t.recorrencia, t.dia_aprovado,
           t.liquido
      from fw
      join fin.vw_transacoes t
        on t.status in ('APPROVED','COMPLETE')
       and t.aprovado_em > fw.corte
       and t.aprovado_em < (fw.j1 + 1)::timestamp at time zone 'America/Sao_Paulo'
     where fw.foto_em is not null
  ), inf as materialized (
    select distinct i.de, i.ref::uuid id, i.grupo from itens i where i.bloco = 5
  ), alvo as materialized (
    select a.id, a.emails, a.docs from fin.informados_alvos() a where a.id in (select inf.id from inf)
  ), m5 as (
    -- bloco 5 via Hotmart: a mesma regra de casamento de fin.informados_situacao (e-mail OU documento, produto, acordo)
    select distinct on (x.de, x.transacao) x.de, x.transacao, inf.grupo
      from tx x
      join inf on inf.de = x.de
      join fin.recebimentos_informados r on r.id = inf.id and r.via_hotmart
      join alvo a on a.id = inf.id
      join fin.hotmart_transacoes h on h.transacao = x.transacao
     where x.produto_id = any (r.produto_ids) and x.dia_aprovado >= r.acordo_desde
       and (lower(trim(h.comprador_email)) = any (a.emails)
            or regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = any (a.docs))
     order by x.de, x.transacao, r.data_prevista, r.id
  ), rc as materialized (
    -- contrato recorrente → a MESMA ref opaca de fin.cobrancas_previstas ('rc:' || e-mail || '|' || oferta)
    select y.email, y.oferta_codigo, fin.chave_opaca('rc:' || y.email || '|' || y.oferta_codigo) ref
      from (select distinct x.email, x.oferta_codigo from tx x
             where x.recorrencia >= 2 and x.email is not null and x.oferta_codigo is not null
               and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')) y
  ), g2 as materialized (
    select distinct on (fw.de, f.ref) fw.de, f.ref, f.grupo
      from fw join fin.receber_fotos f on f.foto_em = fw.foto_em
     where f.bloco = 2
     order by fw.de, f.ref, f.grupo
  ), atrib as (
    select x.de, x.dia_aprovado, x.liquido,
           case when m5.transacao is not null then 5 when g2.ref is not null then 2 end::smallint bloco,
           coalesce(m5.grupo, g2.grupo, 'Fora da foto (vendas novas e outros)') grupo
      from tx x
      left join m5 on m5.de = x.de and m5.transacao = x.transacao
      left join rc on x.recorrencia >= 2 and rc.email = x.email and rc.oferta_codigo = x.oferta_codigo
                  and (x.oferta_modo in ('SUBSCRIPTION','MULTIPLE_PAYMENTS') or x.oferta_modo like 'HOTMART_INSTALLMENTS%')
      left join g2 on g2.de = x.de and g2.ref = rc.ref
  ), rpos as (
    select d.de, d.bloco, d.grupo,
           sum(case when r.entra_em between fw.j0 and fw.j1 then r.entra_rapido else 0 end
               + case when r.libera_em between fw.j0 and fw.j1 then r.retido else 0 end) realizado
      from (select a.de, a.bloco, a.grupo, a.dia_aprovado, sum(a.liquido) liq
              from atrib a group by 1, 2, 3, 4) d
      join fw on fw.de = d.de
      cross join lateral fin.recebimento(d.dia_aprovado, d.liq) r
     group by 1, 2, 3
  ), r5b as (
    -- baixa manual (fora da Hotmart): valor cheio na data da baixa
    select inf.de, 5::smallint bloco, inf.grupo, sum(r.valor) realizado
      from inf
      join fw on fw.de = inf.de
      join fin.recebimentos_informados r on r.id = inf.id
     where r.baixa_manual_em between fw.j0 and fw.j1
     group by 1, 2, 3
  ), r7b as (
    -- z73: contrato Holding Familiar (bloco 7, fora da Hotmart): valor cheio na data da baixa, como o bloco 5
    select i7.de, 7::smallint bloco, i7.grupo, sum(r.valor) realizado
      from (select distinct i.de, i.ref::uuid id, i.grupo from itens i where i.bloco = 7) i7
      join fw on fw.de = i7.de
      join fin.recebimentos_informados r on r.id = i7.id
     where r.baixa_manual_em between fw.j0 and fw.j1
     group by 1, 2, 3
  ), rea as (
    select u.de, u.bloco, u.grupo, sum(u.realizado) realizado
      from (select * from r1 union all select * from rpos union all select * from r5b union all select * from r7b) u
     group by 1, 2, 3
  ), sem as (
    select fw.de, fw.ate, fw.j0, fw.j1, fw.foto_em, coalesce(p.bloco, r.bloco) bloco, coalesce(p.grupo, r.grupo) grupo,
           p.previsto, p.previsto_bruto,
           case when coalesce(p.bloco, r.bloco) in (3, 4, 6) then null else coalesce(r.realizado, 0) end realizado,
           case when fw.reconstruida then 'foto reconstruída (dados de hoje)' end nota
      from fw
      join (prev p full join rea r on r.de = p.de and coalesce(r.bloco, 0) = coalesce(p.bloco, 0) and r.grupo = p.grupo)
        on fw.de = coalesce(p.de, r.de)
     where fw.foto_em is not null and (p.previsto is not null or coalesce(r.realizado, 0) <> 0)
  ), coorte as (
    select i.de, i.grupo, i.ref, i.origem_dia, sum(i.valor_bruto) vb
      from itens i join fw on fw.de = i.de
     where i.bloco = 2 and i.origem_dia between fw.de and fw.ate
     group by 1, 2, 3, 4
  ), res as materialized (
    select fw.de, c.foto_em
      from fw
      cross join lateral (
        select c.foto_em from fin.receber_fotos_cabecalho c
         where c.cenario = 'base' and c.dia > fw.ate + v_tol
         order by c.dia, c.foto_em limit 1
      ) c
     where fw.foto_em is not null
  ), rf as materialized (
    select res.de, f.ref, f.origem_dia, bool_or(f.situacao = 'realizada') pago, bool_or(f.situacao = 'em_atraso_fora') atraso,
           bool_or(f.situacao = 'coberta_informado') coberta, bool_or(f.situacao = 'a_receber') aberta
      from res join fin.receber_fotos f on f.foto_em = res.foto_em and f.bloco = 2
     group by 1, 2, 3
  ), rref as (
    select rf.de, rf.ref, bool_or(rf.pago and rf.origem_dia is null) pago_sem_venc from rf group by 1, 2
  ), est as (
    select co.grupo, co.vb,
           case when res.foto_em is null then 'pendente'
                when x.pago then 'paga'
                when x.coberta then 'fora'
                when x.atraso then 'perdida'
                when x.aberta then 'pendente'
                when y.pago_sem_venc then 'paga'
                when y.ref is null then 'perdida'
                else 'fora' end st
      from coorte co
      left join res on res.de = co.de
      left join rf x on x.de = co.de and x.ref = co.ref and x.origem_dia = co.origem_dia
      left join rref y on y.de = co.de and y.ref = co.ref
  ), perda as (
    select e.grupo, count(*) filter (where e.st in ('paga','perdida'))::int resolvidas,
           count(*) filter (where e.st = 'perdida')::int perdidas,
           coalesce(sum(e.vb) filter (where e.st in ('paga','perdida')), 0) v_res,
           coalesce(sum(e.vb) filter (where e.st = 'perdida'), 0) v_perd
      from est e group by 1
  )
  select 'semana'::text, s.de, s.ate, s.j0, s.j1, s.foto_em, s.bloco, s.grupo, s.previsto, s.previsto_bruto, s.realizado,
         s.realizado - coalesce(s.previsto, 0),
         case when s.previsto > 0 and s.realizado is not null
              then pg_catalog.round(greatest(0::numeric, 100 * (1 - abs(s.realizado - s.previsto) / s.previsto)), 1) end,
         null::text, null::numeric, null::numeric, null::int, null::int, null::numeric, null::numeric, s.nota
    from sem s
  union all
  select 'semana'::text, fw.de, fw.ate, null::date, null::date, null::timestamptz, null::smallint, null::text,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, null::text, null::numeric,
         null::numeric, null::int, null::int, null::numeric, null::numeric, 'sem foto base no início da semana'::text
    from fw where fw.foto_em is null
  union all
  select 'perda'::text, null::date, null::date, null::date, null::date, null::timestamptz, 2::smallint, pe.grupo,
         null::numeric, null::numeric, null::numeric, null::numeric, null::numeric, m.chave,
         case when pe.v_res > 0 then pg_catalog.round(pe.v_perd / pe.v_res, 4) end,
         fin.premissa(m.chave, v_hoje, 'base'),
         pe.resolvidas, pe.perdidas, pe.v_res, pe.v_perd,
         'sugestão medida (não grava): perdidas ÷ resolvidas, por valor, nas ' || p_semanas || ' semanas'
    from perda pe
    left join (values ('Assinaturas Serviço Diamante'::text,         'perda_mensal:servico_diamante'::text),
                      ('Assinaturas Holding - Holding Masters'::text, 'perda_mensal:holding_hm'::text),
                      ('Outras assinaturas'::text,                    'perda_mensal:outras_assinaturas'::text),
                      ('Parcelas a vencer HM'::text,                  'perda_mensal:parcelas_hm'::text),
                      ('Parcelas a vencer Aurum'::text,               'perda_mensal:parcelas_aurum'::text),
                      ('Parcelas a vencer outros'::text,              'perda_mensal:parcelas_outros'::text)
              ) m(grupo, chave) on m.grupo = pe.grupo
   order by 1 desc, 2 desc nulls last, 7 nulls last, 8;
end $$;
revoke all on function public.fn_fin_receber_previsto_realizado(int) from public, anon;
grant execute on function public.fn_fin_receber_previsto_realizado(int) to authenticated;


-- ─── 9. Conferência dentro da migration (falha → rollback de tudo) ──────────────────────────────────────────────────
do $chk$
declare
  v_dia   date := (now() at time zone 'America/Sao_Paulo')::date;
  v_adm   uuid;
  v_ok    boolean;
  v_n     int;
  v_m     int;
  v_tol   int;
  v_max   int;
  v_s     numeric;
  v_esp   text;
  v_obt   text;
  v_a     uuid;
  v_b     uuid;
  v_c     uuid;
  v_d     uuid;
  v_e     uuid;
  v_fa    timestamptz;
  v_fb    timestamptz;
  v_fc    timestamptz;
  v_f     uuid;
  v_con   text;
  v_slot  int[];
  v_base  jsonb;
  v_row   fin.recebimentos_informados;
  f       text;
  t       text;
  j       jsonb;
begin
  -- 9.1 grants e forma: tabelas fechadas (inclusive as colunas novas); internas sem EXECUTE; RPCs só authenticated,
  --     SECURITY DEFINER e search_path vazio; nenhuma com EXECUTE para PUBLIC; sem sobrecarga
  foreach t in array array['fin.recebimentos_informados','fin.recebimentos_informados_historico',
                           'fin.premissas_receber','fin.premissas_receber_catalogo'] loop
    if has_table_privilege('anon', t, 'select,insert,update,delete,truncate,references,trigger')
       or has_table_privilege('authenticated', t, 'select,insert,update,delete,truncate,references,trigger') then
      raise exception 'z73: grant aberto em %', t;
    end if;
    if not (select c.relrowsecurity from pg_class c where c.oid = t::regclass) then
      raise exception 'z73: RLS desligada em %', t;
    end if;
  end loop;
  foreach t in array array['parcela_n','parcela_de','contrato_assinado'] loop
    if has_column_privilege('anon', 'fin.recebimentos_informados', t, 'select,insert,update,references')
       or has_column_privilege('authenticated', 'fin.recebimentos_informados', t, 'select,insert,update,references') then
      raise exception 'z73: coluna % aberta a anon/authenticated', t;
    end if;
  end loop;
  foreach f in array array['fin.informado_normalizar(jsonb,fin.recebimentos_informados,boolean)',
                           'fin.receber_posicao(timestamptz,date,text)','fin.receber_fotografar(text,timestamptz)',
                           'fin.premissa(text,date,text)','fin.tg_informados_historico()'] loop
    if has_function_privilege('anon', f, 'execute') or has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z73: interna % executável por anon/authenticated', f;
    end if;
    if exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef) then
      raise exception 'z73: interna % é SECURITY DEFINER', f;
    end if;
  end loop;
  foreach f in array array['public.fn_fin_informados_listar()','public.fn_fin_informado_salvar(jsonb)',
                           'public.fn_fin_informado_baixar(uuid,date)','public.fn_fin_informado_arquivar(uuid,text)',
                           'public.fn_fin_informados_importar(jsonb,boolean)',
                           'public.fn_fin_receber_semanal(timestamptz,date,text)',
                           'public.fn_fin_receber_mudancas(timestamptz,timestamptz)',
                           'public.fn_fin_receber_previsto_realizado(integer)',
                           'public.fn_fin_premissas_receber_listar()',
                           'public.fn_fin_premissa_receber_salvar(text,numeric,date,text)'] loop
    if has_function_privilege('anon', f, 'execute') then raise exception 'z73: % executável por anon', f; end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception 'z73: authenticated sem execute em %', f;
    end if;
    if not exists (select 1 from pg_proc p where p.oid = f::regprocedure and p.prosecdef
                      and p.proconfig = array['search_path=""']) then
      raise exception 'z73: % sem SECURITY DEFINER ou sem search_path vazio', f;
    end if;
  end loop;
  if exists (select 1 from pg_proc p
              where ((p.pronamespace = 'public'::regnamespace
                      and (p.proname like 'fn_fin_informad%'
                           or p.proname in ('fn_fin_receber_semanal','fn_fin_receber_mudancas',
                                            'fn_fin_receber_previsto_realizado')))
                     or (p.pronamespace = 'fin'::regnamespace
                         and p.proname in ('informado_normalizar','receber_posicao','receber_fotografar','premissa')))
                and (p.proacl is null or exists (select 1 from unnest(p.proacl) ac where ac::text like '=%'))) then
    raise exception 'z73: função com EXECUTE para PUBLIC (ou proacl nulo = padrão público)';
  end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'fn_fin_informad%') <> 5
     or (select count(*) from pg_proc p
          where (p.pronamespace = 'fin'::regnamespace and p.proname in ('receber_posicao','informado_normalizar'))
             or (p.pronamespace = 'public'::regnamespace
                 and p.proname in ('fn_fin_receber_mudancas','fn_fin_receber_previsto_realizado'))) <> 4 then
    raise exception 'z73: sobrecarga viva depois das trocas';
  end if;
  if (select count(*) from pg_proc p
       where p.oid in ('public.fn_fin_informado_salvar(jsonb)'::regprocedure,
                       'public.fn_fin_informados_importar(jsonb,boolean)'::regprocedure)
         and p.prosrc like '%pg_advisory_xact_lock(hashtext(''fin.recebimentos_informados:escrita''))%') <> 2 then
    raise exception 'z73: salvar/importar sem o advisory lock de escrita';
  end if;
  select pg_get_constraintdef(c.oid) into v_obt from pg_constraint c
   where c.conrelid = 'fin.recebimentos_informados'::regclass and c.conname = 'recebimentos_informados_tipo_check';
  if regexp_replace(coalesce(v_obt, ''), '\s+', '', 'g')
     <> regexp_replace('CHECK ((tipo = ANY (ARRAY[''renovacao_diamante''::text, ''renovacao_aurum''::text, '
                       || '''diamante_extra''::text, ''outro''::text, ''contrato_holding_familiar''::text])))', '\s+', '', 'g') then
    raise exception 'z73: CHECK do tipo reescrito errado (perdeu valor?): %', v_obt;
  end if;

  -- 9.2 sem sessão → 42501 nas RPCs tocadas (e nada gravado)
  foreach f in array array[
      'select * from public.fn_fin_informados_listar()',
      'select public.fn_fin_informado_salvar(''{"data_prevista":"2026-12-01","cliente":"z73","tipo":"contrato_holding_familiar","valor":1,"contrato_assinado":true}''::jsonb)',
      'select * from public.fn_fin_informados_importar(''[{"data_prevista":"2026-12-01","cliente":"z73","tipo":"contrato_holding_familiar","valor":1,"contrato_assinado":true}]''::jsonb, false)',
      'select * from public.fn_fin_receber_mudancas(now(), now())',
      'select * from public.fn_fin_receber_previsto_realizado(8)',
      'select * from public.fn_fin_receber_semanal(null, null, ''base'')'] loop
    v_ok := false;
    begin
      execute f;
    exception when insufficient_privilege then v_ok := true;
    end;
    if not v_ok then raise exception 'z73: RPC respondeu sem sessão: %', f; end if;
  end loop;
  if (select count(*) from fin.recebimentos_informados) <> (select c.inf from z73_cont c) then
    raise exception 'z73: RPC gravou sem sessão';
  end if;

  -- 9.3 tabela sem contratos: a previsão (5 fotos: 2 cortes × cenários), a lista (18 colunas de antes), as mudanças e o
  --     previsto × realizado são IDÊNTICOS aos de antes, linha a linha e ao centavo
  if exists (select 1 from fin.recebimentos_informados r where r.tipo = 'contrato_holding_familiar') then
    raise exception 'z73: já há contrato na tabela — a conferência 9.3 supõe tabela sem contratos';
  end if;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp from z73_pos_antes z;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt from (
    select 'passado'::text foto, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'base') x
    union all
    select 'passado_c'::text, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x
    union all
    select 'agora'::text, x.* from fin.receber_posicao(now(), null, 'base') x
    union all
    select 'agora_c'::text, x.* from fin.receber_posicao(now(), null, 'conservador') x
    union all
    select 'agora_o'::text, x.* from fin.receber_posicao(now(), null, 'otimista') x) z;
  if v_esp is distinct from v_obt then
    raise exception 'z73: fin.receber_posicao mudou com a tabela sem contratos (blocos 1–6/8 deveriam ser idênticos)';
  end if;
  select p.id into v_adm from public.perfis p where p.status = 'ativo' and p.cargo in ('dev','admin') order by p.id limit 1;
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp from z73_lis_antes z;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt from (
    select l.id, l.data_prevista, l.cliente, l.tipo, l.valor, l.via_hotmart, l.produtos, l.identificador1, l.identificador2,
           l.acordo_desde, l.baixa_manual_em, l.situacao, l.recebido_hotmart, l.acumulado_acordo, l.valor_provisionado,
           l.arquivado_em, l.motivo_arquivo, l.atualizado_em
      from public.fn_fin_informados_listar() l) z;
  if v_esp is distinct from v_obt
     or exists (select 1 from public.fn_fin_informados_listar() l
                 where l.parcela_n is not null or l.parcela_de is not null or l.contrato_assinado is not null) then
    raise exception 'z73: fn_fin_informados_listar mudou nas 18 colunas de antes (ou colunas novas não nulas)';
  end if;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp from z73_pr_antes z;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt
    from public.fn_fin_receber_previsto_realizado(8) z;
  if v_esp is distinct from v_obt then raise exception 'z73: fn_fin_receber_previsto_realizado(8) mudou'; end if;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp from z73_mud_antes z;
  select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt
    from public.fn_fin_receber_mudancas((select min(c.foto_em) from fin.receber_fotos_cabecalho c),
                                        (select max(c.foto_em) from fin.receber_fotos_cabecalho c)) z;
  if v_esp is distinct from v_obt then raise exception 'z73: fn_fin_receber_mudancas mudou'; end if;
  perform set_config('request.jwt.claims', '', true);

  -- 9.4 premissas: carga, fallback de cenário e faixa (o trigger da z66 barra fora de 0–1)
  if fin.premissa('recebimento_contrato:assinado', v_dia, 'base') is distinct from 1
     or fin.premissa('recebimento_contrato:sem_assinatura', v_dia, 'base') is distinct from 1
     or fin.premissa('recebimento_contrato:sem_assinatura', v_dia, 'conservador') is distinct from 0.5
     or fin.premissa('recebimento_contrato:assinado', v_dia, 'conservador') is distinct from 1
     or fin.premissa('recebimento_contrato:sem_assinatura', v_dia, 'otimista') is distinct from 1
     or (select count(*) from fin.premissas_receber_catalogo k
          where k.chave like 'recebimento_contrato:%' and k.unidade = 'percentual' and k.minimo = 0 and k.maximo = 1
            and k.aceita_cenario) <> 2 then
    raise exception 'z73: premissas recebimento_contrato:* fora da carga (1 / 1 / conservador sem assinatura 0,5)';
  end if;
  begin
    insert into fin.premissas_receber (chave, vigente_de, valor, fonte)
    values ('recebimento_contrato:assinado', v_dia + 400, 1.5, 'z73 teste');
    raise exception 'z73: premissa 150%% aceita (faixa 0–1 não barrou)';
  exception when sqlstate '22023' then null;
  end;

  -- 9.5 comportamento com contratos de teste (tudo desfeito no fim do bloco)
  v_tol := fin.premissa('tolerancia_atraso_dias', v_dia, 'base')::int;
  v_max := fin.premissa('atraso_max_projetado_dias', v_dia, 'base')::int;
  if v_tol is null or v_max is null or v_tol < 1 or v_tol + 1 > v_max then
    raise exception 'z73: tolerância (%)/atraso máximo (%) fora do que a conferência supõe', v_tol, v_max;
  end if;
  -- dias passados sem foto 'otimista' (a foto é idempotente por (dia, cenário)): n e n+1 seguidos (fotos C e B, com
  -- contratos: a parcela vencida muda de data de caixa de uma para a outra) e um 3º (foto A, sem contratos)
  select s.n into v_n from generate_series(1, 120) s(n)
   where not exists (select 1 from fin.receber_fotos_cabecalho c where c.dia = v_dia - s.n and c.cenario = 'otimista')
     and not exists (select 1 from fin.receber_fotos_cabecalho c where c.dia = v_dia - s.n - 1 and c.cenario = 'otimista')
   order by s.n limit 1;
  select s.n into v_m from generate_series(1, 150) s(n)
   where s.n not in (v_n, v_n + 1)
     and not exists (select 1 from fin.receber_fotos_cabecalho c where c.dia = v_dia - s.n and c.cenario = 'otimista')
   order by s.n limit 1;
  if v_n is null or v_m is null then raise exception 'z73: sem dia livre para as fotos de teste'; end if;
  v_slot := array[v_n, v_n + 1, v_m];
  perform set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  begin
    select r.foto_em into v_fa from fin.receber_fotografar('otimista', now() - make_interval(days => v_slot[3])) r;

    v_base := jsonb_build_object('tipo', 'contrato_holding_familiar');
    v_a := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia + 10)::text,
             'cliente', 'z73 teste A', 'valor', 1000, 'parcela_n', 2, 'parcela_de', 5, 'contrato_assinado', true));
    v_b := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia + 20)::text,
             'cliente', 'z73 teste B', 'valor', 800, 'parcela_n', 1, 'parcela_de', 5, 'contrato_assinado', false,
             'identificador1', '123.456.789-01'));
    v_c := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia - 1)::text,
             'cliente', 'z73 teste C', 'valor', 300, 'parcela_n', 3, 'parcela_de', 5, 'contrato_assinado', false));
    v_d := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia - v_tol - 1)::text,
             'cliente', 'z73 teste D', 'valor', 400, 'parcela_n', 4, 'parcela_de', 5, 'contrato_assinado', true));
    v_e := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia + 5)::text,
             'cliente', 'z73 teste E', 'valor', 500, 'contrato_assinado', true));
    perform public.fn_fin_informado_baixar(v_e, v_dia);

    -- bloco 7 no base, linha a linha
    v_esp := concat_ws(E'\n',
      concat_ws('|', 'z73 teste A', 'Contratos Holding Familiar — assinados', 'cheio', v_dia + 10, '1000.00', '1000.00', '1',
                'a_receber', 'certo', 'Parcela 2 de 5 · contrato assinado · 100%', v_dia + 10),
      concat_ws('|', 'z73 teste B', 'Contratos Holding Familiar — sem contrato assinado', 'cheio', v_dia + 20, '800.00',
                '800.00', '1', 'a_receber', 'estimado', 'Parcela 1 de 5 · sem contrato assinado · 100%', v_dia + 20),
      concat_ws('|', 'z73 teste C', 'Contratos Holding Familiar — sem contrato assinado', 'cheio', v_dia + 1, '300.00',
                '300.00', '1', 'a_receber', 'estimado',
                'Parcela 3 de 5 · sem contrato assinado · 100% · Vencida e não paga: cobrar (entra no dia seguinte ao corte)',
                v_dia - 1),
      concat_ws('|', 'z73 teste D', 'Contratos Holding Familiar — assinados', 'cheio', '-', '400.00', '400.00', '1',
                'em_atraso_fora', 'certo',
                'Parcela 4 de 5 · contrato assinado · Em atraso: cobrar (vencido há mais de ' || v_tol || ' dias)',
                v_dia - v_tol - 1),
      concat_ws('|', 'z73 teste E', 'Contratos Holding Familiar — assinados', 'cheio', '-', '500.00', '500.00', '1',
                'realizada', 'certo', 'contrato assinado · Baixado fora da Hotmart', v_dia + 5));
    select string_agg(concat_ws('|', x.rotulo, x.grupo, x.componente, coalesce(x.data_caixa::text, '-'), x.valor,
                                x.valor_bruto, x.fator, x.situacao, x.certeza, x.tratamento, x.origem_dia), E'\n'
                      order by x.rotulo)
      into v_obt
      from fin.receber_posicao(now(), null, 'base') x where x.bloco = 7;
    if v_obt is distinct from v_esp then
      raise exception 'z73: bloco 7 (base) fora do contrato. Esperado:% Obtido:%', E'\n' || v_esp, E'\n' || coalesce(v_obt, '∅');
    end if;
    if exists (select 1 from fin.receber_posicao(now(), null, 'base') x
                where x.bloco = 7 and (x.centro_custo is distinct from '4. Receita de vendas (Direta de clientes)'
                                       or x.cenario <> 'base' or x.k is not null or x.detalhe is not null
                                       or x.ref not in (v_a::text, v_b::text, v_c::text, v_d::text, v_e::text)))
       or exists (select 1 from fin.receber_posicao(now(), null, 'base') x
                   where x.bloco = 5 and x.ref in (v_a::text, v_b::text, v_c::text, v_d::text, v_e::text)) then
      raise exception 'z73: bloco 7 com centro de custo/ref errado, ou contrato contado também no bloco 5';
    end if;
    -- cenários: sem assinatura a 50% no conservador (B 400, C 150); otimista = base
    if (select string_agg(x.rotulo || '=' || x.valor || '/' || x.valor_bruto || '×' || x.fator || ':' || x.tratamento, ', '
                          order by x.rotulo)
          from fin.receber_posicao(now(), null, 'conservador') x where x.bloco = 7 and x.situacao = 'a_receber')
       is distinct from
       'z73 teste A=1000.00/1000.00×1:Parcela 2 de 5 · contrato assinado · 100%, '
       || 'z73 teste B=400.00/800.00×0.5:Parcela 1 de 5 · sem contrato assinado · 50%, '
       || 'z73 teste C=150.00/300.00×0.5:Parcela 3 de 5 · sem contrato assinado · 50% · Vencida e não paga: cobrar (entra no dia seguinte ao corte)'
       or (select sum(x.valor) from fin.receber_posicao(now(), null, 'otimista') x
            where x.bloco = 7 and x.situacao = 'a_receber') <> 2100 then
      raise exception 'z73: %% de recebimento por cenário errado';
    end if;
    -- blocos 1–6/8 intactos com contratos na tabela (as 5 fotos de antes, sem o bloco 7)
    select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_esp from z73_pos_antes z;
    select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt from (
      select 'passado'::text foto, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'base') x where x.bloco <> 7
      union all
      select 'passado_c'::text, x.* from fin.receber_posicao('2026-09-25 23:59:59-03', '2026-12-31', 'conservador') x where x.bloco <> 7
      union all
      select 'agora'::text, x.* from fin.receber_posicao(now(), null, 'base') x where x.bloco <> 7
      union all
      select 'agora_c'::text, x.* from fin.receber_posicao(now(), null, 'conservador') x where x.bloco <> 7
      union all
      select 'agora_o'::text, x.* from fin.receber_posicao(now(), null, 'otimista') x where x.bloco <> 7) z;
    if v_esp is distinct from v_obt then
      raise exception 'z73: com contratos na tabela, os blocos 1–6/8 mudaram';
    end if;
    -- a RPC da aba (guarda + leitura da interna) devolve o bloco 7
    if (select count(*) from public.fn_fin_receber_semanal(null, null, 'base') x where x.bloco = 7) <> 5 then
      raise exception 'z73: fn_fin_receber_semanal sem as 5 linhas do bloco 7';
    end if;

    -- listar devolve os campos do contrato e a situação
    if (select string_agg(l.cliente || ':' || coalesce(l.parcela_n::text, '-') || '/' || coalesce(l.parcela_de::text, '-')
                          || ':' || l.contrato_assinado || ':' || l.situacao || ':' || l.via_hotmart, ', ' order by l.cliente)
          from public.fn_fin_informados_listar() l where l.tipo = 'contrato_holding_familiar')
       is distinct from 'z73 teste A:2/5:true:a_receber:false, z73 teste B:1/5:false:a_receber:false, '
                        || 'z73 teste C:3/5:false:a_receber:false, z73 teste D:4/5:true:em_atraso_cobrar:false, '
                        || 'z73 teste E:-/-:true:baixado_fora:false' then
      raise exception 'z73: listar sem os campos do contrato ou com situação errada';
    end if;

    -- salvar: chave ausente mantém; sem mudança não grava; trocar contrato_assinado muda o grupo
    perform public.fn_fin_informado_salvar(jsonb_build_object('id', v_a, 'valor', 1200));
    perform public.fn_fin_informado_salvar(jsonb_build_object('id', v_a));
    perform public.fn_fin_informado_salvar(jsonb_build_object('id', v_a, 'contrato_assinado', false));
    select * into v_row from fin.recebimentos_informados x where x.id = v_a;
    if (v_row.valor, v_row.parcela_n, v_row.parcela_de, v_row.contrato_assinado, v_row.via_hotmart)
       is distinct from (1200::numeric, 2, 5, false, false)
       or (select string_agg(h.acao, ',' order by h.id) from fin.recebimentos_informados_historico h where h.informado_id = v_a)
          is distinct from 'criado,alterado,alterado'
       or (select x.grupo from fin.receber_posicao(now(), null, 'base') x where x.ref = v_a::text)
          is distinct from 'Contratos Holding Familiar — sem contrato assinado' then
      raise exception 'z73: salvar parcial do contrato errado (valor %, parcela %/%, assinado %)',
        v_row.valor, v_row.parcela_n, v_row.parcela_de, v_row.contrato_assinado;
    end if;

    -- validação na RPC (P0001 com texto para a tela)
    j := v_base || jsonb_build_object('data_prevista', (v_dia + 30)::text, 'cliente', 'z73 erro', 'valor', 10,
                                      'parcela_n', 1, 'parcela_de', 2, 'contrato_assinado', true);
    foreach f in array array[
        (j || '{"via_hotmart":true}')::text || '§via_hotmart deve ser falso',
        (j - 'contrato_assinado')::text || '§informe se o contrato está assinado',
        (j || '{"parcela_n":6,"parcela_de":5}')::text || '§Parcela fora do intervalo',
        (j || '{"parcela_de":61}')::text || '§Parcela fora do intervalo',
        (j || '{"parcela_n":0}')::text || '§Parcela fora do intervalo',
        (j - 'parcela_de')::text || '§juntos',
        (j || '{"tipo":"outro","via_hotmart":false}')::text || '§só valem para o tipo contrato_holding_familiar',
        (j || '{"contrato_assinado":"sim"}')::text || '§contrato_assinado como verdadeiro ou falso',
        (j || '{"parcela_n":"1 de 5"}')::text || '§Número da parcela inválido',
        (j || '{"parcela_de":2.5}')::text || '§Total de parcelas inválido'] loop
      v_ok := false;
      begin
        perform public.fn_fin_informado_salvar(split_part(f, '§', 1)::jsonb);
      exception when raise_exception then
        v_ok := sqlerrm like '%' || split_part(f, '§', 2) || '%';
      end;
      if not v_ok then raise exception 'z73: validação do contrato não barrou (ou texto errado): %', f; end if;
    end loop;
    -- contrato sem via_hotmart → false; parcela como texto "3" aceita
    v_n := (select count(*) from fin.recebimentos_informados);
    perform public.fn_fin_informado_salvar(j || '{"parcela_n":"2","parcela_de":"2"}');
    if (select count(*) from fin.recebimentos_informados x
         where x.cliente = 'z73 erro' and not x.via_hotmart and x.parcela_n = 2 and x.parcela_de = 2) <> 1 then
      raise exception 'z73: contrato sem via_hotmart não virou fora da Hotmart';
    end if;
    -- troca de tipo contrato → outro limpa os campos do contrato (e sai do bloco 7 para o bloco 5)
    perform public.fn_fin_informado_salvar(jsonb_build_object('id', v_d, 'tipo', 'outro'));
    select * into v_row from fin.recebimentos_informados x where x.id = v_d;
    if (v_row.tipo, v_row.parcela_n, v_row.parcela_de, v_row.contrato_assinado)
       is distinct from ('outro'::text, null::int, null::int, null::boolean)
       or not exists (select 1 from fin.receber_posicao(now(), null, 'base') x
                       where x.ref = v_d::text and x.bloco = 5 and x.grupo = 'Outros recebimentos informados') then
      raise exception 'z73: troca de tipo não limpou o contrato ou não levou ao bloco 5';
    end if;

    -- CHECK da tabela vale para qualquer caminho de escrita (não só a RPC); confere QUAL constraint barrou
    foreach f in array array[
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, produtos, produto_ids, acordo_desde, contrato_assinado, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, true, ''{x}'', ''{x}'', current_date, true, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, false, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, parcela_n, parcela_de, origem) values (current_date, ''z73'', ''outro'', 1, false, 1, 2, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, contrato_assinado, origem) values (current_date, ''z73'', ''outro'', 1, false, true, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, contrato_assinado, parcela_n, parcela_de, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, false, true, 0, 5, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, contrato_assinado, parcela_n, parcela_de, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, false, true, 3, 61, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, contrato_assinado, parcela_n, parcela_de, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, false, true, 4, 3, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, contrato_assinado, parcela_n, origem) values (current_date, ''z73'', ''contrato_holding_familiar'', 1, false, true, 1, ''manual'')§recebimentos_informados_contrato_ck',
        'insert into fin.recebimentos_informados (data_prevista, cliente, tipo, valor, via_hotmart, origem) values (current_date, ''z73'', ''contrato'', 1, false, ''manual'')§recebimentos_informados_tipo_check'] loop
      v_ok := false;
      v_con := null;
      begin
        execute split_part(f, '§', 1);
      exception when check_violation then
        get stacked diagnostics v_con = constraint_name;
        v_ok := v_con = split_part(f, '§', 2);
      end;
      if not v_ok then
        raise exception 'z73: CHECK da tabela não barrou (ou barrou por outra constraint: %): %', v_con, f;
      end if;
    end loop;

    -- importar: prévia não grava; parcela na chave de duplicata; gravar é tudo ou nada
    v_n := (select count(*) from fin.recebimentos_informados);
    j := v_base || jsonb_build_object('data_prevista', (v_dia + 40)::text, 'cliente', 'z73 imp', 'valor', 100,
                                      'parcela_de', 2, 'contrato_assinado', true);
    if (select string_agg(i.linha || ':' || i.ok || coalesce(':' || i.erro, ''), ' | ' order by i.linha)
          from public.fn_fin_informados_importar(jsonb_build_array(
                 j || '{"parcela_n":1}', j || '{"parcela_n":2}', j || '{"parcela_n":1}',
                 v_base || jsonb_build_object('data_prevista', (v_dia - 1)::text, 'cliente', 'Z73 TESTE C', 'valor', 300,
                                              'parcela_n', 3, 'parcela_de', 5, 'contrato_assinado', false),
                 (j || '{"parcela_n":1}') - 'contrato_assinado'), true) i)
       is distinct from
       '1:true | 2:true | 3:false:Linha repetida nesta importação (mesma data, cliente, valor e tipo, parcela 1). | '
       || '4:false:Já cadastrado (mesma data, cliente, valor e tipo, parcela 3). | '
       || '5:false:Contrato Holding Familiar: informe se o contrato está assinado (contrato_assinado).'
       or (select count(*) from fin.recebimentos_informados) <> v_n then
      raise exception 'z73: prévia da importação de contratos errada ou gravou';
    end if;
    select string_agg(i.linha || ':' || i.ok || coalesce(':' || i.erro, ''), ' | ' order by i.linha) into v_obt
      from public.fn_fin_informados_importar(jsonb_build_array(j || '{"parcela_n":1}', j || '{"parcela_n":2}'), false) i;
    if v_obt is distinct from '1:true | 2:true'
       or (select string_agg(x.parcela_n || '/' || x.parcela_de || ':' || x.origem, ',' order by x.parcela_n)
             from fin.recebimentos_informados x where x.cliente = 'z73 imp') is distinct from '1/2:importacao,2/2:importacao' then
      raise exception 'z73: importação de contratos não gravou as colunas novas: %', v_obt;
    end if;
    -- mesma data, cliente, valor e tipo de um contrato já gravado, com OUTRA parcela, não é duplicata
    if (select string_agg(i.linha || ':' || i.ok || coalesce(':' || i.erro, ''), ' | ' order by i.linha)
          from public.fn_fin_informados_importar(jsonb_build_array(j || '{"parcela_n":3,"parcela_de":3}',
                                                                   j || '{"parcela_n":2}'), true) i)
       is distinct from '1:true | 2:false:Já cadastrado (mesma data, cliente, valor e tipo, parcela 2).' then
      raise exception 'z73: parcela diferente tratada como duplicata (ou parcela igual aceita)';
    end if;

    -- trilha: CPF mascarado (antes e depois) e campos do contrato presentes
    if exists (select 1 from fin.recebimentos_informados_historico h
                where h.informado_id = v_b and (coalesce(h.antes::text, '') || h.depois::text) ~ '12345678901')
       or (select h.depois ->> 'identificador1' || '|' || (h.depois ->> 'parcela_n') || '/' || (h.depois ->> 'parcela_de')
                  || '|' || (h.depois ->> 'contrato_assinado')
             from fin.recebimentos_informados_historico h where h.informado_id = v_b and h.acao = 'criado')
          is distinct from 'CPF ···8901|1/5|false' then
      raise exception 'z73: trilha do contrato sem máscara ou sem os campos novos';
    end if;

    -- fotos: o bloco 7 entra (= posição agregada, ao centavo); A (sem contratos) → B (com) = 'entrou'; B → C (dia
    -- seguinte, mesmos contratos) = nada, embora a parcela vencida F mude de data de caixa com o corte
    v_f := public.fn_fin_informado_salvar(v_base || jsonb_build_object('data_prevista', (v_dia - v_slot[2] - 1)::text,
             'cliente', 'z73 teste F', 'valor', 250, 'parcela_n', 5, 'parcela_de', 5, 'contrato_assinado', true));
    select r.foto_em into v_fb from fin.receber_fotografar('otimista', now() - make_interval(days => v_slot[2])) r;
    select r.foto_em into v_fc from fin.receber_fotografar('otimista', now() - make_interval(days => v_slot[1])) r;
    select md5(coalesce(string_agg(z::text, '|' order by z::text), '')), count(*) into v_esp, v_n
      from (select x.bloco, x.grupo, x.ref, x.origem_dia, x.data_caixa, x.componente, x.situacao, x.certeza,
                   sum(x.valor) valor, sum(x.valor_bruto) valor_bruto
              from fin.receber_posicao((select c.corte from fin.receber_fotos_cabecalho c where c.foto_em = v_fb),
                                       (select c.ate from fin.receber_fotos_cabecalho c where c.foto_em = v_fb), 'otimista') x
             where x.bloco = 7
             group by 1, 2, 3, 4, 5, 6, 7, 8) z;
    select md5(coalesce(string_agg(z::text, '|' order by z::text), '')) into v_obt
      from (select f.bloco, f.grupo, f.ref, f.origem_dia, f.data_caixa, f.componente, f.situacao, f.certeza, f.valor,
                   f.valor_bruto
              from fin.receber_fotos f where f.foto_em = v_fb and f.bloco = 7) z;
    if v_n = 0 or v_esp is distinct from v_obt then
      raise exception 'z73: foto sem o bloco 7 ou ≠ posição agregada (linhas na posição: %)', v_n;
    end if;
    select count(*), sum(m.valor_b) into v_m, v_s from public.fn_fin_receber_mudancas(v_fa, v_fb) m
     where m.bloco = 7 and m.valor_a = 0 and m.delta = m.valor_b
       and m.motivos = jsonb_build_array(jsonb_build_object('motivo', 'entrou', 'itens', m.motivos -> 0 -> 'itens',
                                                            'valor', m.delta));
    if v_m <> 2 or v_s is distinct from (select sum(f.valor) from fin.receber_fotos f
                                          where f.foto_em = v_fb and f.bloco = 7 and f.situacao = 'a_receber') then
      raise exception 'z73: mudanças A→B sem o "entrou" do bloco 7 (grupos %, soma %)', v_m, v_s;
    end if;
    if (select f1.data_caixa from fin.receber_fotos f1 where f1.foto_em = v_fb and f1.ref = v_f::text)
       is not distinct from (select f2.data_caixa from fin.receber_fotos f2 where f2.foto_em = v_fc and f2.ref = v_f::text)
       or not exists (select 1 from public.fn_fin_receber_mudancas(v_fb, v_fc) m where m.bloco = 7)
       or exists (select 1 from public.fn_fin_receber_mudancas(v_fb, v_fc) m
                   where m.bloco = 7 and (m.delta <> 0 or m.motivos <> '[]'::jsonb)) then
      raise exception 'z73: mudanças B→C acusou o bloco 7 (a data de caixa da vencida anda com o corte; o item é o informado)';
    end if;
    if exists (select 1 from public.fn_fin_receber_mudancas(v_fb, v_fb) m where m.delta <> 0 or m.motivos <> '[]'::jsonb) then
      raise exception 'z73: mudancas(B, B) devolveu mudança';
    end if;

    raise exception using errcode = 'P0001', message = 'z73_desfaz_teste';
  exception when raise_exception then
    if sqlerrm <> 'z73_desfaz_teste' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);

  -- 9.6 nada do teste ficou (linhas, trilha, fotos, premissas)
  if (select count(*) from fin.recebimentos_informados) <> (select c.inf from z73_cont c)
     or (select count(*) from fin.recebimentos_informados_historico) <> (select c.hist from z73_cont c)
     or (select count(*) from fin.receber_fotos_cabecalho) <> (select c.cab from z73_cont c)
     or (select count(*) from fin.receber_fotos) <> (select c.fotos from z73_cont c)
     or (select count(*) from fin.premissas_receber) <> (select c.prem from z73_cont c) + 3 then
    raise exception 'z73: linhas de teste não foram desfeitas';
  end if;
end $chk$;

drop function pg_temp.z73_norm(text);


-- ═══ PROVAS (rodar DEPOIS de aplicar, como postgres; cada bloco é UMA chamada — o MCP é autocommit) ════════════════
-- <UUID_FINANCEIRO> = perfis.id ativo que VÊ o financeiro. explain: rodar 2× e usar a 2ª (1ª é cache frio).
-- Nenhuma prova executa UPDATE/DELETE: as de escrita estão dentro de begin … rollback.
/*
-- P1) A previsão inteira (a RPC da aba chama isto). Teto: ≤ o medido na z69 (fn_fin_receber_semanal 202,9 ms) + 10%.
--     plpgsql: o explain de fora mostra Function Scan; o que importa é o tempo total e os buffers.
explain (analyze, buffers) select * from fin.receber_posicao(now(), null, 'base');
explain (analyze, buffers) select * from fin.receber_posicao(now(), null, 'base');
select bloco, situacao, count(*), sum(valor) from fin.receber_posicao(now(), null, 'base') group by 1, 2 order by 1, 2;

-- P2) O que o bloco 7 lê por dentro: a situação dos informados (a mesma 1 chamada de antes) + a tabela (centenas de
--     linhas: Seq Scan é o plano certo) + 2 premissas pela PK. Esperado: "Index Scan using premissas_receber_pkey"
--     nas premissas; nenhum Seq Scan em hotmart_transacoes.
explain (analyze, buffers)
select r.id, r.contrato_assinado, r.parcela_n, r.parcela_de, s.situacao, s.valor_provisionado, s.data_efetiva
  from fin.informados_situacao(now()) s
  join fin.recebimentos_informados r on r.id = s.id
 where r.tipo = 'contrato_holding_familiar' and s.situacao <> 'arquivado';
explain (analyze, buffers)
select pr.valor from fin.premissas_receber pr
 where pr.chave = 'recebimento_contrato:sem_assinatura@conservador' and pr.vigente_de <= current_date
 order by pr.vigente_de desc limit 1;

-- P3) A lista e a checagem de duplicata da importação (tabela pequena).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_informados_listar();
explain (analyze, buffers) select * from public.fn_fin_informados_listar();
rollback;
explain (analyze, buffers)
select 1 from fin.recebimentos_informados x
 where x.arquivado_em is null and x.data_prevista = current_date and lower(x.cliente) = lower('Fulano')
   and x.valor = 1000 and x.tipo = 'contrato_holding_familiar' and x.parcela_n is not distinct from 2;

-- P4) Mudanças e previsto × realizado (create or replace; mesmos índices da z69).
begin;
select set_config('request.jwt.claims', '{"sub":"<UUID_FINANCEIRO>","role":"authenticated"}', true);
set local role authenticated;
explain (analyze, buffers) select * from public.fn_fin_receber_mudancas(
  (select min(foto_em) from fin.receber_fotos_cabecalho), (select max(foto_em) from fin.receber_fotos_cabecalho));
explain (analyze, buffers) select * from public.fn_fin_receber_previsto_realizado(8);
explain (analyze, buffers) select * from public.fn_fin_receber_previsto_realizado(8);
rollback;
*/

-- ═══ MEDIDO no PGlite (29/09/2026, Victor; dados sintéticos do harness z63→z69: 8 informados, 95 linhas na previsão) ═══
-- Produção: medido em 29/09 (ver bloco MEDIDO em produção no fim) (sem acesso ao banco) — o coordenador roda P1–P4 depois de aplicar e cola aqui.
-- P1 fin.receber_posicao(now(), null, 'base'), 5 execuções quentes, tabela SEM contratos:
--    antes (corpo z67): 9,05–10,89 ms · Buffers: shared hit=1336
--    depois (z73):      8,47–9,62 ms  · Buffers: shared hit=1336   ← mesmo custo (informados_situacao continua 1 chamada)
--    com 5 contratos:   8,91 ms · Buffers: shared hit=1338 (+2 = as 2 premissas do % de recebimento)
-- P2 bloco 7 por dentro: Hash Join (s.id = r.id) · Function Scan on informados_situacao (8 linhas) · Seq Scan on
--    recebimentos_informados (Filter tipo = contrato_holding_familiar, Rows Removed by Filter: 3) — 1,81 ms, shared hit=42.
--    premissa: Seq Scan on premissas_receber (15 linhas no harness; em produção a PK premissas_receber_pkey
--    (chave, vigente_de) deve aparecer como Index Scan — conferir na P2) — 0,023 ms.
-- P3 duplicata da importação: Seq Scan on recebimentos_informados (Rows Removed by Filter: 8) — 0,015 ms.
--    listar (Gestora): 1,82 ms, shared hit=44. fn_fin_receber_semanal (Gestora): 9,49 ms, shared hit=1339.
-- P4 fn_fin_receber_previsto_realizado(8) (Gestora): 9,20 ms, shared hit=954.

-- ═══ MEDIDO em produção (29/09/2026, 2ª execução; usuário do Financeiro) ═══════════════════════════════════════════
-- fn_fin_receber_semanal(null,null) 205,1 ms (551 linhas, hit=8941; z69: 202,9 ms; teto +10% = 223) · listar 2,37 ms (0 linhas).
-- P1 fin.receber_posicao(now(),null,'base') 203,5 ms. P2a bloco 7 1,92 ms (tabela vazia — Hash Join, Seq Scan nunca executado).
-- P2b premissa: Seq Scan on premissas_receber (15 linhas, 1 buffer, 0,026 ms) — o planner prefere seq em tabela deste tamanho.
-- P3 duplicata: Seq Scan on recebimentos_informados (vazia) 0,019 ms. P4 mudancas(foto,foto) 5,96 ms · previsto_realizado(8) 9,07 ms.
-- Obs.: a P4 escrita acima usa min/max de fin.receber_fotos_cabecalho e falha como authenticated (sem USAGE em fin) — rodar
-- como postgres para achar as fotos e depois chamar a RPC como authenticated com os horários literais.
-- Reconferir P2/P3 com carga real (hoje 0 recebimentos informados).
