-- Reversão da 20261014200000: tira o gatilho, a função, a coluna etiqueta e o de-para.
-- A etiqueta gravada nas inscrições se perde (é derivada da origem; reaplicar a migration a recompõe).

do $g$
begin
  if to_regclass('metodo.origem_etiqueta') is null then
    raise exception 'reversão 20261014200000: metodo.origem_etiqueta não existe; nada a reverter';
  end if;
end
$g$;

drop trigger if exists pesquisa_respostas_etiqueta on metodo.pesquisa_respostas;
drop function if exists metodo.pesquisa_respostas_etiqueta();
alter table metodo.pesquisa_respostas drop column if exists etiqueta;
drop table if exists metodo.origem_etiqueta;
delete from supabase_migrations.schema_migrations where version = '20261014200000';
