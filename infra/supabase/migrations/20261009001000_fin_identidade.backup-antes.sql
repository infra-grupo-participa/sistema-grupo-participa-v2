-- BACKUP de fin.recalcular_identidade() antes de 20261009001000_fin_identidade_rapida — lido em 08/10/2026 ~21:10 UTC
-- (pg_get_functiondef, projeto mbvybujpkwuorhtdzcde). md5(prosrc) = 203c6f02285e76595ac22ea1ee688650
-- ACL viva: {postgres=X/postgres} (PUBLIC, anon, authenticated e service_role SEM execute).
-- Cron: jobid 54 'fin-identidade-recalcular', '47 * * * *', ' select fin.recalcular_identidade() ' (não muda).
CREATE OR REPLACE FUNCTION fin.recalcular_identidade()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_rodada int := 0; v_mudou bigint; r jsonb;
begin
  truncate fin.identidade_aresta;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'd:' || t.comprador_documento, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and length(t.comprador_documento) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'u:' || t.comprador_ucode, 'hotmart'
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null and t.comprador_ucode is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'd:' || regexp_replace(a.documento, '\D', '', 'g'), 'thb_alunos'
    from public.thb_alunos a
   where a.email is not null and length(regexp_replace(coalesce(a.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(a.email)), 'e:' || lower(trim(c.email)), 'thb_alunos.comprador_id'
    from public.thb_alunos a join public.compradores c on c.id = a.comprador_id
   where a.email is not null and c.email is not null and lower(trim(a.email)) <> lower(trim(c.email))
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;
  -- (removida) rede.perfis.aluno_thb_email é autodeclarado: não é fonte de identidade
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;

  truncate fin.identidade_revisao;
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from fin.identidade_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  -- z42: ponte entre CPFs (e-mail de escritório/cônjuge) nunca junta duas pessoas
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'ponte entre CPFs: e-mail ligado a ' || x.n || ' CPFs diferentes — não juntado', null
    from (select e.no, count(distinct e.cpf) n
            from (select a no, b cpf from fin.identidade_aresta where a like 'e:%' and b ~ '^d:\d{11}$'
                  union select b, a from fin.identidade_aresta where b like 'e:%' and a ~ '^d:\d{11}$') e
           where e.cpf not in (select valor from fin.identidade_bloqueio)
             and e.cpf not in (select no from fin.identidade_revisao)
           group by e.no having count(distinct e.cpf) > 1) x
  on conflict (no) do nothing;
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'CNPJ ponte entre CPFs: alcança ' || x.n || ' CPFs pelos e-mails — não juntado', null
    from (select c.b no, count(distinct p.b) n
            from fin.identidade_aresta c
            join fin.identidade_aresta p on p.a = c.a and p.b ~ '^d:\d{11}$'
           where c.b ~ '^d:\d{14}$' and c.a like 'e:%'
             and c.a not in (select no from fin.identidade_revisao)
             and p.b not in (select valor from fin.identidade_bloqueio)
             and p.b not in (select no from fin.identidade_revisao)
           group by c.b having count(distinct p.b) > 1) x
  on conflict (no) do nothing;
  insert into fin.identidade_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from fin.identidade_aresta ar
   where ar.a in (select no from fin.identidade_revisao) or ar.b in (select no from fin.identidade_revisao);

  truncate fin.identidade;
  insert into fin.identidade (no, pessoa_chave)
  select n, n from (select a n from fin.identidade_aresta union select b from fin.identidade_aresta) x;
  insert into fin.identidade (no, pessoa_chave)
  select distinct 'e:' || lower(trim(t.comprador_email)), 'e:' || lower(trim(t.comprador_email))
    from fin.hotmart_transacoes_identidade t where t.comprador_email is not null
  on conflict (no) do nothing;

  loop
    v_rodada := v_rodada + 1;
    if v_rodada > 40 then
      raise exception 'fin.recalcular_identidade: não convergiu em 40 rodadas. Nada confirmado.';
    end if;
    with viz as (
      select ar.a no, i.pessoa_chave rot from fin.identidade_aresta ar join fin.identidade i on i.no = ar.b
      union all
      select ar.b, i.pessoa_chave from fin.identidade_aresta ar join fin.identidade i on i.no = ar.a
    ), menor as (select no, min(rot) rot from viz group by no)
    update fin.identidade i set pessoa_chave = m.rot
      from menor m where m.no = i.no and m.rot < i.pessoa_chave;
    get diagnostics v_mudou = row_count;
    exit when v_mudou = 0;
  end loop;

  truncate fin.identidade_sugestao;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.comprador_documento not in (select no from fin.identidade_revisao)) x
    join (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes_identidade t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from fin.identidade i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.comprador_telefone, 11)
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2 on right(t2.comprador_telefone, 11) = right(t1.comprador_telefone, 11)
                                   and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join fin.identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join fin.identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(t1.comprador_telefone) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.comprador_nome
    from fin.hotmart_transacoes_identidade t1
    join fin.hotmart_transacoes_identidade t2
      on lower(public.unaccent(trim(t2.comprador_nome))) = lower(public.unaccent(trim(t1.comprador_nome)))
     and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join fin.identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join fin.identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(trim(t1.comprador_nome)) >= 8 and position(' ' in trim(t1.comprador_nome)) > 0
     and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;

  update fin.identidade set calculado_em = now();
  select jsonb_build_object(
    'rodadas', v_rodada,
    'nos', (select count(*) from fin.identidade),
    'pessoas', (select count(distinct pessoa_chave) from fin.identidade),
    'emails_hotmart', (select count(distinct lower(trim(comprador_email))) from fin.hotmart_transacoes where conta = 'academy'),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from fin.identidade i
                          where i.no in (select 'e:' || lower(trim(comprador_email)) from fin.hotmart_transacoes where conta = 'academy')),
    'arestas', (select count(*) from fin.identidade_aresta),
    'revisao', (select count(*) from fin.identidade_revisao),
    'sugestoes', (select count(*) from fin.identidade_sugestao)) into r;
  return r;
end $function$;
revoke all on function fin.recalcular_identidade() from public, anon, authenticated, service_role;
