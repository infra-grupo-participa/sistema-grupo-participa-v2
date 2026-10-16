-- Reversão: só se a tabela ainda não tiver aplicação real.
do $$ begin
  if (select count(*) from metodo.renov_aplicacoes where not teste) > 0 then
    raise exception 'há aplicações reais: exportar antes de reverter';
  end if;
end $$;
drop table metodo.renov_aplicacoes;
