-- Reversão de 20261017020500: tira as duas funções de disparos da Clínica. Nada mais é tocado (funções novas, só leitura).
-- Se a tela da Clínica já as chama, ela volta a ficar sem a aba de disparos no formato do ATM (a dados_presencial_disparos antiga segue).
set local lock_timeout = '5s';
set local statement_timeout = '30s';

drop function if exists public.dados_presencial_disparos_canais(text, date, date);
drop function if exists public.dados_presencial_disparos_lista(text, date, date);

do $c$
begin
  if to_regprocedure('public.dados_presencial_disparos_canais(text,date,date)') is not null
     or to_regprocedure('public.dados_presencial_disparos_lista(text,date,date)') is not null then
    raise exception 'reversão de 20261017020500 incompleta';
  end if;
end
$c$;
