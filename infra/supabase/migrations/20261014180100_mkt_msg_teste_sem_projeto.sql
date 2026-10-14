-- 20261014180100: campanha com a palavra TESTE nunca recebe projeto em mkt_mensageria.api_item (ok do Victor, 14/10).
-- Não muda disparos já gravados (medido em 14/10: nenhum disparo com "teste" na campanha está em projeto).
-- Sem grant, RLS ou auth. Reversão: 20261014180100_reversao.sql. Ver 20261014180100.explain.md.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure)
      is distinct from '33979359147310564fac40f1ebad2aec' then
    raise exception '20261014180100: corpo vivo de api_item mudou; revisar';
  end if;
end
$g$;

CREATE OR REPLACE FUNCTION mkt_mensageria.api_item(p_fonte text, p_ferr_fixa bigint, p_item jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  v_ext text;
  d mkt_mensageria.disparos%rowtype;
  v_existe boolean;
  v_campanha text;
  v_proj bigint;
  v_nproj integer;
  v_sigla text;
  v_ferr bigint;
  v_txt text;
  v_num bigint;
  v_canon jsonb;
  k text;
  r jsonb;
  v_motivo text;
  v_proj_grupo bigint;
  v_n_grupo integer;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    return jsonb_build_object('motivo', 'Item não é um objeto JSON.');
  end if;
  v_ext := btrim(coalesce(p_item ->> 'id_externo', ''));
  if v_ext = '' or length(v_ext) > 200 then
    return jsonb_build_object('motivo', 'id_externo ausente ou com mais de 200 caracteres.');
  end if;

  select * into d from mkt_mensageria.disparos x where x.origem_sistema = p_fonte and x.id_externo = v_ext;
  v_existe := found;
  if v_existe and d.arquivado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- arquivado pela tela: a API não mexe
  end if;
  if v_existe and d.anonimizado_em is not null then
    return jsonb_build_object('id_externo', v_ext, 'arquivado', true);   -- LGPD: anonimizado, a API não regrava nada
  end if;

  v_campanha := nullif(left(btrim(coalesce(p_item ->> 'campanha', '')), 300), '');
  if v_campanha is null and v_existe then v_campanha := d.campanha; end if;
  -- [SIGLA]: o conteúdo de um colchete que seja sigla cadastrada, comparado só por letras e dígitos (João, 06/10:
  -- [PB/26] = PB26, [HT 33] = HT33; [HT] sem edição não casa). Nenhuma, ou duas siglas diferentes = sem projeto.
  select min(pr.id), count(distinct pr.id) into v_proj, v_nproj
    from regexp_matches(coalesce(v_campanha, ''), '\[([^][]{1,20})\]', 'g') m
    join mkt.projetos pr
      on regexp_replace(upper(pr.sigla), '[^A-Z0-9]', '', 'g') = regexp_replace(upper(m[1]), '[^A-Z0-9]', '', 'g')
     and regexp_replace(upper(m[1]), '[^A-Z0-9]', '', 'g') <> '';
  if v_nproj <> 1 then v_proj := null; end if;
  -- 20261014150000: disparo de grupo do SendFlow sem [SIGLA] herda o projeto pela campanha cadastrada no dashboard
  -- (dados.dashboard_grupos, papel 'dashboard'). Só quando a campanha leva a exatamente um projeto. Ex.: "ATM 10/26" -> 75.
  if v_proj is null and p_fonte = 'sendflow' and v_campanha is not null then
    select min(db.projeto_id), count(distinct db.projeto_id) into v_proj_grupo, v_n_grupo
      from dados.dashboard_grupos dg
      join dados.dashboards db on db.chave = dg.chave
     where dg.papel = 'dashboard' and db.projeto_id is not null
       and lower(btrim(dg.sendflow_campanha)) = lower(v_campanha);
    if v_n_grupo = 1 then v_proj := v_proj_grupo; end if;
  end if;
  -- 20261014180100 (Victor, 14/10): campanha de teste nunca ganha projeto, nem por [SIGLA] nem pelo grupo do dashboard.
  -- "teste" ou "testes" como palavra (sem diferenciar maiúscula; "_" e "-" separam): [TESTE], TESTE - x, TESTE_DE_X.
  -- "testemunho" não casa. O projeto já gravado à mão continua (o api_upsert não troca projeto gravado).
  if v_campanha ~* '(^|[^[:alpha:]])testes?([^[:alpha:]]|$)' then v_proj := null; end if;
  if v_existe and d.projeto_id is not null then v_proj := d.projeto_id; end if;
  select pr.sigla into v_sigla from mkt.projetos pr where pr.id = v_proj;

  if p_ferr_fixa is not null then
    v_ferr := p_ferr_fixa;
  else
    v_txt := btrim(coalesce(p_item ->> 'ferramenta', ''));
    if v_txt <> '' then
      select f.id into v_ferr from mkt_mensageria.ferramentas f where lower(f.nome) = lower(v_txt);
      if v_ferr is null then
        return jsonb_build_object('id_externo', v_ext, 'motivo', 'Ferramenta "' || left(v_txt, 60) || '" não cadastrada.');
      end if;
    elsif v_existe then
      v_ferr := d.ferramenta_id;
    end if;
  end if;

  v_txt := regexp_replace(coalesce(p_item ->> 'numero', ''), '[\s().-]', '', 'g');
  if v_txt <> '' then
    if left(v_txt, 1) <> '+' then v_txt := '+' || v_txt; end if;
    select nu.id into v_num from mkt_mensageria.numeros nu where nu.numero = v_txt;
    if v_num is null then
      return jsonb_build_object('id_externo', v_ext, 'motivo', 'Número ' || left(v_txt, 20) || ' não cadastrado em Números.');
    end if;
  elsif v_existe then
    v_num := d.numero_id;
  end if;

  v_canon := case when v_existe then jsonb_build_object(
      'enviado_em', d.enviado_em, 'canal', d.canal, 'tipo', d.tipo, 'copy_texto', d.copy_texto, 'copy_link', d.copy_link,
      'publico_lista', d.publico_lista, 'publico_origem', d.publico_origem, 'tamanho_lista', d.tamanho_lista,
      'entregues', d.entregues, 'lidas', d.lidas, 'cliques', d.cliques, 'falhas', d.falhas,
      'custo_centavos', d.custo_centavos, 'disparado_por', d.disparado_por)
    else '{}'::jsonb end;
  foreach k in array array['enviado_em', 'canal', 'tipo', 'copy_texto', 'copy_link', 'publico_lista', 'publico_origem',
                           'tamanho_lista', 'entregues', 'lidas', 'cliques', 'falhas', 'custo_centavos', 'disparado_por'] loop
    if jsonb_typeof(p_item -> k) is not null and jsonb_typeof(p_item -> k) <> 'null'
       and not (k in ('tipo', 'custo_centavos') and jsonb_typeof(v_canon -> k) is not null and jsonb_typeof(v_canon -> k) <> 'null') then
      v_canon := v_canon || jsonb_build_object(k, p_item -> k);
    end if;
  end loop;
  v_canon := v_canon || jsonb_build_object('projeto', coalesce(v_sigla, ''), 'ferramenta_id', v_ferr::text,
                                           'numero_id', v_num::text);
  if nullif(btrim(coalesce(v_canon ->> 'disparado_por', '')), '') is null then
    v_canon := v_canon || jsonb_build_object('disparado_por', 'api:' || p_fonte);
  end if;

  r := mkt_mensageria.disparo_validar(v_canon);
  select left(string_agg(x ->> 'campo' || ': ' || (x ->> 'msg'), '; '), 500) into v_motivo
    from jsonb_array_elements(r -> 'erros') x
   where x ->> 'campo' <> 'projeto';
  if v_motivo is not null then
    return jsonb_build_object('id_externo', v_ext, 'motivo', v_motivo);
  end if;
  return jsonb_build_object('id_externo', v_ext, 'existe', v_existe,
    'v', (r -> 'v') || jsonb_build_object('projeto_id', v_proj, 'campanha', v_campanha, 'id_externo', v_ext));
end
$function$;

do $g$
begin
  if exists (select 1 from pg_proc p cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) g
              where p.oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure and g.grantee <> p.proowner) then
    raise exception '20261014180100: api_item tem grant além do dono';
  end if;
end
$g$;
