-- 20260928z30 — Evento novo do Holding Total nasce sozinho no calendário (item 6 da proposta de limpeza, aprovado 28/09).
-- Fonte: public.ht_editions (a equipe cria a edição no Centro de Controle). Regra SEGURA: só entra a edição de número
-- MAIOR que o maior HT já no calendário (hoje HT32) e com event_start_date preenchida — as datas planejadas antigas da
-- tabela divergem do que aconteceu (o HT29 planejado para 06–20/07 foi em 26/07) e não podem sobrescrever o calendário.
-- Janela de venda: sale_start_at → sale_end_at (ou início + 5 dias). Roda todo dia 04:41 e pode ser chamada à mão.
alter table fin.eventos add column if not exists automatico boolean not null default false;

create or replace function fin.sincronizar_eventos_ht()
returns integer
language plpgsql security definer set search_path = ''
as $$
declare v_max int; v_n int;
begin
  select coalesce(max(substring(e.codigo from '^HT(\d+)$')::int), 0) into v_max
    from fin.eventos e where e.categoria = 'holding_total';
  insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, carrinho_inicio, codigo, fonte, observacao, turma_hm, automatico)
  select 'Holding Total (HT' || h.edition_number || ')', 'holding_total', 'educacao',
         h.event_start_date,
         coalesce((h.sale_end_at at time zone 'America/Sao_Paulo')::date, h.event_start_date + 2),
         coalesce((h.sale_end_at at time zone 'America/Sao_Paulo')::date, h.event_start_date + 5),
         (h.sale_start_at at time zone 'America/Sao_Paulo')::date,
         'HT' || h.edition_number, 'public.ht_editions (automático)',
         'criado sozinho a partir da edição cadastrada no Centro de Controle', null, true
    from public.ht_editions h
   where h.edition_number > v_max and h.event_start_date is not null
  on conflict (categoria, inicio) do nothing;
  get diagnostics v_n = row_count;
  return v_n;
end $$;
revoke all on function fin.sincronizar_eventos_ht() from public, anon, authenticated;

select cron.schedule('fin-eventos-ht-automaticos', '41 4 * * *', $c$ select fin.sincronizar_eventos_ht() $c$);
