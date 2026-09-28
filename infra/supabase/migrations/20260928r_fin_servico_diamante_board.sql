-- 20260928r — Board do Serviço Diamante (pedido do João, 27/09/2026): "quais serviços ele contratou, quais está
-- devendo, quais está em dia, quem está devendo" — separando os Diamantes que já pagaram alguma vez.
--
-- 1) fin.diamante_ofertas: cada oferta do produto 1462643 → um serviço. As 22 ofertas vieram do projeto
--    "Serviços Diamante" (portal.hotmart_offers + as que só aparecem em portal.hotmart_purchases). Oferta que não
--    está aqui aparece como "Oferta desconhecida" com o código — nunca some.
--    geracao: 'legado' (R$ 800–1.000) · '2025' (R$ 1.300–1.500) · 'regularizacao' (ofertas "… Vencido", usadas
--    para cobrar mensalidade atrasada) · 'pacote' (Serviço Diamante N serviços, sem dizer quais).
-- 2) public.fn_fin_diamante_servicos(): uma linha por pessoa × serviço.
--    Dívida = mensalidade (e-mail × oferta × recorrência) que atrasou e nunca foi paga nem estornada — a mesma regra
--    de fin.parcelas_devidas (OVERDUE é por tentativa; cada mensalidade conta uma vez) — e que NÃO foi regularizada
--    por um pagamento posterior de oferta "Vencido" do mesmo serviço.
--    Dívida recente (≤ 120 dias) × antiga (> 120 dias, a mesma régua do HM): 35 das dívidas medidas eram de assinaturas
--    paradas em 2024–2025.
--    Situação do serviço: devendo (dívida recente) · em_dia (pagou nos últimos 40 dias) · parou_devendo (parou de pagar
--    e ficou dívida antiga — provável cancelamento com débito) · encerrado (parou sem dívida — cancelou ou pausou; a
--    Hotmart não diz qual) · nunca_pagou (só tentativa).
--    Só leitura; guarda de financeiro; telefone mascarado sem gp_pode_ver_cpf().

create table if not exists fin.diamante_ofertas (
  oferta_codigo text primary key,
  servico text not null,
  geracao text not null check (geracao in ('legado','2025','regularizacao','pacote')),
  mensalidade numeric,
  nome_hotmart text
);
alter table fin.diamante_ofertas enable row level security;
revoke all on fin.diamante_ofertas from public, anon, authenticated;

insert into fin.diamante_ofertas (oferta_codigo, servico, geracao, mensalidade, nome_hotmart) values
  ('td9xav44', 'trafego',        'legado',        1000, 'Tráfego'),
  ('52pqh4nd', 'trafego',        '2025',          1500, 'Gestão de Tráfego 2025'),
  ('mrt15ap7', 'web_design',     'legado',         800, 'Web Designer'),
  ('oo578cny', 'web_design',     '2025',          1300, 'Web Design 2025'),
  ('gj3dommw', 'web_design',     'regularizacao', null, 'Web Designer Vencido'),
  ('hqhbhqhd', 'video',          'legado',        1000, 'Edição de Vídeo'),
  ('c07ieg22', 'video',          '2025',          1500, 'Edição de Vídeo 2025'),
  ('dz345zj4', 'video',          '2025',          null, 'Edição de Vídeo 2025'),
  ('az6i68mg', 'video',          'regularizacao', null, 'Edição de Vídeo Vencida'),
  ('g9w7txad', 'copy',           'legado',         800, 'Copywriter'),
  ('ihbplci2', 'copy',           '2025',          1300, 'Copywriter 2025'),
  ('iaafjy8m', 'social_media',   'legado',         800, 'Gestão de Redes Sociais'),
  ('33oyqi0b', 'social_media',   '2025',          null, 'Gestão de redes sociais (Social Media) 2025'),
  ('vc6hmeig', 'social_media',   'regularizacao', null, 'Gestão de Redes Sociais Vencido'),
  ('lbjzicmm', 'design_grafico', 'legado',         800, 'Design Gráfico'),
  ('ua9qomou', 'design_grafico', '2025',          null, 'Design Gráfico 2025'),
  ('n6o84uq5', 'disparos',       'legado',         800, 'Gestor de Disparos'),
  ('bbs6f4qn', 'disparos',       '2025',          1300, 'Gestor de Disparos 2025'),
  ('kkl8wty9', 'disparos',       'regularizacao', null, 'Gestor de Disparos Vencido'),
  ('rm2ba3f5', 'pacote',         'pacote',         800, 'Serviço Diamante - 1 - R$ 800'),
  ('s3psmik8', 'pacote',         'pacote',        2400, 'Serviço Diamante - 3 - R$ 2.400')
on conflict (oferta_codigo) do update
  set servico = excluded.servico, geracao = excluded.geracao, mensalidade = excluded.mensalidade, nome_hotmart = excluded.nome_hotmart;

drop function if exists public.fn_fin_diamante_servicos();
create or replace function public.fn_fin_diamante_servicos()
returns table (
  pessoa_chave text, nome text, email text, emails text[], telefone text, nivel text,
  servico text, ofertas text[], desconhecida boolean,
  primeira_paga date, ultima_paga date, pagamentos int, total_pago numeric, liquido numeric, mensalidade numeric,
  devendo_n int, devendo_valor numeric, devendo_desde date, antigo_n int, antigo_valor numeric, antigo_desde date,
  estornos int, tentativas int, situacao text
)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_hoje date := (now() at time zone 'America/Sao_Paulo')::date;
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  return query
  with tx as (
    select coalesce(ip.pessoa_chave, 'e:' || t.email) pessoa, t.*,
           coalesce(o.servico, 'desconhecida') serv, o.geracao, (o.oferta_codigo is null) descon
      from fin.vw_transacoes t
      join fin.produtos p on p.produto_id = t.produto_id and p.papel = 'servico'
      left join fin.identidade ip on ip.no = 'e:' || t.email
      left join fin.diamante_ofertas o on o.oferta_codigo = t.oferta_codigo
     where t.email is not null
  ), parc as (
    -- uma linha por mensalidade (e-mail × oferta × recorrência): OVERDUE é por tentativa
    select x.pessoa, x.serv, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao) parcela,
           bool_or(x.grupo in ('pago','estornado')) quitada, bool_or(x.grupo = 'atrasado') atrasou,
           min(x.pedido_em) desde, max(x.valor_oferta) valor
      from tx x
     group by x.pessoa, x.serv, x.email, x.oferta_codigo, coalesce(x.recorrencia::text, 't:' || x.transacao)
  ), reg as (
    select x.pessoa, x.serv, max(x.aprovado_em) ult_reg
      from tx x where x.grupo = 'pago' and x.geracao = 'regularizacao'
     group by x.pessoa, x.serv
  ), div as (
    select p.pessoa, p.serv,
           count(*) filter (where p.desde >= now() - interval '120 days')::int n,
           coalesce(sum(p.valor) filter (where p.desde >= now() - interval '120 days'), 0) valor,
           min(p.desde) filter (where p.desde >= now() - interval '120 days') desde,
           count(*) filter (where p.desde < now() - interval '120 days')::int an,
           coalesce(sum(p.valor) filter (where p.desde < now() - interval '120 days'), 0) avalor,
           min(p.desde) filter (where p.desde < now() - interval '120 days') adesde
      from parc p
      left join reg r on r.pessoa = p.pessoa and r.serv = p.serv
     where p.atrasou and not p.quitada and (r.ult_reg is null or r.ult_reg < p.desde)
     group by p.pessoa, p.serv
  ), agg as (
    select x.pessoa, x.serv,
           array_agg(distinct x.oferta_codigo) ofertas,
           bool_or(x.descon) descon,
           min(x.dia_aprovado) filter (where x.grupo = 'pago') prim,
           max(x.dia_aprovado) filter (where x.grupo = 'pago') ult,
           count(*) filter (where x.grupo = 'pago')::int pagos,
           coalesce(sum(x.valor_oferta) filter (where x.grupo = 'pago'), 0) total,
           coalesce(sum(x.liquido) filter (where x.grupo = 'pago'), 0) liq,
           (array_agg(x.valor_oferta order by x.aprovado_em desc) filter (where x.grupo = 'pago' and coalesce(x.geracao, '') <> 'regularizacao'))[1] mens,
           count(*) filter (where x.grupo = 'estornado')::int estornos,
           count(*)::int tentativas
      from tx x
     group by x.pessoa, x.serv
  ), pes as (
    select x.pessoa,
           (array_agg(x.nome order by x.pedido_em desc))[1] nome,
           (array_agg(x.email order by x.pedido_em desc))[1] email,
           array_agg(distinct x.email) emails,
           (array_agg(h.comprador_telefone order by x.pedido_em desc) filter (where h.comprador_telefone is not null))[1] tel
      from tx x join fin.hotmart_transacoes h on h.transacao = x.transacao
     group by x.pessoa
  ), niv as (
    -- nível do cadastro do aluno por qualquer e-mail da pessoa (o maior)
    select e.pessoa,
           (array_agg(a.nivel_resultado order by array_position(
              array['diamante_vermelho','diamante','platina','ouro','profissional','em_formacao','pessoal','iniciante'], a.nivel_resultado)))[1] nivel
      from (select distinct x.pessoa, x.email from tx x
            union select distinct x.pessoa, substr(i.no, 3) from tx x join fin.identidade i on i.pessoa_chave = x.pessoa and i.no like 'e:%') e
      join public.thb_alunos a on lower(trim(a.email)) = e.email and a.nivel_resultado is not null
     group by e.pessoa
  )
  select a.pessoa, pe.nome, pe.email, pe.emails,
         case when coalesce(public.gp_pode_ver_cpf(), false) then pe.tel
              when pe.tel is not null then '···' || right(regexp_replace(pe.tel, '\D', '', 'g'), 4) end,
         nv.nivel,
         a.serv, a.ofertas, a.descon,
         a.prim, a.ult, a.pagos, a.total, a.liq, a.mens,
         coalesce(d.n, 0), coalesce(d.valor, 0), (d.desde at time zone 'America/Sao_Paulo')::date,
         coalesce(d.an, 0), coalesce(d.avalor, 0), (d.adesde at time zone 'America/Sao_Paulo')::date,
         a.estornos, a.tentativas,
         case when coalesce(d.n, 0) > 0 then 'devendo'
              when a.pagos = 0 then 'nunca_pagou'
              when a.ult >= v_hoje - 40 then 'em_dia'
              when coalesce(d.an, 0) > 0 then 'parou_devendo'
              else 'encerrado' end
    from agg a
    join pes pe on pe.pessoa = a.pessoa
    left join div d on d.pessoa = a.pessoa and d.serv = a.serv
    left join niv nv on nv.pessoa = a.pessoa;
end $$;
revoke all on function public.fn_fin_diamante_servicos() from public, anon;
grant execute on function public.fn_fin_diamante_servicos() to authenticated;
