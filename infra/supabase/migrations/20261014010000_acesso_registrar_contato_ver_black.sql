-- 20261014010000: registra em migration a permissão contato.ver dada a 4 perfis da equipe em 13/10/2026 18:36 UTC
--
-- POR QUE: em 13/10 as 4 linhas de contato.ver (listas da Mensageria da Black) entraram em acesso.capacidade por SQL direto,
-- sem migration (auditoria pelo guia do JP, item 4; guia 6.3 e 10.4). Permissão também é migration.
-- O QUE FAZ: insert idempotente das 4 linhas, por perfil_id (nunca por e-mail: o repo é público). No banco de produção as 4
-- já existem, então não muda nada (on conflict do nothing; o gatilho de log só dispara em insert real). Serve para quem
-- recriar o banco a partir das migrations (ex.: homologação). Quem são: decisão do Victor de 13/10, lista nominal no cérebro.
-- AS 5 PERGUNTAS: escala = 4 linhas; índice = PK (perfil_id, chave); frequência = única; repetição = nenhuma;
--   reversão = 20261014010000_reversao.sql (só registra; apagar a permissão é decisão do Victor, não reversão desta migration).

set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $g$
begin
  if (select count(*) from public.perfis p where p.id in ('81d2eaee-cce1-4058-8714-439b0fc6f970', '3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975', '843d43db-73b3-44a9-b449-1731e362dbc3', '012bbcd3-cade-4889-a6ff-4804ed15c36d') and p.status = 'ativo') <> 4 then
    raise exception '20261014010000: os 4 perfis não estão todos ativos. Reler.';
  end if;
end
$g$;

insert into acesso.capacidade (perfil_id, chave, criado_por)
select x.perfil_id, 'contato.ver', '81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid
  from (values
    ('81d2eaee-cce1-4058-8714-439b0fc6f970'::uuid),
    ('3bd183e5-34bf-4d4a-9ee9-b9cae2ed4975'::uuid),
    ('843d43db-73b3-44a9-b449-1731e362dbc3'::uuid),
    ('012bbcd3-cade-4889-a6ff-4804ed15c36d'::uuid)
  ) as x(perfil_id)
on conflict (perfil_id, chave) do nothing;
