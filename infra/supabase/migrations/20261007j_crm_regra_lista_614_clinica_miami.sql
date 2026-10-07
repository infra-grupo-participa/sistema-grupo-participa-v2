-- 20261007j: Comercial, a regra da lista 614 do ActiveCampaign leva à CLÍNICA de Miami, não ao Encontro dos Diamantes.
--
-- STATUS: NÃO APLICADA. Ensaio escrito e NÃO rodado: 20261007j_ensaio.sql. Relatório: 20261007j.explain.md.
--
-- POR QUE
--   A 20261007141044_crm_catalogacao_origem (APLICADA) semeou em crm.catalogo_regra:
--     ('ac_lista', 'contem', 'Clínica Internacional Diamante Dez/26', 'miami-2026-12', 100, 'Lista 614 (confirmado 07/10)')
--   Decisão do Victor Hugo (07/10/2026): a lista 614 é da Clínica de Miami (chave clinica-miami-2026-12, 03 e 04/12),
--   não do Encontro Internacional dos Diamantes (miami-2026-12, 01 e 02/12). Migration aplicada não se edita: arquivo novo.
--
-- O QUE FAZ
--   1. Guarda: existe UMA regra ativa tipo 'projeto', campo 'ac_lista', operador 'contem', padrão "Clínica Internacional
--      Diamante Dez/26" (mesma expressão do índice único: lower(btrim(padrao))), sem janela de datas, com projeto
--      'miami-2026-12' (estado da 20261007141044) ou 'clinica-miami-2026-12' (já corrigida: roda de novo sem efeito).
--      Qualquer outro estado aborta. Aborta também se crm.origem_catalogar(uuid) não existir ou se a massa a recatalogar
--      passar de 1.000 contatos (~3 ms cada pelo explain da 20261007141044: acima disso, rodar em lotes).
--   2. Corrige a regra: projeto = 'clinica-miami-2026-12', nota com a origem da decisão, atualizado_em = now().
--      Padrão, operador, campo, tipo, datas e prioridade não mudam (o índice único catalogo_regra_uidx não é tocado; a
--      chave nova cabe no CHECK '^[a-z0-9][a-z0-9-]{1,79}$').
--   3. Recataloga com a função da própria 20261007141044 (crm.origem_catalogar, a mesma que crm_catalogo_reaplicar usa),
--      porque crm.pessoa_origem GUARDA o projeto copiado (coluna projeto + projeto_regra_id), não deriva na leitura:
--        a) quem tem projeto_regra_id = esta regra (veio por ela);
--        b) quem está sem projeto e tem utm_campaign = clinica-miami-2026-12 entre as chaves vistas: a chave passa a ser
--           "conhecida" (crm.projeto_conhecido lê crm.catalogo_regra.projeto) e o utm implícito passa a resolver.
--      Projeto definido à mão (projeto_manual) não muda: origem_catalogar já preserva.
--   NÃO cria o projeto em mkt.projetos (sigla pendente de confirmação), NÃO mexe em fin.produtos, NÃO mexe na Ativação.
--
-- QUEM LÊ (grep no repo, 07/10/2026): crm.catalogo_regra e crm.pessoa_origem só são lidas pelas funções da
--   20261007141044 (resolver, contatos_itens, crm_contatos_pagina/resumo, crm_catalogo, crm_contato_origem) e pela tela
--   do Comercial via RPC. Nenhum outro repo (disparos-thb, controle-de-eventos, gp-operacoes) lê essas tabelas.
--   A Ativação (20261007135415) chama crm.projeto_do_evento: daqui em diante, evento da lista 614 aponta para
--   clinica-miami-2026-12 (só entra se existir crm.projeto_ativacao com essa chave; sem ela, devolve 'projeto_fechado').
--   Entradas de Ativação já gravadas em miami-2026-12 vindas da lista 614 NÃO são movidas: a migration só conta e avisa
--   (raise notice); mover negócio é decisão do Victor/Arthur.
--
-- AS 5 PERGUNTAS
--   escala: 1 update de 1 linha + origem_catalogar por contato afetado (guarda de 1.000; esperado bem menos: lista de
--     pré-checkout de um evento). A busca do item b) varre crm.pessoa_origem uma vez (base de ~2.800 a 6.000 linhas).
--   índice: a) e b) não têm índice próprio (projeto_regra_id sem índice; chaves em jsonb). Seq scan único numa tabela de
--     milhares de linhas, uma vez. Não justifica índice novo.
--   frequência: uma vez.
--   repetição: nenhuma.
--   reversão: bloco REVERSÃO no fim (voltar o projeto da regra e recatalogar os mesmos contatos).

set local lock_timeout = '5s';

-- ─── 1. Guarda de premissa ────────────────────────────────────────────────────────────────────────────────────────
do $g$
declare v_n int; v_proj text; v_massa int;
begin
  if to_regclass('crm.catalogo_regra') is null or to_regclass('crm.pessoa_origem') is null then
    raise exception '20261007j: falta a 20261007141044 (crm.catalogo_regra / crm.pessoa_origem). Aplique antes.';
  end if;
  if to_regprocedure('crm.origem_catalogar(uuid)') is null then
    raise exception '20261007j: crm.origem_catalogar(uuid) não existe; a recatalogação depende dela (20261007141044).';
  end if;
  select count(*), min(r.projeto) into v_n, v_proj
    from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  if v_n <> 1 then
    raise exception '20261007j: esperava 1 regra ativa ac_lista contem "Clínica Internacional Diamante Dez/26", achei %. Releia crm.catalogo_regra.', v_n;
  end if;
  if v_proj is distinct from 'miami-2026-12' and v_proj is distinct from 'clinica-miami-2026-12' then
    raise exception '20261007j: a regra da lista 614 aponta para "%", nem miami-2026-12 nem clinica-miami-2026-12. Alguém mudou pela tela; conferir com o Victor.', coalesce(v_proj, '(sem projeto)');
  end if;
  select count(*) into v_massa
    from crm.pessoa_origem po
   where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                   and r.vale_de is null and r.vale_ate is null)
      or (po.projeto is null and not po.projeto_manual
          and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                       where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'));
  if v_massa > 1000 then
    raise exception '20261007j: % contatos a recatalogar (teto 1.000). Rodar em lotes antes de seguir.', v_massa;
  end if;
end
$g$;

-- ─── 2. Corrige a regra ───────────────────────────────────────────────────────────────────────────────────────────
update crm.catalogo_regra r
   set projeto = 'clinica-miami-2026-12',
       nota = 'Lista 614: Clínica de Miami, não o Encontro dos Diamantes (decisão do Victor Hugo, 07/10/2026; corrige a semente da 20261007141044)',
       atualizado_em = now()
 where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
   and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
   and r.vale_de is null and r.vale_ate is null
   and r.projeto = 'miami-2026-12';

-- ─── 3. Recataloga quem a correção atinge (função da 20261007141044, não reimplementada) ─────────────────────────
do $r$
declare v uuid; v_id bigint; v_n int := 0; v_ativ int := 0;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null;
  for v in
    select po.pessoa_id from crm.pessoa_origem po
     where po.projeto_regra_id = v_id
        or (po.projeto is null and not po.projeto_manual
            and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                         where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'))
     order by po.pessoa_id
  loop
    perform crm.origem_catalogar(v);
    v_n := v_n + 1;
  end loop;
  raise notice '20261007j: % contatos recatalogados', v_n;

  -- Ativação: entradas já gravadas em miami-2026-12 vindas de lista que esta regra casa. Só conta (não move).
  if to_regclass('crm.ativacao_entrada') is not null then
    select count(*) into v_ativ
      from crm.ativacao_entrada ae
      join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
      left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
     where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
       and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista));
    if v_ativ > 0 then
      raise notice '20261007j: ATENÇÃO, % entradas de Ativação em miami-2026-12 vieram da lista da Clínica. Não foram movidas: levar ao Victor.', v_ativ;
    end if;
  end if;
end
$r$;

-- ─── 4. Conferência ──────────────────────────────────────────────────────────────────────────────────────────────
do $c$
declare v_id bigint; v_res record;
begin
  select r.id into v_id from crm.catalogo_regra r
   where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
     and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
     and r.vale_de is null and r.vale_ate is null and r.projeto = 'clinica-miami-2026-12';
  if v_id is null then raise exception '20261007j: a regra não ficou com clinica-miami-2026-12'; end if;
  if exists (select 1 from crm.pessoa_origem po where po.projeto_regra_id = v_id and po.projeto is distinct from 'clinica-miami-2026-12') then
    raise exception '20261007j: há contato ligado à regra da lista 614 com projeto diferente de clinica-miami-2026-12';
  end if;
  if not crm.projeto_conhecido('clinica-miami-2026-12') then
    raise exception '20261007j: clinica-miami-2026-12 não ficou conhecida (crm.projeto_conhecido)';
  end if;
  -- nome da lista 614 como semeado em crm.ac_lista pela 20261007141044
  select * into v_res from crm.catalogo_resolver(
    jsonb_build_object('ac_lista', '614', 'ac_lista_nome', 'Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout'));
  if v_res.r_projeto is distinct from 'clinica-miami-2026-12' or v_res.r_motivo is distinct from 'regra' then
    raise exception '20261007j: o resolver leva a lista 614 para "%" (motivo %), não para clinica-miami-2026-12', v_res.r_projeto, v_res.r_motivo;
  end if;
end
$c$;

-- ─── REVERSÃO (manual, numa transação) ────────────────────────────────────────────────────────────────────────────
-- 1. update crm.catalogo_regra set projeto = 'miami-2026-12', nota = 'Lista 614 (confirmado 07/10)', atualizado_em = now()
--     where ativo and tipo = 'projeto' and campo = 'ac_lista' and operador = 'contem'
--       and lower(btrim(padrao)) = lower('Clínica Internacional Diamante Dez/26') and vale_de is null and vale_ate is null;
-- 2. Recatalogar os mesmos contatos: perform crm.origem_catalogar(pessoa_id) para quem tem projeto_regra_id = id da regra
--    e para quem tem projeto = 'clinica-miami-2026-12' com projeto_motivo = 'utm'.
