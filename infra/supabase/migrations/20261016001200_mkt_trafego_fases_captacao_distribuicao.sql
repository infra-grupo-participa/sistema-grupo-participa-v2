-- 20261016001200: objetivo CAPTAÇÃO e fases distribuicao e pre_captacao (padrão de nomes do Caio, BF26)
--
-- POR QUE: a BF26 passou a nomear a campanha como `CF | BF26 | CAPTAÇÃO | ...` e `... | DISTRIBUIÇÃO | ...`. CAPTAÇÃO não está em
-- mkt.campanha_objetivos (a leitura acusa objetivo_desconhecido) e DISTRIBUIÇÃO existe mas não aponta para fase nenhuma. A tela de
-- Tráfego não tem fase para a distribuição do C1 nem para a pré-captação (CPF01, ENTRESAFRA). Ok do Victor em 16/10/2026.
-- O QUE FAZ: só dados de configuração, 5 linhas, nenhuma tabela, função, view, policy ou grant alterado.
--   mkt.campanha_objetivos        + CAPTAÇÃO
--   mkt_trafego.fases             + distribuicao (Distribuição, ordem 7) e pre_captacao (Pré-captação, ordem 8); as 6 existentes ficam como estão
--   mkt_trafego.objetivo_fase     + CAPTAÇÃO -> captacao e DISTRIBUIÇÃO -> distribuicao
-- EFEITO (medido no ensaio): campanha com objetivo CAPTAÇÃO deixa de acusar objetivo_desconhecido na leitura (mkt.campanha_traduzir);
--   as campanhas com objetivo CAPTAÇÃO ou DISTRIBUIÇÃO ganham fase efetiva; a tela de Tráfego passa a listar as 2 fases novas.
--   mkt.campanha_traduzir NÃO é reescrita: ela já lê a tabela. Campanha só é regravada na próxima coleta e só se a leitura mudar.
-- AS 5 PERGUNTAS: escala = 3 tabelas de configuração com 6 a 8 linhas; índice = a chave primária de cada uma; frequência = uma vez;
--   repetição = nenhuma; reversão = 20261016001200_reversao.sql (as FKs RESTRICT impedem apagar se alguém já usou a fase).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from mkt.campanha_objetivos where codigo = 'CAPTAÇÃO')
     or exists (select 1 from mkt_trafego.fases where codigo in ('distribuicao', 'pre_captacao'))
     or exists (select 1 from mkt_trafego.objetivo_fase where objetivo in ('CAPTAÇÃO', 'DISTRIBUIÇÃO')) then
    raise exception '20261016001200: objetivo, fase ou mapeamento já existe; revisar antes de aplicar';
  end if;
  if not exists (select 1 from mkt.campanha_objetivos where codigo = 'DISTRIBUIÇÃO') then
    raise exception '20261016001200: DISTRIBUIÇÃO não existe em mkt.campanha_objetivos';
  end if;
end
$g$;

insert into mkt.campanha_objetivos (codigo, ativo) values ('CAPTAÇÃO', true);
insert into mkt_trafego.fases (codigo, nome, ordem, ativa) values
  ('distribuicao', 'Distribuição', 7, true),
  ('pre_captacao', 'Pré-captação', 8, true);
insert into mkt_trafego.objetivo_fase (objetivo, fase) values
  ('CAPTAÇÃO', 'captacao'),
  ('DISTRIBUIÇÃO', 'distribuicao');
