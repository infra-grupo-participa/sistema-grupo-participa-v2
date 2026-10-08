-- 20261009002000: work_mem só na RPC public.fn_acelera_sync_funil(p_linhas jsonb) — tira o spill em disco
--
-- STATUS: APLICADA em produção 08/10/2026 (~23h BRT; versão em supabase_migrations.schema_migrations). Proposta (bônus do pedido de 08/10, independente da 20261009001000).
--
-- QUEM: única RPC com parâmetro p_linhas chamada pelo PostgREST no pg_stat_statements desde o restart de 08/10 20:35
--   (texto: "... LATERAL \"public\".\"fn_acelera_sync_funil\"(\"p_linhas\" := ...)"). ACL: postgres + service_role.
--   Medido 08/10 ~21:40 UTC: 28 chamadas, temp_blks_written 7.840 (280 blocos ≈ 2,2 MB de spill por chamada),
--   média 491 ms, máx 1.297 ms. work_mem do banco = 3500kB.
--
-- PROVA (begin … rollback, payload sintético: os 1.944 contatos ACELERA com as datas atuais + 30.000 e-mails
--   @exemplo.invalid; 0 linha alterada), temp_blks_written da chamada no pg_stat_statements:
--     work_mem 3500kB → 473 blocos | 8MB → 0 | 16MB → 0 | 32MB → 0
--   Com só os 1.944 contatos: 0 bloco em 3500kB (o spill é do tamanho da planilha recebida, não da base).
--   Explain do corpo não sai pelo pg_stat_statements (track = top): o número acima é o da chamada inteira.
--
-- POR QUE 16MB e não 32MB: 8MB já zera com 32 mil linhas (~1,6× a planilha real estimada pelos 280 blocos/chamada);
--   16MB dá 2× de folga com metade da memória por nó de sort/hash num banco de ~1 GB e 60 conexões.
--
-- Reversão: alter function public.fn_acelera_sync_funil(jsonb) reset work_mem;

set local lock_timeout = '3s';

do $g$
declare v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'public.fn_acelera_sync_funil(jsonb)'::regprocedure;
  if v_md5 is distinct from '9f82a8aac4cdef4d30a9f508042d54cc' then
    raise exception '20261009002000: fn_acelera_sync_funil mudou desde a medição (md5 %); medir de novo', v_md5;
  end if;
end
$g$;

alter function public.fn_acelera_sync_funil(jsonb) set work_mem = '16MB';
