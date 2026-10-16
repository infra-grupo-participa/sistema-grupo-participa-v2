-- /renov do Time Holding Brasil (16/10/2026): cada aplicação de renovação, gravada pela Edge Function
-- renov-thb (service_role). Mesmo molde de metodo.consultoria_aplicacoes: RLS ligada, sem
-- política e sem grant para anon/authenticated. O painel lê por RPC própria (PR do painel).
do $$ begin
  if to_regclass('metodo.renov_aplicacoes') is not null then
    raise exception 'premissa: metodo.renov_aplicacoes já existe';
  end if;
end $$;

create table metodo.renov_aplicacoes (
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  nome text not null,
  email text not null,
  telefone text not null,                       -- E.164 com "+"
  opcao text not null check (opcao in ('nao-renovar', 'renovar-holding-masters', 'upgrade-implementacao-assistida')),
  utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
  sck text,
  pagina text not null default '',
  user_agent text not null default '',
  origem text not null default 'renov-thb',
  teste boolean not null default false,
  pago boolean,                                 -- preenchido quando a venda da Hotmart for cruzada (pendente)
  pago_em timestamptz
);

create index renov_aplicacoes_criado_em_idx on metodo.renov_aplicacoes (criado_em desc);
create index renov_aplicacoes_email_idx on metodo.renov_aplicacoes (lower(email));

alter table metodo.renov_aplicacoes enable row level security;
revoke all on metodo.renov_aplicacoes from public, anon, authenticated;
grant select, insert, update on metodo.renov_aplicacoes to service_role;

comment on table metodo.renov_aplicacoes is 'Aplicações da página /renov do THB (16/10/2026). Escrita só pela Edge Function renov-thb.';
