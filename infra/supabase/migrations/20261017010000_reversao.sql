-- Reversão de 20261017010000: desfaz as rodadas de revisão em lote que ainda não foram revertidas e remove as funções e a chave.
-- Revisão e pessoa voltam ao estado copiado em arquivo.pessoas_revisao_lote_item (a mescla é desfeita por pessoas.desfazer_mescla).
-- As duas tabelas (pessoas.revisao_lote e arquivo.pessoas_revisao_lote_item) FICAM: são histórico, nunca se apaga.
-- Aborta, sem remover nada, se sobrar item que não deu para reverter (alguém mexeu na revisão ou na pessoa depois do lote): olhar à mão.
set local lock_timeout = '5s';
set local statement_timeout = '120s';

do $r$
declare v jsonb; n int;
begin
  if to_regprocedure('pessoas.revisao_lote_reverter(bigint,integer)') is null then
    raise exception '20261017010000: reversão sem efeito, a migration não está aplicada.';
  end if;
  v := pessoas.revisao_lote_reverter(null, 5000);
  select count(*) into n from arquivo.pessoas_revisao_lote_item where revertido_em is null;
  if n > 0 then
    raise exception '20261017010000: % item(ns) sem reverter (resultado do lote: %). Nada foi removido; conferir à mão.', n, v;
  end if;
  update pessoas.carga_chave set ligada = false, por = 'reversao 20261017010000', em = now() where fonte = 'revisao_lote';
end
$r$;

drop procedure if exists pessoas.revisao_lote_rodar(text[], integer, integer, integer, bigint);
drop function if exists pessoas.revisao_lote_reverter(bigint, integer);
drop function if exists pessoas.revisao_lote_passo(bigint, bigint, integer, text[], bigint[]);
drop function if exists pessoas.revisao_classificar(bigint, integer, bigint[]);
delete from pessoas.carga_chave where fonte = 'revisao_lote';
