-- public.thb_turmas: cria a turma T42 (pedido do Victor, 14/10/2026: "t42 tem que ter... garante que vão entrar").
-- Mesmo formato que a Central usa ao criar turma (public.fn_turma_criar: só codigo e tipo, atual = false). A turma atual
-- continua a T41. sale_start_at e chave ficam NULOS: nenhuma fonte dá a data de início da T42 (a aba da planilha de
-- ativação chama "T42 - HT 32 - Set/26" e só traz a data da compra de cada aluno). Decisão do Maestro, 14/10 ~22:20.
-- public.thb_alunos NÃO é tocado (turma na Central é decisão do Victor).
-- Liga ao turma_id da T42 só a linha do tempo da pessoa única (aditivo): eventos e relações vindos da planilha de
-- ativação com turma "T42" e turma_id nulo. A carga da planilha (20261014152239) já liga sozinha quando a turma existe.
begin;
set local lock_timeout = '5s';

insert into public.thb_turmas (codigo, tipo)
select 'T42', 'thb'
 where not exists (select 1 from public.thb_turmas where codigo = 'T42');

update pessoas.eventos e
   set turma_id = t.id
  from public.thb_turmas t
 where t.codigo = 'T42'
   and e.fonte_tabela = 'pessoas.planilha_linha'
   and e.detalhe->>'turma' = 'T42'
   and e.turma_id is distinct from t.id
   and e.turma_id is null;

update pessoas.relacoes r
   set turma_id = t.id
  from public.thb_turmas t, pessoas.planilha_linha l
 where t.codigo = 'T42'
   and r.fonte_tabela = 'pessoas.planilha_linha'
   and l.chave = r.fonte_id
   and l.turma = 'T42'
   and r.turma_id is distinct from t.id
   and r.turma_id is null;

commit;
