-- Reversão de 20261016235000: devolve o 1537308 a OUTROS com a nota anterior, lendo arquivo.fin_produtos__20261016_235000 (o backup fica até 2027-01-14).
set local lock_timeout = '5s';
set local statement_timeout = '30s';
update fin.produtos x set familia = b.familia, nota = b.nota
  from arquivo.fin_produtos__20261016_235000 b
 where b.motivo = 'familia_alterada' and b.produto_id = '1537308' and x.produto_id = b.produto_id
   and (x.familia is distinct from b.familia or x.nota is distinct from b.nota);
