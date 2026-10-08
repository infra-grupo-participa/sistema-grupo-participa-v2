-- 20261008210100: carga ÚNICA das UTMs do AC para os leads do ATM 1 que estão hoje sem UTM
--
-- STATUS: ver 20261008210000.explain.md. Depende de 20261008210000.
-- O QUE FAZ: põe na fila dados.ac_utm_fila os contatos inscritos na lista 615 cujo e-mail ainda não tem UTM em
--   dados.ac_utm. O ciclo dados.ac_utm_ciclo() (cron só com fila) busca os campos de cada um, 5 por rodada.
--   Não cria lead: só lê contatos que já estão em crm.evento_jornada. Não sincroniza de novo depois.
-- PARA VOLTAR: delete from dados.ac_utm_fila where lista = '615' and estado in ('pendente', 'pedido');
--   (as UTMs já obtidas saem com a reversão da 20261008210000).

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if to_regclass('dados.ac_utm_fila') is null then
    raise exception 'premissa: 20261008210000 não aplicada';
  end if;
end
$g$;

insert into dados.ac_utm_fila (lista, contato_id, email_norm)
select distinct on (split_part(j.fonte_evento_id, ':', 1))
       j.lista, split_part(j.fonte_evento_id, ':', 1), lower(btrim(j.email_norm))
  from crm.evento_jornada j
 where j.fonte = 'activecampaign' and j.tipo = 'subscribe' and j.lista = '615'
   and j.email_norm is not null and lower(btrim(j.email_norm)) not like '%@exemplo.invalid'
   and split_part(j.fonte_evento_id, ':', 1) ~ '^[0-9]{1,20}$'
   and not exists (select 1 from dados.ac_utm a where a.lista = j.lista and a.email_norm = lower(btrim(j.email_norm)))
 order by split_part(j.fonte_evento_id, ':', 1), j.ocorreu_em
on conflict (lista, contato_id) do nothing;
