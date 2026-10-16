-- APLICADA em 16/10/2026 (versão 20261016153042, nome crm_marcio_gestor).
-- Marcio (dev, marcio@advmais.com) passa a ser gestor do Comercial: escreve, move negócios e vê tudo completo.
-- Pedido do João. Gestor = id em crm.config.gestores (crm.eh_gestor); como dev ele era "leitor" (só leitura, crm.pode_escrever = false).
-- Prova (transação desfeita, JWT dele): gestor=true leitor=false pode_escrever=true; 100 contatos sem telefone/e-mail mascarado.
-- Reversão: update crm.config set gestores = array_remove(gestores, 'ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid);
-- Efeito colateral: como gestor ele também recebe os avisos de gestor e pode aprovar o que exige gestor (ex.: fichas de disparo).
do $$
begin
  if not exists (select 1 from public.perfis p
                  where p.id = 'ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid and lower(p.email) = 'marcio@advmais.com'
                    and p.cargo = 'dev' and p.status = 'ativo') then
    raise exception 'Premissa: perfil ec6d1905… não é o marcio@advmais.com dev ativo.';
  end if;
end $$;

update crm.config
   set gestores = array_append(coalesce(gestores, '{}'::uuid[]), 'ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid)
 where not ('ec6d1905-200e-4efd-a172-8546f293a4bd'::uuid = any(coalesce(gestores, '{}'::uuid[])));
