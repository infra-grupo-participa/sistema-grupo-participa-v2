-- Reversão de 20261016230200: devolve as linhas tiradas, restaura o evento_id e tira a chave setor das linhas Hotmart.
-- Lê o backup arquivo.pessoas__eventos__20261016 (não apaga o backup: ele vale até 2027-01-14).
set local lock_timeout = '5s';
set local statement_timeout = '60s';
insert into pessoas.eventos overriding system value
  select a.id, a.pessoa_id, a.tipo, a.projeto_id, a.origem_id, a.fonte, a.ref_tipo, a.ref_id, a.detalhe, a.quando, a.por, a.evento_id, a.turma_id, a.fonte_tabela, a.fonte_id
    from arquivo.pessoas__eventos__20261016 a where a.motivo = 'duplicado_removido'
  on conflict do nothing;
update pessoas.eventos x set evento_id = a.evento_id
  from arquivo.pessoas__eventos__20261016 a
 where a.motivo = 'evento_educacao_em_escritorio' and a.id = x.id and x.evento_id is distinct from a.evento_id;
update pessoas.eventos x set detalhe = x.detalhe - 'setor'
 where x.ref_tipo = 'hotmart.transacao' and x.detalhe ->> 'setor' = 'escritorio';
