-- Reversão de 20261016230200: devolve as linhas tiradas, restaura o evento_id e volta o setor SÓ das linhas que o passo 3 marcou.
-- Lê o backup arquivo.pessoas__eventos__20261016 (não apaga o backup: ele vale até 2027-01-14).
-- Linhas que o webhook ou a carga gravaram depois da 230200 NÃO são tocadas: o setor só volta nas linhas com motivo setor_marcado, por id,
-- e só a chave setor (o resto do detalhe, inclusive o que mudou depois, fica).
set local lock_timeout = '5s';
set local statement_timeout = '60s';
insert into pessoas.eventos overriding system value
  select a.id, a.pessoa_id, a.tipo, a.projeto_id, a.origem_id, a.fonte, a.ref_tipo, a.ref_id, a.detalhe, a.quando, a.por, a.evento_id, a.turma_id, a.fonte_tabela, a.fonte_id
    from arquivo.pessoas__eventos__20261016 a where a.motivo = 'duplicado_removido'
  on conflict do nothing;
update pessoas.eventos x set evento_id = a.evento_id
  from arquivo.pessoas__eventos__20261016 a
 where a.motivo = 'evento_educacao_em_escritorio' and a.id = x.id and x.evento_id is distinct from a.evento_id;
update pessoas.eventos x
   set detalhe = case when a.detalhe ? 'setor' then x.detalhe || jsonb_build_object('setor', a.detalhe -> 'setor') else x.detalhe - 'setor' end
  from arquivo.pessoas__eventos__20261016 a
 where a.motivo = 'setor_marcado' and a.id = x.id and x.detalhe -> 'setor' is distinct from a.detalhe -> 'setor';
