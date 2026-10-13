-- 20261013193000_reversao.sql: desfaz 20261013193000 (marca 20261013av) inteira.
--
-- O que faz: volta o corpo de dados.transacoes guardado em acesso.corpo_antes (md5 do prosrc conferido, byte a byte),
-- confere antes que o corpo vivo ainda é o desta migration (md5 efbd212fc50a114fa307b4681454e1a9), tira o cron dados-hotmart-ao-vivo-limpar e apaga dados.hotmart_ao_vivo (com o que estiver dentro, que é só ponte: o
-- espelho do Financeiro continua com tudo) e as 4 funções novas. Não toca fin.*, cs.*, os webhooks nem o sync.
-- Antes de rodar em produção: tirar o webhook na Hotmart (senão ela recebe 500 até o cadastro sair). O arquivo já
-- abre e fecha a própria transação (begin ... commit); em psql, rodar com ON_ERROR_STOP. Ensaiada dentro de 20261013193000_ensaio.sql (aplica, reverte, compara).

begin;  -- tudo ou nada: se o bloco abaixo recusar, a transação aborta e o commit do fim vira rollback
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $r$
declare
  v_def text;
  v_md5 text;
begin
  select c.definicao, c.md5 into v_def, v_md5
    from acesso.corpo_antes c
   where c.tipo = 'funcao' and c.migration = '20261013av' and c.alvo = 'dados.transacoes(text,text)';
  if v_def is null then
    raise exception '20261013av reversão: corpo de antes não está em acesso.corpo_antes; nada foi revertido';
  end if;
  -- só restaura se o corpo vivo ainda for o que esta migration aplicou (alguém pode ter mudado depois)
  if md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure)) <> 'efbd212fc50a114fa307b4681454e1a9' then
    raise exception '20261013av reversão: corpo vivo de dados.transacoes não é o desta migration (md5 %); conferir antes, nada foi revertido',
      md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure));
  end if;
  execute v_def;
  if md5((select p.prosrc from pg_proc p where p.oid = 'dados.transacoes(text,text)'::regprocedure)) <> v_md5 then
    raise exception '20261013av reversão: corpo restaurado não bate com o md5 guardado; nada foi revertido';
  end if;
end
$r$;

select cron.unschedule(j.jobid) from cron.job j where j.jobname = 'dados-hotmart-ao-vivo-limpar';

drop function if exists dados.hotmart_ao_vivo_sem_espelho(integer);
drop function if exists dados.hotmart_ao_vivo_limpar();
drop function if exists dados.hotmart_ao_vivo_gravar(text, jsonb);
drop function if exists dados.hotmart_ao_vivo_payload_ok(jsonb);
drop table if exists dados.hotmart_ao_vivo;

delete from acesso.corpo_antes where tipo = 'funcao' and migration = '20261013av' and alvo = 'dados.transacoes(text,text)';
delete from supabase_migrations.schema_migrations where version = '20261013193000';

commit;
