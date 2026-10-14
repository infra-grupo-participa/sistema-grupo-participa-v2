-- 20261014200000: inscrição das páginas de captação (metodo.pesquisa_respostas) passa a levar a etiqueta do projeto.
-- Pedido do Victor (14/10, Black do THB com acesso vencido): a página timeholdingbrasil.com.br/renovacao já grava aqui
-- (api.php da dominiodometodo.com.br/oportunidade -> Edge metodo-perfeito, ação "reuniao", origem 'dp4-thb-vencidos'),
-- mas sem a etiqueta black-thb-2026-10. A etiqueta sai da origem por uma tabela de-para, preenchida por gatilho no
-- INSERT, sem mexer na Edge nem na página. Origem sem de-para fica com etiqueta nula (nada muda para as outras).
-- Reversão: 20261014200000_reversao.sql. Ver 20261014200000.explain.md.

do $g$
begin
  if to_regclass('metodo.pesquisa_respostas') is null then
    raise exception '20261014200000: metodo.pesquisa_respostas não existe; revisar';
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema = 'metodo' and table_name = 'pesquisa_respostas' and column_name = 'etiqueta') then
    raise exception '20261014200000: pesquisa_respostas.etiqueta já existe; revisar';
  end if;
  if to_regclass('metodo.origem_etiqueta') is not null then
    raise exception '20261014200000: metodo.origem_etiqueta já existe; revisar';
  end if;
  if exists (select 1 from pg_trigger where tgrelid = 'metodo.pesquisa_respostas'::regclass and not tgisinternal) then
    raise exception '20261014200000: pesquisa_respostas ganhou gatilho; revisar';
  end if;
end
$g$;

create table metodo.origem_etiqueta (
  origem    text primary key,
  etiqueta  text not null check (etiqueta ~ '^[a-z0-9]+(-[a-z0-9]+)*-20[0-9]{2}-[0-9]{2}$'),
  criado_em timestamptz not null default now()
);
comment on table metodo.origem_etiqueta is
  'De-para origem da inscrição (pesquisa_respostas.origem) -> etiqueta do projeto (a mesma do ClickUp e do utm_campaign). '
  'Lido pelo gatilho pesquisa_respostas_etiqueta no INSERT. Página nova: uma linha aqui.';
alter table metodo.origem_etiqueta enable row level security;
revoke all on metodo.origem_etiqueta from public, anon, authenticated;
grant select on metodo.origem_etiqueta to service_role;

insert into metodo.origem_etiqueta (origem, etiqueta) values ('dp4-thb-vencidos', 'black-thb-2026-10');

alter table metodo.pesquisa_respostas add column etiqueta text;
comment on column metodo.pesquisa_respostas.etiqueta is
  'Etiqueta do projeto da inscrição. Preenchida no INSERT pelo de-para metodo.origem_etiqueta quando vier nula.';

create function metodo.pesquisa_respostas_etiqueta()
 returns trigger
 language plpgsql
 set search_path to ''
as $function$
begin
  if new.etiqueta is null then
    select e.etiqueta into new.etiqueta from metodo.origem_etiqueta e where e.origem = new.origem;
  end if;
  return new;
end
$function$;
revoke execute on function metodo.pesquisa_respostas_etiqueta() from public, anon, authenticated;

create trigger pesquisa_respostas_etiqueta
  before insert on metodo.pesquisa_respostas
  for each row execute function metodo.pesquisa_respostas_etiqueta();

-- As inscrições que já chegaram pela origem mapeada recebem a etiqueta.
update metodo.pesquisa_respostas r
   set etiqueta = e.etiqueta
  from metodo.origem_etiqueta e
 where e.origem = r.origem and r.etiqueta is null;
