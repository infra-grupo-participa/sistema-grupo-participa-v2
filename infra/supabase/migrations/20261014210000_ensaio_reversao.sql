begin;
create temp table _z_out (em serial, passo text, linha text);
grant all on pg_temp._z_out to public;
grant usage, select on sequence pg_temp._z_out_em_seq to public;
do $a$ declare v text; begin select m.perfil_id::text into v from acesso.master m join public.perfis p on p.id=m.perfil_id where p.status='ativo' and p.email ilike '%@advmais.com' order by m.perfil_id limit 1; perform set_config('request.jwt.claims', json_build_object('sub',v,'role','authenticated')::text, true); end $a$;
create temp table _z_antes as
  select d.chave, (select md5(string_agg(t::text, '|' order by t.email)) from dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t) as m
    from dados.dashboards d;
insert into pg_temp._z_out(passo, linha) select '1 antes: leads_todos por chave', string_agg(chave || ' ' || left(coalesce(m,'vazio'), 8), ', ' order by chave) from pg_temp._z_antes;
insert into pg_temp._z_out(passo, linha) select '1b antes: resumo ATM', md5((select jsonb_object_agg(k, v) from jsonb_each(to_jsonb(r)) e(k, v) where v <> to_jsonb(now()))::text) from public.dados_atm_resumo('atm-elaine-1-2026-10', null, null) r;
-- 20261014210000: estrutura para o dashboard "Ações da Black Friday" (pedido do Victor, 14/10; card 17tya50gmcm).
-- Uma aba por ação, cada ação é uma linha de dados.dashboards com modelo 'acao-black' (o cadastro da primeira ação,
-- black-thb-2026-10, está na 20261014210100). A tela reaproveita as RPCs do "Esta edição" do ATM (dados_atm_*), sem RPC nova.
--   1. modelo 'acao-black' no check de dados.dashboards; dados.atm_cadastro aceita 'seminario-atm' e 'acao-black'.
--   2. dados.leads_todos ganha a fonte 'pagina': metodo.pesquisa_respostas com etiqueta = chave (origem 'teste' = teste).
--   3. mkt_mensageria.planilha_sync_receber ganha duas opções POR ABA, só para quem as pede no mapa (o ATM não pede):
--      "ano" (data dd/mm sem ano) e "hora_faixa" (hora "09H-18H" lida pelo início).
-- Guardas pelos md5 vivos. Reversão: 20261014210000_reversao.sql. Ver 20261014210000.explain.md.

do $g$
begin
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_cadastro(text)'::regprocedure) <> '0501ccd5647a89b44c7b9c02dc4ad8ca' then
    raise exception '20261014210000: dados.atm_cadastro mudou; revisar';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.leads_todos(text,bigint,text)'::regprocedure) <> '2cd22123b9efd32e0a86fd772a050960' then
    raise exception '20261014210000: dados.leads_todos mudou; revisar';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.planilha_sync_receber(bigint,jsonb)'::regprocedure) <> '7bfcdff51a6bf7d4473cda3a8ce8901b' then
    raise exception '20261014210000: mkt_mensageria.planilha_sync_receber mudou; revisar';
  end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'dados.dashboards'::regclass and conname = 'dashboards_modelo_check')
      <> 'CHECK ((modelo = ANY (ARRAY[''presencial-base''::text, ''seminario-atm''::text, ''jornada-captacao''::text])))' then
    raise exception '20261014210000: dashboards_modelo_check mudou; revisar';
  end if;
end
$g$;

alter table dados.dashboards drop constraint dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check
  check (modelo = any (array['presencial-base', 'seminario-atm', 'jornada-captacao', 'acao-black']));

CREATE OR REPLACE FUNCTION dados.atm_cadastro(p_chave text)
 RETURNS dados.dashboards
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  -- 20261014210000: as ações da Black (modelo acao-black) usam as mesmas RPCs do "Esta edição" do ATM.
  if r.modelo is null or r.modelo not in ('seminario-atm', 'acao-black') then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$function$;

CREATE OR REPLACE FUNCTION dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000; UTM do AC (dados.ac_utm) quando não há da rota de captura em 20261008210000
  with passagens as (
    -- sistema (rota /api/captura/lead -> pessoas.registrar, tipo lead)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'lead'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista de leads da edição)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           au.utm_source, au.utm_medium, au.utm_campaign, au.utm_content, au.utm_term,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join dados.ac_utm au on au.lista = p_lista and au.email_norm = lower(btrim(j.email_norm))
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.fonte = 'activecampaign' and j.lista = p_lista and j.email_norm is not null
    union all
    -- 20261014210000: página de captação do metodo (pesquisa_respostas) pela etiqueta do projeto = chave do dashboard
    -- (ex.: /renovacao -> black-thb-2026-10). Origem 'teste' é teste. Sem pessoa_id: a página não passa por pessoas.
    select r.email, r.nome, r.whatsapp, r.criado_em, 'pagina',
           r.utm_source, r.utm_medium, r.utm_campaign, r.utm_content, r.utm_term,
           null::uuid, r.origem = 'teste'
      from metodo.pesquisa_respostas r
     where r.etiqueta = p_chave
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term, x.pessoa_id, x.teste
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign'
              when bool_and(l.fonte = 'pagina') then 'pagina' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term,
         (select y.pessoa_id from limpo y where y.email = l.email and y.pessoa_id is not null
           order by y.teste desc, y.quando desc limit 1),
         bool_or(l.teste)
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y
                        where y.email = l.email
                          and coalesce(y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term) is not null
                        order by (y.fonte = 'sistema') desc, y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$function$;

CREATE OR REPLACE FUNCTION mkt_mensageria.planilha_sync_receber(p_planilha bigint, p_abas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  -- 20261014140000: linha sem copy nem link entra com este texto (antes era recusada calada).
  c_sem_copy constant text := 'Copy não registrada na planilha: a coluna COPY UTILIZADA traz só o texto-modelo e LINKS está vazia.';
  v_copy_val text;
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
                    then (select make_date(m[3]::int, m[2]::int, m[1]::int) from regexp_match(v_data, '^([0-9]+)/([0-9]+)/([0-9]+)$') m)
                    -- 20261014210000: aba com "ano" no mapa aceita data sem ano (dd/mm), com o ano do mapa. Só quem pede.
                    when (v_cfg ->> 'ano') ~ '^20[0-9]{2}$' and btrim(coalesce(v_data, '')) ~ '^[0-9]{1,2}/[0-9]{1,2}$'
                    then (select make_date((v_cfg ->> 'ano')::int, m[2]::int, m[1]::int)
                            from regexp_match(btrim(v_data), '^([0-9]+)/([0-9]+)$') m) end;
      -- 20261014210000: data aceita pelo "ano" segue normalizada (dd/mm/aaaa) para a validação e para a chave da linha.
      if v_dia is not null and v_data !~ '^[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}$' then v_data := to_char(v_dia, 'DD/MM/YYYY'); end if;
      -- Regra da linha que entra.
      if v_dia is null or v_dia < p.desde or (p.ate is not null and v_dia > p.ate)
         or not (v_status like 'ENVIAD%'
                 or coalesce(mkt_mensageria.inteiro_br(v_tam), 0) > 0
                 or coalesce(mkt_mensageria.centavos_br(v_custo), 0) > 0) then
        v_ign := v_ign + 1;
        continue;
      end if;
      v_qualif := v_qualif + 1;
      -- 20261014140000: hora de agenda ilegível (ex.: "-") cai na coluna opcional hora_envio do mapa (a aba API tem
      -- a 2ª coluna HORÁRIO). Sem nenhuma das duas, segue a hora crua e a linha é recusada como antes.
      v_hora := coalesce(mkt_mensageria.planilha_hora(v_get ->> 'hora'), mkt_mensageria.planilha_hora(v_get ->> 'hora_envio'),
                         -- 20261014210000: aba com "hora_faixa" no mapa lê faixa ("09H-18H") pela hora de início. Só quem pede.
                         case when (v_cfg ->> 'hora_faixa') = 'true'
                              then mkt_mensageria.planilha_hora(split_part(v_get ->> 'hora', '-', 1)) end,
                         v_get ->> 'hora');
      v_camp := left(v_get ->> 'campanha', 300);
      v_lista := v_get ->> 'lista';
      v_link := v_get ->> 'link';
      -- "copy" é o texto-modelo que a planilha traz na coluna COPY UTILIZADA: não é copy.
      v_copy := case when lower(coalesce(v_get ->> 'copy', '')) in ('', 'copy') then null else v_get ->> 'copy' end;
      v_copy_val := case when v_copy is null and v_link is null then c_sem_copy else v_copy end;
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
          'projeto', v_sigla, 'copy_texto', v_copy_val, 'copy_link', v_link, 'publico_lista', v_lista,
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
               copy_texto = coalesce(case when v_copy is not null then v_v ->> 'copy_texto' end, d.copy_texto),
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
                coalesce(case when v_copy is not null then v_v ->> 'copy_texto' end, d.copy_texto), coalesce(v_v ->> 'copy_link', d.copy_link),
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

  -- 20261014140000: linha recusada é falha da rodada (ok = false, a Edge responde 502 e o vigia enxerga). Antes a rodada
  -- fechava ok com recusas, e 6 disparos pagos do ATM ficaram fora do banco sem ninguém ver.
  if jsonb_array_length(v_recusas) > 0 then v_ok := false; end if;
  v_erro := (select left(string_agg(x, '; '), 500) from (
               select (a ->> 'aba') || ': ' || (a ->> 'erro') as x from jsonb_array_elements(v_abas_res) a where a ? 'erro'
               union all
               select jsonb_array_length(v_recusas) || ' linha(s) recusada(s): ver resumo.recusas'
                where jsonb_array_length(v_recusas) > 0) e);
  v_resumo := jsonb_build_object('lidas', v_lidas, 'ignoradas', v_ign, 'qualificadas', v_qualif, 'inseridos', v_ins,
                'adotados', v_ado, 'atualizados', v_atu, 'inalterados', v_inal, 'desarquivados', v_desarq,
                'arquivados', v_arq, 'recusadas', jsonb_array_length(v_recusas),
                'recusas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_recusas) x limit 100) s),
                'abas', v_abas_res);
  insert into mkt_mensageria.planilha_execucoes (planilha_id, ok, resumo, erro) values (p.id, v_ok, v_resumo, v_erro);
  return jsonb_build_object('ok', v_ok, 'planilha', p.nome) || v_resumo;
end
$function$;
-- 20261014210100: cadastro da primeira ação do dashboard "Ações da Black Friday": THB com acesso vencido
-- (etiqueta black-thb-2026-10). Depende da 20261014210000.
--
-- STATUS: NÃO APLICADA. TRAVADA DE PROPÓSITO até alguém preencher a SIGLA (v_sigla abaixo). A sigla é decisão do Victor
-- (dono do padrão de nomenclatura), como foi a ATMEL126 do ATM, e tem de casar com '^[A-Z]{2,10}[0-9]{2,4}$'.
-- Ensaio: 20261014210000_ensaio.sql (com sigla fictícia só dentro da transação).
--
-- O QUE CADASTRA (cada valor com a fonte)
--   mkt.projetos ......... etiqueta black-thb-2026-10 (card 17tya50gmcm e PEDIDO); nome "Black do THB com acesso vencido"
--                          (nome da planilha de público citada na planilha de mensageria); linha 'Black Friday', tipo
--                          interno, unidade csm (iguais ao BF26, projeto 4); evento 16/10/2026 (reunião no Zoom).
--   dados.dashboards ..... modelo acao-black; conta academy (o Holding Masters vende na conta academy em
--                          fin.hotmart_transacoes); oferta_codigo NULO (a oferta ainda não existe; o Victor passa e entra
--                          por update de 1 linha); lista_ac NULA (pré-checkout); periodo_inicio 14/10/2026 (começo da
--                          captação pela /renovacao); vendas_desde 14/10/2026 00:00 de São Paulo.
--   dados.sessoes ........ live 16/10/2026 14:00 de São Paulo (Reunião Direto ao Ponto).
--   dados.dashboard_grupos campanha "Reunião Direto ao Ponto | 16/10 às 14h no Zoom" (R89eeAMF6pccfKbE9RYR), papel
--                          dashboard, SEM conta de export e sem foto_ate: o ingresso conta só o que chega pelo SendHook
--                          (decisão do Victor, 14/10). O papel dashboard também faz o disparo de grupo do SendFlow desta
--                          campanha herdar o projeto (20261014150000).
--   mkt_mensageria.planilhas  [BF26 THB VENCIDOS] MENSAGERIA, DESLIGADA (ativa = false): ligar é uma rotina lendo o
--                          Google Sheets a cada 10 min, só com ok do Victor. Abas API, E-MAIL, GRUPO DA REUNIÃO e LIGAÇÃO,
--                          com "ano" 2026 (a planilha escreve a data sem ano) e "hora_faixa" na LIGAÇÃO. Ferramentas pelo
--                          precedente do ATM: API = Infobip (8), LIGAÇÃO = Ligue Lead (10); E-MAIL = ActiveCampaign (3);
--                          GRUPO = SendFlow (1). A coluna TIPO desta planilha é DISPARO/AUTOMAÇÃO (não o tipo de template
--                          da API), então não entra no mapa; fica só na conferência do
--                          cabeçalho. Na API, o tipo vem da coluna CATEGORIA META (J), que tem de trazer utility ou marketing. Fora: GRUPOS THB (é lista de grupos, não registro de disparo) e SMS (não
--                          há aba de registro; só o link na aba LINKS).
--
-- PARA VOLTAR: 20261014210100_reversao.sql.


do $c$
declare
  v_sigla   text := 'ZZENSAIO99';   -- PREENCHER com a sigla aprovada pelo Victor
  v_chave   text := 'black-thb-2026-10';
  v_proj    bigint;
  v_cab     jsonb := '{"B": "DATA", "C": "HORÁRIO", "D": "NOME DA MENSAGEM", "F": "LISTA/SEGMENTO", "G": "LINK", "H": "COPY (link do doc)"}';
begin
  if v_sigla is null then
    raise exception '20261014210100: sigla do projeto não definida. Preencher v_sigla com a sigla aprovada pelo Victor.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261014210100: sigla % fora do padrão de mkt.projetos', v_sigla;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'dashboards_modelo_check'
                  and pg_get_constraintdef(oid) like '%acao-black%') then
    raise exception '20261014210100: aplicar antes a 20261014210000';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_chave) then
    raise exception '20261014210100: a sigla % já existe com outra etiqueta', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave and sigla <> v_sigla) then
    raise exception '20261014210100: % já cadastrada com outra sigla', v_chave;
  end if;
  if exists (select 1 from mkt_mensageria.planilhas where planilha_id = '1J5QFTBEALI1TiqQ6FiAcbEtgTRB0OxhXo75zyAI9R2Q') then
    raise exception '20261014210100: a planilha de mensageria já está cadastrada; revisar';
  end if;

  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, tipo, unidade, evento_inicio, evento_fim, obs)
  select v_sigla, 'Black do THB com acesso vencido', 'Black Friday', 2026, v_chave, 'interno', 'csm',
         date '2026-10-16', date '2026-10-16',
         'Ação da Black Friday para o THB com acesso vencido; Reunião Direto ao Ponto 16/10 14h. Card 17tya50gmcm. 20261014210100.'
   where not exists (select 1 from mkt.projetos where etiqueta_clickup = v_chave);
  select id into v_proj from mkt.projetos where etiqueta_clickup = v_chave;

  insert into dados.dashboards (chave, modelo, projeto_id, conta_hotmart, oferta_codigo, lista_ac, lista_ac_leads,
                                periodo_inicio, vendas_desde)
  values (v_chave, 'acao-black', v_proj, 'academy', null, null, null,
          date '2026-10-14', timestamptz '2026-10-14 00:00:00-03')
  on conflict (chave) do nothing;

  insert into dados.sessoes (chave, tipo, inicio)
  values (v_chave, 'live', timestamptz '2026-10-16 14:00:00-03')
  on conflict (chave, tipo, inicio) do nothing;

  insert into dados.dashboard_grupos (chave, sendflow_campanha, sendflow_release_id, papel)
  values (v_chave, 'Reunião Direto ao Ponto | 16/10 às 14h no Zoom', 'R89eeAMF6pccfKbE9RYR', 'dashboard')
  on conflict (chave, sendflow_campanha) do nothing;

  insert into mkt_mensageria.planilhas (planilha_id, nome, projeto_id, desde, abas, ativa)
  values ('1J5QFTBEALI1TiqQ6FiAcbEtgTRB0OxhXo75zyAI9R2Q', '[BF26 THB VENCIDOS] MENSAGERIA', v_proj, date '2026-10-14',
    jsonb_build_array(
      jsonb_build_object('aba', 'API', 'canal', 'whatsapp_api', 'ferramenta_id', 8, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "N",
                     "tamanho_lista": "O", "entregues": "P", "lidas": "R", "cliques": "T", "falhas": "V",
                     "tipo": "J", "custo": "Y"}'::jsonb,
        'cabecalho', v_cab || '{"J": "CATEGORIA META", "N": "STATUS", "O": "ENVIADOS", "P": "ENTREGUES", "R": "ABERTOS/LIDAS", "T": "CLIQUES",
                                "V": "FALHAS", "X": "TIPO (DISPARO ou AUTOMAÇÃO)", "Y": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'E-MAIL', 'canal', 'email', 'ferramenta_id', 3, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "lidas": "P", "cliques": "R", "falhas": "T",
                     "custo": "W"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "ENVIADOS", "N": "ENTREGUES", "P": "ABERTOS/LIDAS", "R": "CLIQUES",
                                "T": "FALHAS", "V": "TIPO (DISPARO ou AUTOMAÇÃO)", "W": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'GRUPO DA REUNIÃO', 'canal', 'grupo', 'ferramenta_id', 1, 'cabecalho_linha', 1, 'ano', 2026,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "lidas": "P", "cliques": "R", "falhas": "T",
                     "custo": "W"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "ENVIADOS", "N": "ENTREGUES", "P": "ABERTOS/LIDAS", "R": "CLIQUES",
                                "T": "FALHAS", "V": "TIPO (DISPARO ou AUTOMAÇÃO)", "W": "CUSTO (R$)"}'::jsonb),
      jsonb_build_object('aba', 'LIGAÇÃO', 'canal', 'ligacao', 'ferramenta_id', 10, 'cabecalho_linha', 1, 'ano', 2026,
        'hora_faixa', true,
        'colunas', '{"data": "B", "hora": "C", "campanha": "D", "lista": "F", "link": "G", "copy": "H", "status": "L",
                     "tamanho_lista": "M", "entregues": "N", "custo": "S"}'::jsonb,
        'cabecalho', v_cab || '{"L": "STATUS", "M": "QTD LIGAÇÕES", "N": "ATENDIDOS", "S": "CUSTO (R$)"}'::jsonb)
    ), false);
end
$c$;
insert into pg_temp._z_out(passo, linha) select '3 cadastro', (select jsonb_build_object('projeto', pr.sigla, 'modelo', d.modelo, 'conta', d.conta_hotmart, 'oferta', d.oferta_codigo, 'sessoes', (select count(*) from dados.sessoes s where s.chave = d.chave), 'grupos', (select count(*) from dados.dashboard_grupos g where g.chave = d.chave), 'planilha_ativa', (select ativa from mkt_mensageria.planilhas where projeto_id = d.projeto_id))::text from dados.dashboards d join mkt.projetos pr on pr.id = d.projeto_id where d.chave = 'black-thb-2026-10');
insert into pg_temp._z_out(passo, linha) select '3b leads da ação (fonte página)', (select jsonb_build_object('total', count(*), 'teste', count(*) filter (where teste), 'fonte', string_agg(distinct fonte, ','))::text from dados.leads_todos('black-thb-2026-10', (select projeto_id from dados.dashboards where chave='black-thb-2026-10'), null));
insert into pg_temp._z_out(passo, linha) select '3c resumo da ação (sem planilha)', (select to_jsonb(r)::text from public.dados_atm_resumo('black-thb-2026-10', null, null) r);
-- Reversão da 20261014210100: apaga o cadastro da ação black-thb-2026-10 (planilha de mensageria, grupo, sessão, linha de
-- dados.dashboards e o projeto). Para se algum disparo ainda apontar para o projeto: arquivar antes (sem_delete).
do $g$
declare v_proj bigint := (select id from mkt.projetos where etiqueta_clickup = 'black-thb-2026-10');
begin
  if v_proj is null then raise exception 'reversão 20261014210100: projeto não existe; nada a reverter'; end if;
  if exists (select 1 from mkt_mensageria.disparos where projeto_id = v_proj) then
    raise exception 'reversão 20261014210100: há disparos no projeto; revisar antes de apagar';
  end if;
  delete from mkt_mensageria.planilhas where projeto_id = v_proj;
  delete from dados.dashboard_grupos where chave = 'black-thb-2026-10';
  delete from dados.sessoes where chave = 'black-thb-2026-10';
  delete from dados.dashboards where chave = 'black-thb-2026-10';
  delete from mkt.projetos where id = v_proj;
end
$g$;
delete from supabase_migrations.schema_migrations where version = '20261014210100';
-- Reversão da 20261014210000: volta dados.atm_cadastro, dados.leads_todos e mkt_mensageria.planilha_sync_receber ao corpo
-- de antes e tira 'acao-black' do check. Reverter ANTES a 20261014210100 (cadastro), se ela tiver sido aplicada.
do $g$
begin
  if exists (select 1 from dados.dashboards where modelo = 'acao-black') then
    raise exception 'reversão 20261014210000: há dashboard acao-black; reverter antes a 20261014210100';
  end if;
  if (select md5(prosrc) from pg_proc where oid = 'dados.atm_cadastro(text)'::regprocedure) <> 'e63ce1c2f24d6b8535fcf80dda88ad48'
     or (select md5(prosrc) from pg_proc where oid = 'dados.leads_todos(text,bigint,text)'::regprocedure) <> 'f106bf124249e3d14548654dbd33d702'
     or (select md5(prosrc) from pg_proc where oid = 'mkt_mensageria.planilha_sync_receber(bigint,jsonb)'::regprocedure) <> '51406ca73a9efdaca49a5a794a56ba97' then
    raise exception 'reversão 20261014210000: alguma função mudou depois da 210000; revisar';
  end if;
end
$g$;

alter table dados.dashboards drop constraint dashboards_modelo_check;
alter table dados.dashboards add constraint dashboards_modelo_check
  check (modelo = any (array['presencial-base', 'seminario-atm', 'jornada-captacao']));

CREATE OR REPLACE FUNCTION dados.atm_cadastro(p_chave text)
 RETURNS dados.dashboards
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  r dados.dashboards := dados.cadastro(p_chave);   -- 42501 sem acesso, P0002 chave fora do cadastro
begin
  if r.modelo is distinct from 'seminario-atm' then
    raise exception 'dashboard de outro modelo' using errcode = 'P0002';
  end if;
  return r;
end
$function$;

CREATE OR REPLACE FUNCTION dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
 RETURNS TABLE(email text, nome text, telefone text, primeiro_em timestamp with time zone, fonte text, utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text, pessoa_id uuid, teste boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  -- 20261008161000; UTM do AC (dados.ac_utm) quando não há da rota de captura em 20261008210000
  with passagens as (
    -- sistema (rota /api/captura/lead -> pessoas.registrar, tipo lead)
    select em.chave as email, p.nome, tel.valor as telefone, e.quando, 'sistema'::text as fonte,
           o.utm_source, o.utm_medium, o.utm_campaign, o.utm_content, o.utm_term,
           p.id as pessoa_id, coalesce(p.teste, false) as teste
      from pessoas.eventos e
      join pessoas.pessoas p on p.id = pessoas.atual(e.pessoa_id)
      cross join lateral (select i.chave from pessoas.identificadores i
                           where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'email' order by i.criado_em desc limit 1) em
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (e.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
      left join pessoas.origens o on o.id = e.origem_id
     where e.tipo = 'lead'
       and (e.projeto_id = p_projeto_id or e.detalhe ->> 'chave_evento' = p_chave)
    union all
    -- ActiveCampaign (entrada na lista de leads da edição)
    select j.email_norm, nullif(btrim(j.nome), ''), tel.valor, j.ocorreu_em, 'activecampaign',
           au.utm_source, au.utm_medium, au.utm_campaign, au.utm_content, au.utm_term,
           p.id, coalesce(p.teste, false)
      from crm.evento_jornada j
      left join dados.ac_utm au on au.lista = p_lista and au.email_norm = lower(btrim(j.email_norm))
      left join pessoas.pessoas p on p.id = pessoas.atual(j.pessoa_id)
      left join lateral (select i.valor from pessoas.identificadores i
                          where i.pessoa_id in (j.pessoa_id, p.id) and i.tipo = 'telefone' order by i.criado_em desc limit 1) tel on true
     where p_lista is not null and j.fonte = 'activecampaign' and j.lista = p_lista and j.email_norm is not null
  ), limpo as (
    select lower(btrim(x.email)) as email, nullif(btrim(x.nome), '') as nome, nullif(btrim(x.telefone), '') as telefone,
           x.quando, x.fonte, x.utm_source, x.utm_medium, x.utm_campaign, x.utm_content, x.utm_term, x.pessoa_id, x.teste
      from passagens x
     where nullif(btrim(x.email), '') is not null and lower(btrim(x.email)) not like '%@exemplo.invalid'
  )
  select l.email,
         (select y.nome from limpo y where y.email = l.email and y.nome is not null order by y.quando desc limit 1),
         (select y.telefone from limpo y where y.email = l.email and y.telefone is not null order by y.quando desc limit 1),
         min(l.quando),
         case when bool_and(l.fonte = 'sistema') then 'sistema'
              when bool_and(l.fonte = 'activecampaign') then 'activecampaign' else 'ambos' end,
         u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term,
         (select y.pessoa_id from limpo y where y.email = l.email and y.pessoa_id is not null
           order by y.teste desc, y.quando desc limit 1),
         bool_or(l.teste)
    from limpo l
    left join lateral (select y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term
                         from limpo y
                        where y.email = l.email
                          and coalesce(y.utm_source, y.utm_medium, y.utm_campaign, y.utm_content, y.utm_term) is not null
                        order by (y.fonte = 'sistema') desc, y.quando limit 1) u on true
   group by l.email, u.utm_source, u.utm_medium, u.utm_campaign, u.utm_content, u.utm_term
$function$;

CREATE OR REPLACE FUNCTION mkt_mensageria.planilha_sync_receber(p_planilha bigint, p_abas jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
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
  -- 20261014140000: linha sem copy nem link entra com este texto (antes era recusada calada).
  c_sem_copy constant text := 'Copy não registrada na planilha: a coluna COPY UTILIZADA traz só o texto-modelo e LINKS está vazia.';
  v_copy_val text;
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
      -- 20261014140000: hora de agenda ilegível (ex.: "-") cai na coluna opcional hora_envio do mapa (a aba API tem
      -- a 2ª coluna HORÁRIO). Sem nenhuma das duas, segue a hora crua e a linha é recusada como antes.
      v_hora := coalesce(mkt_mensageria.planilha_hora(v_get ->> 'hora'), mkt_mensageria.planilha_hora(v_get ->> 'hora_envio'),
                         v_get ->> 'hora');
      v_camp := left(v_get ->> 'campanha', 300);
      v_lista := v_get ->> 'lista';
      v_link := v_get ->> 'link';
      -- "copy" é o texto-modelo que a planilha traz na coluna COPY UTILIZADA: não é copy.
      v_copy := case when lower(coalesce(v_get ->> 'copy', '')) in ('', 'copy') then null else v_get ->> 'copy' end;
      v_copy_val := case when v_copy is null and v_link is null then c_sem_copy else v_copy end;
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
          'projeto', v_sigla, 'copy_texto', v_copy_val, 'copy_link', v_link, 'publico_lista', v_lista,
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
               copy_texto = coalesce(case when v_copy is not null then v_v ->> 'copy_texto' end, d.copy_texto),
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
                coalesce(case when v_copy is not null then v_v ->> 'copy_texto' end, d.copy_texto), coalesce(v_v ->> 'copy_link', d.copy_link),
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

  -- 20261014140000: linha recusada é falha da rodada (ok = false, a Edge responde 502 e o vigia enxerga). Antes a rodada
  -- fechava ok com recusas, e 6 disparos pagos do ATM ficaram fora do banco sem ninguém ver.
  if jsonb_array_length(v_recusas) > 0 then v_ok := false; end if;
  v_erro := (select left(string_agg(x, '; '), 500) from (
               select (a ->> 'aba') || ': ' || (a ->> 'erro') as x from jsonb_array_elements(v_abas_res) a where a ? 'erro'
               union all
               select jsonb_array_length(v_recusas) || ' linha(s) recusada(s): ver resumo.recusas'
                where jsonb_array_length(v_recusas) > 0) e);
  v_resumo := jsonb_build_object('lidas', v_lidas, 'ignoradas', v_ign, 'qualificadas', v_qualif, 'inseridos', v_ins,
                'adotados', v_ado, 'atualizados', v_atu, 'inalterados', v_inal, 'desarquivados', v_desarq,
                'arquivados', v_arq, 'recusadas', jsonb_array_length(v_recusas),
                'recusas', (select coalesce(jsonb_agg(x), '[]'::jsonb) from (select x from jsonb_array_elements(v_recusas) x limit 100) s),
                'abas', v_abas_res);
  insert into mkt_mensageria.planilha_execucoes (planilha_id, ok, resumo, erro) values (p.id, v_ok, v_resumo, v_erro);
  return jsonb_build_object('ok', v_ok, 'planilha', p.nome) || v_resumo;
end
$function$;

delete from supabase_migrations.schema_migrations where version = '20261014210000';
insert into pg_temp._z_out(passo, linha) select '5 depois da reversão', string_agg(p.oid::regprocedure::text || '=' || left(md5(p.prosrc), 8), ' ; ') || ' / check ' || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'dashboards_modelo_check') || ' / projeto ' || (select count(*) from mkt.projetos where etiqueta_clickup = 'black-thb-2026-10')::text from pg_proc p where p.oid in ('dados.atm_cadastro(text)'::regprocedure, 'dados.leads_todos(text,bigint,text)'::regprocedure, 'mkt_mensageria.planilha_sync_receber(bigint,jsonb)'::regprocedure);
insert into pg_temp._z_out(passo, linha) select '5b leads_todos e resumo ATM de volta?', string_agg(a.chave || ' ' || (a.m is not distinct from (select md5(string_agg(t::text, '|' order by t.email)) from dados.dashboards d, dados.leads_todos(d.chave, d.projeto_id, d.lista_ac_leads) t where d.chave = a.chave))::text, ', ' order by a.chave) || ' / resumo ATM ' || (select (md5((select jsonb_object_agg(k, v) from jsonb_each(to_jsonb(r)) e(k, v) where v <> to_jsonb(now()))::text) = (select linha from pg_temp._z_out where passo = '1b antes: resumo ATM'))::text from public.dados_atm_resumo('atm-elaine-1-2026-10', null, null) r) from pg_temp._z_antes a;
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
