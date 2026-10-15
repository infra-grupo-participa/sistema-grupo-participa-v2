-- Reversão da 20261015062247: desliga a T42 da linha do tempo e apaga a linha da turma SÓ se nada no sistema a usa.
begin;
set local lock_timeout = '5s';
update pessoas.eventos set turma_id = null
 where turma_id = (select id from public.thb_turmas where codigo = 'T42') and fonte_tabela = 'pessoas.planilha_linha';
update pessoas.relacoes set turma_id = null
 where turma_id = (select id from public.thb_turmas where codigo = 'T42') and fonte_tabela = 'pessoas.planilha_linha';
do $$
declare v smallint := (select id from public.thb_turmas where codigo = 'T42');
begin
  if v is null then return; end if;
  if exists (select 1 from public.thb_alunos where turma_id = v or turma_aurum_id = v)
     or exists (select 1 from public.hm_liberacoes where turma_id = v)
     or exists (select 1 from public.ht_editions where hm_turma_id = v)
     or exists (select 1 from pessoas.eventos where turma_id = v)
     or exists (select 1 from pessoas.relacoes where turma_id = v) then
    raise exception 'T42 já está em uso no sistema: não apagar (decidir com o dono da Central)';
  end if;
  delete from public.thb_turmas where id = v;
end $$;
commit;
