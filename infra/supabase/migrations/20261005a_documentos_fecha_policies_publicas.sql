-- 🔴 Pentest 01/10/2026: o bucket `documentos` (comprovantes e declarações de
-- placa — CPF, endereço, faturamento) tinha 4 policies abertas em
-- storage.objects. Com a anon key (pública) dava para LISTAR as 153 pastas
-- `placas/<token>/` — o nome da pasta É o token do processo — e, com o token,
-- ler a PII e editar o processo alheio pelo /api/placa. Também dava para
-- enviar/sobrescrever arquivo (anon) e apagar (qualquer uma das 11 mil contas
-- da auth.users compartilhada).
--
-- 🔑 Ninguém legítimo depende delas: o único gravador desde 03/2026 é o
-- servidor (`supabase-public-placa.ts`, service_role, que ignora RLS). O
-- download pelo painel usa a URL pública do objeto, que um bucket `public`
-- serve SEM policy — continua funcionando. O que morre é listar, enviar,
-- trocar e apagar pela API.
--
-- Reversão (não recomendada): recriar as 4 policies abaixo.
--   documentos_public_read   SELECT  to public        using (bucket_id='documentos')
--   documentos_public_insert INSERT  to public        with check (bucket_id='documentos')
--   documentos_public_update UPDATE  to public        using/with check (bucket_id='documentos')
--   documentos_public_delete DELETE  to authenticated using (bucket_id='documentos')

drop policy if exists documentos_public_read   on storage.objects;
drop policy if exists documentos_public_insert on storage.objects;
drop policy if exists documentos_public_update on storage.objects;
drop policy if exists documentos_public_delete on storage.objects;
