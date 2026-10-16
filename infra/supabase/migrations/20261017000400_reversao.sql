-- Reverte 20261017000400: remove o vínculo de membro do Marco no Comercial criado por ela.
delete from acesso.vinculo
 where perfil_id = '85016fb8-5f7b-4474-a418-bc1ab87f870b' and departamento = 'comercial' and area is null and papel = 'membro'
   and criado_em >= '2026-10-16';
