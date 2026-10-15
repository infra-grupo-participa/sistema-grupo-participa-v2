-- 20261015210000: RPC nova public.dados_atm_grupo_leads(p_chave, p_de, p_ate). Aba "Leads" do modal "Ingresso no grupo"
-- das Ações da Black (modelo acao-black; serve também ao seminario-atm): todo número que entrou no grupo, uma vez só,
-- cruzado com a lista do disparo (dados.lista_membros da chave -> public.thb_alunos) e com a base de leads da chave
-- (dados.atm_leads). Pedido do Victor Hugo em 15/10/2026 (frente black-ingresso-grupo-unicos).
--
-- STATUS: NÃO APLICADA. Ensaio: 20261015210000_ensaio.sql. Reversão: 20261015210000_reversao.sql.
-- Relatório: 20261015210000.explain.md.
--
-- REGRAS
--   - Um número uma vez: a base é dados.v_grupo_pessoas_todos (uma linha por número por chave), igual a
--     dados_atm_grupo_numeros e ao grupo_entradas do dados_atm_resumo. Teste fica de fora, como no card.
--   - Casamento por telefone com os 8 últimos dígitos da controle.fone_key (o mesmo do resto do ATM e da Black; o campo
--     já tem DDD) e, na base de leads, também pela pessoa_id do evento do grupo.
--   - origem: 'lista_disparo' se o número está na lista do disparo; senão 'base_leads' se está na base de leads;
--     senão 'nao_encontrado' (só o telefone do grupo; o resto vazio). na_lista e na_base dizem as duas coisas.
--   - nome, email e telefone vêm da fonte que casou (lista primeiro). turma e instrucao vêm de dados.perfil(email),
--     a mesma regra de dados_atm_leads (valor exato da Central).
--   - Dado pessoal: exige contato.ver (42501), como dados_black_leads e dados_atm_leads; e equipe com acesso ao
--     dashboard via dados.atm_cadastro.
--
-- AS 5 PERGUNTAS
--   escala: lê os números do grupo da chave (dezenas a poucos milhares), a lista da chave (centenas) e dados.atm_leads
--     (já materializada); dados.perfil só para as linhas casadas. índice: lista_membros por chave; fone8 casado em hash.
--   frequência: ao abrir a aba (sob demanda, não em polling). repetição: 1 chamada por abertura.
--   reversão: 20261015210000_reversao.sql (drop da função). Nada muda nas RPCs que já existem.

set local lock_timeout = '3s';
set local statement_timeout = '30s';

do $g$
begin
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname = 'dados_atm_grupo_leads') then
    raise exception '20261015210000: public.dados_atm_grupo_leads já existe';
  end if;
  if to_regprocedure('dados.atm_leads(text)') is null or to_regprocedure('dados.perfil(text)') is null
     or to_regprocedure('dados.atm_cadastro(text)') is null or to_regclass('dados.v_grupo_pessoas_todos') is null then
    raise exception '20261015210000: dependência ausente';
  end if;
end
$g$;

create function public.dados_atm_grupo_leads(p_chave text, p_de date default null, p_ate date default null)
returns table (
  fone_grupo text, origem text, na_lista boolean, na_base boolean,
  nome text, email text, telefone text, turma text, instrucao text,
  entrou_em timestamptz, saiu_em timestamptz, no_grupo boolean, entrada_aproximada boolean
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards;
  v_ini timestamptz; v_fim timestamptz;
begin
  d := dados.atm_cadastro(p_chave);   -- 42501 sem acesso ao dashboard, P0002 chave fora do cadastro ou outro modelo
  if not coalesce(acesso.tem('contato.ver'), false) then
    raise exception 'sem permissão para ver contatos' using errcode = '42501';
  end if;
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  with g as (
    select p.fone8, coalesce(p.fone_key, p.fone8) as fone, p.pessoa_id, p.entrou_em, p.saiu_em, p.no_grupo, p.entrada_aproximada
      from dados.v_grupo_pessoas_todos p
     where p.chave = d.chave and p.entrou_em >= v_ini and p.entrou_em < v_fim and not p.teste
  ),
  lst as materialized (
    select distinct on (right(controle.fone_key(a.telefone), 8))
           right(controle.fone_key(a.telefone), 8) as fk8, a.nome, m.email_norm as email, a.telefone
      from dados.lista_membros m
      join public.thb_alunos a on pessoas.norm_email(a.email) = m.email_norm
     where m.chave = d.chave and a.telefone is not null
     order by right(controle.fone_key(a.telefone), 8), a.eh_socio, a.id
  ),
  ld as materialized (
    select right(controle.fone_key(x.telefone), 8) as fk8, x.pessoa_id, x.nome, x.email, x.telefone, x.primeiro_em
      from dados.atm_leads(d.chave) x
     where not coalesce(x.teste, false)
  ),
  c as (
    select g.*, l.nome as l_nome, l.email as l_email, l.telefone as l_tel,
           b.nome as b_nome, b.email as b_email, b.telefone as b_tel, (l.fk8 is not null) as em_lista, coalesce(b.achou, false) as em_base
      from g
      left join lst l on l.fk8 = g.fone8
      left join lateral (select true as achou, ld.nome, ld.email, ld.telefone from ld
                          where ld.fk8 = g.fone8 or (g.pessoa_id is not null and ld.pessoa_id = g.pessoa_id)
                          order by (ld.fk8 = g.fone8) desc, ld.primeiro_em limit 1) b on true
  )
  select c.fone,
         case when c.em_lista then 'lista_disparo' when c.em_base then 'base_leads' else 'nao_encontrado' end,
         c.em_lista, c.em_base,
         coalesce(c.l_nome, c.b_nome), coalesce(c.l_email, c.b_email), coalesce(c.l_tel, c.b_tel, c.fone),
         pf.turma, pf.instrucao,
         c.entrou_em, c.saiu_em, c.no_grupo, c.entrada_aproximada
    from c
    left join lateral (select x.turma, x.instrucao from dados.perfil(coalesce(c.l_email, c.b_email)) x
                        where coalesce(c.l_email, c.b_email) is not null limit 1) pf on true
   order by c.entrou_em desc, c.fone;
end
$function$;

comment on function public.dados_atm_grupo_leads(text, date, date) is
  '20261015210000: aba Leads do modal Ingresso no grupo (acao-black e seminario-atm). Um número do grupo uma vez, cruzado com a lista do disparo e a base de leads. Exige contato.ver.';

revoke all on function public.dados_atm_grupo_leads(text, date, date) from public, anon;
grant execute on function public.dados_atm_grupo_leads(text, date, date) to authenticated;
