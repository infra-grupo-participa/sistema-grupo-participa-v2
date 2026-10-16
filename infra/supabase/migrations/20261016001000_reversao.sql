-- Reversão da 20261016001000: remove mkt_trafego.linha_black(text, text).
-- Antes, reverter a 20261016001100 (public.dados_black_trafego passa a chamar a função); a guarda abaixo para se alguém ainda a usa.
-- Depois: delete from supabase_migrations.schema_migrations where version = '20261016001000';
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from pg_proc p
              where p.prokind = 'f' and p.oid <> 'mkt_trafego.linha_black(text,text)'::regprocedure
                and p.prosrc like '%linha_black%') then
    raise exception '20261016001000 reversão: ainda há função que chama linha_black; reverter a 20261016001100 antes';
  end if;
end
$g$;

drop function mkt_trafego.linha_black(text, text);
