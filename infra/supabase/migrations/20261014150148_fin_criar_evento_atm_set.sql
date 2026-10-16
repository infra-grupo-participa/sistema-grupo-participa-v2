-- APLICADA em 14/10/2026 com a versão gravada 20261014150148 (o arquivo se chamava 20261014160500; renomeado conforme o guia 6.3).
-- 20261014160500: o Seminário ATM de setembro de 2026 entra no catálogo oficial de eventos
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única, ETAPA 2B), 14/10/2026. Depende de 20261014160000.
--   Linha nova em fin.eventos: aplicar com o aceite do dono do fin (JP) e o ok do Maestro.
--   Ensaios: 20261014160400_ensaio.sql (estrutura) e 20261014160500_ensaio_impacto.sql (leitores do fin).
--
-- POR QUE: o Victor lembrou de um ATM em setembro (14/10/2026), edição diferente do de julho (atm-1-2026-07) e do de
--   outubro (atm-elaine-1-2026-10). Achado na fonte: gp-operacoes projetos/2026-09-seminario-atm e
--   dados.edicoes_historico ('atm-2-2026-09', rótulo "ATM SET/26").
-- O QUE FAZ: insere o evento. categoria seminario_elaine (como o 68, "Seminário ATM (Dra. Elaine)"; quem conduz é a
--   Dra. Elaine, oferta-do-fechamento.md), setor escritorio, inicio 09/09/2026 (live), fim 11/09/2026 (treplay),
--   concepcao.md "3. Cronograma". venda_ate 11/09 (a condição encerra às 23h59 do dia de cada exibição; A CONFIRMAR).
--   chave atm-2-2026-09 = a mesma de dados.edicoes_historico. Divergência registrada: a pasta do gp-operacoes usa a
--   chave seminario-atm-2026-09 e a etiqueta antiga do ClickUp era sem-atm-set-2026.
-- PROVA (ensaio de impacto): o fn_fin_funis passa a mostrar 9 compradores e R$ 13.500 brutos no evento, igual às 9
--   vendas de Sessão de Viabilidade do debriefing (dados.edicoes_historico.vendas = 9); nenhum outro evento muda.
-- AS 5 PERGUNTAS: escala = 1 linha; índice = PK e chave; frequência = única; repetição = nenhuma;
--   reversão = 20261014160500_reversao.sql.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from fin.eventos where chave = 'atm-2-2026-09' or (categoria = 'seminario_elaine' and inicio = date '2026-09-09')) then
    raise exception '20261014160500: o ATM de setembro já existe.';
  end if;
end
$g$;

insert into fin.eventos (nome, categoria, setor, inicio, fim, venda_ate, codigo, fonte, observacao, automatico, chave)
values ('Seminário ATM (Dra. Elaine, set/2026)', 'seminario_elaine', 'escritorio', date '2026-09-09', date '2026-09-11', date '2026-09-11', null,
        'gp-operacoes projetos/2026-09-seminario-atm (concepcao.md, oferta-do-fechamento.md)',
        'Live 09/09 19h, replay 10/09 e treplay 11/09 (internos). venda_ate = última exibição: confirmar.', false, 'atm-2-2026-09');
