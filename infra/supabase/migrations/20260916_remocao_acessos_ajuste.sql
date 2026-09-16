-- =====================================================================
-- 20260916_remocao_acessos_ajuste
-- "Não remover" vira "Ajustar acesso" (pedido do Victor, 16/09/2026).
--
-- Quando a pessoa tem acesso antigo válido, a triagem pede a data de expiração
-- antiga (obrigatória) e, se mudou, a instrução antiga. O caso NÃO fecha: fica
-- em 'ajustando_acesso' com dois itens do Victor por pessoa (Central e Base de
-- Alunos), aparece no lembrete e só conclui quando os dois forem marcados.
-- Os sócios acompanham a data do titular.
-- O ajuste da Base continua MANUAL por decisão do Victor (a Central ainda não é
-- 100% confiável para automatizar); ra_casos guarda as datas para ligar depois.
-- =====================================================================

alter table public.ra_casos drop constraint if exists ra_casos_status_check;
alter table public.ra_casos add constraint ra_casos_status_check
  check (status in ('alerta', 'aguardando_triagem', 'mantem_acesso', 'em_remocao', 'ajustando_acesso', 'concluido'));
alter table public.ra_casos add column if not exists decisao text check (decisao in ('remover', 'manter'));
alter table public.ra_casos add column if not exists expiracao_atual date;
alter table public.ra_casos add column if not exists expiracao_antiga date;
alter table public.ra_casos add column if not exists instrucao_atual text;
alter table public.ra_casos add column if not exists instrucao_antiga text;
update public.ra_casos set decisao = 'remover' where decisao is null and status in ('em_remocao', 'concluido');
update public.ra_casos set decisao = 'manter' where decisao is null and status = 'mantem_acesso';

alter table public.ra_itens_catalogo add column if not exists fluxo text not null default 'remocao'
  check (fluxo in ('remocao', 'ajuste'));
insert into public.ra_itens_catalogo (item, rotulo, responsavel_id, ordem, so_programa, fluxo) values
  ('ajuste_central', 'Expiração na Central (planilha)', '81d2eaee-cce1-4058-8714-439b0fc6f970', 110, false, 'ajuste'),
  ('ajuste_sistema', 'Expiração na Base de Alunos (sistema)', '81d2eaee-cce1-4058-8714-439b0fc6f970', 120, false, 'ajuste')
on conflict (item) do nothing;

drop function if exists public.ra_triar(uuid, text, text, boolean);
create or replace function public.ra_triar(p_caso uuid, p_decisao text, p_obs text default null,
                                           p_programa boolean default null,
                                           p_expiracao_antiga date default null,
                                           p_instrucao_antiga text default null)
returns json language plpgsql security definer set search_path to 'public' as $$
declare
  v_caso public.ra_casos%rowtype;
  v_aluno public.thb_alunos%rowtype;
  v_uid uuid := (select auth.uid());
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem decide este passo.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.status <> 'aguardando_triagem' then
    return json_build_object('ok', false, 'msg', 'Este caso já foi triado.');
  end if;
  if p_programa is not null and p_programa is distinct from v_caso.eh_programa then
    update public.ra_casos set eh_programa = p_programa where id = p_caso;
    v_caso.eh_programa := p_programa;
  end if;

  if p_decisao = 'manter' then
    if p_expiracao_antiga is null then
      return json_build_object('ok', false, 'msg', 'Informe a data de expiração antiga (a que volta a valer).');
    end if;
    if v_caso.aluno_id is not null then
      select * into v_aluno from public.thb_alunos where id = v_caso.aluno_id;
    end if;
    update public.ra_casos
       set status = 'ajustando_acesso', decisao = 'manter', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), ''),
           expiracao_atual = v_aluno.data_expiracao, expiracao_antiga = p_expiracao_antiga,
           instrucao_atual = v_aluno.instrucao,
           instrucao_antiga = nullif(trim(coalesce(p_instrucao_antiga, '')), '')
     where id = p_caso;
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select p_caso, p.id, c.item, c.responsavel_id
      from public.ra_pessoas p cross join public.ra_itens_catalogo c
     where p.caso_id = p_caso and c.ativo and c.fluxo = 'ajuste'
    on conflict (pessoa_id, item) do nothing;
  elsif p_decisao = 'remover' then
    update public.ra_casos
       set status = 'em_remocao', decisao = 'remover', triado_por = v_uid, triado_em = now(),
           decisao_obs = nullif(trim(coalesce(p_obs, '')), '')
     where id = p_caso;
    insert into public.ra_itens (caso_id, pessoa_id, item, responsavel_id)
    select p_caso, p.id, c.item, c.responsavel_id
      from public.ra_pessoas p cross join public.ra_itens_catalogo c
     where p.caso_id = p_caso and c.ativo and c.fluxo = 'remocao' and (not c.so_programa or v_caso.eh_programa)
    on conflict (pessoa_id, item) do nothing;
  else
    return json_build_object('ok', false, 'msg', 'Decisão inválida.');
  end if;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem', v_uid, jsonb_build_object('decisao', p_decisao, 'obs', p_obs, 'programa', v_caso.eh_programa,
          'expiracao_antiga', p_expiracao_antiga, 'instrucao_antiga', p_instrucao_antiga));
  return json_build_object('ok', true, 'msg', case when p_decisao = 'manter'
    then 'Não remover: falta ajustar a expiração na Central e na Base de Alunos.'
    else 'Remoção liberada para os responsáveis.' end);
end $$;

create or replace function public.ra_responsaveis()
returns setof json language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public.ra_pode_ver() then return; end if;
  return query
    select to_json(x) from (
      select c.item, c.rotulo, c.ordem, c.so_programa, c.fluxo, c.ativo, c.responsavel_id, p.nome as responsavel, p.email
        from public.ra_itens_catalogo c left join public.perfis p on p.id = c.responsavel_id
       order by c.ordem) x;
end $$;

CREATE OR REPLACE FUNCTION public.ra_marcar_item(p_item uuid, p_situacao text, p_obs text DEFAULT NULL::text)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_item public.ra_itens%rowtype;
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_triador boolean := public.ra_eh_triador();
  v_pendentes int;
begin
  if not public.ra_pode_ver() then
    return json_build_object('ok', false, 'msg', 'Sem acesso ao módulo Remoção de Acessos.');
  end if;
  if p_situacao not in ('pendente', 'feito', 'nao_se_aplica') then
    return json_build_object('ok', false, 'msg', 'Situação inválida.');
  end if;
  select * into v_item from public.ra_itens where id = p_item for update;
  if not found then return json_build_object('ok', false, 'msg', 'Item não encontrado.'); end if;
  if not (v_item.responsavel_id = v_uid or v_triador) then
    return json_build_object('ok', false, 'msg', 'Este item é de outro responsável.');
  end if;
  select * into v_caso from public.ra_casos where id = v_item.caso_id for update;
  if v_caso.status not in ('em_remocao', 'ajustando_acesso', 'concluido') then
    return json_build_object('ok', false, 'msg', 'Este caso ainda não passou pela triagem.');
  end if;

  update public.ra_itens
     set situacao = p_situacao,
         marcado_por = case when p_situacao = 'pendente' then null else v_uid end,
         marcado_em = case when p_situacao = 'pendente' then null else now() end,
         corrigido = (v_item.responsavel_id is distinct from v_uid),
         obs = nullif(trim(coalesce(p_obs, '')), '')
   where id = p_item;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (v_item.caso_id, 'item', v_uid, jsonb_build_object(
    'item', v_item.item, 'pessoa_id', v_item.pessoa_id, 'situacao', p_situacao,
    'correcao', v_item.responsavel_id is distinct from v_uid, 'obs', p_obs));

  select count(*) into v_pendentes from public.ra_itens where caso_id = v_item.caso_id and situacao = 'pendente';
  if v_pendentes = 0 and v_caso.status in ('em_remocao', 'ajustando_acesso') then
    update public.ra_casos set status = 'concluido', concluido_em = now() where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'concluido', v_uid);
  elsif v_pendentes > 0 and v_caso.status = 'concluido' then
    update public.ra_casos
       set status = case when v_caso.decisao = 'manter' then 'ajustando_acesso' else 'em_remocao' end,
           concluido_em = null
     where id = v_item.caso_id;
    insert into public.ra_historico (caso_id, acao, por) values (v_item.caso_id, 'reaberto', v_uid);
  end if;
  return json_build_object('ok', true, 'msg', 'Registrado.');
end $function$;

CREATE OR REPLACE FUNCTION public.ra_desfazer_triagem(p_caso uuid)
 RETURNS json
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_caso public.ra_casos%rowtype;
  v_uid uuid := (select auth.uid());
  v_marcados int;
  v_avisou boolean;
begin
  if not public.ra_eh_triador() then
    return json_build_object('ok', false, 'msg', 'Só o responsável pela triagem pode desfazer.');
  end if;
  select * into v_caso from public.ra_casos where id = p_caso for update;
  if not found then return json_build_object('ok', false, 'msg', 'Caso não encontrado.'); end if;
  if v_caso.status not in ('em_remocao', 'mantem_acesso', 'ajustando_acesso', 'concluido') then
    return json_build_object('ok', false, 'msg', 'Este caso não tem triagem para desfazer.');
  end if;

  select count(*) into v_marcados from public.ra_itens where caso_id = p_caso and situacao <> 'pendente';
  if v_marcados > 0 then
    return json_build_object('ok', false, 'msg',
      format('%s item(ns) já marcado(s). Desmarque antes de desfazer a triagem.', v_marcados));
  end if;

  delete from public.ra_itens where caso_id = p_caso;

  v_avisou := v_caso.slack_ts is not null
              and (v_caso.slack_avisos ? 'liberado' or v_caso.slack_avisos ? 'fechado' or v_caso.slack_avisos ? 'ajuste');
  update public.ra_casos
     set status = 'aguardando_triagem', triado_por = null, triado_em = null,
         decisao_obs = null, concluido_em = null, decisao = null,
         expiracao_atual = null, expiracao_antiga = null, instrucao_atual = null, instrucao_antiga = null,
         slack_avisos = (slack_avisos - 'liberado' - 'fechado' - 'ajuste' - 'concluido')
                        || case when v_avisou then '{"desfazer_pendente": true}'::jsonb else '{}'::jsonb end
   where id = p_caso;

  insert into public.ra_historico (caso_id, acao, por, detalhe)
  values (p_caso, 'triagem_desfeita', v_uid, jsonb_build_object('status_anterior', v_caso.status));
  return json_build_object('ok', true, 'msg', 'Triagem desfeita. O caso voltou para aguardando triagem.');
end $function$;

CREATE OR REPLACE FUNCTION public.ra_slack_pendentes_base(p_segredo text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_out json;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;

  with base as (
    select c.*, to_char(c.ocorrido_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as quando,
           to_char(c.prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as prazo,
           '<' || v_url || '/relatorios/remocoes?caso=' || c.id || '|Abrir no sistema>' as link
      from public.ra_casos c
  ),
  msgs as (
    -- Disputa: só alerta, marca o triador.
    select b.id as caso_id, 'alerta' as aviso, null::text as thread_ts, 1 as ordem,
           ':warning: *Disputa aberta no HM*' || E'\n' || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando || E'\n\n'
           || 'Ainda não é reembolso nem chargeback.' || E'\n' || b.link as texto
      from base b where b.tipo = 'disputa' and not (b.slack_avisos ? 'alerta')
    union all
    -- Caso novo: marca só o triador.
    select b.id, 'novo', null, 1,
           ':rotating_light: *' || initcap(b.tipo) || ' no HM, triagem pendente*' || E'\n'
           || public.ra_slack_marca(v_triador) || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || '*Compra*' || E'\n' || coalesce(b.produto_nome, '') || ' · ' || public.ra_brl(b.valor) || ' · ' || b.quando
           || case when b.eh_programa then E'\n' || 'Programa de Implementação' else '' end || E'\n\n'
           || '*Sugestão:* ' || coalesce(b.sugestao->>'recomendacao', 'sem sugestão') || E'\n' || coalesce(b.sugestao->>'motivo', '') || E'\n\n'
           || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n' || b.link
      from base b where b.tipo <> 'disputa' and not (b.slack_avisos ? 'novo')
    union all
    -- Triagem: manter acesso.
    select b.id, 'fechado', b.slack_ts, 2,
           ':white_check_mark: *Mantém o acesso antigo.* Nada a remover.'
           || coalesce(E'\n' || b.decisao_obs, '')
      from base b where b.status = 'mantem_acesso' and b.slack_ts is not null and not (b.slack_avisos ? 'fechado')
    union all
    -- Triagem: não remover. Marca quem ajusta a expiração, com as datas.
    select b.id, 'ajuste', b.slack_ts, 2,
           ':white_check_mark: *Não remover acessos*' || E'\n'
           || 'A pessoa mantém o acesso antigo. Ninguém precisa remover nada.' || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || public.ra_slack_marca((select responsavel_id from public.ra_itens_catalogo where item = 'ajuste_central')) || E'\n'
           || 'Voltar a expiração na Central (planilha) e na Base de Alunos (sistema)' || E'\n'
           || coalesce(to_char(b.expiracao_atual, 'DD/MM/YYYY'), 'data atual') || ' → *' || to_char(b.expiracao_antiga, 'DD/MM/YYYY') || '*'
           || case when b.instrucao_antiga is not null and b.instrucao_antiga is distinct from b.instrucao_atual
                   then E'\n' || 'Instrução: ' || coalesce(b.instrucao_atual, 'sem instrução') || ' → *' || b.instrucao_antiga || '*'
                        || case when exists (select 1 from public.ra_pessoas p where p.caso_id = b.id and p.papel = 'socio')
                                then ' (sócios: ' || b.instrucao_antiga || ' - SÓCIO)' else '' end
                   else '' end
           || coalesce(E'\n\n' || b.decisao_obs, '') || E'\n\n'
           || 'Marque no sistema quando atualizar.' || E'\n' || b.link
      from base b where b.decisao = 'manter' and b.status in ('ajustando_acesso', 'concluido')
                    and b.slack_ts is not null and not (b.slack_avisos ? 'ajuste')
    union all
    -- Triagem: remoção liberada. Pessoas uma vez, responsáveis uma vez.
    select b.id, 'liberado', b.slack_ts, 2,
           ':scissors: *Remover acessos*' || E'\n' || '*Prazo:* ' || coalesce(b.prazo, 'sem prazo') || E'\n\n'
           || '*Pessoas*' || E'\n' || public.ra_slack_pessoas(b.id) || E'\n\n'
           || coalesce(public.ra_slack_responsaveis(b.id, false), 'Nenhum item.') || E'\n\n'
           || 'Marquem no sistema quando removerem.' || E'\n' || b.link
      from base b where b.status in ('em_remocao', 'concluido') and coalesce(b.decisao, 'remover') = 'remover'
                    and b.slack_ts is not null and not (b.slack_avisos ? 'liberado')
    union all
    -- Concluído.
    select b.id, 'concluido', b.slack_ts, 3,
           case when b.decisao = 'manter' then ':white_check_mark: *Acesso ajustado*' else ':white_check_mark: *Acessos removidos*' end || E'\n\n'
           || (select string_agg('• ' || linha, E'\n') from (
                 select coalesce(mp.nome, 'sem nome') || ' ' || to_char(max(i.marcado_em) at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI') as linha
                   from public.ra_itens i left join public.perfis mp on mp.id = i.marcado_por
                  where i.caso_id = b.id
                  group by mp.nome) z)
      from base b where b.status = 'concluido' and b.slack_ts is not null
                    and (b.slack_avisos ? 'liberado' or b.slack_avisos ? 'ajuste') and not (b.slack_avisos ? 'concluido')
  )
  select json_build_object('ok', true, 'mensagens',
           coalesce(json_agg(json_build_object('caso_id', m.caso_id, 'aviso', m.aviso,
                                               'thread_ts', m.thread_ts, 'texto', m.texto) order by m.ordem), '[]'::json))
    into v_out from msgs m;
  return v_out;
end $function$;

CREATE OR REPLACE FUNCTION public.ra_slack_lembrete(p_segredo text)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_url text := (select valor from public.ra_config where chave = 'app_url');
  v_triador uuid := (select valor::uuid from public.ra_config where chave = 'triador_id');
  v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
  v_casos int;
  v_atrasados int;
  v_corpo text;
begin
  if not public.ra_slack_valido(p_segredo) then return json_build_object('ok', false); end if;
  if not public.ra_dia_util(v_hoje) then return json_build_object('ok', true, 'texto', null); end if;

  select count(*), count(*) filter (where prazo_em < now())
    into v_casos, v_atrasados
    from public.ra_casos where status in ('aguardando_triagem', 'em_remocao', 'ajustando_acesso');
  if v_casos = 0 then return json_build_object('ok', true, 'texto', null); end if;

  with pend as (
    -- Uma linha por (responsável, caso, pessoa) com os itens que faltam.
    select i.responsavel_id, c.id caso_id, c.prazo_em, c.teste, p.ordem pordem,
           coalesce(p.nome, 'sem nome') || case when p.papel = 'socio' then ' (sócio)' else '' end as pessoa,
           case when c.decisao = 'manter'
                then 'voltar a expiração para ' || coalesce(to_char(c.expiracao_antiga, 'DD/MM/YYYY'), 'a data antiga')
                     || ' (' || string_agg(case k.item when 'ajuste_central' then 'Central' else 'Base de Alunos' end, ' e ' order by k.ordem) || ')'
                else string_agg(k.rotulo, ', ' order by k.ordem) end itens, min(k.ordem) kordem
      from public.ra_itens i
      join public.ra_casos c on c.id = i.caso_id and c.status in ('em_remocao', 'ajustando_acesso')
      join public.ra_pessoas p on p.id = i.pessoa_id
      join public.ra_itens_catalogo k on k.item = i.item
     where i.situacao = 'pendente'
     group by i.responsavel_id, c.id, c.prazo_em, c.teste, c.decisao, c.expiracao_antiga, p.id, p.ordem, p.nome, p.papel
    union all
    -- Triagem pendente: conta para o triador, uma linha por caso (titular).
    select v_triador, c.id, c.prazo_em, c.teste, 0,
           coalesce(c.nome, 'sem nome'), 'triagem', 0
      from public.ra_casos c where c.status = 'aguardando_triagem'
  ), linhas as (
    select responsavel_id, prazo_em, caso_id, pordem, kordem,
           '• <' || v_url || '/relatorios/remocoes?caso=' || caso_id || '|' || pessoa || '>: '
           || regexp_replace(itens, ', ([^,]*)$', ' e \1')
           || case when prazo_em < now() then ' · :red_circle: atrasado'
                   when (prazo_em at time zone 'America/Sao_Paulo')::date = v_hoje
                     then ' · :large_yellow_circle: vence hoje ' || to_char(prazo_em at time zone 'America/Sao_Paulo', 'HH24:MI')
                   else ' · prazo ' || coalesce(to_char(prazo_em at time zone 'America/Sao_Paulo', 'DD/MM HH24:MI'), 'sem prazo') end
           || case when teste then ' · teste' else '' end as linha
      from pend
  ), por_resp as (
    select responsavel_id, min(kordem) kordem,
           public.ra_slack_marca(responsavel_id) || E'\n'
           || string_agg(linha, E'\n' order by prazo_em nulls last, caso_id, pordem) as bloco
      from linhas group by responsavel_id
  )
  -- Linha em branco dupla entre responsáveis, para cada bloco ficar separado.
  select string_agg(bloco, E'\n\n\n' order by kordem) into v_corpo from por_resp;

  return json_build_object('ok', true, 'texto',
    ':alarm_clock: *Remoção de acessos: ' || v_casos || ' caso(s) em aberto'
    || case when v_atrasados > 0 then ', ' || v_atrasados || ' atrasado(s)' else '' end || '*'
    || E'\n\n' || coalesce(v_corpo, 'Nada pendente.'));
end $function$;

CREATE OR REPLACE FUNCTION public.ra_fila()
 RETURNS SETOF json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := (select auth.uid()); v_doc boolean;
begin
  if not public.ra_pode_ver() then return; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  return query
    select to_json(x) from (
      select c.id, c.tipo, c.status, c.nome, c.email, c.produto_nome, c.oferta_codigo, c.valor,
             c.hotmart_transaction, c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.teste, c.origem, c.decisao, c.expiracao_antiga,
             public.mask_sensivel(c.documento, v_doc) as documento,
             c.sugestao->>'recomendacao' as recomendacao,
             (select count(*) from public.ra_pessoas p where p.caso_id = c.id) as pessoas,
             (select count(*) from public.ra_itens i where i.caso_id = c.id) as itens_total,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao <> 'pendente') as itens_feitos,
             (select count(*) from public.ra_itens i where i.caso_id = c.id and i.situacao = 'pendente'
                and i.responsavel_id = v_uid) as meus_pendentes
        from public.ra_casos c
       order by case c.status when 'aguardando_triagem' then 0 when 'em_remocao' then 1 when 'ajustando_acesso' then 1 when 'alerta' then 2 else 3 end,
                c.prazo_em nulls last, c.ocorrido_em desc
    ) x;
end $function$;

CREATE OR REPLACE FUNCTION public.ra_caso(p_caso uuid)
 RETURNS json
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid := (select auth.uid()); v_doc boolean; v_triador boolean;
begin
  if not public.ra_pode_ver() then return null; end if;
  v_doc := public.tem_permissao(v_uid, 'alunos.ver_sensivel');
  v_triador := public.ra_eh_triador();
  return (
    select json_build_object(
      'caso', (select to_json(y) from (
                 select c.id, c.tipo, c.status, c.nome, c.email, c.telefone,
                        public.mask_sensivel(c.documento, v_doc) as documento,
                        c.produto_nome, c.oferta_codigo, c.valor, c.hotmart_transaction,
                        c.ocorrido_em, c.prazo_em, c.concluido_em, c.eh_programa, c.sugestao,
                        c.decisao_obs, c.triado_em, tp.nome as triado_por_nome, c.aluno_id, c.teste, c.origem, c.decisao,
                        c.expiracao_atual, c.expiracao_antiga, c.instrucao_atual, c.instrucao_antiga
                   from public.ra_casos c left join public.perfis tp on tp.id = c.triado_por
                  where c.id = p_caso) y),
      'pessoas', coalesce((select json_agg(json_build_object(
                    'id', p.id, 'nome', p.nome, 'email', p.email, 'papel', p.papel, 'aluno_id', p.aluno_id,
                    'itens', coalesce((select json_agg(json_build_object(
                                'id', i.id, 'item', i.item, 'rotulo', k.rotulo, 'situacao', i.situacao,
                                'responsavel', rp.nome, 'marcado_por', mp.nome, 'marcado_em', i.marcado_em,
                                'corrigido', i.corrigido, 'obs', i.obs,
                                'pode_marcar', (i.responsavel_id = v_uid or v_triador)) order by k.ordem)
                              from public.ra_itens i
                              join public.ra_itens_catalogo k on k.item = i.item
                              left join public.perfis rp on rp.id = i.responsavel_id
                              left join public.perfis mp on mp.id = i.marcado_por
                             where i.pessoa_id = p.id), '[]'::json)) order by p.ordem)
                  from public.ra_pessoas p where p.caso_id = p_caso), '[]'::json),
      'historico', coalesce((select json_agg(json_build_object(
                      'acao', h.acao, 'em', h.em, 'por', hp.nome, 'detalhe', h.detalhe) order by h.em)
                    from public.ra_historico h left join public.perfis hp on hp.id = h.por
                   where h.caso_id = p_caso), '[]'::json),
      'pode_triar', v_triador
    )
  );
end $function$;

revoke all on function public.ra_triar(uuid, text, text, boolean, date, text) from public, anon;
grant execute on function public.ra_triar(uuid, text, text, boolean, date, text) to authenticated;
revoke all on function public.ra_slack_pendentes_base(text) from public, anon, authenticated;
