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
