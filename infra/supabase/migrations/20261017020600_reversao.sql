-- Reversão de 20261017020600: os 7 disparos voltam a ficar sem projeto (como a integração os gravou). Nada é apagado.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

update mkt_mensageria.disparos set projeto_id = null
 where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id = 68 and origem = 'api';

do $c$
begin
  if exists (select 1 from mkt_mensageria.disparos where id in (39935, 41099, 42695, 44024, 44512, 39925, 40560) and projeto_id is not null) then
    raise exception 'reversão de 20261017020600 incompleta';
  end if;
end
$c$;
