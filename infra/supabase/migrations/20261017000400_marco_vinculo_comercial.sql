-- 20261017000400: Marco (marco@advmais.com) ganha vínculo de membro no departamento Comercial (acesso v2).
-- Motivo: a 20261017000300 o pôs em crm.vendedor, mas a porta do CRM no site (acessoComercial com acessoV2) exige
-- `comercial` em `editar` do gp_meu_acesso(), que vem de acesso.vinculo. Sem o vínculo ele caía em 'relatorios'
-- e /comercial/funil devolvia para a home. Mesmo vínculo que Luis (lf) e Aldri (as) já têm.
do $$
begin
  if exists (select 1 from acesso.vinculo where perfil_id = '85016fb8-5f7b-4474-a418-bc1ab87f870b'
               and departamento = 'comercial' and area is null and vigente_ate is null) then
    raise exception 'Marco já tem vínculo vigente no comercial';
  end if;
end $$;

insert into acesso.vinculo (perfil_id, departamento, area, papel, criado_por)
values ('85016fb8-5f7b-4474-a418-bc1ab87f870b', 'comercial', null, 'membro', '81d2eaee-cce1-4058-8714-439b0fc6f970');
