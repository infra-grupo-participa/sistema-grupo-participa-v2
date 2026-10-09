-- Reversão de 20261009153515 (ações na mensagem, status do atendimento, mensagem agendada). NÃO APLICADA.
-- Antes de rodar: desligar o que estiver na fila de ações (update crm.mensagem_acao set status='falhou' where status in
-- ('na_fila','enviando')) e cancelar agendadas pendentes, porque as colunas somem. O texto editado continua em
-- crm.mensagem.texto; editada_em/apagada_em/citada_id/agendada_para se perdem (exportar antes, se precisar).
-- Corpos devolvidos = os vivos lidos em 09/10/2026 (md5 na guarda da migration).
begin;
drop trigger if exists mensagem_reabre on crm.mensagem;
drop trigger if exists mensagem_agendada on crm.mensagem;
drop function if exists crm.tg_mensagem_reabre();
drop function if exists crm.tg_mensagem_agendada();
drop function if exists public.crm_mensagem_editar(uuid, text);
drop function if exists public.crm_mensagem_apagar(uuid);
drop function if exists public.crm_responder_mensagem(uuid, text, uuid);
drop function if exists public.crm_conversa_atendimento(uuid, text);
drop function if exists public.crm_agendar_mensagem(uuid, text, timestamptz, uuid, uuid, uuid);
drop function if exists public.crm_cancelar_agendada(uuid);
drop function if exists crm.mensagem_acao_motivo(crm.mensagem, text, uuid);
drop function if exists crm.evolution_acoes_pegar(integer);
drop function if exists crm.evolution_acao_resultado(uuid, integer, text);
drop function if exists crm.evolution_citacoes(uuid[]);
drop function if exists crm.evolution_alteracao(uuid, jsonb);

create or replace function crm.mensagem_json(m crm.mensagem, p_contato uuid)
 returns jsonb language sql immutable set search_path to ''
as $function$
  select jsonb_build_object(
    'id', m.id, 'contatoId', p_contato, 'canal', 'whatsapp', 'direcao', m.direcao, 'tipo', m.tipo, 'texto', m.texto, 'em', m.em,
    'status', case when m.direcao = 'entrada' then case when m.lida_em is null then null else 'lida' end
                   when m.status in ('na_fila', 'enviando') then null else m.status end,
    'envio', case when m.status in ('na_fila', 'enviando') then m.status end,
    'erro', m.erro, 'autorId', m.autor_id, 'templateId', m.template_id, 'fichaId', m.ficha_id,
    'canalId', m.numero_id, 'externa', m.externa, 'origem', m.origem,  -- 20261009060000: 'mcp' = enviada pelo Claude
    'midia', case when m.midia_status is not null then jsonb_build_object(
               'status', m.midia_status, 'caminho', case when m.midia_status = 'ok' then m.midia_caminho end,
               'mime', m.midia_mime, 'tamanho', m.midia_tamanho, 'nome', m.midia_nome) end);
$function$;

create or replace function public.crm_conversas(p_limite integer default 300)
 returns jsonb language plpgsql stable set search_path to ''
as $function$
declare v_lim int := least(greatest(coalesce(p_limite, 300), 1), 1000); v jsonb;
begin
  perform crm.exige_comercial();
  with c as (select x.* from crm.conversa x where x.ultima_mensagem_id is not null and x.excluida_em is null order by x.ultima_em desc limit v_lim * 2),
  al as (select * from crm.atual_de(array(select distinct c.pessoa_id from c))),
  g as (select al.atual, (array_agg(c.ultima_mensagem_id order by c.ultima_em desc))[1] msg_id, sum(c.nao_lidas)::int nao,
               max(c.ultima_entrada_em) ent, max(c.ultima_em) ult,
               (array_agg(c.numero_id order by c.ultima_em desc))[1] canal, array_agg(distinct c.numero_id) canais,
               jsonb_agg(jsonb_build_object('id', c.id, 'canalId', c.numero_id) order by c.ultima_em desc) convs
          from c join al on al.pessoa_id = c.pessoa_id group by al.atual order by max(c.ultima_em) desc limit v_lim)
  select coalesce(jsonb_agg(jsonb_build_object(
           'contatoId', g.atual, 'ultimaMensagem', crm.mensagem_json(m, g.atual), 'naoLidas', g.nao,
           'janelaAteEm', case when g.ent > now() - interval '24 hours' then g.ent + interval '24 hours' end,
           'atribuidaA', pc.dono_id, 'canalId', g.canal, 'canais', to_jsonb(g.canais), 'conversas', g.convs) order by g.ult desc), '[]'::jsonb)
    into v
    from g join crm.mensagem m on m.id = g.msg_id
    left join crm.pessoa_comercial pc on pc.pessoa_id = g.atual;
  return v;
end
$function$;

create or replace function crm.tg_rt_caixa()
 returns trigger language plpgsql security definer set search_path to ''
as $function$
declare v_mudou boolean := false;
begin
  begin
    if tg_table_name = 'mensagem' and tg_op = 'INSERT' then
      v_mudou := exists (select 1 from novas);
    elsif tg_table_name = 'mensagem' then
      -- só o que a tela mostra (crm.mensagem_json) ou a conversa a que pertence
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.status, n.lida_em, n.erro, n.texto, n.tipo, n.em, n.pessoa_id, n.autor_id, n.template_id,
                n.midia_status, n.midia_caminho, n.midia_mime, n.midia_tamanho, n.midia_nome)
               is distinct from
               (o.status, o.lida_em, o.erro, o.texto, o.tipo, o.em, o.pessoa_id, o.autor_id, o.template_id,
                o.midia_status, o.midia_caminho, o.midia_mime, o.midia_tamanho, o.midia_nome));
    elsif tg_table_name = 'conversa' then
      -- contador de não lidas (marcar como lida em outra tela) e unificação de pessoa
      v_mudou := exists (
        select 1 from novas n join velhas o on o.id = n.id
         where (n.nao_lidas, n.pessoa_id) is distinct from (o.nao_lidas, o.pessoa_id));
    end if;
    if v_mudou then
      perform realtime.send(jsonb_build_object('t', tg_table_name), 'mudou', 'crm:caixa', true);
    end if;
  exception when others then
    raise warning 'crm.tg_rt_caixa: %', sqlerrm;
  end;
  return null;
end $function$;

-- crm.tg_mensagem_canal: a única diferença é "and m.em <= now()" nas 3 contagens (inofensivo sem agendadas);
-- para voltar o corpo exato, use pg_get_functiondef do backup ou a migration 20261008152212.

create or replace function crm.evolution_fila_tem()
 returns boolean language sql stable security definer set search_path to ''
as $function$
  select coalesce((select c.evolution_ligado from crm.config c), false)
     and (exists (select 1 from crm.integracao_evento x where x.fonte = 'evolution' and x.processado_em is null and x.tentativas < 5)
          or (coalesce((select c.envio_ligado from crm.config c), false)
              and (exists (select 1 from crm.mensagem m where m.status = 'na_fila' and m.provedor = 'evolution' and m.fila_em <= now()
                              and coalesce(m.proxima_tentativa_em, m.fila_em) <= now())
                   or exists (select 1 from crm.mensagem m where m.status = 'enviando' and m.provedor = 'evolution'
                                and m.status_em < now() - interval '5 minutes')))
          or exists (select 1 from crm.mensagem m where m.midia_status = 'pendente' and m.provedor = 'evolution'
                       and m.midia_proxima_em < now() - interval '15 minutes'));
$function$;

-- crm.evolution_webhook: sem o ramo edicao/revogacao, esses eventos caem em "ignorados" (o ramo novo é aditivo);
-- recriar a partir do corpo vivo anterior (md5 c3526c98…) só se precisar do texto exato.

alter table crm.notificacao drop constraint notificacao_gatilho_check;
update crm.notificacao set gatilho = 'prazo_estourado' where gatilho = 'mensagem_falhou';
alter table crm.notificacao add constraint notificacao_gatilho_check check (gatilho = any (array['lead_novo'::text, 'lead_respondeu'::text,
  'prazo_estourado'::text, 'venda_aprovada'::text, 'ficha_para_aprovar'::text, 'atividade_vencendo'::text, 'estrategia'::text]));

drop table if exists crm.mensagem_acao;
alter table crm.conversa drop column atendimento, drop column atendimento_em, drop column atendimento_por;
alter table crm.mensagem drop column editada_em, drop column apagada_em, drop column apagada_por, drop column citada_id, drop column agendada_para;
commit;
