-- 20261014190000: etiqueta do ClickUp no fim do nome da campanha não apaga a página (decisão de 14/10: toda campanha do Meta
-- ganha " | <etiqueta-clickup>" no fim). mkt.campanha_traduzir passa a tirar a etiqueta do último campo antes de ler página
-- e descrição, e devolve "etiqueta". Sem isso, mkt_trafego.campanha_aplicar_leitura apagaria o pagina_id na próxima coleta.
-- Sem grant, RLS ou auth. NÃO APLICADA: espera o ok do Victor. Reversão: 20261014190000_reversao.sql.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt.campanha_traduzir(text)'::regprocedure)
      is distinct from '7cd7f9e5920cf84d3676738551242fef' then
    raise exception '20261014190000: corpo vivo de mkt.campanha_traduzir mudou; revisar';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION mkt.campanha_traduzir(p_nome text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
-- 20261006e: descrição = tudo depois do objetivo (várias partes); página só no último campo e só no formato de slug.
-- 20261014190000: etiqueta do ClickUp no fim (" | black-friday-2026-10"): se o último campo é uma etiqueta cadastrada
-- (mkt.projetos.etiqueta_clickup) ou tem o formato slug-AAAA-MM, ela sai antes de ler página e descrição e volta em
-- "etiqueta". Mesma regra do TS (web/modules/marketing/projetos/domain/campanha.ts).
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
  v_etiqueta text;
  v_sem_etiqueta text;
  i int;
begin
  if btrim(v_bruto) = '' then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('vazio'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null,
                              'descricao_partes', '[]'::jsonb, 'campos', 0, 'etiqueta', null);
  end if;

  -- utm_campaign no formato nome|id (gp-operacoes): o id da plataforma no fim (só dígitos) não é parte do nome. Quem
  -- manda o utm cru (ex.: pessoas.registrar) passa a ler a página e a descrição certas.
  v_bruto := regexp_replace(v_bruto, '\|\s*[0-9]{6,}\s*$', '');
  v_partes := string_to_array(v_bruto, '|');
  v_n := coalesce(array_length(v_partes, 1), 0);
  for i in 1..v_n loop
    v_partes[i] := btrim(regexp_replace(v_partes[i], '\s+', ' ', 'g'));
  end loop;

  -- 20261014190000: etiqueta do ClickUp no último campo (com pelo menos gestor, projeto e objetivo antes)
  v_sem_etiqueta := v_bruto;
  if v_n >= 4 and (lower(v_partes[v_n]) ~ '^[a-z0-9]+(-[a-z0-9]+)*-20[0-9]{2}-[0-9]{2}$'
                   or exists (select 1 from mkt.projetos p where lower(p.etiqueta_clickup) = lower(v_partes[v_n]))) then
    v_etiqueta := lower(v_partes[v_n]);
    v_partes := v_partes[1:v_n - 1];
    v_n := v_n - 1;
    v_sem_etiqueta := btrim(regexp_replace(v_bruto, '\|[^|]*$', ''));
  end if;

  if v_n < 3 then
    return jsonb_build_object('padrao', false, 'erros', jsonb_build_array('numero_de_campos'), 'avisos', '[]'::jsonb,
                              'gestor', null, 'projeto', null, 'objetivo', null, 'descricao', null, 'pagina', null,
                              'projeto_id', null, 'pagina_id', null, 'nome_canonico', null,
                              'descricao_partes', '[]'::jsonb, 'campos', v_n, 'etiqueta', v_etiqueta);
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
  -- avisos de forma olham o nome sem a etiqueta (a etiqueta é em minúsculas por padrão)
  if v_sem_etiqueta <> mkt.maiusculas(v_sem_etiqueta) then v_avisos := array_append(v_avisos, 'minusculas'); end if;
  if mkt.sem_acento(v_sem_etiqueta) <> mkt.sem_acento(v_canonico) then v_avisos := array_append(v_avisos, 'espacos_extras'); end if;
  if v_etiqueta is not null then v_canonico := v_canonico || ' | ' || v_etiqueta; end if;

  return jsonb_build_object(
    'padrao', cardinality(v_erros) = 0,
    'gestor', v_gestor, 'projeto', v_projeto, 'objetivo', v_objetivo, 'descricao', v_descricao, 'pagina', v_pagina,
    'projeto_id', v_proj.id, 'pagina_id', v_pagina_id,
    'erros', to_jsonb(v_erros), 'avisos', to_jsonb(v_avisos), 'nome_canonico', v_canonico,
    'descricao_partes', to_jsonb(v_desc), 'campos', v_n, 'etiqueta', v_etiqueta);
end
$function$;

do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt.campanha_traduzir(text)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261014190000: campanha_traduzir tem grant além do dono';
  end if;
end
$g$;
