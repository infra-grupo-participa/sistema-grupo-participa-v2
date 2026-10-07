-- 20261007k: cadastro do projeto da Clínica de Miami em mkt.projetos (sigla CNFMIAMI26, chave clinica-miami-2026-12)
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007152825 (nome mkt_projeto_clinica_miami, era 20261007k) em
-- supabase_migrations.schema_migrations, pelo aplica_sql.py aplicar + insert na mesma transação. md5 gravado =
-- cacd142226c57ee7308879a24d7a3fc0 = este arquivo antes desta troca de STATUS. Relatório: 20261007152825.explain.md.
--
-- POR QUE
--   A chave clinica-miami-2026-12 (gp-operacoes/projetos/calendario.md, decisão do Victor Hugo de 07/10/2026) já é usada
--   pela regra da lista 614 do ActiveCampaign (20261007j) e pela captura de pré-checkout (20261007i), mas não tem linha
--   em mkt.projetos: a tela mostra a chave crua e o Tráfego não tem o projeto. Sigla CNFMIAMI26 aprovada pelo Victor
--   Hugo em 07/10/2026 (cabe no CHECK projetos_sigla_check ^[A-Z]{2,10}[0-9]{2,4}$).
--
-- DE ONDE VEM CADA VALOR (nada inventado)
--   sigla             CNFMIAMI26                                   aprovada pelo Victor Hugo (07/10/2026)
--   etiqueta_clickup  clinica-miami-2026-12                        gp-operacoes/projetos/calendario.md, linha 14 do calendário
--   nome              Clínica Internacional de Holding Familiar    idem (string exata do calendário)
--   linha             Clínica de Holding Familiar                  gp-operacoes/produtos-e-ofertas/infoprodutos/esteira-de-produtos.md
--                                                                  (coluna obrigatória; a CONFIRMAR com o Victor)
--   ano               2026                                         chave e calendário (03 e 04/12/2026)
--   evento_inicio/fim 2026-12-03 / 2026-12-04                      calendário ("03 e 04/12", Miami)
--   inicio/fim        derivados pelo gatilho projetos_tipo_unidade a partir das datas do evento
--   tipo, unidade, tipo_lancamento, subarea_trafego, especialista, captação: NULOS (fonte não diz; a CONFIRMAR com o Victor).
--     subarea_trafego é derivada pelo gatilho a partir de tipo/unidade: com os dois nulos, fica nula.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha numa tabela de 4. índice: únicos de sigla e etiqueta já existem. frequência: uma vez.
--   repetição: nenhuma. reversão: bloco REVERSÃO no fim (inativar, não apagar).
--
-- IDEMPOTENTE: se a linha (sigla + etiqueta) já existir, não insere de novo. Sigla ou etiqueta já usada por OUTRA linha
--   aborta (não sobrescreve cadastro de ninguém).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

-- 0. Guarda de premissa
do $g$
begin
  if to_regclass('mkt.projetos') is null then
    raise exception '20261007k: mkt.projetos não existe';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'mkt.projetos'::regclass and c.conname = 'projetos_sigla_check')
     is distinct from 'CHECK ((sigla ~ ''^[A-Z]{2,10}[0-9]{2,4}$''::text))' then
    raise exception '20261007k: projetos_sigla_check mudou. Releia pg_get_constraintdef.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007k: a sigla CNFMIAMI26 já existe com outra etiqueta. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = 'clinica-miami-2026-12' and sigla <> 'CNFMIAMI26') then
    raise exception '20261007k: a etiqueta clinica-miami-2026-12 já está em outro projeto. Conferir com o Victor.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12') then
    raise notice '20261007k: projeto CNFMIAMI26 já cadastrado; nada a fazer.';
  end if;
end
$g$;

-- 1. Cadastro (só se ainda não existe)
insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, evento_inicio, evento_fim, obs)
select 'CNFMIAMI26', 'Clínica Internacional de Holding Familiar', 'Clínica de Holding Familiar', 2026,
       'clinica-miami-2026-12', date '2026-12-03', date '2026-12-04',
       'Clínica de Miami (03 e 04/12/2026), paga. Não confundir com o Encontro Internacional dos Diamantes (miami-2026-12, '
       || '01 e 02/12). Cadastrado pela migration 20261007k a pedido do Victor Hugo (07/10/2026). Fonte: '
       || 'gp-operacoes/projetos/calendario.md. A confirmar: linha, tipo, unidade e tipo de lançamento.'
 where not exists (select 1 from mkt.projetos where sigla = 'CNFMIAMI26' or etiqueta_clickup = 'clinica-miami-2026-12');

-- 2. Pós-condição
do $c$
declare r record;
begin
  select count(*) as n, min(nome) as nome, min(inicio) as ini, max(fim) as fim into r
    from mkt.projetos where sigla = 'CNFMIAMI26' and etiqueta_clickup = 'clinica-miami-2026-12';
  if r.n <> 1 then raise exception '20261007k: esperava 1 linha CNFMIAMI26, achei %', r.n; end if;
  if r.ini is distinct from date '2026-12-03' or r.fim is distinct from date '2026-12-04' then
    raise exception '20261007k: período derivado % a %, esperado 2026-12-03 a 2026-12-04', r.ini, r.fim;
  end if;
  if to_regprocedure('crm.projeto_conhecido(text)') is not null and not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007k: clinica-miami-2026-12 não ficou conhecida';
  end if;
end
$c$;

-- REVERSÃO (numa transação; inativar, nunca apagar: pessoas.eventos/origens podem apontar para o id):
-- update mkt.projetos set ativo = false, atualizado_em = now() where sigla = 'CNFMIAMI26';
