-- Reversão de 20261016233000: devolve o produto 3595938 a OUTROS (com a nota anterior), restaura o evento_id e tira o setor SÓ das linhas
-- que o passo 3 marcou. Lê arquivo.fin_produtos__20261016 e arquivo.pessoas__eventos__20261016_233000 (não apaga os backups: valem até 2027-01-14).
-- Linhas que o webhook ou a carga gravaram depois NÃO são tocadas: o setor só volta nas linhas com motivo setor_marcado, por id, e só a chave setor.
-- Ordem: se a 20261016230200 também for revertida, reverter esta ANTES.
set local lock_timeout = '5s';
set local statement_timeout = '60s';
update fin.produtos x set familia = b.familia, nota = b.nota
  from arquivo.fin_produtos__20261016 b
 where b.motivo = 'familia_alterada' and b.produto_id = '3595938' and x.produto_id = b.produto_id
   and (x.familia is distinct from b.familia or x.nota is distinct from b.nota);
update pessoas.eventos x set evento_id = a.evento_id
  from arquivo.pessoas__eventos__20261016_233000 a
 where a.motivo = 'evento_educacao_em_escritorio' and a.id = x.id and x.evento_id is distinct from a.evento_id;
update pessoas.eventos x
   set detalhe = case when a.detalhe ? 'setor' then x.detalhe || jsonb_build_object('setor', a.detalhe -> 'setor') else x.detalhe - 'setor' end
  from arquivo.pessoas__eventos__20261016_233000 a
 where a.motivo = 'setor_marcado' and a.id = x.id and x.detalhe -> 'setor' is distinct from a.detalhe -> 'setor';
