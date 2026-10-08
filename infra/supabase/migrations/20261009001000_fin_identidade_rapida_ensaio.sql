-- Ensaio de 20261009001000 (fin.recalcular_identidade rápida). DOIS blocos independentes, cada um UMA transação desfeita no
-- rollback; rodar cada bloco numa chamada da Management API (/database/query, arquivo lido em utf-8), < 25 s cada.
-- A saída só tem contagens, md5 e tempos (nenhum e-mail/CPF). Esperado: todas as linhas com ok = true.
--
-- BLOCO 1 — equivalência: calcula o resultado com o ALGORITMO ANTIGO (texto do corpo vivo md5 203c6f02…, trocando
--   fin.identidade* por tabelas temporárias v_*), aplica a migration (cópia literal), roda a função nova e compara
--   md5 das 4 tabelas e o jsonb de retorno.
-- BLOCO 2 — caminho da diferença: estraga as tabelas reais (apaga, altera, insere lixo nas 4), roda a função nova,
--   exige o md5 de antes; roda de novo e exige zero escrita (pg_stat_xact_user_tables). Mede o tempo sem
--   temp_buffers alterado (igual ao cron).

-- ═════════════ BLOCO 1 ═════════════
set temp_buffers = '64MB';  -- só para o cálculo ANTIGO de referência caber em memória (sessão do ensaio)
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _ens (teste text, ok boolean, detalhe text) on commit drop;
-- referência: algoritmo antigo em tabelas temporárias
create temp table v_identidade_aresta (like fin.identidade_aresta including all) on commit drop;
create temp table v_identidade_revisao (like fin.identidade_revisao including all) on commit drop;
create temp table v_identidade (like fin.identidade including all) on commit drop;
create temp table v_identidade_sugestao (like fin.identidade_sugestao including all) on commit drop;
create temp table v_log (fase text, ms numeric, extra text) on commit drop;
create function pg_temp.f_1() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  truncate pg_temp.v_identidade_aresta;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'd:' || t.comprador_documento, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and length(t.comprador_documento) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'u:' || t.comprador_ucode, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and t.comprador_ucode is not null
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'd:' || regexp_replace(a.documento, '\D', '', 'g'), 'thb_alunos'
    from public.thb_alunos a
   where a.email is not null and length(regexp_replace(coalesce(a.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'e:' || lower(trim(c.email)), 'thb_alunos.comprador_id'
    from public.thb_alunos a join public.compradores c on c.id = a.comprador_id
   where a.email is not null and c.email is not null and lower(trim(a.email)) <> lower(trim(c.email))
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  -- (removida) rede.perfis.aluno_thb_email é autodeclarado: não é fonte de identidade
  insert into pg_temp.v_identidade_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;


insert into pg_temp.v_log values ('1_arestas', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
create function pg_temp.f_2() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  truncate pg_temp.v_identidade_revisao;
  insert into pg_temp.v_identidade_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from pg_temp.v_identidade_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas
  insert into pg_temp.v_identidade_revisao (no, motivo, emails)
  select x.no, 'ponte entre CPFs: e-mail ligado a ' || x.n || ' CPFs diferentes — não juntado', null
    from (select e.no, count(distinct e.cpf) n
            from (select a no, b cpf from pg_temp.v_identidade_aresta where a like 'e:%' and b ~ '^d:\d{11}$'
                  union select b, a from pg_temp.v_identidade_aresta where b like 'e:%' and a ~ '^d:\d{11}$') e
           where e.cpf not in (select valor from fin.identidade_bloqueio)
             and e.cpf not in (select no from pg_temp.v_identidade_revisao)
           group by e.no having count(distinct e.cpf) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp.v_identidade_revisao (no, motivo, emails)
  select x.no, 'CNPJ ponte entre CPFs: alcança ' || x.n || ' CPFs pelos e-mails — não juntado', null
    from (select c.b no, count(distinct p.b) n
            from pg_temp.v_identidade_aresta c
            join pg_temp.v_identidade_aresta p on p.a = c.a and p.b ~ '^d:\d{11}$'
           where c.b ~ '^d:\d{14}$' and c.a like 'e:%'
             and c.a not in (select no from pg_temp.v_identidade_revisao)
             and p.b not in (select valor from fin.identidade_bloqueio)
             and p.b not in (select no from pg_temp.v_identidade_revisao)
           group by c.b having count(distinct p.b) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp.v_identidade_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from pg_temp.v_identidade_aresta ar
   where ar.a in (select no from pg_temp.v_identidade_revisao) or ar.b in (select no from pg_temp.v_identidade_revisao);


insert into pg_temp.v_log values ('2_revisao', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
create function pg_temp.f_3() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  truncate pg_temp.v_identidade;
  insert into pg_temp.v_identidade (no, pessoa_chave)
  select n, n from (select a n from pg_temp.v_identidade_aresta union select b from pg_temp.v_identidade_aresta) x;
  insert into pg_temp.v_identidade (no, pessoa_chave)
  select distinct 'e:' || lower(trim(t.comprador_email)), 'e:' || lower(trim(t.comprador_email))
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null
  on conflict (no) do nothing;


insert into pg_temp.v_log values ('3_nos', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
create function pg_temp.f_4() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  loop
    v_rodada := v_rodada + 1;
    if v_rodada > 40 then
      raise exception 'fin.recalcular_identidade: não convergiu em 40 rodadas. Nada confirmado.';
    end if;
    with viz as (
      select ar.a no, i.pessoa_chave rot from pg_temp.v_identidade_aresta ar join pg_temp.v_identidade i on i.no = ar.b
      union all
      select ar.b, i.pessoa_chave from pg_temp.v_identidade_aresta ar join pg_temp.v_identidade i on i.no = ar.a
    ), menor as (select no, min(rot) rot from viz group by no)
    update pg_temp.v_identidade i set pessoa_chave = m.rot
      from menor m where m.no = i.no and m.rot < i.pessoa_chave;
    get diagnostics v_mudou = row_count;
    exit when v_mudou = 0;
  end loop;


insert into pg_temp.v_log values ('4_loop', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
create function pg_temp.f_5() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  truncate pg_temp.v_identidade_sugestao;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into pg_temp.v_identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join pg_temp.v_identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.comprador_documento not in (select no from pg_temp.v_identidade_revisao)) x
    join (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join pg_temp.v_identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from pg_temp.v_identidade i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into pg_temp.v_identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.comprador_telefone, 11)
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2 on right(t2.comprador_telefone, 11) = right(t1.comprador_telefone, 11)
                                   and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join pg_temp.v_identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join pg_temp.v_identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(t1.comprador_telefone) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into pg_temp.v_identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.comprador_nome
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2
      on lower(public.unaccent(trim(t2.comprador_nome))) = lower(public.unaccent(trim(t1.comprador_nome)))
     and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join pg_temp.v_identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join pg_temp.v_identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(trim(t1.comprador_nome)) >= 8 and position(' ' in trim(t1.comprador_nome)) > 0
     and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;


insert into pg_temp.v_log values ('5_sugestao', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
create function pg_temp.f_6() returns void language plpgsql as $f$
declare v_rodada int := 0; v_mudou bigint; r jsonb; t0 timestamptz := clock_timestamp();
begin
  update pg_temp.v_identidade set calculado_em = now();
  select jsonb_build_object(
    'rodadas', v_rodada,
    'nos', (select count(*) from pg_temp.v_identidade),
    'pessoas', (select count(distinct pessoa_chave) from pg_temp.v_identidade),
    'emails_hotmart', (select count(distinct lower(trim(comprador_email))) from fin.hotmart_transacoes where conta = 'academy'),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from pg_temp.v_identidade i
                          where i.no in (select 'e:' || lower(trim(comprador_email)) from fin.hotmart_transacoes where conta = 'academy')),
    'arestas', (select count(*) from pg_temp.v_identidade_aresta),
    'revisao', (select count(*) from pg_temp.v_identidade_revisao),
    'sugestoes', (select count(*) from pg_temp.v_identidade_sugestao)) into r;
  

insert into pg_temp.v_log values ('6_final', round(extract(epoch from clock_timestamp()-t0)*1000), coalesce(v_rodada::text,'')||' '||coalesce(r::text,''));
end $f$;
select pg_temp.f_1(); select pg_temp.f_2(); select pg_temp.f_3(); select pg_temp.f_4(); select pg_temp.f_5(); select pg_temp.f_6();
-- ═══ MIGRATION (cópia literal de 20261009001000_fin_identidade_rapida.sql) ═══
-- 20261009001000: fin.recalcular_identidade() rápida — mesmo resultado, sem truncate, lendo fin.hotmart_transacoes uma vez
--
-- STATUS: APLICADA em produção 08/10/2026 (~23h BRT; versão em supabase_migrations.schema_migrations). Ensaio: 20261009001000_fin_identidade_rapida_ensaio.sql (begin … rollback). Medição e 5 perguntas:
-- 20261009001000_fin_identidade_rapida.explain.md. Reversão: 20261009001000_fin_identidade_rapida_reversao.sql.
-- Backup do corpo vivo: 20261009001000_fin_identidade.backup-antes.sql (md5(prosrc) 203c6f02285e76595ac22ea1ee688650).
--
-- POR QUE: o job 54 (fin-identidade-recalcular, '47 * * * *') levava ~930 ms quando nasceu (27/09) e hoje leva média
--   31,5 s, máx 67 s (cron.job_run_details 08/10), com os dados de entrada quase parados desde 29/09
--   (fin.hotmart_transacoes +105 linhas em 9 dias). O custo é do desenho, não do volume:
--   1. TRUNCATE de fin.identidade/_aresta/_revisao/_sugestao: ACCESS EXCLUSIVE a rodada inteira. Durante 30–67 s por
--      hora toda leitura de fin.identidade (crm_jornada, crm.emails_da_pessoa, trajetória do aluno, relatórios do
--      financeiro, ~25 funções) fica parada esperando.
--   2. Regrava as ~68 mil linhas de fin.identidade e ~49 mil de _aresta toda hora (WAL + 2 índices), propaga o
--      rótulo com UPDATE da tabela inteira por rodada (5 rodadas) e no fim faz UPDATE de todas as linhas só para
--      carimbar calculado_em. Muda em média 0 linha por hora.
--   3. Varre fin.hotmart_transacoes (114 MB de heap, bruto_json, não cabe em shared_buffers de 256 MB junto com o
--      resto) ~10 vezes por rodada: o tempo sobe com a disputa de cache dos 7 sistemas, não com o dado.
--
-- O QUE FAZ (mesma assinatura, mesmo SECURITY DEFINER, mesmo search_path, mesmo jsonb de retorno; cron intacto)
--   a. Lê fin.hotmart_transacoes uma vez, só 7 colunas, para uma tabela temporária (on commit drop).
--   b. Calcula arestas, revisão, nós, propagação e sugestões em tabelas temporárias, com as MESMAS regras e
--      filtros do corpo vivo (texto copiado; só trocou a origem). A 1ª rodada da propagação sai no insert dos nós
--      e as seguintes olham só vizinhos de quem mudou: mesmo rótulo final, mesmo número de rodadas.
--   c. Grava em fin.* só a diferença (delete do que sumiu, update do que mudou, insert do que é novo). Sem truncate:
--      só row lock; o leitor nunca espera. calculado_em passa a ser "quando a linha mudou" (ninguém lê a coluna:
--      conferido em pg_proc, views e web/).
--   d. pg_advisory_xact_lock serializa duas chamadas simultâneas (antes o truncate fazia isso).
-- Medido (ensaio, begin … rollback): antigo 9,0 s de cálculo em temp + escrita em tabela logada (cron: 31,5 s);
--   novo 4,9–5,3 s ponta a ponta. Resultado idêntico (md5 das 4 tabelas e do jsonb), ver o explain.

set local lock_timeout = '3s';

do $g$
declare v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'fin.recalcular_identidade()'::regprocedure;
  if v_md5 is distinct from '203c6f02285e76595ac22ea1ee688650' then
    raise exception '20261009001000: fin.recalcular_identidade() mudou desde o backup (md5 %); reavalie antes de aplicar', v_md5;
  end if;
end
$g$;

create or replace function fin.recalcular_identidade()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rodada int := 0; v_mudou bigint; r jsonb;
begin
  -- Uma rodada por vez (antes o truncate serializava; agora só há row lock).
  perform pg_advisory_xact_lock(hashtext('fin.recalcular_identidade'));

  drop table if exists pg_temp._idt_tx, pg_temp._idt_aresta, pg_temp._idt_revisao,
                       pg_temp._idt_no, pg_temp._idt_mud, pg_temp._idt_mud2, pg_temp._idt_sugestao;

  -- 1) fin.hotmart_transacoes (114 MB de heap, por causa do bruto_json) lida UMA vez, só as colunas usadas.
  --    vis = a regra da view fin.hotmart_transacoes_identidade (academy, fora de A_CLASSIFICAR).
  create temp table _idt_tx on commit drop as
  select lower(trim(t.comprador_email)) email, t.comprador_documento doc, t.comprador_ucode ucode, t.status,
         t.comprador_telefone tel, t.comprador_nome nome,
         not exists (select 1 from fin.produtos p where p.produto_id = t.produto_id and p.familia = 'A_CLASSIFICAR') vis
    from (select * from fin.hotmart_transacoes where conta = 'academy') t;
  analyze pg_temp._idt_tx;

  create temp table _idt_aresta (a text, b text, fonte text, primary key (a, b, fonte)) on commit drop;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || t.email, 'd:' || t.doc, 'hotmart'
    from pg_temp._idt_tx t where t.vis and t.email is not null and length(t.doc) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || t.email, 'u:' || t.ucode, 'hotmart'
    from pg_temp._idt_tx t where t.vis and t.email is not null and t.ucode is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(a.email)), 'd:' || regexp_replace(a.documento, '\D', '', 'g'), 'thb_alunos'
    from public.thb_alunos a
   where a.email is not null and length(regexp_replace(coalesce(a.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(a.email)), 'e:' || lower(trim(c.email)), 'thb_alunos.comprador_id'
    from public.thb_alunos a join public.compradores c on c.id = a.comprador_id
   where a.email is not null and c.email is not null and lower(trim(a.email)) <> lower(trim(c.email))
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  -- (removida) rede.perfis.aluno_thb_email é autodeclarado: não é fonte de identidade
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;
  analyze pg_temp._idt_aresta;

  create temp table _idt_revisao (no text primary key, motivo text, emails integer) on commit drop;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from pg_temp._idt_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'ponte entre CPFs: e-mail ligado a ' || x.n || ' CPFs diferentes — não juntado', null
    from (select e.no, count(distinct e.cpf) n
            from (select a no, b cpf from pg_temp._idt_aresta where a like 'e:%' and b ~ '^d:\d{11}$'
                  union select b, a from pg_temp._idt_aresta where b like 'e:%' and a ~ '^d:\d{11}$') e
           where e.cpf not in (select valor from fin.identidade_bloqueio)
             and e.cpf not in (select no from pg_temp._idt_revisao)
           group by e.no having count(distinct e.cpf) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'CNPJ ponte entre CPFs: alcança ' || x.n || ' CPFs pelos e-mails — não juntado', null
    from (select c.b no, count(distinct p.b) n
            from pg_temp._idt_aresta c
            join pg_temp._idt_aresta p on p.a = c.a and p.b ~ '^d:\d{11}$'
           where c.b ~ '^d:\d{14}$' and c.a like 'e:%'
             and c.a not in (select no from pg_temp._idt_revisao)
             and p.b not in (select valor from fin.identidade_bloqueio)
             and p.b not in (select no from pg_temp._idt_revisao)
           group by c.b having count(distinct p.b) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from pg_temp._idt_aresta ar
   where ar.a in (select no from pg_temp._idt_revisao) or ar.b in (select no from pg_temp._idt_revisao);

  -- 2) nós. A 1ª rodada da propagação já sai no insert: rótulo = menor entre o próprio nó e os vizinhos
  --    (é exatamente o que a 1ª rodada do UPDATE antigo fazia partindo de pessoa_chave = no).
  create temp table _idt_no (no text primary key, pessoa_chave text not null) on commit drop;
  insert into pg_temp._idt_no (no, pessoa_chave)
  select x.n, least(x.n, min(x.v))
    from (select a n, b v from pg_temp._idt_aresta union all select b, a from pg_temp._idt_aresta) x
   group by x.n;
  insert into pg_temp._idt_no (no, pessoa_chave)
  select distinct 'e:' || t.email, 'e:' || t.email
    from pg_temp._idt_tx t where t.vis and t.email is not null
  on conflict (no) do nothing;

  -- 3) mesma propagação do menor rótulo, mesmas rodadas (Jacobi: cada rodada lê o rótulo do fim da anterior).
  --    Da 2ª rodada em diante só olha vizinho de quem mudou na rodada anterior: quem não tem
  --    vizinho que mudou já tem rótulo <= ao de todos os vizinhos e não mudaria.
  create temp table _idt_mud (no text primary key) on commit drop;
  create temp table _idt_mud2 (no text primary key) on commit drop;
  v_rodada := 1;
  insert into pg_temp._idt_mud select i.no from pg_temp._idt_no i where i.pessoa_chave <> i.no;
  get diagnostics v_mudou = row_count;
  while v_mudou > 0 loop
    v_rodada := v_rodada + 1;
    if v_rodada > 40 then
      raise exception 'fin.recalcular_identidade: não convergiu em 40 rodadas. Nada confirmado.';
    end if;
    analyze pg_temp._idt_mud;
    truncate pg_temp._idt_mud2;
    with viz as (
      select ar.a no, i.pessoa_chave rot from pg_temp._idt_mud d
        join pg_temp._idt_aresta ar on ar.b = d.no join pg_temp._idt_no i on i.no = d.no
      union all
      select ar.b, i.pessoa_chave from pg_temp._idt_mud d
        join pg_temp._idt_aresta ar on ar.a = d.no join pg_temp._idt_no i on i.no = d.no
    ), menor as (select no, min(rot) rot from viz group by no),
    up as (update pg_temp._idt_no i set pessoa_chave = m.rot
             from menor m where m.no = i.no and m.rot < i.pessoa_chave returning i.no)
    insert into pg_temp._idt_mud2 select no from up;
    get diagnostics v_mudou = row_count;
    truncate pg_temp._idt_mud;
    insert into pg_temp._idt_mud select no from pg_temp._idt_mud2;
  end loop;
  analyze pg_temp._idt_no;

  create temp table _idt_sugestao (pessoa_a text, pessoa_b text, motivo text, evidencia text,
                                   primary key (pessoa_a, pessoa_b, motivo)) on commit drop;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.doc, i.pessoa_chave p
            from pg_temp._idt_tx t
            join pg_temp._idt_no i on i.no = 'e:' || t.email
           where t.vis and length(t.doc) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.doc not in (select no from pg_temp._idt_revisao)) x
    join (select t.doc, i.pessoa_chave p
            from pg_temp._idt_tx t
            join pg_temp._idt_no i on i.no = 'e:' || t.email
           where t.vis and length(t.doc) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from pg_temp._idt_no i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.tel, 11)
    from pg_temp._idt_tx t1
    join pg_temp._idt_tx t2 on right(t2.tel, 11) = right(t1.tel, 11) and t2.email <> t1.email
    join pg_temp._idt_no i1 on i1.no = 'e:' || t1.email
    join pg_temp._idt_no i2 on i2.no = 'e:' || t2.email
   where t1.vis and t2.vis and length(t1.tel) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.nome
    from pg_temp._idt_tx t1
    join pg_temp._idt_tx t2
      on lower(public.unaccent(trim(t2.nome))) = lower(public.unaccent(trim(t1.nome)))
     and t2.email <> t1.email
    join pg_temp._idt_no i1 on i1.no = 'e:' || t1.email
    join pg_temp._idt_no i2 on i2.no = 'e:' || t2.email
   where t1.vis and t2.vis and length(trim(t1.nome)) >= 8 and position(' ' in trim(t1.nome)) > 0
     and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;

  -- 4) grava só a diferença. Sem truncate: quem lê fin.identidade não espera mais o recálculo
  --    (o truncate segurava ACCESS EXCLUSIVE a rodada inteira) e o WAL é só do que mudou.
  delete from fin.identidade_aresta f
   where not exists (select 1 from pg_temp._idt_aresta n where n.a = f.a and n.b = f.b and n.fonte = f.fonte);
  insert into fin.identidade_aresta (a, b, fonte)
  select n.a, n.b, n.fonte from pg_temp._idt_aresta n
   where not exists (select 1 from fin.identidade_aresta f where f.a = n.a and f.b = n.b and f.fonte = n.fonte);

  delete from fin.identidade_revisao f where not exists (select 1 from pg_temp._idt_revisao n where n.no = f.no);
  update fin.identidade_revisao f set motivo = n.motivo, emails = n.emails, calculado_em = now()
    from pg_temp._idt_revisao n
   where n.no = f.no and (f.motivo is distinct from n.motivo or f.emails is distinct from n.emails);
  insert into fin.identidade_revisao (no, motivo, emails)
  select n.no, n.motivo, n.emails from pg_temp._idt_revisao n
   where not exists (select 1 from fin.identidade_revisao f where f.no = n.no);

  delete from fin.identidade f where not exists (select 1 from pg_temp._idt_no n where n.no = f.no);
  update fin.identidade f set pessoa_chave = n.pessoa_chave, calculado_em = now()
    from pg_temp._idt_no n where n.no = f.no and f.pessoa_chave is distinct from n.pessoa_chave;
  insert into fin.identidade (no, pessoa_chave)
  select n.no, n.pessoa_chave from pg_temp._idt_no n
   where not exists (select 1 from fin.identidade f where f.no = n.no);

  delete from fin.identidade_sugestao f
   where not exists (select 1 from pg_temp._idt_sugestao n
                      where n.pessoa_a = f.pessoa_a and n.pessoa_b = f.pessoa_b and n.motivo = f.motivo);
  update fin.identidade_sugestao f set evidencia = n.evidencia, calculado_em = now()
    from pg_temp._idt_sugestao n
   where n.pessoa_a = f.pessoa_a and n.pessoa_b = f.pessoa_b and n.motivo = f.motivo
     and f.evidencia is distinct from n.evidencia;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select n.pessoa_a, n.pessoa_b, n.motivo, n.evidencia from pg_temp._idt_sugestao n
   where not exists (select 1 from fin.identidade_sugestao f
                      where f.pessoa_a = n.pessoa_a and f.pessoa_b = n.pessoa_b and f.motivo = n.motivo);

  select jsonb_build_object(
    'rodadas', v_rodada,
    'nos', (select count(*) from pg_temp._idt_no),
    'pessoas', (select count(distinct pessoa_chave) from pg_temp._idt_no),
    'emails_hotmart', (select count(distinct t.email) from pg_temp._idt_tx t),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from pg_temp._idt_no i
                          where i.no in (select 'e:' || t.email from pg_temp._idt_tx t)),
    'arestas', (select count(*) from pg_temp._idt_aresta),
    'revisao', (select count(*) from pg_temp._idt_revisao),
    'sugestoes', (select count(*) from pg_temp._idt_sugestao)) into r;
  drop table if exists pg_temp._idt_tx, pg_temp._idt_aresta, pg_temp._idt_revisao,
                       pg_temp._idt_no, pg_temp._idt_mud, pg_temp._idt_mud2, pg_temp._idt_sugestao;
  return r;
end
$function$;

revoke all on function fin.recalcular_identidade() from public, anon, authenticated, service_role;
comment on function fin.recalcular_identidade() is
  '20261009001000: identidade recalculada em tabelas temporárias e gravada por diferença (sem truncate). Cron 54, :47.';

-- ═══ fim da migration ═══
insert into pg_temp._ens
select 'T1 corpo novo no ar', md5(p.prosrc) <> '203c6f02285e76595ac22ea1ee688650' and p.prosrc !~* 'truncate\s+fin\.',
       'md5(prosrc) ' || md5(p.prosrc)
  from pg_proc p where p.oid = 'fin.recalcular_identidade()'::regprocedure;
insert into pg_temp._ens
select 'T2 ACL e definição', not has_function_privilege('anon', p.oid, 'execute')
       and not has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('service_role', p.oid, 'execute')
       and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)
       and p.prosecdef and p.proconfig = array['search_path=""'] and p.provolatile = 'v',
       coalesce(p.proacl::text, 'null') || ' ' || p.proconfig::text
  from pg_proc p where p.oid = 'fin.recalcular_identidade()'::regprocedure;
create temp table _t on commit drop as select clock_timestamp() t0;
create temp table _r on commit drop as select fin.recalcular_identidade() r;
insert into pg_temp._ens select 'T3 tempo da função nova (ms, temp_buffers 64MB)', true,
       round(extract(epoch from clock_timestamp() - t0) * 1000)::text from pg_temp._t;
insert into pg_temp._ens
select 'T4 jsonb igual ao antigo', (r - 'rodadas') = (l6.extra_j - 'rodadas') and (r ->> 'rodadas') = l4.rod,
       r::text
  from pg_temp._r,
       (select substr(extra, strpos(extra, '{'))::jsonb extra_j from pg_temp.v_log where fase = '6_final') l6,
       (select btrim(extra) rod from pg_temp.v_log where fase = '4_loop') l4;

create temp table _md5 on commit drop as
select 'identidade' t, (select md5(string_agg(no||'|'||pessoa_chave, ',' order by no)) from fin.identidade) real_,
       (select md5(string_agg(no||'|'||pessoa_chave, ',' order by no)) from pg_temp.v_identidade) ref_
union all select 'identidade_aresta',
  (select md5(string_agg(a||'|'||b||'|'||fonte, ',' order by a,b,fonte)) from fin.identidade_aresta),
  (select md5(string_agg(a||'|'||b||'|'||fonte, ',' order by a,b,fonte)) from pg_temp.v_identidade_aresta)
union all select 'identidade_revisao',
  (select md5(string_agg(no||'|'||motivo||'|'||coalesce(emails::text,'-'), ',' order by no)) from fin.identidade_revisao),
  (select md5(string_agg(no||'|'||motivo||'|'||coalesce(emails::text,'-'), ',' order by no)) from pg_temp.v_identidade_revisao)
union all select 'identidade_sugestao',
  (select md5(string_agg(pessoa_a||'|'||pessoa_b||'|'||motivo||'|'||evidencia, ',' order by pessoa_a,pessoa_b,motivo)) from fin.identidade_sugestao),
  (select md5(string_agg(pessoa_a||'|'||pessoa_b||'|'||motivo||'|'||evidencia, ',' order by pessoa_a,pessoa_b,motivo)) from pg_temp.v_identidade_sugestao);
insert into pg_temp._ens select 'T5 md5 '||t, real_ = ref_, left(real_,8)||' = '||left(ref_,8) from pg_temp._md5;
drop table pg_temp._md5;

select json_agg(_ens) from pg_temp._ens;
rollback;

-- ═════════════ BLOCO 2 ═════════════
begin;
set local lock_timeout = '3s';
set local statement_timeout = '20s';
create temp table _ens (teste text, ok boolean, detalhe text) on commit drop;
-- referência = estado atual das tabelas (o bloco 1 provou que é o resultado do algoritmo antigo)
create temp table ref_identidade on commit drop as select no, pessoa_chave from fin.identidade;
create temp table ref_identidade_aresta on commit drop as select a, b, fonte from fin.identidade_aresta;
create temp table ref_identidade_revisao on commit drop as select no, motivo, emails from fin.identidade_revisao;
create temp table ref_identidade_sugestao on commit drop as select pessoa_a, pessoa_b, motivo, evidencia from fin.identidade_sugestao;
-- ═══ MIGRATION (cópia literal de 20261009001000_fin_identidade_rapida.sql) ═══
-- 20261009001000: fin.recalcular_identidade() rápida — mesmo resultado, sem truncate, lendo fin.hotmart_transacoes uma vez
--
-- STATUS: APLICADA em produção 08/10/2026 (~23h BRT; versão em supabase_migrations.schema_migrations). Ensaio: 20261009001000_fin_identidade_rapida_ensaio.sql (begin … rollback). Medição e 5 perguntas:
-- 20261009001000_fin_identidade_rapida.explain.md. Reversão: 20261009001000_fin_identidade_rapida_reversao.sql.
-- Backup do corpo vivo: 20261009001000_fin_identidade.backup-antes.sql (md5(prosrc) 203c6f02285e76595ac22ea1ee688650).
--
-- POR QUE: o job 54 (fin-identidade-recalcular, '47 * * * *') levava ~930 ms quando nasceu (27/09) e hoje leva média
--   31,5 s, máx 67 s (cron.job_run_details 08/10), com os dados de entrada quase parados desde 29/09
--   (fin.hotmart_transacoes +105 linhas em 9 dias). O custo é do desenho, não do volume:
--   1. TRUNCATE de fin.identidade/_aresta/_revisao/_sugestao: ACCESS EXCLUSIVE a rodada inteira. Durante 30–67 s por
--      hora toda leitura de fin.identidade (crm_jornada, crm.emails_da_pessoa, trajetória do aluno, relatórios do
--      financeiro, ~25 funções) fica parada esperando.
--   2. Regrava as ~68 mil linhas de fin.identidade e ~49 mil de _aresta toda hora (WAL + 2 índices), propaga o
--      rótulo com UPDATE da tabela inteira por rodada (5 rodadas) e no fim faz UPDATE de todas as linhas só para
--      carimbar calculado_em. Muda em média 0 linha por hora.
--   3. Varre fin.hotmart_transacoes (114 MB de heap, bruto_json, não cabe em shared_buffers de 256 MB junto com o
--      resto) ~10 vezes por rodada: o tempo sobe com a disputa de cache dos 7 sistemas, não com o dado.
--
-- O QUE FAZ (mesma assinatura, mesmo SECURITY DEFINER, mesmo search_path, mesmo jsonb de retorno; cron intacto)
--   a. Lê fin.hotmart_transacoes uma vez, só 7 colunas, para uma tabela temporária (on commit drop).
--   b. Calcula arestas, revisão, nós, propagação e sugestões em tabelas temporárias, com as MESMAS regras e
--      filtros do corpo vivo (texto copiado; só trocou a origem). A 1ª rodada da propagação sai no insert dos nós
--      e as seguintes olham só vizinhos de quem mudou: mesmo rótulo final, mesmo número de rodadas.
--   c. Grava em fin.* só a diferença (delete do que sumiu, update do que mudou, insert do que é novo). Sem truncate:
--      só row lock; o leitor nunca espera. calculado_em passa a ser "quando a linha mudou" (ninguém lê a coluna:
--      conferido em pg_proc, views e web/).
--   d. pg_advisory_xact_lock serializa duas chamadas simultâneas (antes o truncate fazia isso).
-- Medido (ensaio, begin … rollback): antigo 9,0 s de cálculo em temp + escrita em tabela logada (cron: 31,5 s);
--   novo 4,9–5,3 s ponta a ponta. Resultado idêntico (md5 das 4 tabelas e do jsonb), ver o explain.

set local lock_timeout = '3s';

do $g$
declare v_md5 text;
begin
  select md5(p.prosrc) into v_md5 from pg_proc p where p.oid = 'fin.recalcular_identidade()'::regprocedure;
  if v_md5 is distinct from '203c6f02285e76595ac22ea1ee688650' then
    raise exception '20261009001000: fin.recalcular_identidade() mudou desde o backup (md5 %); reavalie antes de aplicar', v_md5;
  end if;
end
$g$;

create or replace function fin.recalcular_identidade()
 returns jsonb
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_rodada int := 0; v_mudou bigint; r jsonb;
begin
  -- Uma rodada por vez (antes o truncate serializava; agora só há row lock).
  perform pg_advisory_xact_lock(hashtext('fin.recalcular_identidade'));

  drop table if exists pg_temp._idt_tx, pg_temp._idt_aresta, pg_temp._idt_revisao,
                       pg_temp._idt_no, pg_temp._idt_mud, pg_temp._idt_mud2, pg_temp._idt_sugestao;

  -- 1) fin.hotmart_transacoes (114 MB de heap, por causa do bruto_json) lida UMA vez, só as colunas usadas.
  --    vis = a regra da view fin.hotmart_transacoes_identidade (academy, fora de A_CLASSIFICAR).
  create temp table _idt_tx on commit drop as
  select lower(trim(t.comprador_email)) email, t.comprador_documento doc, t.comprador_ucode ucode, t.status,
         t.comprador_telefone tel, t.comprador_nome nome,
         not exists (select 1 from fin.produtos p where p.produto_id = t.produto_id and p.familia = 'A_CLASSIFICAR') vis
    from (select * from fin.hotmart_transacoes where conta = 'academy') t;
  analyze pg_temp._idt_tx;

  create temp table _idt_aresta (a text, b text, fonte text, primary key (a, b, fonte)) on commit drop;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || t.email, 'd:' || t.doc, 'hotmart'
    from pg_temp._idt_tx t where t.vis and t.email is not null and length(t.doc) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || t.email, 'u:' || t.ucode, 'hotmart'
    from pg_temp._idt_tx t where t.vis and t.email is not null and t.ucode is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(a.email)), 'd:' || regexp_replace(a.documento, '\D', '', 'g'), 'thb_alunos'
    from public.thb_alunos a
   where a.email is not null and length(regexp_replace(coalesce(a.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(a.email)), 'e:' || lower(trim(c.email)), 'thb_alunos.comprador_id'
    from public.thb_alunos a join public.compradores c on c.id = a.comprador_id
   where a.email is not null and c.email is not null and lower(trim(a.email)) <> lower(trim(c.email))
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  -- (removida) rede.perfis.aluno_thb_email é autodeclarado: não é fonte de identidade
  insert into pg_temp._idt_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;
  analyze pg_temp._idt_aresta;

  create temp table _idt_revisao (no text primary key, motivo text, emails integer) on commit drop;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from pg_temp._idt_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'ponte entre CPFs: e-mail ligado a ' || x.n || ' CPFs diferentes — não juntado', null
    from (select e.no, count(distinct e.cpf) n
            from (select a no, b cpf from pg_temp._idt_aresta where a like 'e:%' and b ~ '^d:\d{11}$'
                  union select b, a from pg_temp._idt_aresta where b like 'e:%' and a ~ '^d:\d{11}$') e
           where e.cpf not in (select valor from fin.identidade_bloqueio)
             and e.cpf not in (select no from pg_temp._idt_revisao)
           group by e.no having count(distinct e.cpf) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select x.no, 'CNPJ ponte entre CPFs: alcança ' || x.n || ' CPFs pelos e-mails — não juntado', null
    from (select c.b no, count(distinct p.b) n
            from pg_temp._idt_aresta c
            join pg_temp._idt_aresta p on p.a = c.a and p.b ~ '^d:\d{11}$'
           where c.b ~ '^d:\d{14}$' and c.a like 'e:%'
             and c.a not in (select no from pg_temp._idt_revisao)
             and p.b not in (select valor from fin.identidade_bloqueio)
             and p.b not in (select no from pg_temp._idt_revisao)
           group by c.b having count(distinct p.b) > 1) x
  on conflict (no) do nothing;
  insert into pg_temp._idt_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from pg_temp._idt_aresta ar
   where ar.a in (select no from pg_temp._idt_revisao) or ar.b in (select no from pg_temp._idt_revisao);

  -- 2) nós. A 1ª rodada da propagação já sai no insert: rótulo = menor entre o próprio nó e os vizinhos
  --    (é exatamente o que a 1ª rodada do UPDATE antigo fazia partindo de pessoa_chave = no).
  create temp table _idt_no (no text primary key, pessoa_chave text not null) on commit drop;
  insert into pg_temp._idt_no (no, pessoa_chave)
  select x.n, least(x.n, min(x.v))
    from (select a n, b v from pg_temp._idt_aresta union all select b, a from pg_temp._idt_aresta) x
   group by x.n;
  insert into pg_temp._idt_no (no, pessoa_chave)
  select distinct 'e:' || t.email, 'e:' || t.email
    from pg_temp._idt_tx t where t.vis and t.email is not null
  on conflict (no) do nothing;

  -- 3) mesma propagação do menor rótulo, mesmas rodadas (Jacobi: cada rodada lê o rótulo do fim da anterior).
  --    Da 2ª rodada em diante só olha vizinho de quem mudou na rodada anterior: quem não tem
  --    vizinho que mudou já tem rótulo <= ao de todos os vizinhos e não mudaria.
  create temp table _idt_mud (no text primary key) on commit drop;
  create temp table _idt_mud2 (no text primary key) on commit drop;
  v_rodada := 1;
  insert into pg_temp._idt_mud select i.no from pg_temp._idt_no i where i.pessoa_chave <> i.no;
  get diagnostics v_mudou = row_count;
  while v_mudou > 0 loop
    v_rodada := v_rodada + 1;
    if v_rodada > 40 then
      raise exception 'fin.recalcular_identidade: não convergiu em 40 rodadas. Nada confirmado.';
    end if;
    analyze pg_temp._idt_mud;
    truncate pg_temp._idt_mud2;
    with viz as (
      select ar.a no, i.pessoa_chave rot from pg_temp._idt_mud d
        join pg_temp._idt_aresta ar on ar.b = d.no join pg_temp._idt_no i on i.no = d.no
      union all
      select ar.b, i.pessoa_chave from pg_temp._idt_mud d
        join pg_temp._idt_aresta ar on ar.a = d.no join pg_temp._idt_no i on i.no = d.no
    ), menor as (select no, min(rot) rot from viz group by no),
    up as (update pg_temp._idt_no i set pessoa_chave = m.rot
             from menor m where m.no = i.no and m.rot < i.pessoa_chave returning i.no)
    insert into pg_temp._idt_mud2 select no from up;
    get diagnostics v_mudou = row_count;
    truncate pg_temp._idt_mud;
    insert into pg_temp._idt_mud select no from pg_temp._idt_mud2;
  end loop;
  analyze pg_temp._idt_no;

  create temp table _idt_sugestao (pessoa_a text, pessoa_b text, motivo text, evidencia text,
                                   primary key (pessoa_a, pessoa_b, motivo)) on commit drop;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.doc, i.pessoa_chave p
            from pg_temp._idt_tx t
            join pg_temp._idt_no i on i.no = 'e:' || t.email
           where t.vis and length(t.doc) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.doc not in (select no from pg_temp._idt_revisao)) x
    join (select t.doc, i.pessoa_chave p
            from pg_temp._idt_tx t
            join pg_temp._idt_no i on i.no = 'e:' || t.email
           where t.vis and length(t.doc) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from pg_temp._idt_no i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.tel, 11)
    from pg_temp._idt_tx t1
    join pg_temp._idt_tx t2 on right(t2.tel, 11) = right(t1.tel, 11) and t2.email <> t1.email
    join pg_temp._idt_no i1 on i1.no = 'e:' || t1.email
    join pg_temp._idt_no i2 on i2.no = 'e:' || t2.email
   where t1.vis and t2.vis and length(t1.tel) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into pg_temp._idt_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.nome
    from pg_temp._idt_tx t1
    join pg_temp._idt_tx t2
      on lower(public.unaccent(trim(t2.nome))) = lower(public.unaccent(trim(t1.nome)))
     and t2.email <> t1.email
    join pg_temp._idt_no i1 on i1.no = 'e:' || t1.email
    join pg_temp._idt_no i2 on i2.no = 'e:' || t2.email
   where t1.vis and t2.vis and length(trim(t1.nome)) >= 8 and position(' ' in trim(t1.nome)) > 0
     and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;

  -- 4) grava só a diferença. Sem truncate: quem lê fin.identidade não espera mais o recálculo
  --    (o truncate segurava ACCESS EXCLUSIVE a rodada inteira) e o WAL é só do que mudou.
  delete from fin.identidade_aresta f
   where not exists (select 1 from pg_temp._idt_aresta n where n.a = f.a and n.b = f.b and n.fonte = f.fonte);
  insert into fin.identidade_aresta (a, b, fonte)
  select n.a, n.b, n.fonte from pg_temp._idt_aresta n
   where not exists (select 1 from fin.identidade_aresta f where f.a = n.a and f.b = n.b and f.fonte = n.fonte);

  delete from fin.identidade_revisao f where not exists (select 1 from pg_temp._idt_revisao n where n.no = f.no);
  update fin.identidade_revisao f set motivo = n.motivo, emails = n.emails, calculado_em = now()
    from pg_temp._idt_revisao n
   where n.no = f.no and (f.motivo is distinct from n.motivo or f.emails is distinct from n.emails);
  insert into fin.identidade_revisao (no, motivo, emails)
  select n.no, n.motivo, n.emails from pg_temp._idt_revisao n
   where not exists (select 1 from fin.identidade_revisao f where f.no = n.no);

  delete from fin.identidade f where not exists (select 1 from pg_temp._idt_no n where n.no = f.no);
  update fin.identidade f set pessoa_chave = n.pessoa_chave, calculado_em = now()
    from pg_temp._idt_no n where n.no = f.no and f.pessoa_chave is distinct from n.pessoa_chave;
  insert into fin.identidade (no, pessoa_chave)
  select n.no, n.pessoa_chave from pg_temp._idt_no n
   where not exists (select 1 from fin.identidade f where f.no = n.no);

  delete from fin.identidade_sugestao f
   where not exists (select 1 from pg_temp._idt_sugestao n
                      where n.pessoa_a = f.pessoa_a and n.pessoa_b = f.pessoa_b and n.motivo = f.motivo);
  update fin.identidade_sugestao f set evidencia = n.evidencia, calculado_em = now()
    from pg_temp._idt_sugestao n
   where n.pessoa_a = f.pessoa_a and n.pessoa_b = f.pessoa_b and n.motivo = f.motivo
     and f.evidencia is distinct from n.evidencia;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select n.pessoa_a, n.pessoa_b, n.motivo, n.evidencia from pg_temp._idt_sugestao n
   where not exists (select 1 from fin.identidade_sugestao f
                      where f.pessoa_a = n.pessoa_a and f.pessoa_b = n.pessoa_b and f.motivo = n.motivo);

  select jsonb_build_object(
    'rodadas', v_rodada,
    'nos', (select count(*) from pg_temp._idt_no),
    'pessoas', (select count(distinct pessoa_chave) from pg_temp._idt_no),
    'emails_hotmart', (select count(distinct t.email) from pg_temp._idt_tx t),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from pg_temp._idt_no i
                          where i.no in (select 'e:' || t.email from pg_temp._idt_tx t)),
    'arestas', (select count(*) from pg_temp._idt_aresta),
    'revisao', (select count(*) from pg_temp._idt_revisao),
    'sugestoes', (select count(*) from pg_temp._idt_sugestao)) into r;
  drop table if exists pg_temp._idt_tx, pg_temp._idt_aresta, pg_temp._idt_revisao,
                       pg_temp._idt_no, pg_temp._idt_mud, pg_temp._idt_mud2, pg_temp._idt_sugestao;
  return r;
end
$function$;

revoke all on function fin.recalcular_identidade() from public, anon, authenticated, service_role;
comment on function fin.recalcular_identidade() is
  '20261009001000: identidade recalculada em tabelas temporárias e gravada por diferença (sem truncate). Cron 54, :47.';

-- ═══ fim da migration ═══
-- estraga as 4 tabelas (some, muda, sobra)
delete from fin.identidade where no in (select no from fin.identidade order by md5(no) limit 500);
update fin.identidade set pessoa_chave = 'x:perturbado' where no in (select no from fin.identidade order by md5(no) offset 500 limit 300);
insert into fin.identidade (no, pessoa_chave) values ('e:ensaio@exemplo.invalid', 'e:ensaio@exemplo.invalid');
delete from fin.identidade_aresta where (a, b, fonte) in (select a, b, fonte from fin.identidade_aresta order by md5(a || b) limit 200);
insert into fin.identidade_aresta (a, b, fonte) values ('e:ensaio@exemplo.invalid', 'd:00000000000', 'ensaio');
update fin.identidade_revisao set motivo = motivo || ' (perturbado)' where no in (select no from fin.identidade_revisao order by md5(no) limit 5);
update fin.identidade_revisao set emails = coalesce(emails, 0) + 1 where no in (select no from fin.identidade_revisao order by md5(no) offset 5 limit 3);
delete from fin.identidade_revisao where no in (select no from fin.identidade_revisao order by md5(no) offset 8 limit 3);
insert into fin.identidade_revisao (no, motivo, emails) values ('d:00000000000', 'ensaio', 1);
delete from fin.identidade_sugestao where (pessoa_a, pessoa_b, motivo) in
  (select pessoa_a, pessoa_b, motivo from fin.identidade_sugestao order by md5(pessoa_a || pessoa_b) limit 50);
update fin.identidade_sugestao set evidencia = 'perturbado' where (pessoa_a, pessoa_b, motivo) in
  (select pessoa_a, pessoa_b, motivo from fin.identidade_sugestao order by md5(pessoa_a || pessoa_b) offset 50 limit 20);
insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia) values ('e:a@exemplo.invalid', 'e:b@exemplo.invalid', 'ensaio', 'x');
create temp table _s0 on commit drop as
select relname, n_tup_ins, n_tup_upd, n_tup_del from pg_stat_xact_user_tables where schemaname = 'fin' and relname like 'identidade%';
create temp table _t on commit drop as select clock_timestamp() t0;
create temp table _r on commit drop as select fin.recalcular_identidade() r;
insert into pg_temp._ens select 'T6 tempo da função nova (ms, temp_buffers padrão = cron)', true,
       round(extract(epoch from clock_timestamp() - t0) * 1000)::text from pg_temp._t;
create temp table _s1 on commit drop as
select relname, n_tup_ins, n_tup_upd, n_tup_del from pg_stat_xact_user_tables where schemaname = 'fin' and relname like 'identidade%';
insert into pg_temp._ens
select 'T7 consertou só o estragado: ' || s1.relname, true,
       'ins ' || (s1.n_tup_ins - s0.n_tup_ins) || ' upd ' || (s1.n_tup_upd - s0.n_tup_upd) || ' del ' || (s1.n_tup_del - s0.n_tup_del)
  from pg_temp._s1 s1 join pg_temp._s0 s0 using (relname);

create temp table _md5 on commit drop as
select 'identidade' t, (select md5(string_agg(no||'|'||pessoa_chave, ',' order by no)) from fin.identidade) real_,
       (select md5(string_agg(no||'|'||pessoa_chave, ',' order by no)) from pg_temp.ref_identidade) ref_
union all select 'identidade_aresta',
  (select md5(string_agg(a||'|'||b||'|'||fonte, ',' order by a,b,fonte)) from fin.identidade_aresta),
  (select md5(string_agg(a||'|'||b||'|'||fonte, ',' order by a,b,fonte)) from pg_temp.ref_identidade_aresta)
union all select 'identidade_revisao',
  (select md5(string_agg(no||'|'||motivo||'|'||coalesce(emails::text,'-'), ',' order by no)) from fin.identidade_revisao),
  (select md5(string_agg(no||'|'||motivo||'|'||coalesce(emails::text,'-'), ',' order by no)) from pg_temp.ref_identidade_revisao)
union all select 'identidade_sugestao',
  (select md5(string_agg(pessoa_a||'|'||pessoa_b||'|'||motivo||'|'||evidencia, ',' order by pessoa_a,pessoa_b,motivo)) from fin.identidade_sugestao),
  (select md5(string_agg(pessoa_a||'|'||pessoa_b||'|'||motivo||'|'||evidencia, ',' order by pessoa_a,pessoa_b,motivo)) from pg_temp.ref_identidade_sugestao);
insert into pg_temp._ens select 'T8 depois do estrago md5 '||t, real_ = ref_, left(real_,8)||' = '||left(ref_,8) from pg_temp._md5;
drop table pg_temp._md5;

update pg_temp._t set t0 = clock_timestamp();
create temp table _s2 on commit drop as
select relname, n_tup_ins, n_tup_upd, n_tup_del from pg_stat_xact_user_tables where schemaname = 'fin' and relname like 'identidade%';
select fin.recalcular_identidade();
insert into pg_temp._ens select 'T9 2ª rodada sem mudança (ms)', true,
       round(extract(epoch from clock_timestamp() - t0) * 1000)::text from pg_temp._t;
insert into pg_temp._ens
select 'T10 2ª rodada não escreve nada', sum((s3.n_tup_ins - s2.n_tup_ins) + (s3.n_tup_upd - s2.n_tup_upd) + (s3.n_tup_del - s2.n_tup_del)) = 0,
       'linhas escritas: ' || sum((s3.n_tup_ins - s2.n_tup_ins) + (s3.n_tup_upd - s2.n_tup_upd) + (s3.n_tup_del - s2.n_tup_del))
  from (select relname, n_tup_ins, n_tup_upd, n_tup_del from pg_stat_xact_user_tables
         where schemaname = 'fin' and relname like 'identidade%') s3 join pg_temp._s2 s2 using (relname);
insert into pg_temp._ens
select 'T11 jsonb da função nova = contagem das tabelas', (r ->> 'nos')::int = (select count(*) from fin.identidade)
       and (r ->> 'arestas')::int = (select count(*) from fin.identidade_aresta)
       and (r ->> 'revisao')::int = (select count(*) from fin.identidade_revisao)
       and (r ->> 'sugestoes')::int = (select count(*) from fin.identidade_sugestao), r::text from pg_temp._r;
select json_agg(_ens) from pg_temp._ens;
rollback;
