-- =====================================================================================
-- APLICADA em 30/09/2026 (autorização do João: "polir tudo para a gente matar o máximo de dados que estiverem faltando")
-- 20261004g_cruzamentos_correcoes.sql  (analista, 30/09/2026)
--
-- Correções automáticas de thb_alunos que saíram dos cruzamentos de 30/09.
-- Contagens medidas em prod (mbvybujpkwuorhtdzcde) em 30/09/2026, só leitura:
--   A  tipo_documento coerente com o documento (CPF válido de 11 díg.)  139  (NULL 107 · 'cpf' 24 · 'CNPJ' 8)
--   B  documento sem zero à esquerda (9/10 díg.) -> lpad 11, CPF válido    14
--   C  documento vazio/inválido -> CPF da Hotmart (mesmo e-mail, compra paga,
--      documento único, CPF válido, 1º nome bate, ninguém mais usa)        12
--   D  estado vazio -> UF pela faixa do CEP (8 dígitos)                      5
--   E  socio_de_nome vazio com socio_de_aluno_id preenchido -> nome do titular 54
--   F  pais 'BRASIL'/'BR'/'brasil' -> 'Brasil'                               3
--   G  (SÓ COM OK NOMINAL) vínculo de sócio invertido                       20
--
-- Regras de segurança:
--   * Só alunos ATIVOS (cancelado_em is null): update em cancelado dispara trg_aluno_retornou.
--   * Nenhum bloco toca turma_id/turma_aurum_id/plano/status_acesso/situacao_acesso
--     (trg_thb_alunos_historico não dispara). nivel_resultado não é tocado.
--   * valor_antes de cada campo vai para public.cruzamentos_correcoes antes do update.
--   * Cada bloco re-mede na hora; se a contagem divergir da esperada, aborta (raise).
--   * Bloco G está comentado: exige o João validar a lista nominal antes.
-- Reverter: update thb_alunos set <campo> = valor_antes a partir de cruzamentos_correcoes.
-- =====================================================================================


create table if not exists public.cruzamentos_correcoes (
  id bigserial primary key,
  aluno_id uuid not null references public.thb_alunos(id),
  campo text not null,
  valor_antes text,
  valor_novo text,
  regra text not null,
  aplicado_em timestamptz not null default now()
);
alter table public.cruzamentos_correcoes enable row level security;
revoke all on public.cruzamentos_correcoes from anon, authenticated;

-- ---------- helpers locais (DV de CNPJ não existe no banco; CPF usa gps.cpf_valido) ----------
create temp table _cepuf(u text, lo int, hi int) on commit drop;
insert into _cepuf values ('SP',1000,19999),('RJ',20000,28999),('ES',29000,29999),('MG',30000,39999),
 ('BA',40000,48999),('SE',49000,49999),('PE',50000,56999),('AL',57000,57999),('PB',58000,58999),
 ('RN',59000,59999),('CE',60000,63999),('PI',64000,64999),('MA',65000,65999),('PA',66000,68899),
 ('AP',68900,68999),('AM',69000,69299),('RR',69300,69399),('AM',69400,69899),('AC',69900,69999),
 ('DF',70000,72799),('GO',72800,72999),('DF',73000,73699),('GO',73700,76799),('RO',76800,76999),
 ('TO',77000,77999),('MT',78000,78899),('MS',79000,79999),('PR',80000,87999),('SC',88000,89999),
 ('RS',90000,99999);

create temp table _m (aluno_id uuid, campo text, antes text, novo text, regra text) on commit drop;

-- ---------- B: lpad do CPF (antes de A, para A já enxergar 11 dígitos) ----------
insert into _m
select a.id, 'documento', a.documento, lpad(regexp_replace(a.documento,'\D','','g'),11,'0'), 'cruzamento:cpf_lpad'
  from public.thb_alunos a
 where a.cancelado_em is null
   and length(regexp_replace(coalesce(a.documento,''),'\D','','g')) in (9,10)
   and gps.cpf_valido(lpad(regexp_replace(a.documento,'\D','','g'),11,'0'))
   and not exists (select 1 from public.thb_alunos x where x.id <> a.id
                   and regexp_replace(coalesce(x.documento,''),'\D','','g') = lpad(regexp_replace(a.documento,'\D','','g'),11,'0'));
do $$ begin if (select count(*) from _m where regra='cruzamento:cpf_lpad') <> 14 then
  raise exception 'B: esperado 14, achou %', (select count(*) from _m where regra='cruzamento:cpf_lpad'); end if; end $$;

-- ---------- C: CPF da Hotmart para documento vazio/lixo/inválido ----------
insert into _m
with alvo as (
  select a.id, a.documento, lower(trim(a.email)) em, lower(unaccent(split_part(trim(a.nome),' ',1))) n1,
         regexp_replace(coalesce(a.documento,''),'\D','','g') d
    from public.thb_alunos a
   where a.cancelado_em is null and coalesce(trim(a.email),'') <> ''
), alvo2 as (
  select * from alvo
   where d = '' or length(d) not in (9,10,11,14) or (length(d)=11 and not gps.cpf_valido(d))
), fx as (
  select alvo2.id, alvo2.documento, array_agg(distinct regexp_replace(t.comprador_documento,'\D','','g')) docs,
         bool_or(lower(unaccent(split_part(trim(t.comprador_nome),' ',1))) = alvo2.n1) nome_bate
    from alvo2 join fin.hotmart_transacoes t
      on lower(trim(t.comprador_email)) = alvo2.em
     and t.status in ('APPROVED','COMPLETE')
     and length(regexp_replace(coalesce(t.comprador_documento,''),'\D','','g')) in (11,14)
   group by 1,2
)
select fx.id, 'documento', fx.documento, fx.docs[1], 'cruzamento:cpf_hotmart_mesmo_email'
  from fx
 where array_length(fx.docs,1) = 1 and length(fx.docs[1]) = 11 and gps.cpf_valido(fx.docs[1]) and fx.nome_bate
   and not exists (select 1 from public.thb_alunos x where x.id <> fx.id
                   and regexp_replace(coalesce(x.documento,''),'\D','','g') = fx.docs[1])
   and not exists (select 1 from _m y where y.campo='documento' and y.novo = fx.docs[1]);
do $$ begin if (select count(*) from _m where regra='cruzamento:cpf_hotmart_mesmo_email') <> 12 then
  raise exception 'C: esperado 12, achou %', (select count(*) from _m where regra='cruzamento:cpf_hotmart_mesmo_email'); end if; end $$;

-- ---------- A: tipo_documento pelo documento (após B/C) ----------
insert into _m
select a.id, 'tipo_documento', a.tipo_documento, 'CPF', 'cruzamento:tipo_doc_por_dv'
  from public.thb_alunos a
  left join _m m on m.aluno_id = a.id and m.campo = 'documento'
 where a.cancelado_em is null
   and length(coalesce(m.novo, regexp_replace(coalesce(a.documento,''),'\D','','g'))) = 11
   and gps.cpf_valido(coalesce(m.novo, regexp_replace(coalesce(a.documento,''),'\D','','g')))
   and a.tipo_documento is distinct from 'CPF';
-- esperado: 139 (medido) + 12 de B + 7 de C com tipo diferente de 'CPF' = 158
do $$ begin if (select count(*) from _m where regra='cruzamento:tipo_doc_por_dv') <> 158 then
  raise exception 'A: esperado 158, achou %', (select count(*) from _m where regra='cruzamento:tipo_doc_por_dv'); end if; end $$;

-- ---------- D: UF pelo CEP quando estado vazio ----------
insert into _m
select a.id, 'estado', a.estado, c.u, 'cruzamento:uf_por_cep'
  from public.thb_alunos a
  join _cepuf c on left(regexp_replace(a.cep,'\D','','g'),5)::int between c.lo and c.hi
 where a.cancelado_em is null and nullif(trim(a.estado),'') is null
   and regexp_replace(coalesce(a.cep,''),'\D','','g') ~ '^\d{8}$'
   and coalesce(a.pais,'Brasil') ilike 'br%';
do $$ begin if (select count(*) from _m where regra='cruzamento:uf_por_cep') <> 5 then
  raise exception 'D: esperado 5, achou %', (select count(*) from _m where regra='cruzamento:uf_por_cep'); end if; end $$;

-- ---------- E: socio_de_nome a partir do titular vinculado ----------
insert into _m
select s.id, 'socio_de_nome', s.socio_de_nome, t.nome, 'cruzamento:socio_de_nome_do_titular'
  from public.thb_alunos s join public.thb_alunos t on t.id = s.socio_de_aluno_id
 where s.cancelado_em is null and nullif(trim(s.socio_de_nome),'') is null and nullif(trim(t.nome),'') is not null;
do $$ begin if (select count(*) from _m where regra='cruzamento:socio_de_nome_do_titular') <> 54 then
  raise exception 'E: esperado 54, achou %', (select count(*) from _m where regra='cruzamento:socio_de_nome_do_titular'); end if; end $$;

-- ---------- F: país ----------
insert into _m
select id, 'pais', pais, 'Brasil', 'cruzamento:pais_grafia'
  from public.thb_alunos where cancelado_em is null and pais in ('BRASIL','BR','brasil');

-- ---------- foto do antes + updates ----------
insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
select aluno_id, campo, antes, novo, regra from _m;

update public.thb_alunos a set documento = m.novo from _m m
 where m.aluno_id = a.id and m.campo = 'documento' and a.cancelado_em is null
   and a.documento is not distinct from m.antes;
update public.thb_alunos a set tipo_documento = m.novo from _m m
 where m.aluno_id = a.id and m.campo = 'tipo_documento' and a.cancelado_em is null
   and a.tipo_documento is not distinct from m.antes;
update public.thb_alunos a set estado = m.novo from _m m
 where m.aluno_id = a.id and m.campo = 'estado' and a.cancelado_em is null and nullif(trim(a.estado),'') is null;
update public.thb_alunos a set socio_de_nome = m.novo from _m m
 where m.aluno_id = a.id and m.campo = 'socio_de_nome' and a.cancelado_em is null and nullif(trim(a.socio_de_nome),'') is null;
update public.thb_alunos a set pais = m.novo from _m m
 where m.aluno_id = a.id and m.campo = 'pais' and a.cancelado_em is null and a.pais = m.antes;


-- ---------- G: vínculo de sócio invertido (20) — DESCOMENTAR SÓ APÓS OK NOMINAL DO JOÃO ----------
-- Padrão: S (eh_socio=false) aponta para T (eh_socio=true, sem titular) e T.socio_de_nome = S.nome.
-- Correção: T passa a apontar para S; S perde o vínculo. Ordem importa por fn_thb_alunos_trava_vinculo_socio.
-- create temp table _g on commit drop as
-- select s.id s_id, t.id t_id, s.socio_de_aluno_id s_antes, t.socio_de_aluno_id t_antes
--   from public.thb_alunos s join public.thb_alunos t on t.id = s.socio_de_aluno_id
--  where s.cancelado_em is null and t.cancelado_em is null
--    and not coalesce(s.eh_socio,false) and t.eh_socio and t.socio_de_aluno_id is null
--    and not exists (select 1 from public.thb_alunos x where x.socio_de_aluno_id = s.id)
--    and lower(unaccent(trim(regexp_replace(t.socio_de_nome,'\s+',' ','g'))))
--      = lower(unaccent(trim(regexp_replace(s.nome,'\s+',' ','g'))));
-- do $$ begin if (select count(*) from _g) <> 20 then raise exception 'G: esperado 20'; end if; end $$;
-- insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
-- select s_id, 'socio_de_aluno_id', s_antes::text, null, 'cruzamento:socio_invertido' from _g
-- union all select t_id, 'socio_de_aluno_id', null, s_id::text, 'cruzamento:socio_invertido' from _g;
-- update public.thb_alunos a set socio_de_aluno_id = null, socio_de_nome = null from _g where a.id = _g.s_id;
-- update public.thb_alunos a set socio_de_aluno_id = _g.s_id from _g where a.id = _g.t_id;

-- commit;   -- deixado de fora de propósito: quem aplicar confere o select acima e decide.
