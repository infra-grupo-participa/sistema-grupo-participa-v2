-- Pentest 01/10/2026 (fluxo público de placa), achados médios do banco.
--
-- 1) fn_central_match é SECURITY DEFINER e anon podia executá-la. Ela recebe
--    e-mail/documento e responde se a pessoa é aluna (aluno_id), o que dá
--    um oráculo de "quem é aluno" a quem tiver a anon key, que é pública.
--    🔑 O único chamador é o servidor do v2 (supabase-public-placa.ts, que usa
--    service_role). Varri o disco inteiro: sip, disparos, GPS e o legado não
--    chamam. O comentário da z58 ("formulário público depende de anon")
--    descrevia o formulário PHP antigo.
--    Reversão: grant execute on function public.fn_central_match(text, text) to anon, authenticated;
--
-- 2) idx_placas_sol_token repete o índice único thb_placas_solicitacoes_token_key
--    (mesma coluna, btree). O planner usa o único; o duplicado só custa escrita.
--    Reversão: create index idx_placas_sol_token on public.thb_placas_solicitacoes using btree (token);

revoke execute on function public.fn_central_match(text, text) from public, anon, authenticated;
grant  execute on function public.fn_central_match(text, text) to service_role;

drop index if exists public.idx_placas_sol_token;
