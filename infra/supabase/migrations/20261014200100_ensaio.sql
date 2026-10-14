begin;
create temp table _z_out (em serial, passo text, linha text);
-- 20261014200100: origem própria para a página timeholdingbrasil.com.br/renovacao ('renovacao-thb-vencidos'), separada da
-- /dp4 ('dp4-thb-vencidos'), com a mesma etiqueta black-thb-2026-10. Só o de-para: quem passa a gravar essa origem é a Edge
-- metodo-perfeito (ação "reuniao", campo pagina), em deploy separado. Antes do deploy, esta linha não tem efeito.
-- Reversão: 20261014200100_reversao.sql. Ver 20261014200000.explain.md.

do $g$
begin
  if to_regclass('metodo.origem_etiqueta') is null then
    raise exception '20261014200100: falta a 20261014200000 (metodo.origem_etiqueta)';
  end if;
  if exists (select 1 from metodo.origem_etiqueta where origem = 'renovacao-thb-vencidos') then
    raise exception '20261014200100: renovacao-thb-vencidos já está no de-para; revisar';
  end if;
end
$g$;

insert into metodo.origem_etiqueta (origem, etiqueta) values ('renovacao-thb-vencidos', 'black-thb-2026-10');
set local role service_role;
insert into metodo.pesquisa_respostas (nome, email, whatsapp, origem, token) values ('TESTE ensaio', 'teste.ensaio@advmais.com', '5521999999999', 'renovacao-thb-vencidos', 'ensaio200100');
reset role;
insert into pg_temp._z_out(passo, linha) select '1 insert com a origem nova', (select origem || ' / ' || coalesce(etiqueta, 'nula') from metodo.pesquisa_respostas where token = 'ensaio200100');
delete from metodo.pesquisa_respostas where token = 'ensaio200100';
delete from metodo.origem_etiqueta where origem = 'renovacao-thb-vencidos';
insert into pg_temp._z_out(passo, linha) select '2 depois da reversão', (select string_agg(origem || '>' || etiqueta, ', ' order by origem) from metodo.origem_etiqueta);
select passo, linha from pg_temp._z_out order by em, passo;
rollback;
