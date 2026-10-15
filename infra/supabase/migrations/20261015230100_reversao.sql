-- Reversão de 20261015230100: devolve o corpo anterior de dados.black_live_na_janela (ao_vivo sem teto).
-- Atenção: volta o risco de a janela ficar aberta para sempre se a situação 'ao_vivo' não for corrigida.
set local lock_timeout = '5s';
set local statement_timeout = '60s';

create or replace function dados.black_live_na_janela(p_prevista timestamptz, p_situacao text) returns boolean
language sql stable set search_path = '' as $$
  select p_situacao = 'ao_vivo'
      or (now() >= p_prevista - interval '15 minutes' and now() <= p_prevista + interval '3 hours')
$$;

do $c$
begin
  if (select p.prosrc from pg_proc p where p.oid = 'dados.black_live_na_janela(timestamptz,text)'::regprocedure) ~ '6 hours' then
    raise exception 'reversão de 20261015230100 incompleta';
  end if;
end
$c$;
