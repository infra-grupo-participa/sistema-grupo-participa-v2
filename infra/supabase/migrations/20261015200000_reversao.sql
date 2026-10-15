-- Reversão de 20261015200000_acesso_master_isabela.sql: tira a Isabela Teixeira (e1d2863d…) de acesso.master.
-- O gatilho log_master registra o delete com autor Victor Hugo; mais 1 linha de motivo. Cargo, vínculos e
-- capacidades dela não mudam (continuam como antes da migration). Depois: delete da versão 20261015200000 em
-- supabase_migrations.schema_migrations.
set local lock_timeout = '3s';
set local statement_timeout = '10s';

do $g$
begin
  if not exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception 'reversão 20261015200000: a Isabela não está em acesso.master (nada a reverter)';
  end if;
end
$g$;

select set_config('request.jwt.claims', '{"sub":"81d2eaee-cce1-4058-8714-439b0fc6f970"}', true);
delete from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3';
insert into acesso.log (autor, tabela, acao, perfil_id, antes, depois)
values ('81d2eaee-cce1-4058-8714-439b0fc6f970', 'master', 'motivo', 'e1d2863d-c975-46bd-b35f-45b1039328e3', null,
        jsonb_build_object('motivo', 'reversão de 20261015200000: Isabela deixa de ser master',
                           'registrado_por', 'reversão 20261015200000', 'registrado_em', now()));
select set_config('request.jwt.claims', '', true);

do $c$
begin
  if exists (select 1 from acesso.master where perfil_id = 'e1d2863d-c975-46bd-b35f-45b1039328e3') then
    raise exception 'reversão 20261015200000: a Isabela continua master';
  end if;
  if (select count(*) from acesso.master) <> 6 then
    raise exception 'reversão 20261015200000: esperava 6 masters depois de tirar a Isabela';
  end if;
end
$c$;
