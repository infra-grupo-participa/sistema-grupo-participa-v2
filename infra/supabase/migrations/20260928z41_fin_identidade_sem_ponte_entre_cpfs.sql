-- 20260928z41 — Polimento, rodada 3: uma pessoa, um CPF.
-- O grafo de identidade tinha 66 "pessoas" com 2+ CPFs diferentes: e-mail de escritório usado por dois sócios
-- (contato@…, comercial@…), e-mail de um usado na compra com o CPF do cônjuge, CNPJ do escritório comprado por dois.
-- Fundir CPFs diferentes soma o dinheiro de duas pessoas num card/trajetória só (regra de 27/09: medir a fusão e
-- bloquear a ponte). Mede antes: 63 e-mails são vizinhos diretos de 2+ CPFs; depois de bloqueá-los, sobram 3 CNPJs
-- (escritórios) ligando dois CPFs por e-mails diferentes.
-- Efeito: 66 → 0 fusões suspeitas; 23.033 → ~23.065 pessoas. Custo aceito: a compra feita no e-mail bloqueado deixa de
-- ser atribuída por e-mail (continua pelo CPF, quando há). Reverter: delete from fin.identidade_bloqueio where motivo like '%(z41)%'
-- e select fin.recalcular_identidade().
do $do$
declare n int;
begin
  insert into fin.identidade_bloqueio (valor, motivo)
  select no, 'ligava dois CPFs diferentes (e-mail compartilhado) — polimento de dados, 28/09/2026 (z41)'
    from (with e as (select a x, b y from fin.identidade_aresta union select b, a from fin.identidade_aresta)
          select e.x no from e where e.y ~ '^d:\d{11}$' and e.x !~ '^d:\d{11}$'
           group by e.x having count(distinct e.y) > 1) p
  on conflict do nothing;
  perform fin.recalcular_identidade();

  insert into fin.identidade_bloqueio (valor, motivo)
  select distinct i.no, 'CNPJ de escritório ligando dois CPFs diferentes — polimento de dados, 28/09/2026 (z41)'
    from fin.identidade i
   where i.no ~ '^d:\d{14}$'
     and i.pessoa_chave in (select pessoa_chave from fin.identidade where no ~ '^d:\d{11}$' group by 1 having count(*) > 1)
  on conflict do nothing;
  perform fin.recalcular_identidade();

  select count(*) into n from (select pessoa_chave from fin.identidade where no ~ '^d:\d{11}$' group by 1 having count(*) > 1) x;
  raise notice 'z41: pessoas com 2+ CPFs depois: %', n;
end $do$;
