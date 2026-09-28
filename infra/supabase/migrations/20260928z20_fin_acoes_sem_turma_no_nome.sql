-- 20260928z20 — João, 28/09: "não quero o board financeiro por turma; é por ação que a gente fez, por evento".
-- A turma sai do NOME das ações de 2026 (fica na coluna turma e na turma de origem da pessoa, z17/z18).
update fin.acoes set nome = regexp_replace(nome, '^T\d+ · ', '') where prioridade <> 50 and nome ~ '^T\d+ · ';
-- vw_acao_card: o evento do dia sai sem prefixo de turma; "Migrados (HM R$ 15 mil antes de 25/06/2026)".
-- Aplicado por regexp sobre pg_get_viewdef (o arquivo da z11 guarda a forma anterior; a vigente é a do banco).
