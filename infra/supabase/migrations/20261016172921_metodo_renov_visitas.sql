-- Acessos da /renov (16/10/2026): uma linha por carregamento da página, com o id do visitante (localStorage).
-- Aplicada no Supabase em 16/10/2026 (migração metodo_renov_visitas).
create table if not exists metodo.renov_visitas (
  id bigint generated always as identity primary key,
  criado_em timestamptz not null default now(),
  visitante text not null check (char_length(visitante) between 8 and 64),
  utm_source text, utm_medium text, utm_campaign text, utm_content text, utm_term text,
  pagina text, user_agent text
);
create index if not exists renov_visitas_visitante_idx on metodo.renov_visitas (visitante, criado_em);
alter table metodo.renov_visitas enable row level security;
revoke all on metodo.renov_visitas from anon, authenticated;
grant select, insert on metodo.renov_visitas to service_role;
grant usage, select on sequence metodo.renov_visitas_id_seq to service_role;
alter table metodo.renov_aplicacoes add column if not exists visitante text;
create index if not exists renov_aplicacoes_visitante_idx on metodo.renov_aplicacoes (visitante);
