-- Reversão de 20261014160510. Só funciona se nada apontar para o HT21 novo (FK restrict).
set local lock_timeout = '5s';
update public.ht_editions set evento_id = null where edition_number in (21, 22);
delete from fin.eventos where categoria = 'holding_total' and codigo = 'HT21' and chave ~ '^ht21-[0-9]{4}-[0-9]{2}$';
update fin.eventos set nome = 'Holding Total (HT21/HT22, abr/2026)', chave = 'ht21-ht22-2026-04',
       observacao = 'HT21 e HT22 no mesmo período; HT22: 25 ingressos'
 where id = 59;
