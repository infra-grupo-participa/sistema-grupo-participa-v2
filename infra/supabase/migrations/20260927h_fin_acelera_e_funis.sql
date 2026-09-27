-- 20260927h — Acelera Holding no espelho da Hotmart + funis por data (27/09/2026).
-- Acelera Holding (8381847) é o preparatório/porta de entrada do HM: vendido no funil do CNHF
-- (ago–set/2026) e na imersão de 27/09. Pedido do João: "fazer a mesma coisa que a gente fez para o HM".
-- Medido após a carga: contagem por status 6/6 = API; líquido R$ 783.842,68 = sales/summary.
-- (fn_fin_hotmart_pessoas: card casa com b.origem = p_familia — ver 20260927e.)

insert into fin.produtos (produto_id, nome, familia, papel, sincroniza, nota)
values ('8381847', 'Acelera Holding', 'ACELERA', 'principal', true, 'Preparatório do HM. Backend pago do CNHF (ago/2026) e venda na imersão de 27/09/2026.')
on conflict (produto_id) do update set familia = excluded.familia, sincroniza = true, nome = excluded.nome, nota = excluded.nota;

-- Funil = janela de datas por família: a venda cai no funil pela data de aprovação (tentativa, pela do pedido).
-- Editável sem deploy — mudar o corte é um update aqui.
create table if not exists fin.funis (
  id        serial primary key,
  familia   text not null,
  nome      text not null,
  vale_de   date not null,
  vale_ate  date,
  nota      text,
  criado_em timestamptz not null default now(),
  check (vale_ate is null or vale_ate >= vale_de)
);
revoke all on fin.funis from public, anon, authenticated;
insert into fin.funis (familia, nome, vale_de, vale_ate, nota)
select * from (values
  ('ACELERA', 'CNHF — Curso Nacional de Formação em Holding Familiar', date '2021-01-01', date '2026-09-26',
   'Tudo antes da imersão de 27/09 veio do funil do CNHF (decisão do João, 27/09/2026).'),
  ('ACELERA', 'Imersão 27/09', date '2026-09-27', null::date, 'Venda na imersão de 27/09/2026 em diante.')
) v(familia, nome, vale_de, vale_ate, nota)
where not exists (select 1 from fin.funis f where f.familia = v.familia and f.nome = v.nome);

create or replace function public.fn_fin_hotmart_funis(p_familia text default 'HM', p_inicio date default null, p_fim date default null)
returns table (funil text, vale_de date, vale_ate date, vendas int, compradores int, valor_oferta numeric, cobrado_cliente numeric,
               juros numeric, taxa_hotmart numeric, liquido numeric, estornos int, valor_estornado numeric,
               recusadas int, boletos int, parcelado int, parcelas_media numeric)
language plpgsql stable security definer set search_path = ''
as $$
#variable_conflict use_column
declare v_ini date := coalesce(p_inicio, date '2021-01-01');
        v_fim date := coalesce(p_fim, (now() at time zone 'America/Sao_Paulo')::date);
begin
  if not coalesce(public.gp_pode_ver_financeiro(), false) then
    raise exception 'Sem permissão.' using errcode = '42501';
  end if;
  if v_fim < v_ini then raise exception 'Data final antes da inicial.' using errcode = '22023'; end if;
  return query
  with t as (
    select x.*, coalesce(x.dia_aprovado, x.dia_pedido) dia_ref
      from fin.vw_transacoes x where x.familia = p_familia
  ), tf as (
    select t.*, f.nome funil_nome, f.vale_de f_de, f.vale_ate f_ate
      from t left join fin.funis f on f.familia = p_familia and t.dia_ref between f.vale_de and coalesce(f.vale_ate, 'infinity'::date)
     where t.dia_ref between v_ini and v_fim
  )
  select coalesce(tf.funil_nome, 'Sem funil'), min(tf.f_de), max(tf.f_ate),
         count(*) filter (where tf.grupo = 'pago')::int,
         count(distinct tf.email) filter (where tf.grupo = 'pago')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.valor_cobrado) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.juros) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.taxa_hotmart) filter (where tf.grupo = 'pago'), 0),
         coalesce(sum(tf.liquido) filter (where tf.grupo = 'pago'), 0),
         count(*) filter (where tf.grupo = 'estornado')::int,
         coalesce(sum(tf.valor_oferta) filter (where tf.grupo = 'estornado'), 0),
         count(*) filter (where tf.grupo = 'recusado')::int,
         count(*) filter (where tf.grupo in ('em_aberto','expirado'))::int,
         count(*) filter (where tf.grupo = 'pago' and coalesce(tf.parcelas, 1) > 1)::int,
         round(avg(coalesce(tf.parcelas, 1)) filter (where tf.grupo = 'pago'), 1)
    from tf group by coalesce(tf.funil_nome, 'Sem funil')
   order by min(tf.f_de) nulls last;
end $$;
revoke all on function public.fn_fin_hotmart_funis(text, date, date) from public, anon;
grant execute on function public.fn_fin_hotmart_funis(text, date, date) to authenticated;

-- Carga do Acelera desde 01/06/2026.
insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
select '8381847', g::date, least(g::date + 59, (now() at time zone 'America/Sao_Paulo')::date), 'backfill'
  from generate_series(date '2026-06-01', (now() at time zone 'America/Sao_Paulo')::date, interval '60 days') g
on conflict do nothing;

-- Modo evento da imersão de 27/09: relê hoje e ontem do Acelera e do HM a cada 15 min; desliga sozinho depois de 28/09.
select cron.schedule('fin-hotmart-sync-evento', '*/15 * * * *', $cron$
  insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
  select p, (now() at time zone 'America/Sao_Paulo')::date - 1, (now() at time zone 'America/Sao_Paulo')::date, 'rotina'
    from unnest(array['8381847','5064314']) p
   where (now() at time zone 'America/Sao_Paulo')::date <= date '2026-09-28'
  on conflict do nothing;
  select cron.unschedule('fin-hotmart-sync-evento') where (now() at time zone 'America/Sao_Paulo')::date > date '2026-09-28';
$cron$);
