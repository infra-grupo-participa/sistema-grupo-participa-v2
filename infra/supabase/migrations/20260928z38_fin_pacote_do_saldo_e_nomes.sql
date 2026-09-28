-- 20260928z38 — Polimento, rodada 2 (28/09).
--
-- 1) Pacote 0 em quem pagou só a oferta de SALDO (pós-Acelera, "saldo individual do Programa"): 36 cards HM mostravam
--    pacote R$ 0 e "quitado" com R$ 12 mil pagos. Causa: cs.fn_hm_valores_derivados só conhecia sinal e compra cheia —
--    sem nenhum dos dois, o total virava v_cheia = 0 e cs.fn_hm_recalcular_financeiro gravava 0 em contatos_hm.valor_total
--    (o buraco virou número). O saldo pós-Acelera JÁ é o pacote da pessoa (calculado a partir do que ela pagou do Acelera):
--    sem sinal, sem compra cheia e sem parcelamento Hotmart, o pacote é a soma dos saldos pagos.
--    Corrige a função (a classe) e recalcula os 36 pelo caminho oficial (valor_total := null → recalcular deriva de novo).
--
-- 2) Nome de exibição: também troca nome de usuário (com dígito, sem espaço), nome de uma palavra só e
--    repetição com acento diferente ("Luís … Luis …"); medido: 6 cards pelo nome da pessoa nas compras/base de alunos.
do $do$
declare d text;
begin
  d := pg_get_functiondef('cs.fn_hm_valores_derivados(uuid,text)'::regprocedure);
  if position('saldo_sem_sinal' in d) = 0 then
    d := replace(d,
      E'  elsif v_installments and v_cheia < 15000 then',
      E'  elsif v_cheia = 0 and v_soma > 0 and not v_installments then\n    v_total := v_soma;  -- saldo_sem_sinal (z38): o saldo pago é o pacote\n  elsif v_installments and v_cheia < 15000 then');
    if position('saldo_sem_sinal' in d) = 0 then raise exception 'z38: trecho de fn_hm_valores_derivados não encontrado'; end if;
    execute d;
  end if;
end $do$;

do $do$
declare r record; n int := 0;
begin
  for r in select distinct comprador_id from cs.contatos_hm
            where categoria_entrada = 'diferenca' and valor_total = 0 and coalesce(produto, 'HM') = 'HM'
  loop
    update cs.contatos_hm set valor_total = null
     where comprador_id = r.comprador_id and coalesce(produto, 'HM') = 'HM' and valor_total = 0;
    perform cs.fn_hm_recalcular_financeiro(r.comprador_id);
    n := n + 1;
  end loop;
  raise notice 'z38: % cards de saldo recalculados', n;
end $do$;

create or replace function fin.nome_sem_repeticao(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare w text[]; r text[] := '{}'; i int; k int; n int; mudou boolean := true;
begin
  if p is null then return null; end if;
  w := regexp_split_to_array(btrim(regexp_replace(p, '\s+', ' ', 'g')), ' ');
  foreach i in array array(select generate_subscripts(w, 1)) loop
    if array_length(r, 1) is null
       or lower(public.unaccent('public.unaccent'::regdictionary, r[array_length(r, 1)]))
          <> lower(public.unaccent('public.unaccent'::regdictionary, w[i])) then
      r := r || w[i];
    end if;
  end loop;
  while mudou loop
    mudou := false;
    n := coalesce(array_length(r, 1), 0);
    for k in reverse (n / 2)..2 loop
      if lower(public.unaccent('public.unaccent'::regdictionary, array_to_string(r[n - k + 1:n], ' ')))
         = lower(public.unaccent('public.unaccent'::regdictionary, array_to_string(r[n - 2 * k + 1:n - k], ' '))) then
        r := r[1:n - k]; mudou := true; exit;
      end if;
    end loop;
  end loop;
  return array_to_string(r, ' ');
end $$;

-- nome que não serve para identificar a pessoa: empresa, com dígito, ou uma palavra só
create or replace function fin.nome_ruim(p text)
returns boolean language sql immutable set search_path = '' as $$
  select p is null or fin.nome_de_empresa(p) or p ~ '\d' or btrim(p) !~ '\S+\s+\S+'
$$;

create or replace function fin.nome_da_pessoa(p_email text)
returns text language sql stable set search_path = '' as $$
  with em as (
    select distinct coalesce(substr(i2.no, 3), lower(btrim(p_email))) email
      from (select lower(btrim(p_email)) e) x
      left join fin.identidade i on i.no = 'e:' || x.e
      left join fin.identidade i2 on i2.pessoa_chave = i.pessoa_chave and i2.no like 'e:%'
  ), cpfs as (
    select distinct regexp_replace(h.comprador_documento, '\D', '', 'g') cpf
      from em join fin.hotmart_transacoes h on lower(btrim(h.comprador_email)) = em.email
     where length(regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g')) = 11
  ), nomes as (
    select btrim(h.comprador_nome) nome from em join fin.hotmart_transacoes h on lower(btrim(h.comprador_email)) = em.email
    union all
    select btrim(h.comprador_nome) from cpfs join fin.hotmart_transacoes h
        on regexp_replace(coalesce(h.comprador_documento, ''), '\D', '', 'g') = cpfs.cpf
    union all
    select btrim(a.nome) from em join public.thb_alunos a on lower(btrim(a.email)) = em.email
    union all
    select btrim(c.nome) from em join public.compradores c on lower(btrim(c.email)) = em.email
  )
  select fin.nome_proprio(fin.nome_sem_repeticao(n.nome))
    from nomes n
   where not fin.nome_ruim(n.nome)
   group by lower(fin.nome_sem_repeticao(n.nome)), n.nome
   order by count(*) desc, length(n.nome) desc
   limit 1
$$;

create or replace function fin.nome_exibicao(p_nome text, p_email text)
returns text language sql stable set search_path = '' as $$
  select fin.nome_proprio(fin.nome_sem_repeticao(
           case when fin.nome_ruim(p_nome) then coalesce(fin.nome_da_pessoa(p_email), p_nome) else p_nome end))
$$;
