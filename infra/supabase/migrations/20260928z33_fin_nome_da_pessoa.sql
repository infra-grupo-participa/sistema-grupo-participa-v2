-- 20260928z33 — O financeiro mostra o NOME DA PESSOA responsável pela compra, nunca o do escritório (João, 28/09:
-- "não quero nome de escritório no nome de uma pessoa, deve conter o nome da pessoa responsável pela compra").
-- Também limpa nome com pedaço repetido de cadastro concatenado (sobrenome repetido no fim,
-- ou o bloco "nome do meio + sobrenome" repetido duas vezes).
-- Só EXIBIÇÃO: public.compradores / thb_alunos / cs não são alterados (são de outros sistemas).
--
-- fin.nome_sem_repeticao(nome): tira palavra repetida em sequência e bloco final repetido.
-- fin.nome_da_pessoa(email): melhor nome de pessoa física entre as compras da mesma pessoa (fin.identidade: e-mails,
--   e os CPFs dessas compras), a base de alunos e os compradores — descarta nome de empresa, prefere o mais usado.
-- fin.nome_exibicao(nome, email): nome de empresa → nome da pessoa (se houver); sempre sem repetição e em caixa própria.
create or replace function fin.nome_sem_repeticao(p text)
returns text language plpgsql immutable set search_path = '' as $$
declare w text[]; r text[] := '{}'; i int; k int; n int; mudou boolean := true;
begin
  if p is null then return null; end if;
  w := regexp_split_to_array(btrim(regexp_replace(p, '\s+', ' ', 'g')), ' ');
  foreach i in array array(select generate_subscripts(w, 1)) loop
    if array_length(r, 1) is null or lower(r[array_length(r, 1)]) <> lower(w[i]) then r := r || w[i]; end if;
  end loop;
  while mudou loop
    mudou := false;
    n := coalesce(array_length(r, 1), 0);
    for k in reverse (n / 2)..2 loop
      if lower(array_to_string(r[n - k + 1:n], ' ')) = lower(array_to_string(r[n - 2 * k + 1:n - k], ' ')) then
        r := r[1:n - k]; mudou := true; exit;
      end if;
    end loop;
  end loop;
  return array_to_string(r, ' ');
end $$;

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
   where n.nome is not null and not fin.nome_de_empresa(n.nome) and n.nome ~ '\S+\s+\S+'
   group by lower(fin.nome_sem_repeticao(n.nome)), n.nome
   order by count(*) desc, length(n.nome) desc
   limit 1
$$;

create or replace function fin.nome_exibicao(p_nome text, p_email text)
returns text language sql stable set search_path = '' as $$
  select fin.nome_proprio(fin.nome_sem_repeticao(
           case when fin.nome_de_empresa(p_nome) then coalesce(fin.nome_da_pessoa(p_email), p_nome) else p_nome end))
$$;
