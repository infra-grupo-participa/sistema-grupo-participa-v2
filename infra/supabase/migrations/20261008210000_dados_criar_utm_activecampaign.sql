-- 20261008210000: UTM dos leads do ATM pelos campos personalizados do ActiveCampaign
--
-- STATUS: ver 20261008210000.explain.md. Depende de 20261008161000 (dados.leads_todos), aplicada.
-- Reversão: 20261008210000_reversao.sql. Ensaio: 20261008210000_ensaio.sql.
--
-- POR QUE (pedido do Victor, 08/10/2026, com a correção das 16:55)
--   O card/modal do ATM mostrava utm_source "não identificado" para os 62 leads: todos entram pela lista 615 do AC, e o
--   webhook do AC não traz UTM. A página ak1 grava as UTMs em campos personalizados do contato no AC (conferido pela API
--   /api/3/fields em 08/10: 945 data_hora, 946 utm_source, 947 utm_medium, 948 utm_campaign, 949 utm_content,
--   950 utm_term, 951 pagina_origem; títulos "[SEM ATM OUT/26] ...", ou seja, campos DESTA edição).
--   Correção do Victor: SEM sincronização periódica. (A) quando o lead chega, buscar os campos do contato nessa hora;
--   (B) carga única para os leads que estão hoje sem UTM (arquivo 20261008210100).
--
-- O QUE FAZ
--   a. dados.dashboards.ac_campos_utm (jsonb): id de cada campo no AC por edição. ATM 1: 945..951.
--   b. dados.ac_utm: a UTM de cada e-mail na lista do dashboard (primeira obtida vale; não sobrescreve).
--   c. dados.ac_utm_fila: contatos a consultar (pendente -> pedido -> feito | sem_utm | erro).
--   d. Gatilho em crm.evento_jornada (AFTER INSERT, fonte activecampaign, tipo subscribe, lista de um dashboard com
--      ac_campos_utm): põe o contato na fila. Nunca derruba a gravação do evento (erro vira warning).
--   e. dados.ac_utm_ciclo(): manda até 5 GET /api/3/contacts/{id}/fieldValues por rodada (chave activecampaign_api_key
--      do Vault, a mesma da Mensageria) e processa as respostas; apaga a resposta de net._http_response depois de ler.
--   f. pg_cron dados-ac-utm a cada minuto, que SÓ roda quando há fila (where exists): não consulta o AC à toa.
--   g. dados.leads_todos: UTM do lead = 1ª passagem com UTM pela rota de captura (sistema); sem ela, a do AC.
--
-- AS 5 PERGUNTAS
--   escala: 1 consulta por lead novo (ATM ~1 mil); carga única de ~70 contatos.
--   índice: único (lista, email_norm) em ac_utm; único (lista, contato_id) e parcial por estado na fila.
--   frequência: só quando chega lead (ou na carga); até 5 pedidos por minuto (limite do AC é 5 por segundo).
--   repetição: contato já na fila não entra de novo; e-mail com UTM não é consultado de novo.
--   reversão: 20261008210000_reversao.sql.

set local lock_timeout = '3s';
set local statement_timeout = '60s';

do $g$
begin
  if to_regprocedure('dados.leads_todos(text,bigint,text)') is null or to_regclass('crm.evento_jornada') is null
     or to_regprocedure('net.http_get(text,jsonb,jsonb,integer)') is null then
    raise exception 'premissa: modelo seminario-atm, crm.evento_jornada ou pg_net ausente';
  end if;
  if not exists (select 1 from vault.secrets where name = 'activecampaign_api_key') then
    raise exception 'premissa: segredo activecampaign_api_key ausente no Vault';
  end if;
end
$g$;

-- a. Campos do AC por edição
create or replace function dados.ac_campos_validos(p jsonb)
returns boolean language sql immutable set search_path = '' as $$
  -- 20261008210000: chaves conhecidas, cada valor = id numérico de campo do AC
  select p is null or (jsonb_typeof(p) = 'object'
         and not exists (select 1 from jsonb_each_text(p) x
                          where x.key not in ('data_hora', 'source', 'medium', 'campaign', 'content', 'term', 'pagina')
                             or x.value !~ '^[0-9]{1,6}$'))
$$;
alter table dados.dashboards add column if not exists ac_campos_utm jsonb
  constraint dashboards_ac_campos_utm_check check (dados.ac_campos_validos(ac_campos_utm));
comment on column dados.dashboards.ac_campos_utm is
  'Id dos campos personalizados do ActiveCampaign com as UTMs desta edição (chaves: data_hora, source, medium, campaign, content, term, pagina). Nulo = não consulta o AC. 20261008210000.';
update dados.dashboards
   set ac_campos_utm = '{"data_hora":"945","source":"946","medium":"947","campaign":"948","content":"949","term":"950","pagina":"951"}'::jsonb
 where chave = 'atm-elaine-1-2026-10' and ac_campos_utm is null;

-- b. UTM por e-mail na lista
create table if not exists dados.ac_utm (
  id             bigint generated always as identity primary key,
  lista          text not null check (lista ~ '^[0-9]{1,10}$'),
  email_norm     text not null check (email_norm = lower(btrim(email_norm)) and email_norm like '%@%'),
  contato_id     text check (contato_id is null or contato_id ~ '^[0-9]{1,20}$'),
  utm_source     text check (length(utm_source) <= 300),
  utm_medium     text check (length(utm_medium) <= 300),
  utm_campaign   text check (length(utm_campaign) <= 300),
  utm_content    text check (length(utm_content) <= 300),
  utm_term       text check (length(utm_term) <= 300),
  data_hora_ac   text check (length(data_hora_ac) <= 60),
  pagina_origem  text check (length(pagina_origem) <= 300),
  origem         text not null default 'ac_campos' check (origem in ('ac_campos', 'planilha')),
  obtido_em      timestamptz not null default now(),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (lista, email_norm)
);
comment on table dados.ac_utm is
  'UTM de cada e-mail inscrito na lista do AC de um dashboard, lida dos campos personalizados do contato (ou da planilha da página, origem = planilha). A primeira obtida vale (first touch). 20261008210000.';
alter table dados.ac_utm enable row level security;
revoke all on dados.ac_utm from public, anon, authenticated;
drop trigger if exists ac_utm_carimbar on dados.ac_utm;
create trigger ac_utm_carimbar before update on dados.ac_utm
  for each row execute function public.tg_carimbar_atualizado_em();

-- c. Fila
create table if not exists dados.ac_utm_fila (
  id             bigint generated always as identity primary key,
  lista          text not null check (lista ~ '^[0-9]{1,10}$'),
  contato_id     text not null check (contato_id ~ '^[0-9]{1,20}$'),
  email_norm     text check (email_norm is null or email_norm = lower(btrim(email_norm))),
  estado         text not null default 'pendente' check (estado in ('pendente', 'pedido', 'feito', 'sem_utm', 'erro')),
  req_id         bigint,
  req_anterior   bigint,
  pedido_em      timestamptz,
  tentativas     integer not null default 0,
  erro           text check (length(erro) <= 300),
  criado_em      timestamptz not null default now(),
  atualizado_em  timestamptz not null default now(),
  unique (lista, contato_id)
);
comment on table dados.ac_utm_fila is
  'Contatos do AC cujos campos de UTM ainda serão lidos. Entram pelo gatilho em crm.evento_jornada (inscrição na lista de um dashboard) ou pela carga única. 20261008210000.';
create index if not exists ac_utm_fila_abertos_idx on dados.ac_utm_fila (estado, criado_em) where estado in ('pendente', 'pedido');
alter table dados.ac_utm_fila enable row level security;
revoke all on dados.ac_utm_fila from public, anon, authenticated;
drop trigger if exists ac_utm_fila_carimbar on dados.ac_utm_fila;
create trigger ac_utm_fila_carimbar before update on dados.ac_utm_fila
  for each row execute function public.tg_carimbar_atualizado_em();

-- d. Gatilho na chegada do lead
create or replace function dados.tg_ac_utm_enfileirar()
returns trigger language plpgsql set search_path = '' as $$
-- 20261008210000: inscrição na lista de leads de um dashboard com campos de UTM configurados -> fila
begin
  begin
    if exists (select 1 from dados.dashboards d
                where d.ativo and d.lista_ac_leads = new.lista and d.ac_campos_utm is not null)
       and split_part(new.fonte_evento_id, ':', 1) ~ '^[0-9]{1,20}$' then
      insert into dados.ac_utm_fila (lista, contato_id, email_norm)
      values (new.lista, split_part(new.fonte_evento_id, ':', 1), new.email_norm)
      on conflict (lista, contato_id) do nothing;
    end if;
  exception when others then
    raise warning 'dados.tg_ac_utm_enfileirar: evento % não entrou na fila (%)', new.id, sqlstate;
  end;
  return null;
end
$$;
drop trigger if exists evento_jornada_ac_utm on crm.evento_jornada;
create trigger evento_jornada_ac_utm after insert on crm.evento_jornada
  for each row when (new.fonte = 'activecampaign' and new.tipo = 'subscribe' and new.lista is not null)
  execute function dados.tg_ac_utm_enfileirar();

-- e. Ciclo
create or replace function dados.ac_utm_ciclo()
returns text language plpgsql volatile set search_path = '' as $$
-- 20261008210000: processa respostas e manda até 5 pedidos novos
declare
  r record; v_resp record; v_campos jsonb; v_vals jsonb; v_chave text;
  v_feitos int := 0; v_sem int := 0; v_erros int := 0; v_pedidos int := 0;
  v_src text; v_med text; v_cmp text; v_cnt text; v_trm text;
begin
  if not pg_try_advisory_xact_lock(hashtext('dados.ac_utm_ciclo')) then
    return 'outro ciclo em andamento';
  end if;

  -- resposta que chegou depois de o pedido ser refeito ou dado como erro: sai de net._http_response (pentester 08/10)
  delete from net._http_response h
   using dados.ac_utm_fila f
   where f.req_anterior is not null and h.id = f.req_anterior and h.created >= f.criado_em
     and f.atualizado_em > now() - interval '7 hours';

  -- pedido sem resposta em 10 min volta para a fila (até 5 tentativas)
  update dados.ac_utm_fila
     set estado = case when tentativas >= 5 then 'erro' else 'pendente' end,
         erro = case when tentativas >= 5 then 'sem resposta do AC' end, req_anterior = req_id, req_id = null
   where estado = 'pedido' and pedido_em < now() - interval '10 minutes';

  for r in select f.*, d.ac_campos_utm as campos
             from dados.ac_utm_fila f
             join lateral (select x.ac_campos_utm from dados.dashboards x
                            where x.lista_ac_leads = f.lista and x.ac_campos_utm is not null
                            order by x.ativo desc, x.criado_em desc limit 1) d on true
            where f.estado = 'pedido' and f.req_id is not null loop
    select h.status_code, h.content, h.timed_out, h.error_msg into v_resp
      from net._http_response h where h.id = r.req_id and h.created >= r.pedido_em;
    continue when not found;
    delete from net._http_response h where h.id = r.req_id;   -- traz dado do contato: sai assim que é lido
    if v_resp.status_code = 200 and length(v_resp.content) < 200000 then
      begin
        select jsonb_object_agg(fv ->> 'field', left(nullif(btrim(fv ->> 'value'), ''), 300))
          into v_vals
          from jsonb_array_elements(v_resp.content::jsonb -> 'fieldValues') fv;
      exception when others then v_vals := null;
      end;
      v_campos := r.campos;
      v_src := v_vals ->> (v_campos ->> 'source');   v_med := v_vals ->> (v_campos ->> 'medium');
      v_cmp := v_vals ->> (v_campos ->> 'campaign'); v_cnt := v_vals ->> (v_campos ->> 'content');
      v_trm := v_vals ->> (v_campos ->> 'term');
      if r.email_norm is not null and coalesce(v_src, v_med, v_cmp, v_cnt, v_trm) is not null then
        insert into dados.ac_utm as a (lista, email_norm, contato_id, utm_source, utm_medium, utm_campaign, utm_content,
                                       utm_term, data_hora_ac, pagina_origem, origem)
        values (r.lista, r.email_norm, r.contato_id, v_src, v_med, v_cmp, v_cnt, v_trm,
                left(v_vals ->> (v_campos ->> 'data_hora'), 60), left(v_vals ->> (v_campos ->> 'pagina'), 300), 'ac_campos')
        on conflict (lista, email_norm) do nothing;   -- a primeira UTM obtida vale
        update dados.ac_utm_fila set estado = 'feito', erro = null where id = r.id;
        v_feitos := v_feitos + 1;
      else
        update dados.ac_utm_fila set estado = 'sem_utm', erro = null where id = r.id;
        v_sem := v_sem + 1;
      end if;
    elsif v_resp.status_code in (429, 500, 502, 503, 504) or v_resp.timed_out then
      update dados.ac_utm_fila
         set estado = case when tentativas >= 5 then 'erro' else 'pendente' end, req_anterior = req_id, req_id = null,
             erro = 'http ' || coalesce(v_resp.status_code::text, 'timeout')
       where id = r.id;
      v_erros := v_erros + 1;
    else
      update dados.ac_utm_fila
         set estado = 'erro', erro = 'http ' || coalesce(v_resp.status_code::text, '?') || coalesce(' ' || left(v_resp.error_msg, 200), '')
       where id = r.id;
      v_erros := v_erros + 1;
    end if;
  end loop;

  select s.decrypted_secret into v_chave from vault.decrypted_secrets s where s.name = 'activecampaign_api_key';
  if v_chave is null then
    return format('feitos %s, sem utm %s, erros %s; sem segredo activecampaign_api_key', v_feitos, v_sem, v_erros);
  end if;
  for r in select f.id, f.contato_id from dados.ac_utm_fila f
            where f.estado = 'pendente' order by f.criado_em, f.id limit 5 loop
    update dados.ac_utm_fila
       set estado = 'pedido', pedido_em = now(), tentativas = tentativas + 1,
           req_id = net.http_get(
             url := 'https://drmarciosa79109.api-us1.com/api/3/contacts/' || r.contato_id || '/fieldValues',
             params := '{}'::jsonb,
             headers := jsonb_build_object('Api-Token', v_chave),
             timeout_milliseconds := 30000)
     where id = r.id;
    v_pedidos := v_pedidos + 1;
  end loop;
  return format('feitos %s, sem utm %s, erros %s, pedidos %s', v_feitos, v_sem, v_erros, v_pedidos);
end
$$;

revoke all on function dados.tg_ac_utm_enfileirar(), dados.ac_utm_ciclo() from public, anon, authenticated;
revoke all on function dados.ac_campos_validos(jsonb) from public, anon;

-- f. Agenda: só roda com fila
select cron.schedule('dados-ac-utm', '* * * * *',
  'set statement_timeout = ''60s''; select dados.ac_utm_ciclo() where exists (select 1 from dados.ac_utm_fila where estado in (''pendente'', ''pedido''))');

-- g. Leitura: UTM da rota de captura (sistema) primeiro; sem ela, a do AC
create or replace function dados.leads_todos(p_chave text, p_projeto_id bigint, p_lista text)
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
$function$
;
revoke all on function dados.leads_todos(text, bigint, text) from public, anon, authenticated;

-- pós-condição
do $p$
begin
  if has_table_privilege('authenticated', 'dados.ac_utm', 'select') or has_table_privilege('anon', 'dados.ac_utm', 'select')
     or has_function_privilege('authenticated', 'dados.ac_utm_ciclo()', 'execute') then
    raise exception 'pós-condição: authenticated/anon alcança a UTM do AC';
  end if;
end
$p$;
