-- 20261007l: cadastro do projeto do Encontro Internacional dos Diamantes em mkt.projetos (chave miami-2026-12)
--
-- STATUS: APLICADA em produção em 07/10/2026, versão 20261007152903 (nome mkt_projeto_encontro_diamantes_miami, era 20261007l) em
-- supabase_migrations.schema_migrations, pelo aplica_sql.py aplicar + insert na mesma transação. md5 gravado =
-- 13e86c8ce7769a3adf8f065acbff799e = este arquivo antes desta troca de STATUS. Relatório: 20261007152903.explain.md.
--
-- POR QUE
--   Depois da 20261007j, a regra 42 (lista 614 do ActiveCampaign) passa a levar à Clínica (clinica-miami-2026-12) e a
--   chave miami-2026-12 deixa de ser conhecida por crm.projeto_conhecido: só a regra 42 a sustentava (não está em
--   mkt.projetos, crm.funil nem link rastreável). O Encontro Internacional dos Diamantes continua com essa chave
--   (decisão do Victor Hugo, 07/10/2026): sem esta linha, utm_campaign = miami-2026-12 não resolve sozinha.
--
-- DE ONDE VEM CADA VALOR (nada inventado)
--   sigla             EDIMIAMI26                              dada pelo Victor Hugo (07/10/2026, via Maestro)
--   etiqueta_clickup  miami-2026-12                           gp-operacoes/projetos/calendario.md, linha 13 do calendário;
--                                                             projetos/2026-12-miami/CONTEXT.md (chave, clickup_etiqueta)
--   nome              Encontro Internacional dos Diamantes    idem e concepcao.md seção 5 (string exata)
--   linha             Encontro Internacional dos Diamantes    = o nome: regra da casa para projeto novo sem linha
--                                                             (20261006j, revisão do Victor de 06/10/2026: "o nome do
--                                                             projeto basta"; a coluna é obrigatória)
--   ano               2026                                    chave e calendário
--   evento_inicio/fim 2026-12-01 / 2026-12-02                 calendário e concepcao.md seção 5 ("01 e 02/12", Miami)
--   inicio/fim        derivados pelo gatilho projetos_tipo_unidade a partir das datas do evento
--   obs               gratuito e só para Diamantes            calendario.md, bloco de 07/10/2026 (decisão do Victor Hugo)
--   tipo, unidade, tipo_lancamento, subarea_trafego, especialista, captação, edição: NULOS (a fonte não diz).
--     subarea_trafego é derivada pelo gatilho a partir de tipo/unidade: com os dois nulos, fica nula.
--
-- AS 5 PERGUNTAS
--   escala: 1 linha numa tabela de 4 (5 depois da 20261007k). índice: únicos de sigla e etiqueta já existem.
--   frequência: uma vez. repetição: nenhuma. reversão: bloco REVERSÃO no fim (inativar, não apagar).
--
-- IDEMPOTENTE: se a linha (sigla + etiqueta) já existir, não insere de novo. Sigla ou etiqueta já usada por OUTRA linha
--   aborta (não sobrescreve cadastro de ninguém). Mesma guarda da 20261007k.

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $l$
declare
  -- ÚNICO lugar da sigla: dada pelo Victor Hugo em 07/10/2026 (2 a 10 letras maiúsculas + 2 a 4 dígitos).
  v_sigla constant text := 'EDIMIAMI26';
  v_etq   constant text := 'miami-2026-12';
  r record;
begin
  -- 0. Guarda de premissa
  if v_sigla = 'TROCAR_SIGLA' then
    raise exception '20261007l: sigla do Encontro ainda não definida (marcador TROCAR_SIGLA). Pedir a sigla ao Victor Hugo e trocar v_sigla.';
  end if;
  if v_sigla !~ '^[A-Z]{2,10}[0-9]{2,4}$' then
    raise exception '20261007l: sigla % fora do padrão ^[A-Z]{2,10}[0-9]{2,4}$', v_sigla;
  end if;
  if to_regclass('mkt.projetos') is null then
    raise exception '20261007l: mkt.projetos não existe';
  end if;
  if (select pg_get_constraintdef(c.oid) from pg_constraint c
       where c.conrelid = 'mkt.projetos'::regclass and c.conname = 'projetos_sigla_check')
     is distinct from 'CHECK ((sigla ~ ''^[A-Z]{2,10}[0-9]{2,4}$''::text))' then
    raise exception '20261007l: projetos_sigla_check mudou. Releia pg_get_constraintdef.';
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup is distinct from v_etq) then
    raise exception '20261007l: a sigla % já existe com outra etiqueta. Conferir com o Victor.', v_sigla;
  end if;
  if exists (select 1 from mkt.projetos where etiqueta_clickup = v_etq and sigla <> v_sigla) then
    raise exception '20261007l: a etiqueta % já está em outro projeto. Conferir com o Victor.', v_etq;
  end if;
  if exists (select 1 from mkt.projetos where sigla = v_sigla and etiqueta_clickup = v_etq) then
    raise notice '20261007l: projeto % já cadastrado; nada a fazer.', v_sigla;
  end if;

  -- 1. Cadastro (só se ainda não existe)
  insert into mkt.projetos (sigla, nome, linha, ano, etiqueta_clickup, evento_inicio, evento_fim, obs)
  select v_sigla, 'Encontro Internacional dos Diamantes', 'Encontro Internacional dos Diamantes', 2026,
         v_etq, date '2026-12-01', date '2026-12-02',
         'Encontro Internacional dos Diamantes (01 e 02/12/2026, Miami), gratuito, só para Diamantes. Não confundir com a '
         || 'Clínica Internacional de Holding Familiar (clinica-miami-2026-12, CNFMIAMI26, 03 e 04/12, paga). Cadastrado '
         || 'pela migration 20261007l a pedido do Victor Hugo (07/10/2026). Fonte: gp-operacoes/projetos/calendario.md e '
         || 'projetos/2026-12-miami/concepcao.md. A confirmar: tipo, unidade e tipo de lançamento.'
   where not exists (select 1 from mkt.projetos where sigla = v_sigla or etiqueta_clickup = v_etq);

  -- 2. Pós-condição
  select count(*) as n, min(inicio) as ini, max(fim) as fim into r
    from mkt.projetos where sigla = v_sigla and etiqueta_clickup = v_etq;
  if r.n <> 1 then raise exception '20261007l: esperava 1 linha %, achei %', v_sigla, r.n; end if;
  if r.ini is distinct from date '2026-12-01' or r.fim is distinct from date '2026-12-02' then
    raise exception '20261007l: período derivado % a %, esperado 2026-12-01 a 2026-12-02', r.ini, r.fim;
  end if;
  if to_regprocedure('crm.projeto_conhecido(text)') is not null and not crm.projeto_conhecido(v_etq) then
    raise exception '20261007l: % não ficou conhecida', v_etq;
  end if;
end
$l$;

-- REVERSÃO (numa transação; inativar, nunca apagar: pessoas.eventos/origens podem apontar para o id):
-- update mkt.projetos set ativo = false, atualizado_em = now() where etiqueta_clickup = 'miami-2026-12';
