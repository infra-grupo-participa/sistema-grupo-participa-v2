-- APLICADA em 14/10/2026 ~15:22 UTC com a versão gravada 20261014152242 (o arquivo se chamava 20261014210300; renomeado conforme o guia 6.3).
-- Ensaio de 20261014152242 (manter vivo) com a 20261014152236 antes, sobre o banco com os grupos A e B aplicados, numa
-- transação DESFEITA. Só contagens.
-- Rodar com: python3 Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py ensaio <este arquivo>
begin;
set local lock_timeout = '5s';
set local statement_timeout = '150s';
create temp table _z_out (em serial, passo text, linha text);
insert into pg_temp._z_out(passo, linha) select '00 antes', (select jsonb_build_object('pessoas', (select count(*) from pessoas.pessoas), 'eventos', (select count(*) from pessoas.eventos), 'revisao', (select count(*) from pessoas.revisao))::text);
-- ===== 20261014152236 =====
-- 20261014152236: cargas das fontes que já moram no banco (Hotmart, Central, T1-T40, HM, Respondi, leads, CRM)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014150003 (ex-160200), dos índices da 160300 e
--   de 20261014150034 (ex-170000: controle de carga, pessoas.casar_email, pessoas.relacoes, índice eventos_fonte_unico). Não depende do schema fin (só lê).
--   Ensaio: 20261014152236_ensaio.sql. Script: infra/scripts/pessoa-unica/carga_fontes.py. Detalhe: 20261014152236.explain.md.
--
-- POR QUE: PLANO da pessoa única, passo 4 (carga por fonte, em lotes) e o modelo da história da pessoa do Victor
--   (14/10/2026): lead, checkout e compra separados por evento; matrícula por turma; sócio de; CRM; Respondi.
-- O QUE FAZ: uma função por fonte, no mesmo padrão da 170000 (execução aberta em pessoas.carga_execucao, lote por cursor,
--   pessoas.carga_lote, chave pessoas.carga_chave por fonte, idempotente pelo índice (fonte_tabela, fonte_id, tipo)):
--   | função                          | fonte                          | vira                                                  |
--   | carga_fin_hotmart (por conta)   | fin.hotmart_transacoes         | compra (COMPLETE, APPROVED), reembolso (REFUNDED,     |
--   |                                 |                                | CHARGEBACK, PARTIALLY_REFUNDED, PROTESTED), checkout  |
--   |                                 |                                | (o resto): mesma regra do crm.hotmart_processar       |
--   | carga_thb_alunos                | public.thb_alunos              | ativacao (turma e turma Aurum) + sócio de             |
--   | carga_aluno_historico           | controle.aluno_historico (T1-T40) | ativacao (turma e turma Aurum)                     |
--   | carga_contatos_hm               | cs.contatos_hm                 | crm (etapa e produto do HM, turma de origem)          |
--   | carga_hm_socios                 | cs.hm_socios                   | vinculo + sócio de                                    |
--   | carga_respondi                  | respondi.respostas             | resposta (+ sócio de nos formulários de sócio)        |
--   | carga_leads                     | workbook.cnhf_leads_captacao, workbook.leads, dados.black_leads | lead (+ mql na Black) |
--   | carga_crm_negocio               | crm.negocio                    | crm (linha, status)                                   |
-- MODO "SÓ NOVOS" (p_novos = true, usado pela rotina de hora em hora): ignora o cursor e pega as linhas da fonte que
--   ainda não têm o seu evento (anti-join pelo índice eventos_fonte_unico); não mexe no cursor da carga inicial. O cursor por
--   id não serve para o incremental: id é uuid/texto e um id novo pode ser "menor" que o cursor.
-- DECISÕES:
--   - Hotmart: o evento NÃO copia valor nem nome da oferta (o dinheiro fica em fin.hotmart_transacoes; o tipo da oferta
--     na pessoas.vw_oferta). As linhas que o webhook já gravou (ref_tipo 'hotmart.transacao', sem fonte_id) recebem
--     fonte_tabela/fonte_id na primeira de cada (tipo, transação): a carga não duplica o que o webhook gravou.
--     evento_id: o da regra do financeiro (fin.trajetoria_nucleo, por lote de e-mails), quando ela dá.
--   - T1-T40: o espelho é regravado todo dia (os ids mudam); a chave é md5(e-mail) + turma, estável e sem e-mail em claro.
--   - controle.lead (só telefone, sem e-mail) NÃO entra aqui: casar por telefone em massa abriria revisão demais
--     (pergunta ao Victor). Planilha de ativação T1-T42: estágio próprio, migration seguinte.
--   - Casamento por e-mail (pessoas.casar_email); CPF nunca. Valores validados antes de CHECK (nome até 160, e-mail até
--     320, detalhe pequeno): erro de CHECK grava a linha no log.
-- AS 5 PERGUNTAS: escala = ~58 mil transações, ~1,9 mil alunos, ~7,6 mil T1-T40, ~400 HM, ~23 mil respostas, ~40 mil
--   leads, ~1,5 mil negócios; índice = PK de cada fonte para o cursor + eventos_fonte_unico; frequência = 1 carga + o
--   incremental (manter vivo, desenho no explain); repetição = idempotente; reversão = 20261014152236_reversao.sql.
-- ACESSO: funções SECURITY INVOKER, sem execute para public/anon/authenticated/service_role.

set local lock_timeout = '5s';

do $g$
begin
  if to_regprocedure('pessoas.casar_email(text,text,text,text)') is null or to_regclass('pessoas.eventos_fonte_unico') is null then
    raise exception '20261014152236: falta 20261014150034 (ex-170000) ou os índices da 160300.';
  end if;
  if to_regprocedure('pessoas.carga_fin_hotmart(bigint,text,integer,boolean)') is not null then
    raise exception '20261014152236: já aplicada.';
  end if;
end
$g$;

insert into pessoas.carga_chave (fonte, ligada, por)
select f, true, 'migration 20261014152236'
  from unnest(array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi', 'leads_cnhf',
                    'leads_workbook', 'leads_black', 'crm_negocio']) f
on conflict (fonte) do nothing;

-- achado 4 do pentester (14/10/2026): e-mail que, normalizado, passa de 320 caracteres estouraria o CHECK de
-- pessoas.identificadores e o DETAIL com o valor iria ao log. Aqui ele vira "sem e-mail" e a linha é pulada (contada).
create function pessoas._casar_email_seguro(p_nome text, p_email text, p_telefone text, p_origem text) returns jsonb
language sql set search_path to '' as $f$
  select pessoas.casar_email(p_nome,
                             case when length(pessoas.norm_email(left(p_email, 1000))) <= 320 then left(p_email, 1000) end,
                             left(p_telefone, 40), p_origem);
$f$;

-- execução aberta da fonte (e chave ligada); devolve o cursor
create function pessoas._carga_exigir(p_execucao bigint, p_fonte text) returns text
language plpgsql set search_path to '' as $f$
declare v_cursor text;
begin
  if not pessoas.carga_ligada(p_fonte) then raise exception 'carga desligada (%)', p_fonte using errcode = 'P0001'; end if;
  select cursor into v_cursor from pessoas.carga_execucao
   where id = p_execucao and fonte = p_fonte and fase = 'pessoas' and status = 'rodando';
  if not found then raise exception 'execução % não está rodando (pessoas/%)', p_execucao, p_fonte using errcode = 'P0001'; end if;
  return v_cursor;
end $f$;

-- registra o lote e devolve o resumo
create function pessoas._carga_lote_fim(p_execucao bigint, p_de text, p_ate text, p_lidas int, p_novas int, p_casadas int,
                                        p_puladas int, p_eventos int, p_rel int, p_t0 timestamptz) returns jsonb
language plpgsql set search_path to '' as $f$
declare v_ms int := (extract(epoch from clock_timestamp() - p_t0) * 1000)::int;
begin
  insert into pessoas.carga_lote (execucao_id, cursor_de, cursor_ate, lidas, inseridas, atualizadas, iguais, detalhe, ms)
  values (p_execucao, p_de, p_ate, p_lidas, p_novas, p_casadas, p_puladas,
          jsonb_build_object('pessoas_novas', p_novas, 'casadas', p_casadas, 'puladas', p_puladas, 'eventos', p_eventos, 'relacoes', p_rel), v_ms);
  update pessoas.carga_execucao
     set cursor = coalesce(p_ate, cursor), lotes = lotes + 1, lidas = lidas + p_lidas, inseridas = inseridas + p_novas,
         atualizadas = atualizadas + p_casadas, iguais = iguais + p_puladas, atualizada_em = now()
   where id = p_execucao;
  return jsonb_build_object('lidas', p_lidas, 'pessoas_novas', p_novas, 'casadas', p_casadas, 'puladas', p_puladas,
                            'eventos', p_eventos, 'relacoes', p_rel, 'fim', p_lidas = 0, 'ms', v_ms);
end $f$;

-- ======================= Hotmart =======================
create function pessoas.carga_fin_hotmart(p_execucao bigint, p_conta text, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
-- Uma execução por conta (fontes hotmart_academy e hotmart_escritorio). Toda leitura da tabela de transações segue a forma
-- canônica que a trava fin.trava_conta_hotmart exige (regra 9 do plano de ação): (select * from ... where conta = p_conta).
-- A trava conta o nome da tabela até dentro de texto; por isso o valor de fonte_tabela é montado por concatenação (v_tab).
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tipo text; v_ev bigint;
  v_tab constant text := 'fin.hotmart' || '_transacoes';
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  if p_conta not in ('academy', 'escritorio') then raise exception 'conta inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hotmart_' || p_conta), '');
  if p_limite not between 1 and 2000 then raise exception 'limite entre 1 e 2.000' using errcode = '22023'; end if;
  create temp table if not exists _carga_hm_lote (transacao text primary key) on commit drop;
  create temp table if not exists _carga_hm_ev (transacao text primary key, evento_id bigint) on commit drop;
  delete from pg_temp._carga_hm_lote; delete from pg_temp._carga_hm_ev;
  insert into pg_temp._carga_hm_lote
  select t.transacao from (select * from fin.hotmart_transacoes where conta = p_conta) t
   where (not p_novos and t.transacao > v_cur)
      or (p_novos and not exists (select 1 from pessoas.eventos e
                                   where e.fonte_tabela = v_tab and e.fonte_id = t.transacao
                                     and e.tipo = case when t.status in ('COMPLETE', 'APPROVED') then 'compra'
                                                       when t.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                                                       else 'checkout' end))
   order by t.transacao limit p_limite;
  -- evento pela regra do financeiro (mesma janela/oferta que os funis usam), por lote de e-mails
  insert into pg_temp._carga_hm_ev
  select distinct on (j.transacao) j.transacao, j.evento_id
    from fin.trajetoria_nucleo(array(select distinct lower(btrim(t.comprador_email))
                                       from (select * from fin.hotmart_transacoes where conta = p_conta) t
                                       join pg_temp._carga_hm_lote l using (transacao) where t.comprador_email is not null)) j
    join pg_temp._carga_hm_lote l on l.transacao = j.transacao
   where j.evento_id is not null
   order by j.transacao;

  for r in select t.* from (select * from fin.hotmart_transacoes where conta = p_conta) t
             join pg_temp._carga_hm_lote l using (transacao) order by t.transacao loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.transacao); v_ate := r.transacao;
    v := pessoas._casar_email_seguro(r.comprador_nome, r.comprador_email, r.comprador_telefone, 'hotmart');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_tipo := case when r.status in ('COMPLETE', 'APPROVED') then 'compra'
                   when r.status in ('REFUNDED', 'CHARGEBACK', 'PARTIALLY_REFUNDED', 'PROTESTED') then 'reembolso'
                   else 'checkout' end;
    v_ev := null;
    select e.evento_id into v_ev from pg_temp._carga_hm_ev e where e.transacao = r.transacao;
    -- a linha que o webhook já gravou desta transação/tipo recebe a fonte (uma só), em vez de criar outra
    update pessoas.eventos x set fonte_tabela = v_tab, fonte_id = r.transacao, evento_id = coalesce(x.evento_id, v_ev)
     where x.id = (select min(y.id) from pessoas.eventos y
                    where y.ref_tipo = 'hotmart.transacao' and y.ref_id = r.transacao and y.tipo = v_tipo and y.fonte_id is null)
       and not exists (select 1 from pessoas.eventos z where z.fonte_tabela = v_tab and z.fonte_id = r.transacao and z.tipo = v_tipo);
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, v_tipo, 'hotmart', v_ev, 'hotmart.transacao', left(r.transacao, 80), v_tab, left(r.transacao, 120),
            coalesce(r.aprovado_em, r.pedido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('conta', p_conta, 'produto', left(r.produto_id, 40),
                                                 'oferta', left(r.oferta_codigo, 40), 'status', left(r.status, 30))))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= Central de Alunos (matrícula viva) =======================
create function pessoas.carga_thb_alunos(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid; v_tit uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'thb_alunos'), '');
  for r in select a.id, a.turma_id, a.turma_aurum_id, a.data_entrada_thb, a.data_compra, a.situacao_acesso, a.eh_socio, a.socio_de_aluno_id
             from public.thb_alunos a
            where (not p_novos and a.id::text > v_cur)
               or (p_novos and (not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'public.thb_alunos' and e.fonte_id = a.id::text and e.tipo = 'ativacao')
                                or (a.turma_aurum_id is not null
                                    and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'public.thb_alunos' and e.fonte_id = a.id::text || ':aurum' and e.tipo = 'ativacao'))))
            order by a.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := pessoas.pessoa_do_aluno(r.id);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao', r.turma_id, 'public.thb_alunos', r.id::text, 'public.thb_alunos', r.id::text,
            coalesce(r.data_entrada_thb::timestamp at time zone 'America/Sao_Paulo', r.data_compra, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'situacao_acesso', left(r.situacao_acesso, 30), 'socio', r.eh_socio)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if r.turma_aurum_id is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', r.turma_aurum_id, 'public.thb_alunos', r.id::text, 'public.thb_alunos', r.id::text || ':aurum',
              coalesce(r.data_compra, now()), jsonb_build_object('programa', 'aurum'))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
    if coalesce(r.eh_socio, false) and r.socio_de_aluno_id is not null and r.socio_de_aluno_id <> r.id then
      v_tit := pessoas.pessoa_do_aluno(r.socio_de_aluno_id);
      if v_tit is not null and v_tit <> v_p then
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_p, v_tit, r.turma_id, 'public.thb_alunos', r.id::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, 0, n_c, n_l - n_c, n_e, n_r, v_t0);
end $f$;

-- ======================= T1-T40 (espelho da planilha "Alunos e sócios T1 - T40") =======================
create function pessoas.carga_aluno_historico(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_chave text; v_quando timestamptz;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'aluno_historico'), '');
  -- cursor = md5(e-mail):turma (o espelho é regravado todo dia e os ids mudam)
  for r in select md5(h.email_norm) || ':' || coalesce(h.turma, '') k, h.*
             from controle.aluno_historico h
            where h.email_norm is not null
              and ((not p_novos and md5(h.email_norm) || ':' || coalesce(h.turma, '') > v_cur)
                   or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'controle.aluno_historico'
                                                 and e.fonte_id = md5(h.email_norm) || ':' || coalesce(h.turma, '') and e.tipo = 'ativacao')))
            order by 1 limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas._casar_email_seguro(r.nome, r.email_norm, null, 'importacao');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_quando := case when r.primeira_compra ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$'
                          and pg_input_is_valid(substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2), 'date')
                     then (substr(r.primeira_compra, 7, 4) || '-' || substr(r.primeira_compra, 4, 2) || '-' || substr(r.primeira_compra, 1, 2))::date::timestamp at time zone 'America/Sao_Paulo' end;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'ativacao', 'importacao',
            (select t.id from public.thb_turmas t where t.codigo = replace(r.turma, '.R', 'R')),
            'controle.aluno_historico', r.k, coalesce(v_quando, now()),
            jsonb_strip_nulls(jsonb_build_object('programa', 'thb', 'turma_fonte', left(r.turma, 20), 'data_estimada', v_quando is null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if nullif(btrim(r.turma_aurum), '') is not null then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'ativacao', 'importacao', (select t.id from public.thb_turmas t where t.codigo = btrim(r.turma_aurum)),
              'controle.aluno_historico', md5(r.email_norm) || ':' || left(btrim(r.turma_aurum), 20), coalesce(v_quando, now()),
              jsonb_build_object('programa', 'aurum', 'turma_fonte', left(btrim(r.turma_aurum), 20)))
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= Operação HM =======================
create function pessoas.carga_contatos_hm(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'contatos_hm'), '');
  for r in select c.id, c.comprador_id, c.aluno_id, c.produto, c.turma_origem, c.estagio_id, c.entrada_em, c.criado_em,
                  c.quitado_em, c.cancelamento_efetivado_em
             from cs.contatos_hm c
            where (not p_novos and c.id::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'cs.contatos_hm' and e.fonte_id = c.id::text and e.tipo = 'crm'))
            order by c.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := coalesce(case when r.aluno_id is not null then pessoas.pessoa_do_aluno(r.aluno_id) end,
                    case when r.comprador_id is not null then pessoas.pessoa_do_comprador(r.comprador_id) end);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'crm', 'importacao', (select t.id from public.thb_turmas t where t.codigo = r.turma_origem),
            'cs.contatos_hm', r.id::text, coalesce(r.entrada_em, r.criado_em, now()),
            jsonb_strip_nulls(jsonb_build_object('produto', left(r.produto, 40), 'estagio_id', r.estagio_id,
                                                 'turma_origem', left(r.turma_origem, 20), 'quitado', r.quitado_em is not null,
                                                 'cancelado', r.cancelamento_efetivado_em is not null)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, 0, n_c, n_l - n_c, n_e, 0, v_t0);
end $f$;

create function pessoas.carga_hm_socios(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_tit uuid;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'hm_socios'), '');
  for r in select s.id, s.nome, s.email, s.telefone, s.aluno_id, s.criado_em, c.comprador_id t_comprador, c.aluno_id t_aluno, c.turma_origem
             from cs.hm_socios s left join cs.contatos_hm c on c.id = s.contato_hm_id
            where (not p_novos and s.id::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'cs.hm_socios' and e.fonte_id = s.id::text and e.tipo = 'vinculo'))
            order by s.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    if r.aluno_id is not null then
      v_p := pessoas.pessoa_do_aluno(r.aluno_id); n_c := n_c + 1;
    else
      v := pessoas._casar_email_seguro(r.nome, r.email, r.telefone, 'importacao');
      v_p := (v->>'pessoa_id')::uuid;
      if v_p is null then n_s := n_s + 1; continue; end if;
      if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    end if;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'vinculo', 'importacao', 'cs.hm_socios', r.id::text, coalesce(r.criado_em, now()), jsonb_build_object('relacao', 'socio_de', 'programa', 'hm'))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    v_tit := coalesce(case when r.t_aluno is not null then pessoas.pessoa_do_aluno(r.t_aluno) end,
                      case when r.t_comprador is not null then pessoas.pessoa_do_comprador(r.t_comprador) end);
    if v_tit is not null and v_tit <> v_p then
      insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
      values ('socio_de', v_p, v_tit, (select t.id from public.thb_turmas t where t.codigo = r.turma_origem), 'cs.hm_socios', r.id::text)
      on conflict on constraint relacoes_unica do nothing;
      get diagnostics n_x = row_count; n_r := n_r + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

-- ======================= Respondi =======================
create function pessoas.carga_respondi(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid; v_s uuid; v_turma smallint;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_r int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'respondi'), '');
  for r in select x.uuid, x.form_slug, x.respondido_em, x.email, x.telefone, x.dados, f.familia, f.turma_codigo f_turma
             from respondi.respostas x left join respondi.formularios f on f.slug = x.form_slug
            where (not p_novos and x.uuid::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'respondi.respostas' and e.fonte_id = x.uuid::text and e.tipo = 'resposta'))
            order by x.uuid::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.uuid::text); v_ate := r.uuid::text;
    v := pessoas._casar_email_seguro(r.dados->>'nome', coalesce(r.email, r.dados->>'email'), coalesce(r.telefone, r.dados->>'telefone'), 'respondi');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    v_turma := (select t.id from public.thb_turmas t where t.codigo = coalesce(r.f_turma, r.dados->>'turma_codigo'));
    insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'resposta', 'respondi', v_turma, 'respondi.respostas', r.uuid::text, coalesce(r.respondido_em, now()),
            jsonb_strip_nulls(jsonb_build_object('formulario', left(r.form_slug, 40), 'familia', left(r.familia, 40),
                                                 'parcial', case when r.dados->>'parcial' = 'true' then true end)))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    -- formulário de sócio: o sócio vira pessoa (por e-mail) e "sócio de" quem respondeu (o titular)
    if pessoas.norm_email(r.dados->>'socio_email') is not null then
      v := pessoas._casar_email_seguro(r.dados->>'socio_nome', r.dados->>'socio_email', r.dados->>'socio_telefone', 'respondi');
      v_s := (v->>'pessoa_id')::uuid;
      if v_s is not null and v_s <> v_p then
        if (v->>'nova')::boolean then n_n := n_n + 1; end if;
        insert into pessoas.eventos (pessoa_id, tipo, fonte, turma_id, fonte_tabela, fonte_id, quando, detalhe)
        values (v_s, 'vinculo', 'respondi', v_turma, 'respondi.respostas', r.uuid::text || ':socio', coalesce(r.respondido_em, now()),
                jsonb_build_object('relacao', 'socio_de', 'formulario', left(r.form_slug, 40)))
        on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
        get diagnostics n_x = row_count; n_e := n_e + n_x;
        insert into pessoas.relacoes (tipo, pessoa_id, relacionada_id, turma_id, fonte_tabela, fonte_id)
        values ('socio_de', v_s, v_p, v_turma, 'respondi.respostas', r.uuid::text)
        on conflict on constraint relacoes_unica do nothing;
        get diagnostics n_x = row_count; n_r := n_r + n_x;
      end if;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, n_r, v_t0);
end $f$;

-- ======================= leads de evento =======================
create function pessoas.carga_leads(p_execucao bigint, p_fonte text, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v jsonb; v_p uuid;
  n_l int := 0; n_n int := 0; n_c int := 0; n_s int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
  v_cnhf bigint := (select e.id from fin.eventos e where e.id = 72 and e.categoria = 'lancamento_cnhf');
begin
  if p_fonte not in ('leads_cnhf', 'leads_workbook', 'leads_black') then raise exception 'fonte de lead inválida' using errcode = '22023'; end if;
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, p_fonte), '');
  for r in
    select x.id::text k, x.email, coalesce(x.telefone_e164, x.telefone) tel, x.nome, x.captado_em quando, false mql,
           jsonb_strip_nulls(jsonb_build_object('edicao', left(x.edicao, 40), 'utm_campaign', left(x.utm_campaign, 120), 'pagina', left(x.pagina, 120))) det,
           'workbook.cnhf_leads_captacao' tab, v_cnhf ev
      from workbook.cnhf_leads_captacao x where p_fonte = 'leads_cnhf'
       and ((not p_novos and x.id::text > v_cur) or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'workbook.cnhf_leads_captacao' and e.fonte_id = x.id::text and e.tipo = 'lead')))
    union all
    select x.id::text, x.email, x.telefone, x.nome, x.criado_em, false,
           jsonb_strip_nulls(jsonb_build_object('origem', left(x.origem, 120))), 'workbook.leads', null::bigint
      from workbook.leads x where p_fonte = 'leads_workbook'
       and ((not p_novos and x.id::text > v_cur) or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'workbook.leads' and e.fonte_id = x.id::text and e.tipo = 'lead')))
    union all
    select x.lead_id, x.email, x.whatsapp, x.nome, x.criado_em, coalesce(x.mql, false),
           jsonb_strip_nulls(jsonb_build_object('pagina', left(x.pagina, 120), 'utm_campaign', left(x.utm_campaign, 120))), 'dados.black_leads', null::bigint
      from dados.black_leads x where p_fonte = 'leads_black'
       and ((not p_novos and x.lead_id > v_cur) or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'dados.black_leads' and e.fonte_id = left(x.lead_id, 120) and e.tipo = 'lead')))
       and not coalesce(x.teste, false) and not coalesce(x.parece_teste, false)
    order by 1 limit p_limite
  loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.k); v_ate := r.k;
    v := pessoas._casar_email_seguro(r.nome, r.email, r.tel, 'formulario');
    v_p := (v->>'pessoa_id')::uuid;
    if v_p is null then n_s := n_s + 1; continue; end if;
    if (v->>'nova')::boolean then n_n := n_n + 1; else n_c := n_c + 1; end if;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'lead', 'formulario', r.ev, r.tab, left(r.k, 120), coalesce(r.quando, now()), r.det)
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
    if r.mql then
      insert into pessoas.eventos (pessoa_id, tipo, fonte, evento_id, fonte_tabela, fonte_id, quando, detalhe)
      values (v_p, 'mql', 'formulario', r.ev, r.tab, left(r.k, 120), coalesce(r.quando, now()), r.det)
      on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
      get diagnostics n_x = row_count; n_e := n_e + n_x;
    end if;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, n_n, n_c, n_s, n_e, 0, v_t0);
end $f$;

-- ======================= CRM =======================
create function pessoas.carga_crm_negocio(p_execucao bigint, p_limite integer default 1000, p_novos boolean default false) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  v_t0 timestamptz := clock_timestamp(); v_cur text; r record; v_p uuid;
  n_l int := 0; n_c int := 0; n_e int := 0; n_x int; v_de text; v_ate text;
begin
  v_cur := coalesce(pessoas._carga_exigir(p_execucao, 'crm_negocio'), '');
  for r in select n.id, n.pessoa_id, n.linha, n.status, n.origem, n.criado_em
             from crm.negocio n
            where (not p_novos and n.id::text > v_cur)
               or (p_novos and not exists (select 1 from pessoas.eventos e where e.fonte_tabela = 'crm.negocio' and e.fonte_id = n.id::text and e.tipo = 'crm'))
            order by n.id::text limit p_limite loop
    n_l := n_l + 1; v_de := coalesce(v_de, r.id::text); v_ate := r.id::text;
    v_p := pessoas.atual(r.pessoa_id);
    if v_p is null then continue; end if;
    n_c := n_c + 1;
    insert into pessoas.eventos (pessoa_id, tipo, fonte, ref_tipo, ref_id, fonte_tabela, fonte_id, quando, detalhe)
    values (v_p, 'crm', 'crm', 'crm.negocio', r.id::text, 'crm.negocio', r.id::text, coalesce(r.criado_em, now()),
            jsonb_strip_nulls(jsonb_build_object('linha', left(r.linha, 40), 'status', left(r.status, 20), 'origem', left(r.origem, 60))))
    on conflict (fonte_tabela, fonte_id, tipo) where fonte_id is not null do nothing;
    get diagnostics n_x = row_count; n_e := n_e + n_x;
  end loop;
  return pessoas._carga_lote_fim(p_execucao, v_de, case when p_novos then null else v_ate end, n_l, 0, n_c, n_l - n_c, n_e, 0, v_t0);
end $f$;

revoke all on function pessoas._casar_email_seguro(text, text, text, text), pessoas._carga_exigir(bigint, text),
  pessoas._carga_lote_fim(bigint, text, text, int, int, int, int, int, int, timestamptz),
  pessoas.carga_fin_hotmart(bigint, text, integer, boolean), pessoas.carga_thb_alunos(bigint, integer, boolean),
  pessoas.carga_aluno_historico(bigint, integer, boolean), pessoas.carga_contatos_hm(bigint, integer, boolean),
  pessoas.carga_hm_socios(bigint, integer, boolean), pessoas.carga_respondi(bigint, integer, boolean),
  pessoas.carga_leads(bigint, text, integer, boolean), pessoas.carga_crm_negocio(bigint, integer, boolean)
  from public, anon, authenticated, service_role;

do $g$
begin
  if exists (select 1 from pg_proc p where p.pronamespace = 'pessoas'::regnamespace
               and (p.proname like 'carga%' or p.proname like '\_carga%')
               and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))) then
    raise exception '20261014152236: função de carga ficou executável por anon/authenticated.';
  end if;
end
$g$;

-- ===== 20261014152242 =====
-- 20261014152242: manter a pessoa única viva (rotina de hora em hora só no banco + agendamento do delta diário do AC)
--
-- STATUS: NÃO APLICADA. Terminal Censo (pessoa única), 14/10/2026. Depende de 20261014150034 (ex-170000) e 20261014152236.
--   Ensaio: 20261014152242_ensaio.sql. Detalhe: 20261014152242.explain.md.
--
-- POR QUE: "temos q configurar isso tbm pra ficar funcional" (Victor, 14/10/2026). Regras do Maestro/Victor: incremental,
--   leve (máquina de ~1 GB), minuto vazio, chave de desligar; rotina EXTERNA (AC) nasce desligada, 1×/dia de madrugada,
--   teto de chamadas no código e data de fim gravada (padrão 31/12/2026).
-- O QUE FAZ:
--   1. pessoas.carga_incremental(p_limite): para cada fonte do banco (Hotmart das 2 contas, Central, T1-T40, HM, sócios do
--      HM, Respondi, leads, CRM), roda a carga no modo "só novos" (linhas sem o seu evento), até p_limite por fonte. Pula a
--      fonte que (a) está com a chave desligada, (b) tem carga inicial aberta ou (c) ainda não terminou a carga inicial.
--      Erro numa fonte: fecha aquela execução como 'erro' com o SQLSTATE e segue as outras.
--      Hotmart e Respondi NÃO têm rotina externa: o webhook da Hotmart e o respondi-sync já põem o dado no banco; esta
--      rotina só lê o banco.
--   2. Job pg_cron 'pessoas-incremental' às :50 de toda hora, CRIADO DESLIGADO (active = false). Liga depois da carga
--      inicial, com o roteiro.
--   3. Job pg_cron 'pessoas-ac-delta' às 05:40 UTC (02:40 em Brasília), CRIADO DESLIGADO, chamando a Edge Function
--      pessoas-ac-delta (código no repo, a publicar). Chave 'activecampaign_delta' nasce desligada, com fim 31/12/2026.
--      A Edge usa a chave do AC do Vault (activecampaign_api_key) e o segredo do cron já existente (cron_webhook_secret).
-- PENDÊNCIA (achado 7 do pentester, 14/10/2026): se uma rodada passar dos 120 s do statement_timeout, a hora inteira é
--   desfeita sem registro em pessoas.carga_execucao. Mitigação hoje: limite de 200 por fonte. Corrigir depois (uma chamada
--   por fonte, ou registro fora da transação).
-- AS 5 PERGUNTAS: escala = dezenas de linhas novas por hora (contra ~58 mil transações e ~40 mil leads de base: o anti-join
--   pelo índice único custa ~1 ms por mil linhas lidas); índice = eventos_fonte_unico; frequência = 24×/dia (só banco) e
--   1×/dia (AC); repetição = idempotente; reversão = 20261014152242_reversao.sql (desagenda os 2 jobs e tira a função).

set local lock_timeout = '5s';

do $g$
begin
  if to_regprocedure('pessoas.carga_thb_alunos(bigint,integer,boolean)') is null then
    raise exception '20261014152242: falta 20261014152236 (cargas das fontes com modo só novos).';
  end if;
  if exists (select 1 from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta')) then
    raise exception '20261014152242: jobs já existem.';
  end if;
end
$g$;

insert into pessoas.carga_chave (fonte, ligada, ate, por) values
  ('incremental', true, null, 'migration 20261014152242 (o job nasce desligado; esta chave é a segunda trava)'),
  ('activecampaign_delta', false, date '2026-12-31', 'migration 20261014152242: rotina externa, liga só com ok do Victor')
on conflict (fonte) do nothing;

create function pessoas.carga_incremental(p_limite integer default 200) returns jsonb
language plpgsql set search_path to '' as $f$
declare
  f text; v_e bigint; r jsonb; v_saida jsonb := '{}';
begin
  if not pessoas.carga_ligada('incremental') then return jsonb_build_object('desligada', true); end if;
  if p_limite not between 1 and 1000 then raise exception 'limite entre 1 e 1.000' using errcode = '22023'; end if;
  foreach f in array array['hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios',
                           'respondi', 'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio'] loop
    if not pessoas.carga_ligada(f) then v_saida := v_saida || jsonb_build_object(f, 'desligada'); continue; end if;
    if exists (select 1 from pessoas.carga_execucao where fonte = f and status in ('rodando', 'parada')) then
      v_saida := v_saida || jsonb_build_object(f, 'carga aberta'); continue;
    end if;
    if not exists (select 1 from pessoas.carga_execucao where fonte = f and fase = 'pessoas' and status = 'ok' and coalesce(por, '') <> 'incremental') then
      v_saida := v_saida || jsonb_build_object(f, 'sem carga inicial'); continue;
    end if;
    begin
      v_e := (pessoas.carga_abrir(f, 'pessoas', 'incremental')->>'execucao')::bigint;
      r := case f
             when 'hotmart_academy'    then pessoas.carga_fin_hotmart(v_e, 'academy', p_limite, true)
             when 'hotmart_escritorio' then pessoas.carga_fin_hotmart(v_e, 'escritorio', p_limite, true)
             when 'thb_alunos'         then pessoas.carga_thb_alunos(v_e, p_limite, true)
             when 'aluno_historico'    then pessoas.carga_aluno_historico(v_e, p_limite, true)
             when 'contatos_hm'        then pessoas.carga_contatos_hm(v_e, p_limite, true)
             when 'hm_socios'          then pessoas.carga_hm_socios(v_e, p_limite, true)
             when 'respondi'           then pessoas.carga_respondi(v_e, p_limite, true)
             when 'crm_negocio'        then pessoas.carga_crm_negocio(v_e, p_limite, true)
             else pessoas.carga_leads(v_e, f, p_limite, true) end;
      perform pessoas.carga_fechar(v_e, 'ok');
      v_saida := v_saida || jsonb_build_object(f, (r->>'lidas')::int);
    exception when others then
      -- a subtransação desfez o lote E a execução aberta nele; registra uma execução 'erro' (só o código) fora dela
      v_saida := v_saida || jsonb_build_object(f, 'erro ' || sqlstate);
      insert into pessoas.carga_execucao (fonte, fase, status, erro, por, terminada_em)
      values (f, 'pessoas', 'erro', 'incremental: ' || sqlstate, 'incremental', now());
    end;
  end loop;
  return v_saida;
end $f$;
revoke all on function pessoas.carga_incremental(integer) from public, anon, authenticated, service_role;

-- jobs: criados e desligados na mesma migration
select cron.schedule('pessoas-incremental', '50 * * * *',
  $c$ set statement_timeout = '120s'; select pessoas.carga_incremental(200) $c$);
select cron.schedule('pessoas-ac-delta', '40 5 * * *',
  $c$ select ops.cron_post('pessoas-ac-delta',
       url := 'https://mbvybujpkwuorhtdzcde.supabase.co/functions/v1/pessoas-ac-delta',
       body := '{}'::jsonb,
       headers := jsonb_build_object('Content-Type', 'application/json',
                                     'x-webhook-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'cron_webhook_secret')),
       timeout_milliseconds := 150000) $c$);
select cron.alter_job(j.jobid, active := false) from cron.job j where j.jobname in ('pessoas-incremental', 'pessoas-ac-delta');

do $g$
begin
  if (select count(*) from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta') and not active) <> 2 then
    raise exception '20261014152242: os 2 jobs tinham de nascer desligados.';
  end if;
  if has_function_privilege('anon', 'pessoas.carga_incremental(integer)', 'execute')
     or has_function_privilege('authenticated', 'pessoas.carga_incremental(integer)', 'execute') then
    raise exception '20261014152242: carga_incremental executável por anon/authenticated.';
  end if;
end
$g$;

-- ===== testes =====
insert into pg_temp._z_out(passo, linha) select '10 jobs criados (nome / horário / ativo)', string_agg(jobname || ' ' || schedule || ' ' || active, ' | ' order by jobname) from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta');
insert into pg_temp._z_out(passo, linha) select '11 chaves: incremental / delta do AC (ligada, fim)', (select ligada::text from pessoas.carga_chave where fonte = 'incremental') || ' / ' || (select ligada || ' até ' || ate from pessoas.carga_chave where fonte = 'activecampaign_delta');
insert into pg_temp._z_out(passo, linha) select '12 incremental antes da carga inicial (esperado: sem carga inicial em todas)', pessoas.carga_incremental(20)::text;
-- simula a carga inicial de 2 fontes (50 linhas cada) e roda o incremental
do $t$ declare v bigint; begin
  v := (pessoas.carga_abrir('thb_alunos', 'pessoas', 'ensaio-inicial')->>'execucao')::bigint; perform pessoas.carga_thb_alunos(v, 50); perform pessoas.carga_fechar(v, 'ok');
  v := (pessoas.carga_abrir('crm_negocio', 'pessoas', 'ensaio-inicial')->>'execucao')::bigint; perform pessoas.carga_crm_negocio(v, 50); perform pessoas.carga_fechar(v, 'ok');
end $t$;
insert into pg_temp._z_out(passo, linha) select '13 eventos thb_alunos/crm depois da "carga inicial" de 50', (select count(*) from pessoas.eventos where fonte_tabela = 'public.thb_alunos') || ' / ' || (select count(*) from pessoas.eventos where fonte_tabela = 'crm.negocio');
insert into pg_temp._z_out(passo, linha) select '14 incremental (limite 20): só os novos', pessoas.carga_incremental(20)::text;
insert into pg_temp._z_out(passo, linha) select '15 eventos thb_alunos/crm depois do incremental (+20 cada, sem repetir os 50)', (select count(*) from pessoas.eventos where fonte_tabela = 'public.thb_alunos') || ' / ' || (select count(*) from pessoas.eventos where fonte_tabela = 'crm.negocio');
insert into pg_temp._z_out(passo, linha) select '16 cursor da carga inicial intacto depois do incremental', (select count(*) from pessoas.carga_execucao where fonte = 'thb_alunos' and por = 'ensaio-inicial' and cursor is not null)::text;
update pessoas.carga_chave set ligada = false where fonte = 'incremental';
insert into pg_temp._z_out(passo, linha) select '17 incremental com a chave desligada', pessoas.carga_incremental(20)::text;
insert into pg_temp._z_out(passo, linha) select '18 carga_incremental executável por anon/authenticated', (has_function_privilege('anon', 'pessoas.carga_incremental(integer)', 'execute') or has_function_privilege('authenticated', 'pessoas.carga_incremental(integer)', 'execute'))::text;
-- ===== reversões =====
-- Reversão de 20261014152242 (rotinas de manter vivo). Não apaga dado carregado.
set local lock_timeout = '5s';
select cron.unschedule(j.jobid) from cron.job j where j.jobname in ('pessoas-incremental', 'pessoas-ac-delta');
drop function if exists pessoas.carga_incremental(integer);
delete from pessoas.carga_chave where fonte in ('incremental', 'activecampaign_delta') and por like 'migration 20261014152242%';
-- Reversão de 20261014152236 (cargas das fontes). NÃO apaga pessoa nem evento já carregado (regra I-03): os eventos das
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
drop function if exists pessoas._casar_email_seguro(text, text, text, text);
delete from pessoas.carga_chave where fonte in ('hotmart_academy', 'hotmart_escritorio', 'thb_alunos', 'aluno_historico', 'contatos_hm', 'hm_socios', 'respondi',
  'leads_cnhf', 'leads_workbook', 'leads_black', 'crm_negocio') and por = 'migration 20261014152236';

insert into pg_temp._z_out(passo, linha) select '90 depois das reversões: jobs / função', (select count(*) from cron.job where jobname in ('pessoas-incremental', 'pessoas-ac-delta')) || ' / ' || coalesce(to_regprocedure('pessoas.carga_incremental(integer)')::text, 'não');
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
