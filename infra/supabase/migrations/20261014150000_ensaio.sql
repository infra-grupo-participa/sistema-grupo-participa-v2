begin;
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '1 antes', 'md5 ' || (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / acl ' || (select proacl::text from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / 47428 proj ' || coalesce((select projeto_id::text from mkt_mensageria.disparos where id = 47428), 'nulo') || ' / p75 ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 75 and arquivado_em is null);
insert into pg_temp._z_out(passo, linha) select '1 caso 1 sendflow ATM 10/26 (esperado 75)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-0","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-0","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 2 sendflow BF26 - Live 03/11 - Advogados (esperado 4)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-1","campanha":"BF26 - Live 03/11 - Advogados","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-1","campanha":"BF26 - Live 03/11 - Advogados","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 3 sendflow Consultoria ao Vivo - Aberto (esperado nulo)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-2","campanha":"Consultoria ao Vivo - Aberto","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-2","campanha":"Consultoria ao Vivo - Aberto","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 4 sendflow ALUNOS ATIVOS (esperado nulo)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-3","campanha":"ALUNOS ATIVOS","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-3","campanha":"ALUNOS ATIVOS","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 5 sendflow atm 10/26  (esperado 75)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-4","campanha":"atm 10/26 ","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-4","campanha":"atm 10/26 ","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 6 sendflow [BF26] ATM 10/26 (esperado 4)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-5","campanha":"[BF26] ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-5","campanha":"[BF26] ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 caso 7 activecampaign ATM 10/26 (esperado nulo)', coalesce(mkt_mensageria.api_item('activecampaign', 3, $j${"id_externo":"zz-ensaio-6","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('activecampaign', 3, $j${"id_externo":"zz-ensaio-6","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '1 47428 pelo api_item (antes)', coalesce(mkt_mensageria.api_item('sendflow', 1, jsonb_build_object('id_externo', (select id_externo from mkt_mensageria.disparos where id = 47428))) -> 'v' ->> 'projeto_id', 'nulo');
-- 20261014150000: disparo de grupo do SendFlow herda o projeto pela campanha do dashboard (dados.dashboard_grupos) e
-- o 47428 ("ATM 10/26", 14/10 09:03) vai para o projeto 75. Ver 20261014150000.explain.md.
-- Sem grant, RLS ou auth (a ACL de api_item fica igual; quem chama é public.mkt_msg_api_receber, security definer).
-- Reversão: 20261014150000_reversao.sql.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure)
      is distinct from '1d998f800302852516089fc8c89ca408' then
    raise exception '20261014150000: corpo vivo de api_item mudou; revisar';
  end if;
  if (select count(*) from mkt_mensageria.disparos where id = 47428 and projeto_id is null and origem = 'api'
       and origem_sistema = 'sendflow' and canal = 'grupo' and campanha = 'ATM 10/26' and arquivado_em is null) <> 1 then
    raise exception '20261014150000: o disparo 47428 não está no estado esperado';
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
    raise exception '20261014150000: api_item tem grant além do dono';
  end if;
end
$g$;

insert into pg_temp._z_out(passo, linha) select '2 depois da função', 'md5 ' || (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / acl ' || (select proacl::text from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / 47428 proj ' || coalesce((select projeto_id::text from mkt_mensageria.disparos where id = 47428), 'nulo') || ' / p75 ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 75 and arquivado_em is null);
insert into pg_temp._z_out(passo, linha) select '2 caso 1 sendflow ATM 10/26 (esperado 75)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-0","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-0","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 2 sendflow BF26 - Live 03/11 - Advogados (esperado 4)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-1","campanha":"BF26 - Live 03/11 - Advogados","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-1","campanha":"BF26 - Live 03/11 - Advogados","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 3 sendflow Consultoria ao Vivo - Aberto (esperado nulo)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-2","campanha":"Consultoria ao Vivo - Aberto","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-2","campanha":"Consultoria ao Vivo - Aberto","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 4 sendflow ALUNOS ATIVOS (esperado nulo)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-3","campanha":"ALUNOS ATIVOS","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-3","campanha":"ALUNOS ATIVOS","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 5 sendflow atm 10/26  (esperado 75)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-4","campanha":"atm 10/26 ","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-4","campanha":"atm 10/26 ","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 6 sendflow [BF26] ATM 10/26 (esperado 4)', coalesce(mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-5","campanha":"[BF26] ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('sendflow', 1, $j${"id_externo":"zz-ensaio-5","campanha":"[BF26] ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 caso 7 activecampaign ATM 10/26 (esperado nulo)', coalesce(mkt_mensageria.api_item('activecampaign', 3, $j${"id_externo":"zz-ensaio-6","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) -> 'v' ->> 'projeto_id', 'nulo') || coalesce(' motivo=' || (mkt_mensageria.api_item('activecampaign', 3, $j${"id_externo":"zz-ensaio-6","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}$j$::jsonb) ->> 'motivo'), '');
insert into pg_temp._z_out(passo, linha) select '2 47428 pelo api_item (regra nova)', coalesce(mkt_mensageria.api_item('sendflow', 1, jsonb_build_object('id_externo', (select id_externo from mkt_mensageria.disparos where id = 47428))) -> 'v' ->> 'projeto_id', 'nulo');
insert into pg_temp._z_out(passo, linha) select '2 sendflow sem projeto que a regra pegaria se reenviados', (select string_agg(campanha || '=' || n, ' | ') from (select campanha, count(*) n from mkt_mensageria.disparos d where origem_sistema = 'sendflow' and projeto_id is null and arquivado_em is null and exists (select 1 from dados.dashboard_grupos dg where dg.papel = 'dashboard' and lower(btrim(dg.sendflow_campanha)) = lower(d.campanha)) group by 1) z);
update mkt_mensageria.disparos set projeto_id = 75
 where id = 47428 and projeto_id is null and origem = 'api' and origem_sistema = 'sendflow' and campanha = 'ATM 10/26';
insert into pg_temp._z_out(passo, linha) select '3 depois da migration', 'md5 ' || (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / acl ' || (select proacl::text from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / 47428 proj ' || coalesce((select projeto_id::text from mkt_mensageria.disparos where id = 47428), 'nulo') || ' / p75 ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 75 and arquivado_em is null);
insert into pg_temp._z_out(passo, linha) select '4 api_upsert ponta a ponta (item novo ATM 10/26)', (select (mkt_mensageria.api_upsert('sendflow', $j$[{"id_externo":"zz-ensaio-upsert","campanha":"ATM 10/26","enviado_em":"2026-10-14T12:00:00Z","canal":"grupo","publico_lista":"Grupos da campanha teste","tamanho_lista":10,"copy_texto":"ensaio"}]$j$::jsonb))::text) ;
insert into pg_temp._z_out(passo, linha) select '4b projeto gravado pelo api_upsert', coalesce((select projeto_id::text from mkt_mensageria.disparos where origem_sistema = 'sendflow' and id_externo = 'zz-ensaio-upsert'), 'nulo');
-- Reversão da 20261014150000: volta o corpo anterior de api_item e devolve o 47428 a projeto nulo. Disparos que entraram
-- com projeto pela regra nova ficam com ele (arquivar ou editar pela tela, se for o caso).
do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure)
      is distinct from '33979359147310564fac40f1ebad2aec' then
    raise exception '20261014150000 reversão: corpo vivo não é o da 20261014150000';
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
$function$;

update mkt_mensageria.disparos set projeto_id = null where id = 47428 and projeto_id = 75 and origem = 'api';
insert into pg_temp._z_out(passo, linha) select '5 depois da reversão', 'md5 ' || (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / acl ' || (select proacl::text from pg_proc where oid = 'mkt_mensageria.api_item(text,bigint,jsonb)'::regprocedure) || ' / 47428 proj ' || coalesce((select projeto_id::text from mkt_mensageria.disparos where id = 47428), 'nulo') || ' / p75 ' || (select count(*) from mkt_mensageria.disparos where projeto_id = 75 and arquivado_em is null);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
