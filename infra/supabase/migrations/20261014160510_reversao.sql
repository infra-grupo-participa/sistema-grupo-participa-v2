-- Reversão de 20261014160510.
set local lock_timeout = '5s';
update public.ht_editions set evento_id = null where edition_number in (21, 22);
update fin.eventos set nome = 'Holding Total (HT21/HT22, abr/2026)', observacao = 'HT21 e HT22 no mesmo período; HT22: 25 ingressos'
 where id = 59;
