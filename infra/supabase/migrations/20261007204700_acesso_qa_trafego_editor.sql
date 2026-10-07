-- 20261007204700: níveis de acesso, conta de teste "QA Tráfego (conta de teste)" (perfil 6e8d878d…, qa.trafego@advmais.com)
-- vira MEMBRO do Tráfego (marketing/trafego, papel membro = edita a área), sem financeiro, sem master, sem admin.
-- Pedido do Victor Hugo em 07/10/2026: o JP precisa provar na tela (flag NEXT_PUBLIC_ACESSO_V2) que um editor de área
-- não vê o Financeiro e não dá acesso a ninguém, sem usar pessoa real.
--
-- STATUS: ver 20261007204700.explain.md (a linha de STATUS de lá é a fonte; este arquivo vai igual para schema_migrations).
-- Ensaio: 20261007204700_ensaio.sql.
--
-- POR QUE ESTA CONTA E NÃO UMA QUE JÁ EXISTE
--   Contas de teste no banco em 07/10: "QA Sessoes (conta de teste)" (é master desde 20261007204002) e "Robô de teste E2E
--   (Financeiro)" (tem financeiro.ver, é o usuário dos testes e2e do Financeiro, web/e2e). Usar qualquer uma das duas para
--   "editor sem financeiro" mudaria o propósito dela. A conta do Auth foi criada às 20:46 UTC pela API admin do Auth
--   (e-mail confirmado, user_metadata só com o nome, igual ao Robô); o gatilho handle_new_user criou o perfil pendente e
--   visualizador, e o rede.handle_new_user criou rede.perfis pendente/aluno, como acontece com todo convite da rota
--   /api/admin/usuarios.
--
-- CAMINHO OFICIAL
--   1. Ativar o perfil pela RPC da rota de Usuários (public.acesso_perfil_atualizar_como), autor Victor Hugo, o mesmo
--      patch que o POST de /api/admin/usuarios manda no acesso v2 ({nome, status: 'ativo'}).
--   2. Vínculo pela RPC de gestão (public.acesso_vincular), que exige master: o claim sub é o Victor Hugo (81d2eaee…),
--      só dentro desta transação (set_config local), limpo no fim. O gatilho log_vinculo grava autor = Victor.
--   Cargo (visualizador), áreas, funções e CPF NÃO mudam; nenhuma capacidade; nenhuma função recriada (sem blindagem).
--   Igual aos membros do Tráfego que já existem (renan, emmanuel: visualizador, sem áreas, vínculo marketing/trafego membro).
--
-- AS 5 PERGUNTAS
--   escala: 1 update em perfis, 1 linha em acesso.vinculo, 4 em acesso.log. índice: PK de perfis e de vinculo.
--   frequência: uma vez. repetição: idempotente. reversão: explain §5 (desvincular + status negado; apagar no Auth).

set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.nome = 'QA Tráfego (conta de teste)'
                    and p.email = 'qa.trafego@advmais.com' and p.cargo = 'visualizador' and p.status in ('pendente', 'ativo')
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil 6e8d878d não é a conta de teste QA Tráfego como esperado';
  end if;
  if not exists (select 1 from auth.users u where u.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                   and u.email = 'qa.trafego@advmais.com' and u.deleted_at is null and u.email_confirmed_at is not null
                   and (u.banned_until is null or u.banned_until < now())) then
    raise exception '20261007204700: conta do Auth da QA Tráfego não confere (e-mail, confirmação, excluída ou banida)';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.excecao_admin where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master, exceção nem ter capacidade';
  end if;
  if (select nome from public.perfis where id = '81d2eaee-cce1-4058-8714-439b0fc6f970') is distinct from 'Victor Hugo'
     or not exists (select 1 from acesso.master where perfil_id = '81d2eaee-cce1-4058-8714-439b0fc6f970') then
    raise exception '20261007204700: autor esperado (Victor Hugo, master) não confere';
  end if;
  if not exists (select 1 from acesso.area where departamento = 'marketing' and key = 'trafego') then
    raise exception '20261007204700: área marketing/trafego não existe';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);

do $a$
declare r jsonb;
begin
  r := public.acesso_perfil_atualizar_como('81d2eaee-cce1-4058-8714-439b0fc6f970', '6e8d878d-086c-4b12-bef7-c424d89d85b6',
                                           '{"nome": "QA Tráfego (conta de teste)", "status": "ativo"}'::jsonb);
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: ativar perfil falhou: %', r; end if;
  r := public.acesso_vincular('6e8d878d-086c-4b12-bef7-c424d89d85b6', 'marketing', 'trafego', 'membro');
  if r ->> 'ok' is distinct from 'true' then raise exception '20261007204700: vincular falhou: %', r; end if;
end
$a$;

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'vinculo', 'motivo', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta de teste membro do Tráfego, sem financeiro, para o JP testar a tela de acesso, pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6'
                     and tabela = 'vinculo' and acao = 'motivo');

insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
select '81d2eaee-cce1-4058-8714-439b0fc6f970', 'auth', 'senha', '6e8d878d-086c-4b12-bef7-c424d89d85b6', null,
       jsonb_build_object('motivo', 'conta criada pela API admin do Auth com a senha padrão de testes do @advmais, a pedido do Victor 07/10',
                          'registrado_por', 'migration 20261007204700', 'registrado_em', now())
 where not exists (select 1 from acesso.log where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and tabela = 'auth');

select set_config('request.jwt.claims', '', true);

do $c$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and p.status = 'ativo' and p.cargo = 'visualizador'
                    and coalesce(p.areas, '{}') = '{}' and coalesce(p.funcoes, '{}') = '{}'
                    and not coalesce(p.pode_ver_cpf_completo, false)) then
    raise exception '20261007204700: perfil da QA Tráfego não ficou ativo/visualizador sem áreas';
  end if;
  if (select count(*) from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null) <> 1
     or not exists (select 1 from acesso.vinculo where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6' and vigente_ate is null
                      and departamento = 'marketing' and area = 'trafego' and papel = 'membro') then
    raise exception '20261007204700: esperava 1 vínculo vigente marketing/trafego membro';
  end if;
  if exists (select 1 from acesso.master where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6')
     or exists (select 1 from acesso.capacidade where perfil_id = '6e8d878d-086c-4b12-bef7-c424d89d85b6') then
    raise exception '20261007204700: a QA Tráfego não pode ser master nem ter capacidade';
  end if;
end
$c$;
