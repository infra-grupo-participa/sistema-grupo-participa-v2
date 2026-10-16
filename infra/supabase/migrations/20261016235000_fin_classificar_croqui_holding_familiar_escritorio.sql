-- 20261016235000: produto Hotmart 1537308 "Croqui Estrutural para Holding Familiar" (conta academy) passa de OUTROS para ESCRITORIO
--
-- STATUS: APLICADA em 16/10/2026 13:20 UTC (aplica_sql.py aplicar, transação única, registrada em schema_migrations).
--   Decisão do Victor em 16/10/2026 ("é escritorio"), a mesma da 20261016233000 (Holding Familiar 3595938).
-- POR QUE (medido em 16/10/2026): o produto está em fin.produtos com familia 'OUTROS', sincroniza = false e nota "aguarda classificação";
--   0 transações em fin.hotmart_transacoes, então não há linha em pessoas.eventos para marcar. A mudança vale para venda futura: com ela
--   pessoas.hotmart_setor('1537308') passa a devolver 'escritorio' e o webhook e a carga tratam a venda como escritório.
-- O QUE FAZ: só a linha do 1537308 em fin.produtos (familia e nota), com a linha anterior no backup. NÃO mexe em sincroniza.
-- GUARDA: produto existe como Croqui / academy / OUTROS; exatamente 4 produtos já em ESCRITORIO; 0 transações; backup ainda não existe.
-- PÓS-CONDIÇÃO: 5 produtos em ESCRITORIO; hotmart_setor('1537308') = 'escritorio'; sincroniza inalterado; backup com 1 linha.
-- AS 5 PERGUNTAS: escala = 1 linha; índice = PK de fin.produtos; frequência = única; repetição = a guarda recusa; reversão =
--   20261016235000_reversao.sql.
-- Backup: arquivo.fin_produtos__20261016_235000, dono Victor Hugo, prazo 2027-01-14, RLS ligado e sem policy.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regprocedure('pessoas.hotmart_setor(text)') is null then
    raise exception '20261016235000: falta pessoas.hotmart_setor (20261016230100)';
  end if;
  if (select count(*) from fin.produtos where produto_id = '1537308' and conta = 'academy' and familia = 'OUTROS'
        and nome = 'Croqui Estrutural para Holding Familiar') <> 1 then
    raise exception '20261016235000: o 1537308 não está como Croqui Estrutural para Holding Familiar / academy / OUTROS; já rodou ou o catálogo mudou';
  end if;
  if (select count(*) from fin.produtos where familia = 'ESCRITORIO') <> 4 then
    raise exception '20261016235000: esperava exatamente 4 produtos em ESCRITORIO (medido em 16/10); revisar';
  end if;
  if (select count(*) from fin.hotmart_transacoes where produto_id::text = '1537308') <> 0 then
    raise exception '20261016235000: o 1537308 passou a ter transação; esta migration não marca pessoas.eventos, revisar';
  end if;
  if to_regclass('arquivo.fin_produtos__20261016_235000') is not null then
    raise exception '20261016235000: backup arquivo.fin_produtos__20261016_235000 já existe; já rodou?';
  end if;
end $g$;

create table arquivo.fin_produtos__20261016_235000 as
  select p.*, null::text as motivo from fin.produtos p where false;
alter table arquivo.fin_produtos__20261016_235000 enable row level security;
revoke all on arquivo.fin_produtos__20261016_235000 from public, anon, authenticated;
comment on table arquivo.fin_produtos__20261016_235000 is
  '20261016235000: linha de fin.produtos antes de mudar o 1537308 Croqui Estrutural para Holding Familiar de OUTROS para ESCRITORIO (motivo: familia_alterada). dono: Victor Hugo · prazo: 2027-01-14 · reversão: 20261016235000_reversao.sql';

with salva as (
  insert into arquivo.fin_produtos__20261016_235000
    select p.*, 'familia_alterada' from fin.produtos p where p.produto_id = '1537308' and p.familia = 'OUTROS' returning produto_id
)
update fin.produtos x
   set familia = 'ESCRITORIO', nota = 'Decisão do Victor em 16/10/2026: produto do escritório (migration 20261016235000).'
  from salva where x.produto_id = salva.produto_id and x.familia = 'OUTROS';

do $p$
begin
  if (select count(*) from arquivo.fin_produtos__20261016_235000 where motivo = 'familia_alterada' and produto_id = '1537308') <> 1 then
    raise exception '20261016235000: backup sem a linha do 1537308; desfeito';
  end if;
  if (select count(*) from fin.produtos where familia = 'ESCRITORIO') <> 5 then
    raise exception '20261016235000: produtos em ESCRITORIO diferente de 5; desfeito';
  end if;
  if pessoas.hotmart_setor('1537308') is distinct from 'escritorio' then
    raise exception '20261016235000: hotmart_setor(1537308) não devolveu escritorio; desfeito';
  end if;
  if (select p.sincroniza from fin.produtos p where p.produto_id = '1537308') is distinct from
     (select b.sincroniza from arquivo.fin_produtos__20261016_235000 b where b.produto_id = '1537308') then
    raise exception '20261016235000: sincroniza mudou; desfeito';
  end if;
end $p$;
