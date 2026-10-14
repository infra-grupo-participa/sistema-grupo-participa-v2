-- Reversão de 20261014170100 (cargas das fontes). NÃO apaga pessoa nem evento já carregado (regra I-03): os eventos das
-- cargas ficam identificados por fonte_tabela; medir antes com
--   select fonte_tabela, count(*) from pessoas.eventos where fonte_tabela is not null group by 1;
set local lock_timeout = '5s';
drop function if exists pessoas.carga_crm_negocio(bigint, integer, boolean);
drop function if exists pessoas.carga_leads(bigint, text, integer, boolean);
drop function if exists pessoas.carga_respondi(bigint, integer, boolean);
drop function if exists pessoas.carga_hm_socios(bigint, integer, boolean);
drop function if exists pessoas.carga_contatos_hm(bigint, integer, boolean);
drop function if exists pessoas.carga_aluno_historico(bigint, integer, boolean);
drop function if exists pessoas.carga_thb_alunos(bigint, integer, boolean);
drop function if exists pessoas.carga_fin_hotmart(bigint, text, integer, boolean);
drop function if exists pessoas._carga_lote_fim(bigint, text, text, int, int, int, int, int, int, timestamptz);
drop function if exists pessoas._carga_exigir(bigint, text);
delete from pessoas.carga_chave where fonte in ('hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi',
  'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio') and por = 'migration 20261014170100';
