-- 20261006e: ENSAIO (não aplica nada: tudo termina em ROLLBACK)
--
-- Como rodar: arquivo inteiro, de uma vez, numa conexão como postgres (SQL editor do Supabase ou psql), com a 20261005m
--   aplicada (já está em produção). Não depende do Tráfego (20261006g e seguintes); se ele já estiver aplicado, as
--   campanhas guardadas são relidas e o teste 7 confere. Todo resultado vai para a tabela temporária _z_out; o penúltimo
--   comando mostra tudo. Se o cliente só mostra o resultado do ÚLTIMO comando, rode até o "select … from _z_out"
--   (inclusive), leia, e rode o "rollback;" em seguida. NÃO deixe a transação aberta.
--
-- O corpo da migration está copiado abaixo SEM mudança (gerado do arquivo 20261006e_mkt_campanha_traduzir_descricao.sql,
-- das guardas até antes da REVERSÃO). Depois dele, os testes leem nomes de campanha: o exemplo real do Victor (Black
-- Friday do Caio, CF | BF26 | ANTECIPAÇÃO | …), com página no fim, descrição de uma parte, o formato antigo e os erros.
-- Dado fictício: o projeto ZZC28 "Projeto Ensaio Campanha" com a página zz1. Tudo some no rollback.
--
-- Esperado: NENHUMA linha começando com "ERRADO".
--   1 ANTECIPAÇÃO na lista (decisão do Victor, 06/10/2026, semeada por esta migration) e o exemplo da Black Friday:
--     descrição de 5 partes, objetivo reconhecido com ou sem acento
--   2 ANTECIPAÇÃO no padrão, com ou sem acento
--   3 página só no último campo e só com formato de slug (ak1, ak1-b, jt10); senão é descrição
--   4 descrição de uma parte e o formato antigo (mesma resposta de antes, mais as chaves novas)
--   5 motivos de fora do padrão: menos de 3 campos, só 3 campos, campo vazio, gestor, projeto, objetivo
--   6 quem usa a função: chaves que pessoas/CRM (main) e o Tráfego leem; public.mkt_campanha_traduzir como admin
--   7 campanhas do Tráfego relidas e a fase antecipação logo antes da captação com o mapa ANTECIPAÇÃO → antecipação
--     (só se a 20261006g estiver aplicada; na ordem normal ela vem DEPOIS desta e o passo fica PULADO)

begin;
set local lock_timeout = '3s';
set local statement_timeout = '60s';

create temp table _z_out (em timestamptz not null default clock_timestamp(), passo text, linha text) on commit drop;
grant all on _z_out to public;

-- ═══ CORPO DA MIGRATION ═══════════════════════════════════════════════════════════════════════════════════════════════
-- ─── 0. Guardas ──────────────────────────────────────────────────────────────────────────────────────────────────────
do $guarda$
declare v_src text := (select prosrc from pg_proc where oid = to_regprocedure('mkt.campanha_traduzir(text)'));
begin
  if v_src is null then raise exception '20261006e: falta a 20261005m (mkt.campanha_traduzir)'; end if;
  if position('20261006e' in v_src) > 0 then raise exception '20261006e: já aplicada'; end if;
  if position('if v_n not in (4, 5) then' in v_src) = 0 then
    raise exception '20261006e: mkt.campanha_traduzir no banco difere da 20261005m: abortado para não sobrescrever mudança viva';
  end if;
end
$guarda$;

-- ─── 1. A tradução nova ──────────────────────────────────────────────────────────────────────────────────────────────
create or replace function mkt.campanha_traduzir(p_nome text) returns jsonb
language plpgsql stable set search_path = '' as $$
-- 20261006e: descrição = tudo depois do objetivo (várias partes); página só no último campo e só no formato de slug.
declare
  v_bruto text := coalesce(p_nome, '');
  v_partes text[];
  v_n int;
  v_gestor text; v_projeto text; v_objetivo text; v_descricao text; v_pagina text;
  v_desc text[];
  v_obj_canon text;
  v_proj mkt.projetos%rowtype;
  v_pagina_id bigint;
  v_erros text[] := '{}';
  v_avisos text[] := '{}';
  v_canonico text;
  i int;
begin
  if btrim(v_bruto) = '' then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('vazio'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null,
                              'descricao_partes', '[]'::jsonb, 'campos', 0);
  end if;

  -- utm_campaign no formato nome|id (gp-operacoes): o id da plataforma no fim (só dígitos) não é parte do nome. Quem
  -- manda o utm cru (ex.: pessoas.registrar) passa a ler a página e a descrição certas.
  v_bruto := regexp_replace(v_bruto, '\|\s*[0-9]{6,}\s*$', '');
  v_partes := string_to_array(v_bruto, '|');
  v_n := coalesce(array_length(v_partes, 1), 0);
  for i in 1..v_n loop
    v_partes[i] := btrim(regexp_replace(v_partes[i], '\s+', ' ', 'g'));
  end loop;

  if v_n < 3 then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('numero_de_campos'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null,
                              'descricao_partes', '[]'::jsonb, 'campos', v_n);
  end if;

  v_gestor   := mkt.maiusculas(v_partes[1]);
  v_projeto  := mkt.maiusculas(v_partes[2]);
  v_objetivo := mkt.maiusculas(v_partes[3]);
  -- página: só o último campo, com pelo menos uma parte de descrição antes, e só no formato do slug da casa
  if v_n >= 5 and lower(v_partes[v_n]) ~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$' then
    v_pagina := lower(v_partes[v_n]);
    v_desc := v_partes[4:v_n - 1];
  else
    v_desc := coalesce(v_partes[4:v_n], '{}');
  end if;
  select coalesce(array_agg(mkt.maiusculas(d) order by o), '{}') into v_desc from unnest(v_desc) with ordinality x(d, o);
  v_descricao := array_to_string(v_desc, ' | ');

  if not exists (select 1 from mkt.campanha_gestores g where g.sigla = v_gestor and g.ativo) then
    v_erros := array_append(v_erros, 'gestor_desconhecido');
  end if;

  if v_projeto !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    v_erros := array_append(v_erros, 'sigla_invalida');
  else
    select * into v_proj from mkt.projetos p where p.sigla = v_projeto;
    if not found then
      v_erros := array_append(v_erros, 'projeto_nao_cadastrado');
    elsif not v_proj.ativo then
      v_avisos := array_append(v_avisos, 'projeto_inativo');
    end if;
  end if;

  select o.codigo into v_obj_canon from mkt.campanha_objetivos o
   where o.ativo and mkt.sem_acento(o.codigo) = mkt.sem_acento(v_objetivo);
  if v_obj_canon is null then
    v_erros := array_append(v_erros, 'objetivo_desconhecido');
  else
    if v_obj_canon <> v_objetivo then v_avisos := array_append(v_avisos, 'sem_acento'); end if;
    v_objetivo := v_obj_canon;
  end if;

  if v_descricao = '' then
    v_erros := array_append(v_erros, 'descricao_vazia');
  elsif '' = any (v_desc) then
    v_erros := array_append(v_erros, 'campo_vazio');
  end if;

  if v_pagina is not null and v_proj.id is not null then
    select pg.id into v_pagina_id from mkt.paginas pg where pg.projeto_id = v_proj.id and pg.codigo = v_pagina;
    if v_pagina_id is null then v_avisos := array_append(v_avisos, 'pagina_nao_cadastrada'); end if;
  end if;

  v_canonico := array_to_string(array[v_gestor, v_projeto, v_objetivo] || v_desc
                                || case when v_pagina is not null then array[upper(v_pagina)] else '{}'::text[] end, ' | ');
  if v_bruto <> mkt.maiusculas(v_bruto) then v_avisos := array_append(v_avisos, 'minusculas'); end if;
  if mkt.sem_acento(v_bruto) <> mkt.sem_acento(v_canonico) then v_avisos := array_append(v_avisos, 'espacos_extras'); end if;

  return jsonb_build_object(
    'padrao', cardinality(v_erros) = 0,
    'gestor', v_gestor, 'projeto', v_projeto, 'objetivo', v_objetivo, 'descricao', v_descricao, 'pagina', v_pagina,
    'projeto_id', v_proj.id, 'pagina_id', v_pagina_id,
    'erros', to_jsonb(v_erros), 'avisos', to_jsonb(v_avisos), 'nome_canonico', v_canonico,
    'descricao_partes', to_jsonb(v_desc), 'campos', v_n);
end
$$;
revoke all on function mkt.campanha_traduzir(text) from public, anon, authenticated;

-- ─── 1b. ANTECIPAÇÃO na lista de objetivos (Victor, 06/10/2026: vem antes da captação) ───────────────────────────────
insert into mkt.campanha_objetivos (codigo) values ('ANTECIPAÇÃO') on conflict (codigo) do nothing;
-- a fase "antecipação" (logo antes da captação) e o mapa ANTECIPAÇÃO → antecipação nascem na 20261006g, que cria
-- mkt_trafego.fases e vem depois desta.

-- ─── 2. Reler as campanhas guardadas do Tráfego (só se a 20261006g já estiver aplicada) ─────────────────────────────
do $reler$
declare v_n int := 0;
begin
  if to_regprocedure('mkt_trafego.campanha_aplicar_leitura(bigint)') is not null then
    execute 'select count(*) filter (where mkt_trafego.campanha_aplicar_leitura(c.id)) from mkt_trafego.campanhas c' into v_n;
    raise notice '20261006e: % campanha(s) do Tráfego relida(s)', v_n;
  end if;
end
$reler$;

-- ─── 3. Conferência (aborta se a regra nova não bate com os exemplos do Victor ou se a função nasceu aberta) ─────────
do $confere$
declare r jsonb;
begin
  if has_function_privilege('anon', 'mkt.campanha_traduzir(text)', 'execute')
     or has_function_privilege('authenticated', 'mkt.campanha_traduzir(text)', 'execute') then
    raise exception '20261006e: mkt.campanha_traduzir executável por anon/authenticated';
  end if;
  r := mkt.campanha_traduzir('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY');
  if r ->> 'gestor' <> 'CF' or r ->> 'projeto' <> 'BF26' or r ->> 'objetivo' <> 'ANTECIPAÇÃO'
     or r ->> 'descricao' <> 'TEASER | META | PQ | ABO | THRUPLAY' or r ->> 'pagina' is not null or (r ->> 'campos')::int <> 8
     or (r -> 'erros') ? 'objetivo_desconhecido' then
    raise exception '20261006e: o exemplo da Black Friday não foi lido como esperado: %', r;
  end if;
  r := mkt.campanha_traduzir('CF | BF26 | ANTECIPACAO | TEASER');
  if r ->> 'objetivo' <> 'ANTECIPAÇÃO' or (r -> 'erros') ? 'objetivo_desconhecido' then
    raise exception '20261006e: ANTECIPAÇÃO sem acento não foi reconhecida: %', r;
  end if;
  r := mkt.campanha_traduzir('RS | PB26 | LEADS | TESTE | AK1|120211234');
  if r ->> 'pagina' is distinct from 'ak1' or r ->> 'descricao' <> 'TESTE' then
    raise exception '20261006e: o id do utm_campaign (nome|id) não foi descartado: %', r;
  end if;
  r := mkt.campanha_traduzir('RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1');
  if not (r ->> 'padrao')::boolean or r ->> 'pagina' <> 'ak1' or r ->> 'descricao' <> 'TESTE DE ESCRITÓRIOS' then
    raise exception '20261006e: o formato antigo com página parou de valer: %', r;
  end if;
  r := mkt.campanha_traduzir('CF | BF26 | LEADS | TEASER | META | AK1');
  if not (r ->> 'padrao')::boolean or r ->> 'pagina' <> 'ak1' or r ->> 'descricao' <> 'TEASER | META' then
    raise exception '20261006e: descrição de várias partes com página no fim: %', r;
  end if;
end
$confere$;


-- ═══ TESTES ═══════════════════════════════════════════════════════════════════════════════════════════════════════════
create function pg_temp.ok(p_passo text, p_cond boolean, p_info text) returns void language sql as $$
  insert into pg_temp._z_out (passo, linha) values (p_passo, case when coalesce(p_cond, false) then 'ok: ' else 'ERRADO: ' end || p_info);
$$;
create function pg_temp.adm(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970","role":"authenticated"}', true);
  set local role authenticated;
  execute p_sql into v;
  reset role;
  return v;
end $$;
grant execute on function pg_temp.ok(text, boolean, text) to public;
create function pg_temp.t(p text) returns jsonb language sql stable as $$ select mkt.campanha_traduzir(p) $$;

-- projeto e página fictícios (para conferir página cadastrada sem depender do que existe em produção)
insert into mkt.projetos (sigla, nome, linha) values ('ZZC28', 'Projeto Ensaio Campanha', 'Ensaio');
insert into mkt.paginas (projeto_id, codigo, nome, dominio, caminho, funcao)
select id, 'zz1', 'Página Ensaio', 'exemplo.invalid', '/zz1/', 'captura' from mkt.projetos where sigla = 'ZZC28';

do $t$
declare r jsonb; v_tem boolean := exists (select 1 from mkt.campanha_objetivos where codigo = 'ANTECIPAÇÃO' and ativo);
begin
  perform pg_temp.ok('1.lista', v_tem, 'ANTECIPAÇÃO na lista de objetivos (mkt.campanha_objetivos), ativa');
  -- 1. o exemplo do Victor
  r := pg_temp.t('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY');
  perform pg_temp.ok('1.black friday', r ->> 'gestor' = 'CF' and r ->> 'projeto' = 'BF26' and r ->> 'objetivo' = 'ANTECIPAÇÃO'
    and r ->> 'descricao' = 'TEASER | META | PQ | ABO | THRUPLAY' and r -> 'descricao_partes' = '["TEASER","META","PQ","ABO","THRUPLAY"]'::jsonb
    and r -> 'pagina' = 'null'::jsonb and (r ->> 'campos')::int = 8 and r ->> 'projeto_id' is not null
    and r ->> 'nome_canonico' = 'CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY'
    and (v_tem or (r -> 'erros' = '["objetivo_desconhecido"]'::jsonb and not (r ->> 'padrao')::boolean)),
    'CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY: gestor CF, projeto BF26, objetivo ANTECIPAÇÃO, descrição de 5 partes, sem página'
    || case when v_tem then ' (ANTECIPAÇÃO já está na lista)' else '; fora do padrão SÓ pelo objetivo' end);
  r := pg_temp.t('CF | BF26 | ANTECIPACAO | TEASER | META | PQ | ABO | THRUPLAY');
  perform pg_temp.ok('1.sem acento', r ->> 'descricao' = 'TEASER | META | PQ | ABO | THRUPLAY'
    and (v_tem or (r -> 'erros' = '["objetivo_desconhecido"]'::jsonb and r ->> 'objetivo' = 'ANTECIPACAO')),
    'ANTECIPACAO (sem acento): o mesmo, e a tela mostra o que foi escrito');
  -- 2. ANTECIPAÇÃO na lista (decisão do Victor, 06/10/2026): no padrão
  insert into mkt.campanha_objetivos (codigo) values ('ANTECIPAÇÃO') on conflict (codigo) do update set ativo = true;
  r := pg_temp.t('CF | BF26 | ANTECIPACAO | TEASER | META | PQ | ABO | THRUPLAY');
  perform pg_temp.ok('2.com a lista', (r ->> 'padrao')::boolean and r ->> 'objetivo' = 'ANTECIPAÇÃO' and r -> 'avisos' ? 'sem_acento'
    and r ->> 'nome_canonico' = 'CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY',
    'com ANTECIPAÇÃO na lista: no padrão; sem acento vira ANTECIPAÇÃO (aviso sem_acento)');
  if not v_tem then delete from mkt.campanha_objetivos where codigo = 'ANTECIPAÇÃO'; end if;

  -- 3. página
  r := pg_temp.t('CF | ZZC28 | LEADS | TEASER | META | ZZ1');
  perform pg_temp.ok('3.página no fim', (r ->> 'padrao')::boolean and r ->> 'pagina' = 'zz1' and r ->> 'descricao' = 'TEASER | META'
    and r ->> 'pagina_id' = (select id::text from mkt.paginas where codigo = 'zz1' and projeto_id = (select id from mkt.projetos where sigla = 'ZZC28'))
    and r -> 'avisos' = '[]'::jsonb and r ->> 'nome_canonico' = 'CF | ZZC28 | LEADS | TEASER | META | ZZ1',
    'descrição de 2 partes + página cadastrada no último campo: página lida e ligada');
  r := pg_temp.t('rs | zzc28 | leads | teste | Ak1-B');
  perform pg_temp.ok('3.sufixo', (r ->> 'padrao')::boolean and r ->> 'pagina' = 'ak1-b' and r -> 'avisos' ? 'pagina_nao_cadastrada'
    and r -> 'avisos' ? 'minusculas', 'ak1-b sem diferença de maiúscula: página (não cadastrada = aviso, continua no padrão)');
  r := pg_temp.t('RS | ZZC28 | LEADS | TESTE | JT10');
  perform pg_temp.ok('3.dois dígitos', r ->> 'pagina' = 'jt10' and r ->> 'descricao' = 'TESTE', 'jt10 é página');
  r := pg_temp.t('RS | ZZC28 | LEADS | TESTE | OBRIGADO');
  perform pg_temp.ok('3.não é slug', (r ->> 'padrao')::boolean and r -> 'pagina' = 'null'::jsonb and r ->> 'descricao' = 'TESTE | OBRIGADO',
    'último campo fora do formato de slug: faz parte da descrição (antes era pagina_invalida)');
  r := pg_temp.t('RS | ZZC28 | LEADS | AK1');
  perform pg_temp.ok('3.só a descrição', (r ->> 'padrao')::boolean and r -> 'pagina' = 'null'::jsonb and r ->> 'descricao' = 'AK1',
    'com 4 campos o quarto é a descrição, mesmo com cara de slug');
  r := pg_temp.t('RS | ZZC28 | LEADS | AK1 | TESTE');
  perform pg_temp.ok('3.slug no meio', r -> 'pagina' = 'null'::jsonb and r ->> 'descricao' = 'AK1 | TESTE', 'slug fora do último campo: descrição');

  -- 4. descrição de uma parte e formato antigo
  r := pg_temp.t('CF | ZZC28 | VENDAS | ABERTURA DE CARRINHO');
  perform pg_temp.ok('4.uma parte', (r ->> 'padrao')::boolean and r ->> 'descricao' = 'ABERTURA DE CARRINHO' and r -> 'pagina' = 'null'::jsonb
    and (r ->> 'campos')::int = 4 and r -> 'descricao_partes' = '["ABERTURA DE CARRINHO"]'::jsonb, 'descrição de uma parte, sem página');
  r := pg_temp.t('RS  |  zzc28 |LEADS|   TESTE    DE   ESCRITÓRIOS  | zz1');
  perform pg_temp.ok('4.formato antigo', (r ->> 'padrao')::boolean and r ->> 'gestor' = 'RS' and r ->> 'projeto' = 'ZZC28' and r ->> 'objetivo' = 'LEADS'
    and r ->> 'descricao' = 'TESTE DE ESCRITÓRIOS' and r ->> 'pagina' = 'zz1' and r ->> 'pagina_id' is not null
    and r -> 'avisos' = '["minusculas", "espacos_extras"]'::jsonb and r ->> 'nome_canonico' = 'RS | ZZC28 | LEADS | TESTE DE ESCRITÓRIOS | ZZ1'
    and (select count(*) from unnest(array['padrao', 'gestor', 'projeto', 'objetivo', 'descricao', 'pagina', 'projeto_id', 'pagina_id', 'erros',
                                           'avisos', 'nome_canonico']) k where not r ? k) = 0,
    'GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA de antes: mesma leitura, mesmos avisos, todas as chaves de antes');

  -- 5. motivos
  r := pg_temp.t('RS | ZZC28');
  perform pg_temp.ok('5.menos de 3', r -> 'erros' = '["numero_de_campos"]'::jsonb and (r ->> 'campos')::int = 2, 'menos de 3 campos: numero_de_campos');
  r := pg_temp.t('RS | ZZC28 | LEADS');
  perform pg_temp.ok('5.só 3', r -> 'erros' = '["descricao_vazia"]'::jsonb and r ->> 'projeto_id' is not null, 'só 3 campos: sem descrição (o projeto já é lido)');
  r := pg_temp.t('RS | ZZC28 | LEADS | X |  | Y');
  perform pg_temp.ok('5.campo vazio', r -> 'erros' = '["campo_vazio"]'::jsonb, 'parte da descrição em branco ("| |"): campo_vazio');
  r := pg_temp.t('RS | ZZC28 | LEADS | X | ');
  perform pg_temp.ok('5.barra no fim', r -> 'erros' = '["campo_vazio"]'::jsonb, '"|" sobrando no fim: campo_vazio');
  r := pg_temp.t('XX | ZZ99 | TOPO | X | Y');
  perform pg_temp.ok('5.vários', r -> 'erros' = '["gestor_desconhecido", "projeto_nao_cadastrado", "objetivo_desconhecido"]'::jsonb
    and r ->> 'gestor' = 'XX' and r ->> 'objetivo' = 'TOPO', 'gestor, projeto e objetivo fora: os três motivos, com o que foi escrito');
  r := pg_temp.t('   ');
  perform pg_temp.ok('5.vazio', r -> 'erros' = '["vazio"]'::jsonb, 'nome vazio');

  -- 6. quem usa
  r := pg_temp.adm($$select public.mkt_campanha_traduzir('CF | ZZC28 | LEADS | TEASER | META | ZZ1')$$);
  perform pg_temp.ok('6.pública', (r ->> 'padrao')::boolean and r ->> 'pagina' = 'zz1', 'public.mkt_campanha_traduzir (tela, admin) usa a regra nova');
  r := pg_temp.t('CF | ZZC28 | LEADS | TEASER | META | ZZ1');
  perform pg_temp.ok('6.pessoas e CRM', jsonb_typeof(r -> 'padrao') = 'boolean' and (r ->> 'projeto_id')::bigint = (select id from mkt.projetos where sigla = 'ZZC28')
    and (r ->> 'pagina_id')::bigint is not null, 'padrao, projeto_id e pagina_id (o que pessoas.registrar, da main, lê) com o mesmo tipo');
  perform pg_temp.ok('6.grants', not has_function_privilege('anon', 'mkt.campanha_traduzir(text)', 'execute')
    and not has_function_privilege('authenticated', 'mkt.campanha_traduzir(text)', 'execute')
    and has_function_privilege('authenticated', 'public.mkt_campanha_traduzir(text)', 'execute')
    and not has_function_privilege('anon', 'public.mkt_campanha_traduzir(text)', 'execute'),
    'interna fechada; a pública continua só para authenticated (a trava admin/dev mora nela)');

  -- 7. Tráfego
  if to_regclass('mkt_trafego.campanhas') is null then
    insert into pg_temp._z_out (passo, linha) values ('7.tráfego', 'PULADO (20261006g não aplicada: nada a reler)');
  else
    perform pg_temp.ok('7.tráfego', not exists (select 1 from mkt_trafego.campanhas c where c.leitura is distinct from mkt.campanha_traduzir(c.nome)),
      'campanhas do Tráfego relidas: a leitura guardada é a da regra nova');
    perform pg_temp.ok('7.antecipação',
      (select ordem from mkt_trafego.fases where codigo = 'antecipacao') = (select ordem from mkt_trafego.fases where codigo = 'captacao') - 1
      and (select count(*) from mkt_trafego.fases where codigo = 'antecipacao') = 1
      and (select fase from mkt_trafego.objetivo_fase where objetivo = 'ANTECIPAÇÃO') = 'antecipacao'
      and (select count(*) from mkt_trafego.fases f1 join mkt_trafego.fases f2 on f1.ordem = f2.ordem and f1.codigo < f2.codigo) = 0,
      'fase antecipação logo antes da captação (ordem sem repetição) e mapa ANTECIPAÇÃO → antecipação');
  end if;
end
$t$;

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
