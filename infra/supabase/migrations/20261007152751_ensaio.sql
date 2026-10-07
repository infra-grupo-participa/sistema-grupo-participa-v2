-- Ensaio de 20261007j_crm_regra_lista_614_clinica_miami: tudo numa transação que termina em ROLLBACK. Nada persiste.
-- NÃO RODADO (07/10/2026): o ensaio que valeu é o da sequência i → j → k 2×, 20261007k_ensaio.sql
-- (resultado em 20261007k.explain.md §5). Rodar como no padrão da casa: via MCP com o `rollback` final trocado por
-- `raise exception` com o conteúdo de _r (rollback garantido). Colar o resultado no fim e no .explain.md.
-- Só contagens: nenhum nome, e-mail, telefone ou documento sai deste ensaio.
-- A migration roda DUAS vezes (manual §3: a guarda tem de tolerar o estado que ela mesma deixa).
-- Esperado (tabela _r):
--   antes      regra.projeto = 'miami-2026-12', nota 'Lista 614 (confirmado 07/10)'; pela_regra = {"miami-2026-12": N}
--              (N medido; a guarda aborta acima de 1.000); conhecido_clinica = false se mkt.projetos, crm.funil e
--              crm.link_rastreavel não tiverem a chave; ativacao_miami_da_lista_clinica medido (esperado 0 se não houver
--              crm.projeto_ativacao 'miami-2026-12').
--   depois1    regra.projeto = 'clinica-miami-2026-12', nota nova; pela_regra = {"clinica-miami-2026-12": N} (mesmo N,
--              nenhuma chave miami-2026-12); por_projeto_motivo sem 'miami-2026-12 · regra' vindo desta regra;
--              conhecido_clinica = true; sem_projeto_com_utm_clinica = 0 (resolvidos pelo utm implícito).
--              conhecido_miami: comparar com antes. Se virou false, quem tem 'miami-2026-12 · utm' perde o projeto no
--              próximo "Reaplicar a todos" (a migration não os toca): levar ao Victor antes de aplicar.
--              com_projeto_total: depois1 >= antes (só ganha quem tinha utm da Clínica).
--   depois2    idêntico a depois1 (2ª passada não muda nada e não aborta).
--   As mensagens raise notice ("N contatos recatalogados", aviso da Ativação) saem no log da execução: copiar também.
begin;
set local lock_timeout = '3s';
set local statement_timeout = '25s';
create temp table _r (k text, v jsonb) on commit drop;

insert into _r select 'antes', jsonb_build_object(
  'regra', (select jsonb_build_object('id', r.id, 'projeto', r.projeto, 'nota', r.nota) from crm.catalogo_regra r
             where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
               and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null),
  'pela_regra', (select jsonb_object_agg(coalesce(x.projeto, '(nulo)'), x.n) from (
                   select po.projeto, count(*) n from crm.pessoa_origem po
                    where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                                  where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                                    and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                                    and r.vale_de is null and r.vale_ate is null)
                    group by po.projeto) x),
  'por_projeto_motivo', (select jsonb_object_agg(x.projeto || ' · ' || x.projeto_motivo, x.n) from (
                   select po.projeto, po.projeto_motivo, count(*) n from crm.pessoa_origem po
                    where po.projeto in ('miami-2026-12', 'clinica-miami-2026-12') group by 1, 2) x),
  'sem_projeto_com_utm_clinica', (select count(*) from crm.pessoa_origem po
                    where po.projeto is null and not po.projeto_manual
                      and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                                   where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12')),
  'com_projeto_total', (select count(*) from crm.pessoa_origem where projeto is not null),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'mkt_projetos', (select coalesce(jsonb_agg(mp.etiqueta_clickup order by mp.etiqueta_clickup), '[]') from mkt.projetos mp
                    where mp.etiqueta_clickup in ('miami-2026-12', 'clinica-miami-2026-12')),
  'projeto_ativacao', (select coalesce(jsonb_agg(pa.projeto order by pa.projeto), '[]') from crm.projeto_ativacao pa
                        where pa.projeto in ('miami-2026-12', 'clinica-miami-2026-12')),
  'ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae
                        join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
                        left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
                       where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
                         and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))));

-- MIGRATION, 1ª passada (conteúdo idêntico ao arquivo, sem o `set local lock_timeout` do topo)
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

insert into _r select 'depois1', jsonb_build_object(
  'regra', (select jsonb_build_object('id', r.id, 'projeto', r.projeto, 'nota', r.nota) from crm.catalogo_regra r
             where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
               and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null),
  'pela_regra', (select jsonb_object_agg(coalesce(x.projeto, '(nulo)'), x.n) from (
                   select po.projeto, count(*) n from crm.pessoa_origem po
                    where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                                  where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                                    and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                                    and r.vale_de is null and r.vale_ate is null)
                    group by po.projeto) x),
  'por_projeto_motivo', (select jsonb_object_agg(x.projeto || ' · ' || x.projeto_motivo, x.n) from (
                   select po.projeto, po.projeto_motivo, count(*) n from crm.pessoa_origem po
                    where po.projeto in ('miami-2026-12', 'clinica-miami-2026-12') group by 1, 2) x),
  'sem_projeto_com_utm_clinica', (select count(*) from crm.pessoa_origem po
                    where po.projeto is null and not po.projeto_manual
                      and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                                   where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12')),
  'com_projeto_total', (select count(*) from crm.pessoa_origem where projeto is not null),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'mkt_projetos', (select coalesce(jsonb_agg(mp.etiqueta_clickup order by mp.etiqueta_clickup), '[]') from mkt.projetos mp
                    where mp.etiqueta_clickup in ('miami-2026-12', 'clinica-miami-2026-12')),
  'projeto_ativacao', (select coalesce(jsonb_agg(pa.projeto order by pa.projeto), '[]') from crm.projeto_ativacao pa
                        where pa.projeto in ('miami-2026-12', 'clinica-miami-2026-12')),
  'ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae
                        join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
                        left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
                       where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
                         and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))));

-- MIGRATION, 2ª passada (tem de rodar sem erro e sem mudar nada)
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

insert into _r select 'depois2', jsonb_build_object(
  'regra', (select jsonb_build_object('id', r.id, 'projeto', r.projeto, 'nota', r.nota) from crm.catalogo_regra r
             where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
               and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26') and r.vale_de is null and r.vale_ate is null),
  'pela_regra', (select jsonb_object_agg(coalesce(x.projeto, '(nulo)'), x.n) from (
                   select po.projeto, count(*) n from crm.pessoa_origem po
                    where po.projeto_regra_id = (select r.id from crm.catalogo_regra r
                                                  where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista' and r.operador = 'contem'
                                                    and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
                                                    and r.vale_de is null and r.vale_ate is null)
                    group by po.projeto) x),
  'por_projeto_motivo', (select jsonb_object_agg(x.projeto || ' · ' || x.projeto_motivo, x.n) from (
                   select po.projeto, po.projeto_motivo, count(*) n from crm.pessoa_origem po
                    where po.projeto in ('miami-2026-12', 'clinica-miami-2026-12') group by 1, 2) x),
  'sem_projeto_com_utm_clinica', (select count(*) from crm.pessoa_origem po
                    where po.projeto is null and not po.projeto_manual
                      and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
                                   where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12')),
  'com_projeto_total', (select count(*) from crm.pessoa_origem where projeto is not null),
  'conhecido_miami', crm.projeto_conhecido('miami-2026-12'),
  'conhecido_clinica', crm.projeto_conhecido('clinica-miami-2026-12'),
  'mkt_projetos', (select coalesce(jsonb_agg(mp.etiqueta_clickup order by mp.etiqueta_clickup), '[]') from mkt.projetos mp
                    where mp.etiqueta_clickup in ('miami-2026-12', 'clinica-miami-2026-12')),
  'projeto_ativacao', (select coalesce(jsonb_agg(pa.projeto order by pa.projeto), '[]') from crm.projeto_ativacao pa
                        where pa.projeto in ('miami-2026-12', 'clinica-miami-2026-12')),
  'ativacao_miami_da_lista_clinica', (select count(*) from crm.ativacao_entrada ae
                        join crm.evento_jornada e on 'ej-' || e.id::text = ae.ref
                        left join crm.ac_lista l on l.id = nullif(btrim(e.lista), '')
                       where ae.projeto = 'miami-2026-12' and ae.fonte = 'activecampaign'
                         and crm.catalogo_casa('contem', 'Clínica Internacional Diamante Dez/26', coalesce(l.nome, e.lista))));

-- EXPLAIN (rodar à parte, DENTRO de begin … rollback: explain analyze de função que grava executa de verdade). 2× cada.
-- a) a busca de quem recatalogar (seq scan esperado em crm.pessoa_origem):
-- explain (analyze, buffers) select po.pessoa_id from crm.pessoa_origem po
--  where po.projeto_regra_id = (select r.id from crm.catalogo_regra r where r.ativo and r.tipo = 'projeto' and r.campo = 'ac_lista'
--          and r.operador = 'contem' and lower(btrim(r.padrao)) = lower('Clínica Internacional Diamante Dez/26')
--          and r.vale_de is null and r.vale_ate is null)
--     or (po.projeto is null and not po.projeto_manual
--         and exists (select 1 from jsonb_array_elements(coalesce(po.origem_detalhe -> 'chaves', '[]'::jsonb)) k
--                      where k ->> 'campo' = 'utm_campaign' and lower(btrim(k ->> 'valor')) = 'clinica-miami-2026-12'));
-- b) uma recatalogação (a mesma função, por contato; ~3 ms medidos na 20261007141044):
-- explain (analyze, buffers) select crm.origem_catalogar((select po.pessoa_id from crm.pessoa_origem po
--   where po.projeto_regra_id is not null order by po.pessoa_id limit 1));

select k, v from _r order by case k when 'antes' then 1 when 'depois1' then 2 else 3 end;
rollback;

-- RESULTADO: ainda não rodado.
