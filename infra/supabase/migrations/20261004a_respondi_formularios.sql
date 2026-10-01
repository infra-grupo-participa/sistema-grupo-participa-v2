-- Respondi: acervo dos formulários respondidos pelos alunos (workspaces Holding Masters,
-- Diamante, Aurum, Acelera Holding e Holding Total), ligado à ficha do aluno.
--
-- O Respondi não tem API pública: a carga é feita por script (painel autenticado),
-- só com os formulários relevantes para a ficha (questionário inicial, nível, sócios,
-- cadastro, eventos, pesquisas de resultado). NPS, votação e material de curso ficam fora.
--
-- respondi.respostas guarda a resposta inteira (pergunta → valor) e os campos já
-- normalizados em `dados`. O vínculo com o aluno é por e-mail, depois CPF, depois
-- telefone completo (só quando o telefone aponta para um único aluno).
--
-- respondi.aplicacoes registra todo campo da ficha que foi preenchido a partir de uma
-- resposta (valor antes / depois), para auditoria e reversão. Só preenche campo vazio.
--
-- Acesso: tabelas sem policy (RLS ligada) e sem grant para anon/authenticated;
-- a ficha lê pela RPC public.fn_aluno_respondi, que exige equipe.

create schema if not exists respondi;
revoke all on schema respondi from public, anon, authenticated;
grant usage on schema respondi to service_role;

create table respondi.formularios (
  slug          text primary key,
  form_id       bigint not null,
  workspace     text not null,
  nome          text not null,
  familia       text not null check (familia in ('questionario_inicial','nivel','socios','cadastro','evento','pesquisa','outros')),
  turma_codigo  text,
  criado_em     date,
  n_respostas   integer not null default 0,
  campos        jsonb not null default '[]'::jsonb,
  importado_em  timestamptz not null default now()
);

create table respondi.respostas (
  uuid           uuid primary key,
  form_slug      text not null references respondi.formularios(slug) on delete cascade,
  respondido_em  timestamptz not null,
  email          text,
  cpf            text,
  telefone       text,
  dados          jsonb not null default '{}'::jsonb,
  respostas      jsonb not null default '[]'::jsonb,
  aluno_id       uuid references public.thb_alunos(id) on delete set null,
  casado_por     text check (casado_por in ('email','cpf','telefone','email_titular')),
  importado_em   timestamptz not null default now()
);
create index respostas_aluno_idx on respondi.respostas (aluno_id, respondido_em desc);
create index respostas_form_idx  on respondi.respostas (form_slug);
create index respostas_email_idx on respondi.respostas (email);

create table respondi.aplicacoes (
  id             bigserial primary key,
  aluno_id       uuid not null references public.thb_alunos(id) on delete cascade,
  campo          text not null,
  valor_antes    text,
  valor_novo     text,
  resposta_uuid  uuid references respondi.respostas(uuid) on delete set null,
  regra          text not null,
  aplicado_em    timestamptz not null default now(),
  revertido_em   timestamptz
);
create index aplicacoes_aluno_idx on respondi.aplicacoes (aluno_id);

alter table respondi.formularios enable row level security;
alter table respondi.respostas   enable row level security;
alter table respondi.aplicacoes  enable row level security;
revoke all on all tables in schema respondi from public, anon, authenticated;
revoke all on all sequences in schema respondi from public, anon, authenticated;
grant all on all tables in schema respondi to service_role;
grant all on all sequences in schema respondi to service_role;

-- Ficha do aluno: respostas do Respondi deste aluno, mais recente primeiro.
-- Sócio enxerga também as respostas de "Inclusão sócios" em que foi declarado pelo titular.
create or replace function public.fn_aluno_respondi(p_aluno_id uuid)
returns table(uuid uuid, familia text, formulario text, workspace text, turma_codigo text,
              respondido_em timestamptz, casado_por text, dados jsonb, respostas jsonb)
language plpgsql
stable security definer
set search_path to ''
as $function$
begin
  if not coalesce(public.gp_eh_equipe(), false) then return; end if;

  return query
  select r.uuid, f.familia, f.nome, f.workspace, f.turma_codigo,
         r.respondido_em, r.casado_por, r.dados, r.respostas
    from respondi.respostas r
    join respondi.formularios f on f.slug = r.form_slug
   where r.aluno_id = p_aluno_id
      or (f.familia = 'socios' and (r.dados->>'socio_aluno_id') = p_aluno_id::text)
   order by r.respondido_em desc
   limit 300;
end;
$function$;

revoke all on function public.fn_aluno_respondi(uuid) from public, anon;
grant execute on function public.fn_aluno_respondi(uuid) to authenticated, service_role;
