-- Ensaio transacional da 20261016001200: aplica, mede o efeito na leitura de todas as campanhas e nas fases efetivas, ensaia a reversão. Desfaz tudo.
begin;
create temp table _z_out (em int, passo text, linha text);
create temp table _antes as
  select c.id, c.nome, c.objetivo, c.fase_manual, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase_ef, mkt.campanha_traduzir(c.nome) as l
    from mkt_trafego.campanhas c;
create temp table _cfg_antes as select (select count(*) from mkt.campanha_objetivos) o, (select count(*) from mkt_trafego.fases) f, (select count(*) from mkt_trafego.objetivo_fase) m;

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

create temp table _depois as
  select c.id, c.nome, c.objetivo, c.fase_manual, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase_ef, mkt.campanha_traduzir(c.nome) as l
    from mkt_trafego.campanhas c;

insert into _z_out
select 1, 'config_antes_objetivos_fases_mapeamentos', a.o || '/' || a.f || '/' || a.m from _cfg_antes a
union all
select 1, 'config_depois_objetivos_fases_mapeamentos', (select count(*) from mkt.campanha_objetivos) || '/' || (select count(*) from mkt_trafego.fases) || '/' || (select count(*) from mkt_trafego.objetivo_fase)
union all
select 2, 'campanhas_comparadas', count(*)::text from _antes
union all
select 2, 'leitura_mudou', count(*)::text from _antes a join _depois d using (id) where a.l is distinct from d.l
union all
select 2, 'leitura_mudou_so_em_objetivo_CAPTACAO', count(*)::text from _antes a join _depois d using (id)
 where a.l is distinct from d.l and a.objetivo = 'CAPTAÇÃO'
union all
select 2, 'padrao_virou_true', count(*)::text from _antes a join _depois d using (id) where not (a.l->>'padrao')::boolean and (d.l->>'padrao')::boolean
union all
select 2, 'fase_efetiva_mudou', count(*)::text from _antes a join _depois d using (id) where a.fase_ef is distinct from d.fase_ef;
-- campanhas cuja leitura mudou: só nome e o que mudou nos erros (sem dado pessoal)
insert into _z_out
select 3, 'mudou ' || lpad((row_number() over (order by a.nome, a.id))::text, 2, '0') || ' ' || left(a.nome, 90),
       'erros ' || (a.l->'erros')::text || ' -> ' || (d.l->'erros')::text || ' | padrao ' || (a.l->>'padrao') || ' -> ' || (d.l->>'padrao') || ' | fase_ef ' || coalesce(a.fase_ef, 'null') || ' -> ' || coalesce(d.fase_ef, 'null')
  from _antes a join _depois d using (id) where a.l is distinct from d.l or a.fase_ef is distinct from d.fase_ef;
-- o que o dashboard e a tela leem
insert into _z_out
select 4, 'fases_ativas_na_tela', (select string_agg(codigo, ',' order by ordem) from mkt_trafego.fases where ativa);

-- reversão ensaiada: configuração e leitura voltam ao antes
-- Reversão da 20261016001200: tira o objetivo CAPTAÇÃO, as fases distribuicao e pre_captacao e os 2 mapeamentos.
-- Se alguém já usou uma fase nova (fase_manual, projeto_fases, modelo_fases, campanhas esperadas), a FK RESTRICT barra e nada é apagado.
-- Depois: delete from supabase_migrations.schema_migrations where version = '20261016001200';
set local lock_timeout = '5s';
set local statement_timeout = '30s';

delete from mkt_trafego.objetivo_fase where (objetivo, fase) in (('CAPTAÇÃO', 'captacao'), ('DISTRIBUIÇÃO', 'distribuicao'));
delete from mkt_trafego.fases where codigo in ('distribuicao', 'pre_captacao');
delete from mkt.campanha_objetivos where codigo = 'CAPTAÇÃO';

create temp table _revertido as
  select c.id, mkt_trafego.fase_efetiva(c.objetivo, c.fase_manual) as fase_ef, mkt.campanha_traduzir(c.nome) as l from mkt_trafego.campanhas c;
insert into _z_out
select 5, 'apos_reversao_leitura_e_fase_iguais_ao_antes', (not exists (select 1 from _antes a join _revertido r using (id) where a.l is distinct from r.l or a.fase_ef is distinct from r.fase_ef))::text
union all
select 5, 'apos_reversao_config', (select count(*) from mkt.campanha_objetivos) || '/' || (select count(*) from mkt_trafego.fases) || '/' || (select count(*) from mkt_trafego.objetivo_fase);

select passo, linha from pg_temp._z_out order by em, passo;
rollback;
