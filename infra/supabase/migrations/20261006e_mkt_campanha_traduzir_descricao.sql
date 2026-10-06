-- 20261006e: Marketing, nome de campanha com DESCRIÇÃO de várias partes (mkt.campanha_traduzir)
--
-- O QUE FAZ
--   Revisão do Victor (06/10/2026). Padrão: GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA (opcional).
--     1. A DESCRIÇÃO é TUDO o que vem depois do OBJETIVO e pode ter várias partes separadas por " | ". Exemplo real (Black
--        Friday do Caio): CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY → gestor CF, projeto BF26,
--        objetivo ANTECIPAÇÃO, descrição "TEASER | META | PQ | ABO | THRUPLAY", sem página.
--     2. A PÁGINA só é lida no ÚLTIMO campo, só quando há pelo menos uma parte de descrição antes dele, e só se tiver o
--        formato do código de slug da casa (2 letras + número, sufixo opcional -letra: ak1, bl2, jt10, ak1-b; sem diferença
--        de maiúscula). Senão o último campo é parte da descrição. O erro pagina_invalida deixa de existir.
--     3. Gestor, projeto e objetivo válidos + qualquer descrição = NO PADRÃO. Objetivo com ou sem acento (ANTECIPAÇÃO =
--        ANTECIPACAO; já era assim). Erros (motivo de "fora do padrão"): vazio, numero_de_campos (MENOS DE 3 campos),
--        gestor_desconhecido, sigla_invalida, projeto_nao_cadastrado, objetivo_desconhecido, descricao_vazia (só 3 campos
--        ou descrição em branco) e campo_vazio (parte da descrição em branco: "| |").
--     4. ANTECIPAÇÃO ENTRA na lista de objetivos (decisão do Victor, 06/10/2026: vem antes da captação). Insert
--        idempotente em mkt.campanha_objetivos (lista da 20261005m). A fase "antecipação" (ordenada logo antes de
--        "captação") e o mapa ANTECIPAÇÃO → antecipação ficam na 20261006g, que cria mkt_trafego.fases (vem depois desta).
--   A 20261005m (que criou a função) está APLICADA: esta só troca o corpo (create or replace), com a MESMA assinatura e
--   o MESMO retorno (mesmas chaves do jsonb), acrescentando duas: descricao_partes (lista) e campos (quantos campos o nome
--   tem). Quem já usa a função continua igual: public.mkt_campanha_traduzir (20261005m), a Web (20261006f), pessoas e CRM
--   (20261005r_pessoas_e_crm_fundacao do Arthur, aplicada: leem padrao, projeto_id e pagina_id) e o Tráfego
--   (20261006g: gestor, objetivo, projeto, pagina_id, erros, avisos, descricao, pagina). Se o Tráfego já estiver aplicado,
--   as campanhas guardadas são relidas aqui (mkt_trafego.campanha_aplicar_leitura); se não, nada a reler.
--   A mesma regra está em web/modules/marketing/projetos/domain/campanha.ts (testes em campanha.test.ts).
--
-- AS 5 PERGUNTAS
--   escala: nomes de campanha (centenas a poucos milhares).   índice: os mesmos da 20261005m (lookup por PK/único).
--   frequência: a cada nome traduzido (coleta, tela, lead).   repetição: nenhuma query nova por campo; a descrição é só
--   texto.   reversão: bloco REVERSÃO no fim (o corpo da 20261005m, idêntico).
--
-- ENSAIO: infra/supabase/migrations/20261006e_ensaio.sql (begin … rollback). Explicação: 20261006e.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

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


-- ═══ REVERSÃO (volta o corpo da 20261005m, idêntico; numa transação; depois reler as campanhas do Tráfego, se houver) ═══
-- begin;
-- create or replace function mkt.campanha_traduzir(p_nome text) returns jsonb
-- language plpgsql stable set search_path = '' as $f$
-- declare
--   v_bruto text := coalesce(p_nome, '');
--   v_partes text[];
--   v_n int;
--   v_gestor text; v_projeto text; v_objetivo text; v_descricao text; v_pagina text;
--   v_obj_canon text;
--   v_proj mkt.projetos%rowtype;
--   v_pagina_id bigint;
--   v_erros text[] := '{}';
--   v_avisos text[] := '{}';
--   v_canonico text;
--   i int;
-- begin
--   if btrim(v_bruto) = '' then
--     return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('vazio'), 'avisos', '[]'::jsonb,
--                               'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
--                               'projeto_id', null, 'pagina_id', null, 'nome_canonico', null);
--   end if;
--
--   v_partes := string_to_array(v_bruto, '|');
--   v_n := coalesce(array_length(v_partes, 1), 0);
--   for i in 1..v_n loop
--     v_partes[i] := btrim(regexp_replace(v_partes[i], '\s+', ' ', 'g'));
--   end loop;
--
--   if v_n not in (4, 5) then
--     return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('numero_de_campos'), 'avisos', '[]'::jsonb,
--                               'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
--                               'projeto_id', null, 'pagina_id', null, 'nome_canonico', null, 'campos', v_n);
--   end if;
--
--   v_gestor    := mkt.maiusculas(v_partes[1]);
--   v_projeto   := mkt.maiusculas(v_partes[2]);
--   v_objetivo  := mkt.maiusculas(v_partes[3]);
--   v_descricao := mkt.maiusculas(v_partes[4]);
--   v_pagina    := case when v_n = 5 then lower(v_partes[5]) end;
--
--   if not exists (select 1 from mkt.campanha_gestores g where g.sigla = v_gestor and g.ativo) then
--     v_erros := array_append(v_erros, 'gestor_desconhecido');
--   end if;
--
--   if v_projeto !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
--     v_erros := array_append(v_erros, 'sigla_invalida');
--   else
--     select * into v_proj from mkt.projetos p where p.sigla = v_projeto;
--     if not found then
--       v_erros := array_append(v_erros, 'projeto_nao_cadastrado');
--     elsif not v_proj.ativo then
--       v_avisos := array_append(v_avisos, 'projeto_inativo');
--     end if;
--   end if;
--
--   select o.codigo into v_obj_canon from mkt.campanha_objetivos o
--    where o.ativo and mkt.sem_acento(o.codigo) = mkt.sem_acento(v_objetivo);
--   if v_obj_canon is null then
--     v_erros := array_append(v_erros, 'objetivo_desconhecido');
--   else
--     if v_obj_canon <> v_objetivo then v_avisos := array_append(v_avisos, 'sem_acento'); end if;
--     v_objetivo := v_obj_canon;
--   end if;
--
--   if v_descricao = '' then v_erros := array_append(v_erros, 'descricao_vazia'); end if;
--
--   if v_n = 5 then
--     if v_pagina !~ '^[a-z]{2}[0-9]{1,3}(-[a-z])?$' then
--       v_erros := array_append(v_erros, 'pagina_invalida');
--     elsif v_proj.id is not null then
--       select pg.id into v_pagina_id from mkt.paginas pg where pg.projeto_id = v_proj.id and pg.codigo = v_pagina;
--       if v_pagina_id is null then v_avisos := array_append(v_avisos, 'pagina_nao_cadastrada'); end if;
--     end if;
--   end if;
--
--   v_canonico := v_gestor || ' | ' || v_projeto || ' | ' || v_objetivo || ' | ' || v_descricao
--                 || case when v_n = 5 then ' | ' || upper(v_pagina) else '' end;
--   if v_bruto <> mkt.maiusculas(v_bruto) then v_avisos := array_append(v_avisos, 'minusculas'); end if;
--   if mkt.sem_acento(v_bruto) <> mkt.sem_acento(v_canonico) then v_avisos := array_append(v_avisos, 'espacos_extras'); end if;
--
--   return jsonb_build_object(
--     'padrao', cardinality(v_erros) = 0,
--     'gestor', v_gestor, 'projeto', v_projeto, 'objetivo', v_objetivo, 'descricao', v_descricao, 'pagina', v_pagina,
--     'projeto_id', v_proj.id, 'pagina_id', v_pagina_id,
--     'erros', to_jsonb(v_erros), 'avisos', to_jsonb(v_avisos), 'nome_canonico', v_canonico);
-- end
-- $f$;
-- -- se a 20261006g estiver aplicada: select public.trafego_campanhas_reler();  (como admin) ou, como postgres,
-- -- select count(*) filter (where mkt_trafego.campanha_aplicar_leitura(c.id)) from mkt_trafego.campanhas c;
-- -- ANTECIPAÇÃO: só se nenhuma campanha a usa (o mapa e a fase saem junto com a 20261006g, ou à mão):
-- delete from mkt_trafego.objetivo_fase where objetivo = 'ANTECIPAÇÃO';   -- se a 20261006g existir (ou reverter a 20261006g antes)
-- delete from mkt.campanha_objetivos where codigo = 'ANTECIPAÇÃO';
-- commit;
