-- 20261002e — Programa do aluno: status por programa + evidências (somente leitura, nenhuma coluna nova)
--
-- O QUE FAZ
--   1. public.fn_aluno_programas_safe(): 1 linha por aluno ativo (thb_alunos.cancelado_em is null) com
--      programas text[], status_programa jsonb {programa: status}, revisar_motivos text[].
--   2. public.fn_aluno_programa_evidencias(p_aluno uuid): as provas de cada programa (GPS, cadastro, Hotmart,
--      evento, Acelera, sócio). valor só para quem passa em gp_pode_ver_financeiro(); nunca e-mail nem documento.
--   As duas: SECURITY DEFINER, search_path public, pg_temp, guarda gp_eh_equipe() (42501), sem PUBLIC/anon.
--
-- CHAVES DE PROGRAMA: implementacao, hm, aurum, mastermind_diamante, diamante_vermelho, platina.
-- STATUS: confirmado | confirmado_cadastro | a_revisar | reservou.
--
-- REGRAS (decisões do Marcio)
--   implementacao — gps.membros (aluno_id ∪ pessoa_aluno_id) é a verdade absoluta:
--     no GPS                                            → confirmado
--       + sem nenhum pagamento de HM localizado          → motivo impl_gps_sem_pagamento (continua confirmado)
--     fora do GPS e pagou o Programa                    → a_revisar, motivo impl_pago_fora_gps
--       "pagou o Programa" = oferta paga com public.hm_product_catalog.categoria in ('compra_cheia','diferenca')
--       (HM cheio ou saldo quitado; mesmo catálogo que cs.fn_hm_programa usa, sem ligar por comprador_id)
--     fora do GPS e espaco_instrucao = 'holding_masters_implementacao' → a_revisar, motivo impl_espaco_fora_gps
--     fora do GPS, só sinal/reserva pago                → reservou
--   hm — pagamento pago da família HM (fin.produtos.familia), exceto 446345 "Curso Prático de Holding Familiar",
--     e sem implementacao (confirmado ou a_revisar; 'reservou' não tira o HM).
--   aurum — família AURUM + cadastro (espaco_instrucao 'aurum' | turma_aurum_id | plano 'aurum').
--   mastermind_diamante — família PROGRAMA_DIAMANTE + cadastro (espaco_instrucao 'mastermind_diamante' | plano 'diamante').
--     A família DIAMANTE (produto 1462643 "Serviço Diamante", papel servico) é a agência "Serviços Diamante":
--     NÃO entra. fin.diamante_* idem.
--     Para os dois: as duas fontes → confirmado; só uma → a_revisar com <programa>_so_pagamento / _so_cadastro.
--   platina, diamante_vermelho — não há família própria em fin.produtos (medido 30/09: famílias HT, HM, EVENTOS,
--     AURUM, DIAMANTE, OUTRO, ESCRITORIO, ACELERA, OUTROS, PROGRAMA_DIAMANTE, A_CLASSIFICAR, ESCRITORIO_SOLUCOES).
--     Valem só espaço/plano (platina: espaco 'platina' | plano 'platina'; diamante_vermelho: espaco 'diamante_vermelho')
--     → confirmado_cadastro.
--   Sócio (socio_de_aluno_id not null) herda os programas do titular ATIVO; compra própria soma. No mesmo
--     programa vale o melhor status (confirmado > confirmado_cadastro > a_revisar > reservou) e os motivos do
--     status vencedor.
--   Eventos (fin.eventos + fin.evento_ofertas) e ACELERA: só evidência na função 2. Não criam programa.
--
-- LIGAÇÃO PESSOA ↔ COMPRA: e-mail normalizado → fin.vw_email_pessoa.pessoa_chave; todos os e-mails da mesma
--   pessoa_chave somam. NUNCA por comprador_id (1.267 ativos com comprador_id nulo). E-mail sem pessoa_chave em
--   fin.identidade casa só com ele mesmo (chave '#email:<email>').
--   fin.vw_transacoes só cobre a conta Hotmart ACADEMY (where conta = 'academy'); a conta ESCRITÓRIO (510 transações
--   em 30/09) fica fora: compra feita lá não aparece aqui.
--   "pago" = fin.vw_transacoes.grupo = 'pago' (status APPROVED/COMPLETE). 'COMPLETED' não entra (0 linhas em 30/09).
--
-- NÃO ALTERA cs.fn_hm_programa nem nada de cs.* (compartilhado com a Ativação).
--
-- AS 5 PERGUNTAS
--   escala: 1.885 alunos ativos; fin.vw_transacoes 57.307 linhas (≈37 mil pagas); gps.membros 180.
--   índice: F1 é varredura agregada única (hash join); F2 usa hotmart_transacoes_email_idx
--     (lower(TRIM(BOTH FROM comprador_email)) = expressão da coluna email da view), identidade_pkey, identidade_pessoa_idx,
--     membros_aluno_id_idx / membros_pessoa_aluno_idx, hm_product_catalog_offer_code_key, evento_ofertas_oferta_uq.
--   frequência: F1 1x por abertura da lista; F2 1x por aluno aberto.
--   repetição: F1 = 1 passada por fonte (CTEs agregadas por pessoa_chave / aluno_id), nenhuma subquery por aluno.
--   reversão: drop function public.fn_aluno_programa_evidencias(uuid); drop function public.fn_aluno_programas_safe();
--
-- ENSAIO: infra/supabase/migrations/20261002e_ensaio.sql (begin … rollback).

-- ─── 1. Lista: programas × status × motivos ─────────────────────────────────────────────────────────────────────────
create function public.fn_aluno_programas_safe()
returns table (aluno_id uuid, programas text[], status_programa jsonb, revisar_motivos text[])
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_programas_safe: acesso restrito à equipe' using errcode = '42501';
  end if;

  return query
  -- CENTRAL:INICIO
  with al as (
    select a.id, a.socio_de_aluno_id, a.espaco_instrucao, a.plano, a.turma_aurum_id,
           nullif(lower(trim(both from a.email)), '') as email_n
      from public.thb_alunos a
     where a.cancelado_em is null
  ),
  ep as (
    select e.email, e.pessoa_chave
      from fin.vw_email_pessoa e
  ),
  -- 1 passada em fin.vw_transacoes (só conta academy), agregada por e-mail
  pag_email as (
    select t.email,
           bool_or(t.familia = 'HM' and t.produto_id <> '446345'
                   and coalesce(t.produto_nome, '') not ilike '%curso pr_tico%')   as pg_hm,
           bool_or(c.categoria in ('compra_cheia', 'diferenca'))                  as pg_impl,
           bool_or(c.categoria in ('sinal', 'reserva'))                           as pg_sinal,
           bool_or(c.categoria is not null)                                       as pg_catalogo,
           bool_or(t.familia = 'AURUM')                                           as pg_aurum,
           bool_or(t.familia = 'PROGRAMA_DIAMANTE')                               as pg_mmd
      from fin.vw_transacoes t
      left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
     where t.grupo = 'pago'
       and t.email is not null and t.email <> ''
       and (t.familia in ('HM', 'AURUM', 'PROGRAMA_DIAMANTE') or c.categoria is not null)
     group by t.email
  ),
  -- e-mail → pessoa: todos os e-mails da mesma pessoa_chave somam
  pag as (
    select coalesce(ep.pessoa_chave, '#email:' || pe.email) as chave,
           bool_or(pe.pg_hm) as pg_hm, bool_or(pe.pg_impl) as pg_impl, bool_or(pe.pg_sinal) as pg_sinal,
           bool_or(pe.pg_catalogo) as pg_catalogo, bool_or(pe.pg_aurum) as pg_aurum, bool_or(pe.pg_mmd) as pg_mmd
      from pag_email pe
      left join ep on ep.email = pe.email
     group by 1
  ),
  gps_ids as (
    select m.aluno_id as id from gps.membros m
    union
    select m.pessoa_aluno_id from gps.membros m where m.pessoa_aluno_id is not null
  ),
  own as (
    select al.id, al.socio_de_aluno_id,
           (g.id is not null)                                                          as no_gps,
           coalesce(p.pg_hm, false)                                                    as pg_hm,
           coalesce(p.pg_impl, false)                                                  as pg_impl,
           coalesce(p.pg_sinal, false)                                                 as pg_sinal,
           coalesce(p.pg_hm or p.pg_catalogo, false)                                   as pg_hm_algum,
           coalesce(p.pg_aurum, false)                                                 as pg_aurum,
           coalesce(p.pg_mmd, false)                                                   as pg_mmd,
           coalesce(al.espaco_instrucao = 'holding_masters_implementacao', false)      as cad_impl,
           coalesce(al.espaco_instrucao = 'aurum' or al.turma_aurum_id is not null
                    or al.plano = 'aurum', false)                                      as cad_aurum,
           coalesce(al.espaco_instrucao = 'mastermind_diamante' or al.plano = 'diamante', false) as cad_mmd,
           coalesce(al.espaco_instrucao = 'platina' or al.plano = 'platina', false)    as cad_platina,
           coalesce(al.espaco_instrucao = 'diamante_vermelho', false)                  as cad_dv
      from al
      left join ep on ep.email = al.email_n
      left join pag p on p.chave = coalesce(ep.pessoa_chave, '#email:' || al.email_n)
      left join gps_ids g on g.id = al.id
  ),
  prog as (
    select o.id, v.programa, v.status, v.motivos
      from own o
      left join own tt on tt.id = o.socio_de_aluno_id   -- pagamento do titular cobre o sócio no GPS
      cross join lateral (values
        ('implementacao',
         case when o.no_gps                 then 'confirmado'
              when o.pg_impl or o.cad_impl  then 'a_revisar'
              when o.pg_sinal               then 'reservou' end,
         array_remove(array[
           case when o.no_gps and not (o.pg_hm_algum or coalesce(tt.pg_hm_algum, false))
                then 'impl_gps_sem_pagamento' end,
           case when not o.no_gps and o.pg_impl  then 'impl_pago_fora_gps' end,
           case when not o.no_gps and o.cad_impl then 'impl_espaco_fora_gps' end], null)),
        ('hm',
         case when o.pg_hm then 'confirmado' end,
         '{}'::text[]),
        ('aurum',
         case when o.pg_aurum and o.cad_aurum then 'confirmado'
              when o.pg_aurum or o.cad_aurum  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_aurum and not o.cad_aurum then 'aurum_so_pagamento' end,
           case when o.cad_aurum and not o.pg_aurum then 'aurum_so_cadastro' end], null)),
        ('mastermind_diamante',
         case when o.pg_mmd and o.cad_mmd then 'confirmado'
              when o.pg_mmd or o.cad_mmd  then 'a_revisar' end,
         array_remove(array[
           case when o.pg_mmd and not o.cad_mmd then 'mastermind_diamante_so_pagamento' end,
           case when o.cad_mmd and not o.pg_mmd then 'mastermind_diamante_so_cadastro' end], null)),
        ('diamante_vermelho',
         case when o.cad_dv then 'confirmado_cadastro' end,
         '{}'::text[]),
        ('platina',
         case when o.cad_platina then 'confirmado_cadastro' end,
         '{}'::text[])
      ) v(programa, status, motivos)
     where v.status is not null
  ),
  -- sócio herda do titular ativo (o titular também está em own/prog); compra própria soma
  herd as (
    select p.id, p.programa, p.status, p.motivos from prog p
    union all
    select s.id, p.programa, p.status, p.motivos
      from own s
      join prog p on p.id = s.socio_de_aluno_id
  ),
  por_status as (
    select h.id, h.programa, h.status,
           case h.status when 'confirmado' then 1 when 'confirmado_cadastro' then 2
                         when 'a_revisar' then 3 else 4 end                             as r,
           array_agg(distinct m.x) filter (where m.x is not null)                        as motivos
      from herd h
      left join lateral unnest(h.motivos) m(x) on true
     group by h.id, h.programa, h.status
  ),
  melhor as (
    select distinct on (ps.id, ps.programa) ps.id, ps.programa, ps.status, coalesce(ps.motivos, '{}'::text[]) as motivos
      from por_status ps
     order by ps.id, ps.programa, ps.r
  ),
  efetivo as (
    select w.id, w.programa, w.status, w.motivos
      from (select mm.id, mm.programa, mm.status, mm.motivos,
                   bool_or(mm.programa = 'implementacao' and mm.status <> 'reservou')
                     over (partition by mm.id) as tem_impl
              from melhor mm) w
     where not (w.programa = 'hm' and w.tem_impl)
  ),
  mot as (
    select e.id, array_agg(distinct x.m order by x.m) as motivos
      from efetivo e
     cross join lateral unnest(e.motivos) x(m)
     group by e.id
  )
  select al.id,
         coalesce(array_agg(e.programa
                            order by array_position(array['implementacao','hm','aurum','mastermind_diamante',
                                                          'diamante_vermelho','platina']::text[], e.programa))
                  filter (where e.programa is not null), '{}'::text[]),
         coalesce(jsonb_object_agg(e.programa, e.status) filter (where e.programa is not null), '{}'::jsonb),
         coalesce(mo.motivos, '{}'::text[])
    from al
    left join efetivo e on e.id = al.id
    left join mot mo on mo.id = al.id
   group by al.id, mo.motivos
  -- CENTRAL:FIM
  ;
end;
$fn$;

comment on function public.fn_aluno_programas_safe() is
  '20261002e: 1 linha por aluno ativo com programas, status por programa e motivos de revisão. Só equipe (42501). '
  'Pagamentos só da conta Hotmart academy (fin.vw_transacoes), ligados por e-mail → fin.vw_email_pessoa.pessoa_chave.';

revoke all on function public.fn_aluno_programas_safe() from public, anon;
grant execute on function public.fn_aluno_programas_safe() to authenticated;

-- ─── 2. Evidências de um aluno ──────────────────────────────────────────────────────────────────────────────────────
create function public.fn_aluno_programa_evidencias(p_aluno uuid)
returns table (programa text, fonte text, descricao text, data timestamptz, valor numeric)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $fn$
#variable_conflict use_column
declare
  v_fin          boolean;
  v_email        text;
  v_espaco       text;
  v_plano        text;
  v_turma_aurum  smallint;
  v_socio_de     uuid;
  v_chave        text;
  v_emails       text[];
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'fn_aluno_programa_evidencias: acesso restrito à equipe' using errcode = '42501';
  end if;
  v_fin := coalesce(public.gp_pode_ver_financeiro(), false);

  select nullif(lower(trim(both from a.email)), ''), a.espaco_instrucao, a.plano, a.turma_aurum_id, a.socio_de_aluno_id
    into v_email, v_espaco, v_plano, v_turma_aurum, v_socio_de
    from public.thb_alunos a
   where a.id = p_aluno;
  if not found then
    return;
  end if;

  if v_email is not null then
    -- = fin.vw_email_pessoa where email = v_email (a view é substr(no, 3) de no like 'e:%'), pela PK de fin.identidade
    select i.pessoa_chave into v_chave from fin.identidade i where i.no = 'e:' || v_email;
    if v_chave is not null then
      select array_agg(ep.email) into v_emails from fin.vw_email_pessoa ep where ep.pessoa_chave = v_chave;
    end if;
    v_emails := coalesce(v_emails, array[v_email]);
  end if;

  return query
  with tx as (
    -- só conta academy (a view filtra conta = 'academy'; a conta escritório fica fora)
    select t.produto_id, t.produto_nome, t.familia, t.grupo, t.valor_cobrado,
           coalesce(t.aprovado_em, t.pedido_em) as quando,
           c.categoria, ev.nome as evento_nome
      from fin.vw_transacoes t
      left join public.hm_product_catalog c on c.offer_code = t.oferta_codigo
      left join fin.evento_ofertas eo on eo.oferta_codigo = t.oferta_codigo
      left join fin.eventos ev on ev.id = eo.evento_id
     where t.email = any(coalesce(v_emails, '{}'::text[]))
  ),
  tx_cls as (
    select tx.*,
           case when tx.categoria in ('compra_cheia', 'diferenca', 'sinal', 'reserva') then 'implementacao'
                when tx.familia = 'HM' and tx.produto_id <> '446345'
                     and coalesce(tx.produto_nome, '') not ilike '%curso pr_tico%'       then 'hm'
                when tx.familia = 'AURUM'                                                then 'aurum'
                when tx.familia = 'PROGRAMA_DIAMANTE'                                    then 'mastermind_diamante'
           end as prog,
           case when tx.evento_nome is not null or tx.familia = 'EVENTOS' then 'evento'
                when tx.familia = 'ACELERA'                                then 'acelera'
                else 'hotmart' end as fnt
      from tx
  )
  select z.programa, z.fonte, z.descricao, z.data, z.valor
    from (
      -- GPS (mesmo critério da F1: aluno_id ∪ pessoa_aluno_id)
      select 'implementacao'::text as programa, 'gps'::text as fonte, 'Está no GPS'::text as descricao,
             min(m.criado_em) as data, null::numeric as valor
        from gps.membros m
       where m.aluno_id = p_aluno or m.pessoa_aluno_id = p_aluno
      having count(*) > 0
      union all
      -- cadastro
      select v.prog, 'cadastro', v.descr, null::timestamptz, null::numeric
        from (values
          (case v_espaco when 'holding_masters_implementacao' then 'implementacao'
                         when 'holding_masters'               then 'hm'
                         when 'aurum'                         then 'aurum'
                         when 'mastermind_diamante'           then 'mastermind_diamante'
                         when 'platina'                       then 'platina'
                         when 'diamante_vermelho'             then 'diamante_vermelho' end,
           'Espaço de instrução: ' || v_espaco),
          (case v_plano when 'aurum' then 'aurum' when 'diamante' then 'mastermind_diamante'
                        when 'platina' then 'platina' end,
           case when v_plano <> 'aluno' then 'Plano: ' || v_plano end),
          ('aurum',
           case when v_turma_aurum is not null then 'Turma Aurum: ' || coalesce(
             (select tu.codigo::text from public.thb_turmas tu where tu.id = v_turma_aurum), v_turma_aurum::text) end)
        ) v(prog, descr)
       where v.descr is not null
      union all
      -- Hotmart / evento / Acelera (valor só para o financeiro)
      select x.prog, x.fnt,
             coalesce(x.evento_nome, x.produto_nome, 'Produto ' || x.produto_id) || ' — ' ||
             case when x.grupo = 'pago' and x.categoria in ('sinal', 'reserva') then 'sinal'
                  when x.grupo = 'pago'                                         then 'pagou'
                  else 'não pagou (' || x.grupo || ')' end,
             x.quando,
             case when v_fin then x.valor_cobrado end
        from tx_cls x
       where x.prog is not null or x.fnt in ('evento', 'acelera')
      union all
      -- sócio: sem nome do titular
      select null::text, 'socio_de', 'Sócio de outro aluno: herda os programas do titular', null::timestamptz, null::numeric
       where v_socio_de is not null
    ) z
   order by z.data desc nulls last, z.programa, z.fonte;
end;
$fn$;

comment on function public.fn_aluno_programa_evidencias(uuid) is
  '20261002e: evidências dos programas de um aluno (GPS, cadastro, Hotmart academy, evento, Acelera, sócio). '
  'Só equipe (42501); valor só com gp_pode_ver_financeiro(); sem e-mail/documento.';

revoke all on function public.fn_aluno_programa_evidencias(uuid) from public, anon;
grant execute on function public.fn_aluno_programa_evidencias(uuid) to authenticated;

-- ─── 3. Conferência pós-aplicação (kirad 30/09: mesma trava da 20261002d) ───────────────────────────────────────────
do $confere$
declare f regprocedure;
begin
  foreach f in array array['public.fn_aluno_programas_safe()'::regprocedure,
                           'public.fn_aluno_programa_evidencias(uuid)'::regprocedure] loop
    if not exists (select 1 from pg_proc p where p.oid = f and p.prosecdef
                      and p.proconfig @> array['search_path=public, pg_temp']) then
      raise exception '20261002e: % sem SECURITY DEFINER ou search_path', f;
    end if;
    if exists (select 1 from pg_proc p where p.oid = f
                  and (p.proacl is null
                       or exists (select 1 from aclexplode(p.proacl) g where g.grantee = 0 and g.privilege_type = 'EXECUTE'))) then
      raise exception '20261002e: PUBLIC executa %', f;
    end if;
    if has_function_privilege('anon', f, 'execute') then
      raise exception '20261002e: anon executa %', f;
    end if;
    if not has_function_privilege('authenticated', f, 'execute') then
      raise exception '20261002e: authenticated sem EXECUTE em %', f;
    end if;
  end loop;
end $confere$;
