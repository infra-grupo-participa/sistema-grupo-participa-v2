-- 20261006a — Mensageria: sigla do projeto casa ignorando barra, espaço, hífen e ponto.
-- Decisão do João (06/10/2026): no ActiveCampaign as campanhas usam [PB/26], [HT 31], [HT]. Compara só letras e
-- dígitos dos dois lados. [HT] sem edição continua sem projeto (fila "sem projeto"). Única mudança: o join da sigla
-- em mkt_mensageria.api_item (resto idêntico à 20261005o). mkt.projetos tem 4 linhas: sem índice a medir.
-- Reversão: reaplicar o bloco api_item da 20261005o.
set local lock_timeout = '3s';

do $g$
begin
  if position('pr.sigla = upper(btrim(m[1]))' in (select prosrc from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure)) = 0 then
    raise exception 'api_item no banco difere da 20261005o: abortado para não sobrescrever mudança viva';
  end if;
end $g$;

create or replace function mkt_mensageria.api_item(p_fonte text, p_ferr_fixa bigint, p_item jsonb) returns jsonb
language plpgsql stable set search_path = '' as $$
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
$$;
revoke all on function mkt_mensageria.api_item(text, bigint, jsonb) from public, anon, authenticated;

do $g$
begin
  if has_function_privilege('anon', 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure, 'execute') then
    raise exception 'api_item executável por anon';
  end if;
end $g$;
