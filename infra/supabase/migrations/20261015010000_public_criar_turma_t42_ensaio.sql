-- Ensaio da 20261015010000 (transação desfeita). Só contagens.
begin;
set local lock_timeout = '5s';
insert into public.thb_turmas (codigo, tipo) select 'T42', 'thb' where not exists (select 1 from public.thb_turmas where codigo = 'T42');
insert into public.thb_turmas (codigo, tipo) select 'T42', 'thb' where not exists (select 1 from public.thb_turmas where codigo = 'T42');  -- 2ª vez: nada
do $$ begin
  if (select count(*) from public.thb_turmas where codigo = 'T42') <> 1 then raise exception 'T42 duplicada'; end if;
  if (select codigo from public.thb_turmas where tipo = 'thb' and atual) <> 'T41' then raise exception 'turma atual mudou'; end if;
  if exists (select 1 from public.thb_turmas where codigo = 'T42' and (atual or sale_start_at is not null or chave is not null)) then
    raise exception 'T42 fora do formato combinado'; end if;
end $$;
select codigo, tipo, atual, sale_start_at, chave from public.thb_turmas where codigo in ('T41', 'T42') order by codigo;
rollback;
