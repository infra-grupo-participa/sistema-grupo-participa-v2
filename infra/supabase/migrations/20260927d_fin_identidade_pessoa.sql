-- 20260927d — Identidade da pessoa no financeiro: e-mails diferentes, mesma pessoa.
--
-- Pedido do João (27/09): "procure e-mails que têm relação, que provavelmente são da
-- mesma pessoa… dentro do board financeiro tem que ter tudo mapeado da pessoa".
--
-- Régua do cérebro (disparos-brain/"Identidade da pessoa é o componente conexo", 0251):
-- nenhum campo isolado é identidade. E-mail, documento e conta Hotmart (ucode) são NÓS;
-- cada fato que liga dois deles é uma ARESTA com a FONTE anotada. A pessoa é o componente
-- conexo, calculado por propagação de rótulo até estabilizar (falha alto se não convergir).
--
-- O que NÃO junta (vira sugestão/revisão, nunca merge automático):
--   · documento na lista de bloqueio (compartilhado por pessoas diferentes — ex. 0239);
--   · documento que liga e-mails demais (> 6): provável CNPJ de escritório/contador;
--   · CNPJ vindo da base de alunos (Marisa × Gilton dividem o CNPJ da GPS Contadores);
--   · telefone e nome iguais: só SUGESTÃO para conferência humana.
--
-- Só escreve no schema fin. Não mescla cadastro nenhum (thb_alunos, compradores, cards).

create table if not exists fin.identidade_bloqueio (
  valor  text primary key,           -- 'd:<digitos>' ou 'e:<email>'
  motivo text not null,
  criado_em timestamptz not null default now()
);
insert into fin.identidade_bloqueio (valor, motivo) values
  ('d:08834775724', '0239: documento compartilhado por duas pessoas diferentes'),
  ('d:53646257000181', '0239: CNPJ compartilhado por duas pessoas diferentes'),
  ('d:00000000000', 'documento inválido'), ('d:11111111111', 'documento inválido'),
  ('d:12345678909', 'documento de teste')
on conflict (valor) do nothing;

create table if not exists fin.identidade_aresta (
  a text not null, b text not null, fonte text not null,
  primary key (a, b, fonte)
);

create table if not exists fin.identidade (
  no            text primary key,     -- 'e:<email>' | 'd:<documento>' | 'u:<ucode hotmart>'
  pessoa_chave  text not null,
  calculado_em  timestamptz not null default now()
);
create index if not exists identidade_pessoa_idx on fin.identidade (pessoa_chave);

create table if not exists fin.identidade_sugestao (
  pessoa_a text not null, pessoa_b text not null, motivo text not null, evidencia text,
  calculado_em timestamptz not null default now(),
  primary key (pessoa_a, pessoa_b, motivo)
);

create table if not exists fin.identidade_revisao (
  no text primary key, motivo text not null, emails int, calculado_em timestamptz not null default now()
);

revoke all on fin.identidade_bloqueio, fin.identidade_aresta, fin.identidade, fin.identidade_sugestao, fin.identidade_revisao
  from public, anon, authenticated;

create or replace function fin.recalcular_identidade()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rodada int := 0; v_mudou bigint; r jsonb;
begin
  truncate fin.identidade_aresta;

  -- 1. Hotmart (espelho): e-mail × documento × conta Hotmart.
  --    Documento só de transação EFETIVA: numa tentativa recusada/cancelada qualquer um digita o CPF
  --    de outra pessoa, e a aresta juntaria o e-mail do atacante ao histórico da vítima (pentest 27/09).
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'd:' || t.comprador_documento, 'hotmart'
    from fin.hotmart_transacoes t
   where t.comprador_email is not null and length(t.comprador_documento) in (11, 14)
     and t.status in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(t.comprador_email)), 'u:' || t.comprador_ucode, 'hotmart'
    from fin.hotmart_transacoes t
   where t.comprador_email is not null and t.comprador_ucode is not null
  on conflict do nothing;

  -- 2. Compradores do webhook
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'd:' || regexp_replace(c.documento, '\D', '', 'g'), 'compradores'
    from public.compradores c
   where c.email is not null and length(regexp_replace(coalesce(c.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c.email)), 'u:' || c.hotmart_ucode, 'compradores'
    from public.compradores c where c.email is not null and c.hotmart_ucode is not null
  on conflict do nothing;

  -- 3. Base de alunos: só CPF (CNPJ da base é compartilhado entre pessoas); e o comprador vinculado
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

  -- 4. Apelidos já catalogados pela operação (comprador duplicado → canônico)
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(c1.email)), 'e:' || lower(trim(c2.email)), 'cs.hm_comprador_alias'
    from cs.hm_comprador_alias al
    join public.compradores c1 on c1.id = al.comprador_id
    join public.compradores c2 on c2.id = al.canonico_id
   where c1.email is not null and c2.email is not null
  on conflict do nothing;

  -- 5. Identidade já conciliada do Aurum (0251) e o retrato dos exports (0248)
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(i.email)), 'd:' || regexp_replace(i.documento, '\D', '', 'g'), 'cs.hotmart_identidade'
    from cs.hotmart_identidade i
   where i.email is not null and length(regexp_replace(coalesce(i.documento,''), '\D', '', 'g')) in (11, 14)
  on conflict do nothing;

  -- 6. Login do GPS do titular ↔ cadastro dele
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(u.email), 'e:' || lower(trim(a.email)), 'gps.membros(titular)'
    from gps.membros m
    join auth.users u on u.id = m.user_id
    join public.thb_alunos a on a.id = coalesce(m.pessoa_aluno_id, m.aluno_id)
   where m.papel = 'titular' and u.email is not null and a.email is not null
     and lower(u.email) <> lower(trim(a.email))
  on conflict do nothing;

  -- 7. Importação histórica da Central do Aluno (só CPF)
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(ci.email)), 'd:' || regexp_replace(ci.documento, '\D', '', 'g'), 'cs.central_alunos_import'
    from cs.central_alunos_import ci
   where ci.email is not null and length(regexp_replace(coalesce(ci.documento,''), '\D', '', 'g')) = 11
  on conflict do nothing;

  -- 8. (removida em 27/09) rede.perfis.aluno_thb_email é AUTODECLARADO pela pessoa na Rede:
  --    qualquer um declararia o e-mail de outra e herdaria o histórico dela. Não é fonte de identidade.

  -- 9. Login do SIP ↔ e-mail do cadastro SIP
  insert into fin.identidade_aresta
  select distinct 'e:' || lower(trim(su.email)), 'e:' || lower(u.email), 'sip_users.auth_id'
    from public.sip_users su join auth.users u on u.id = su.auth_id
   where su.email is not null and u.email is not null and lower(trim(su.email)) <> lower(u.email)
  on conflict do nothing;

  -- Tira arestas de nós bloqueados e de documentos que ligam e-mails demais (revisão humana)
  truncate fin.identidade_revisao;
  insert into fin.identidade_revisao (no, motivo, emails)
  select x.no, 'documento ligado a ' || x.n || ' e-mails (provável escritório/contador) — não juntado', x.n
    from (select b as no, count(distinct a) n from fin.identidade_aresta where b like 'd:%' and a like 'e:%' group by b) x
   where x.n > 6;
  insert into fin.identidade_revisao (no, motivo, emails)
  select b.valor, 'bloqueado: ' || b.motivo, null from fin.identidade_bloqueio b
  on conflict (no) do nothing;
  delete from fin.identidade_aresta ar
   where ar.a in (select no from fin.identidade_revisao) or ar.b in (select no from fin.identidade_revisao);

  -- Propagação de rótulo (componente conexo). Rótulo inicial = o próprio nó; vence o menor.
  truncate fin.identidade;
  insert into fin.identidade (no, pessoa_chave)
  select n, n from (select a n from fin.identidade_aresta union select b from fin.identidade_aresta) x;
  -- Todo e-mail que aparece no espelho vira nó, mesmo sem aresta (pessoa de um e-mail só)
  insert into fin.identidade (no, pessoa_chave)
  select distinct 'e:' || lower(trim(t.comprador_email)), 'e:' || lower(trim(t.comprador_email))
    from fin.hotmart_transacoes t where t.comprador_email is not null
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

  -- Sugestões (NÃO juntam): mesmo telefone ou mesmo nome em pessoas diferentes
  truncate fin.identidade_sugestao;
  -- CPF digitado em tentativa NÃO paga não junta ninguém (qualquer um digita o CPF de outro),
  -- mas vira sugestão para a equipe conferir: é o caso comum de quem tenta com um e-mail e paga com outro.
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(x.p, y.p), greatest(x.p, y.p), 'mesmo_documento_tentativa', x.doc
    from (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
             and t.status not in ('APPROVED','COMPLETE','REFUNDED','CHARGEBACK','PARTIALLY_REFUNDED','PROTESTED','OVERDUE')
             and 'd:' || t.comprador_documento not in (select no from fin.identidade_revisao)) x
    join (select t.comprador_documento doc, i.pessoa_chave p
            from fin.hotmart_transacoes t
            join fin.identidade i on i.no = 'e:' || lower(trim(t.comprador_email))
           where length(t.comprador_documento) in (11, 14)
          union
          select substr(i.no, 3), i.pessoa_chave from fin.identidade i where i.no like 'd:%') y
      on y.doc = x.doc and y.p <> x.p
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_telefone', right(t1.comprador_telefone, 11)
    from fin.hotmart_transacoes t1
    join fin.hotmart_transacoes t2 on right(t2.comprador_telefone, 11) = right(t1.comprador_telefone, 11)
                                   and lower(trim(t2.comprador_email)) <> lower(trim(t1.comprador_email))
    join fin.identidade i1 on i1.no = 'e:' || lower(trim(t1.comprador_email))
    join fin.identidade i2 on i2.no = 'e:' || lower(trim(t2.comprador_email))
   where length(t1.comprador_telefone) >= 10 and i1.pessoa_chave <> i2.pessoa_chave
  on conflict do nothing;
  insert into fin.identidade_sugestao (pessoa_a, pessoa_b, motivo, evidencia)
  select distinct least(i1.pessoa_chave, i2.pessoa_chave), greatest(i1.pessoa_chave, i2.pessoa_chave),
         'mesmo_nome', t1.comprador_nome
    from fin.hotmart_transacoes t1
    join fin.hotmart_transacoes t2
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
    'emails_hotmart', (select count(distinct lower(trim(comprador_email))) from fin.hotmart_transacoes),
    'pessoas_hotmart', (select count(distinct i.pessoa_chave) from fin.identidade i
                          where i.no in (select 'e:' || lower(trim(comprador_email)) from fin.hotmart_transacoes)),
    'arestas', (select count(*) from fin.identidade_aresta),
    'revisao', (select count(*) from fin.identidade_revisao),
    'sugestoes', (select count(*) from fin.identidade_sugestao)) into r;
  return r;
end $$;
revoke all on function fin.recalcular_identidade() from public, anon, authenticated;

-- Recalcula todo dia depois da rotina das 4h.
select cron.schedule('fin-identidade-recalcular', '37 4 * * *', $$ select fin.recalcular_identidade() $$);
