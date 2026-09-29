-- 20260929z88 — O board do Financeiro volta a ler a turma DO CARD (desfaz o remendo da z18).
--
-- ⚠️ Aplicar SÓ DEPOIS da 0312 do repo sistema-disparos-participa (a turma do card passa a seguir a regra de 29/09).
--    Esta migration aborta sozinha se o gatilho trg_hm_turma_regra não existir.
--
-- Por quê: a z18 fez o board exibir/filtrar pela turma de ORIGEM calculada aqui (fin.vw_turma_origem_card) porque o cadastro
-- (cs.contatos_hm.turma) estava errado — 100 dos 343 cards divergiam. A 0312 corrigiu o cadastro na fonte com a MESMA regra
-- (fin.fn_turma_primeira_compra, z87) mais a regra de 29/09 do Marcio: só sinal = sem turma; quem já foi aluno fica com a
-- primeira turma. Com o cadastro certo, duas turmas (a do card e a da view) só criariam divergência de novo — e a view
-- continuaria dando turma a quem só pagou o sinal. O board passa a mostrar exatamente o campo que alimenta grupos e disparos.
-- fin.vw_turma_origem_card fica como AUDITORIA (nenhum outro objeto a lê — conferido em pg_depend/prosrc 29/09).
--
-- AS 5 PERGUNTAS
--  1. Escala: TIRA um join lateral por card (fn_turma_primeira_compra por e-mail) da leitura do board. Só melhora.
--  2. Índice: sem filtro novo; p_turma volta a comparar a coluna do card.
--  3. Frequência: 1 leitura por abertura do board (igual).
--  4. Repetição: nenhuma nova.
--  5. Reversão: rodar de novo o bloco da z18 (20260928z18_fin_board_turma_de_origem.sql) — ele é idempotente e reaplica o join.
--
-- MEDIÇÃO (29/09, ensaio em begin…rollback, papel sem gp_pode_ver_financeiro → 0 linhas, mede o plano):
--   ver relatório do executor (explain analyze de public.fn_fin_board antes/depois).
do $do$
declare v text; v_md5 text;
begin
  if not exists (select 1 from pg_trigger where tgname = 'trg_hm_turma_regra' and tgrelid = 'cs.contatos_hm'::regclass) then
    raise exception 'z88: a 0312 (repo sistema-disparos-participa) ainda não foi aplicada — o card ainda tem a turma antiga';
  end if;

  v := pg_get_functiondef('public.fn_fin_board(text,text)'::regprocedure);
  if position('vw_turma_origem_card' in v) = 0 then
    raise notice 'z88: fn_fin_board já lê a turma do card — nada a fazer';
    return;
  end if;
  v_md5 := md5(v);
  if v_md5 <> '97758b8cdc5b3f4ab6bbfe18f298daea' then
    raise exception 'z88: public.fn_fin_board mudou desde a medição (md5 %) — reler o corpo vivo antes de aplicar', v_md5;
  end if;

  v := replace(v, 'coalesce(tu.turma, b.turma), b.turma_origem', 'b.turma, b.turma_origem');
  v := replace(v, '
  left join fin.vw_turma_origem_card tu on tu.contato_hm_id = b.contato_hm_id', '');
  v := replace(v, '(p_turma is null or coalesce(tu.turma, b.turma) = p_turma)', '(p_turma is null or b.turma = p_turma)');

  if position('vw_turma_origem_card' in v) > 0 or position('tu.turma' in v) > 0 then
    raise exception 'z88: patch de fn_fin_board não casou por inteiro';
  end if;
  execute v;
end $do$;
