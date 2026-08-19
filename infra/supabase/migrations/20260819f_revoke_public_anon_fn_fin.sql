-- APLICADA EM PRODUÇÃO 2026-08-19 — este arquivo é o registro do que rodou.
--
-- Higiene de GRANT nas 16 funções public.fn_fin_*.
--
-- ── O que estava errado ──────────────────────────────────────────────────────
-- Todas tinham EXECUTE para `anon` (role de usuário NÃO autenticado).
--
-- NÃO havia vazamento: todas são SECURITY DEFINER com guard
-- public.gp_pode_ver_financeiro() dentro do corpo, e com `anon` o auth.uid() é
-- null, então o exists() do guard é falso e a função retorna vazio. Verificado
-- empiricamente antes e depois.
--
-- Mas contraria o padrão da migration 0113 (revoke from public; grant to
-- authenticated) e é defesa em profundidade barata: se alguém editar uma dessas
-- funções e esquecer o guard, o GRANT transforma o descuido em endpoint público.
--
-- ── A armadilha que encontramos no caminho ───────────────────────────────────
-- `revoke execute ... from anon` NÃO teve efeito em 3 delas
-- (fn_fin_compras_aluno, fn_fin_faturamento_diario, fn_fin_ofertas_orfas).
-- Motivo: a permissão não vinha de um grant a `anon` — vinha de PUBLIC. O ACL
-- mostrava `=X/postgres`, e o `=` sem grantee antes da barra é o pseudo-role
-- PUBLIC, que TODA role herda. O comando executou sem erro e sem efeito.
--
-- ⚠️ Corolário: `has_function_privilege('anon', ...)` responde "pode?", não
-- "por quê pode?". Para ver a origem, ler o ACL:
--     select proname, proacl::text from pg_proc ...;
--     -- entrada que começa com '=' é PUBLIC
-- E `proacl::text like '%=X/%'` dá FALSO POSITIVO (casa `postgres=X/` também).
-- Usar: exists (select 1 from unnest(p.proacl) a where a::text like '=%')
--
-- ── Sobre disparos_app ───────────────────────────────────────────────────────
-- As mesmas 3 funções apareciam como executáveis por `disparos_app` (a role do
-- sistema de ativação). Isso NÃO era um grant deliberado: era a mesma herança de
-- PUBLIC. Removido junto. Se o sistema de ativação precisar delas, o certo é um
-- grant nominal — não herdar por acidente.
--
-- ── Estado final verificado ──────────────────────────────────────────────────
-- 16 funções fn_fin_*: anon=false, PUBLIC=false, authenticated=true,
-- service_role=true, todas SECURITY DEFINER com search_path fixo.
--
-- ⚠️ ATENÇÃO PARA FUNÇÃO NOVA: existe DEFAULT PRIVILEGES no schema public
-- concedendo EXECUTE a anon/authenticated/service_role em toda função criada
-- (confirmado em pg_default_acl). Ou seja, TODA fn_fin_* nova nasce com anon
-- podendo executar. Sempre incluir `revoke all ... from public, anon` no CREATE.
-- É a mesma armadilha já registrada para o schema `workbook`.

revoke execute on function public.fn_fin_cobranca_registrar(uuid, text, text, text) from anon;
revoke execute on function public.fn_fin_cobrancas(uuid)                            from anon;
revoke execute on function public.fn_fin_contas_receber(text)                       from anon;
revoke execute on function public.fn_fin_extrato(uuid)                              from anon;
revoke execute on function public.fn_fin_meta_salvar(text, numeric, numeric, integer, date, text) from anon;
revoke execute on function public.fn_fin_metas()                                    from anon;
revoke execute on function public.fn_fin_ofertas()                                  from anon;
revoke execute on function public.fn_fin_regua()                                    from anon;
revoke execute on function public.fn_fin_regua_salvar(jsonb)                        from anon;
revoke execute on function public.fn_fin_salvar_acordo(uuid, date, text, text, text, integer) from anon;
revoke execute on function public.fn_fin_saude()                                    from anon;
revoke execute on function public.fn_fin_turmas()                                   from anon;

-- Estas 3 tinham a permissão via PUBLIC, não via anon — revoke from public.
revoke execute on function public.fn_fin_compras_aluno(uuid)      from public;
revoke execute on function public.fn_fin_faturamento_diario(text) from public;
revoke execute on function public.fn_fin_ofertas_orfas()          from public;
