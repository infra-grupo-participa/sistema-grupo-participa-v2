-- 20261007h: Calendário da empresa na home (/) — leitura de mkt.projetos para toda a equipe
--
-- O QUE FAZ
--   Pedido do Arthur (07/10/2026): "lá no início do sistema haja uma visão de calendário para todo mundo conseguir
--   acompanhar todos os eventos da empresa". A fonte é o cadastro de projetos do Marketing (mkt.projetos, Victor:
--   20261005m e 20261006j). O schema mkt é FECHADO (RLS ligada, sem policy, sem grant para authenticated): quem não é
--   do Marketing não lê. Esta migration cria UMA função de leitura, public.calendario_eventos(p_de, p_ate),
--   SECURITY DEFINER, com guarda gp_eh_equipe() (perfil ativo @advmais.com). Usuários de outros sistemas que dividem o
--   auth.users (rede, metodo, workbook...) não passam na guarda. anon não executa (revoke).
--
--   Devolve SÓ campos não sensíveis: chave (etiqueta do ClickUp), sigla, nome, tipo, unidade, tipo de lançamento,
--   especialista, período do projeto, FASES (jsonb) e LINKS (jsonb, páginas de captura ativas de mkt.paginas). Não
--   devolve orçamento, verba, receita, obs, quem criou nem nada de mkt_trafego.
--
--   Fases: hoje mkt.projetos só tem captação (captacao_inicio/fim) e evento (evento_inicio/fim). Aquecimento/CPLs,
--   carrinho e replay/treplay NÃO existem no cadastro e não são inventados aqui: a tela já sabe desenhar essas fases
--   e passa a mostrá-las quando o cadastro ganhar as colunas (nova versão desta função). Projeto ativo SEM data
--   nenhuma vem com fases vazias e inicio/fim nulos, para a tela listar "sem data no cadastro".
--
--   CRM (schema crm): crm.funil.projeto está vazio em todos os funis e não há data de evento no CRM; nada entra daqui.
--
-- O QUE CRIA
--   public.calendario_eventos(p_de date, p_ate date) — authenticated (guarda interna), sem anon/PUBLIC.
--
-- AS 5 PERGUNTAS
--   escala: mkt.projetos tem 4 linhas (07/10/2026); dezenas por ano. mkt.paginas tem 11. Seq scan é o certo.
--           Janela limitada a 400 dias (erro acima disso).
--   índice: tabelas minúsculas; mkt.paginas(projeto_id) por subselect correlacionado com poucas linhas.
--   frequência: uma chamada por abertura da home (e por troca de mês fora da janela carregada).
--   repetição: a tela carrega uma janela (mês anterior a +3 meses) numa chamada só e filtra no cliente.
--   reversão: drop function public.calendario_eventos(date, date); a home mostra "não foi possível carregar".
--
-- ENSAIO: 20261007h_ensaio.sql (begin … rollback). Explicação: 20261007h.explain.md.

set local lock_timeout = '3s';
set local statement_timeout = '20s';

do $guarda$
begin
  if to_regprocedure('public.calendario_eventos(date, date)') is not null then
    raise exception '20261007h: public.calendario_eventos já existe';
  end if;
  if to_regclass('mkt.projetos') is null or to_regclass('mkt.especialistas') is null or to_regclass('mkt.unidades') is null
     or to_regclass('mkt.tipos_lancamento') is null or to_regclass('mkt.paginas') is null then
    raise exception '20261007h: falta mkt.projetos/especialistas/unidades/tipos_lancamento/paginas (20261005m, 20261006j)';
  end if;
  if (select count(*) from information_schema.columns where table_schema = 'mkt' and table_name = 'projetos'
        and column_name in ('captacao_inicio', 'captacao_fim', 'evento_inicio', 'evento_fim', 'etiqueta_clickup',
                            'tipo', 'unidade', 'tipo_lancamento', 'especialista_id', 'ativo', 'inicio', 'fim')) <> 12 then
    raise exception '20261007h: colunas esperadas de mkt.projetos não batem';
  end if;
  if to_regprocedure('public.gp_eh_equipe()') is null then
    raise exception '20261007h: falta public.gp_eh_equipe()';
  end if;
end
$guarda$;

create function public.calendario_eventos(p_de date, p_ate date)
returns table (
  id                   bigint,
  chave                text,
  sigla                text,
  nome                 text,
  tipo                 text,
  unidade              text,
  unidade_nome         text,
  tipo_lancamento      text,
  tipo_lancamento_nome text,
  especialista         text,
  inicio               date,
  fim                  date,
  fases                jsonb,
  links                jsonb
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce(public.gp_eh_equipe(), false) then
    raise exception 'calendario_eventos: acesso só da equipe' using errcode = '42501';
  end if;
  if p_de is null or p_ate is null or p_ate < p_de or p_ate - p_de > 400 then
    raise exception 'calendario_eventos: janela inválida (de <= até, no máximo 400 dias)' using errcode = '22023';
  end if;

  return query
  with base as (
    select p.id, p.etiqueta_clickup, p.sigla, p.nome, p.tipo, p.unidade, u.nome as unidade_nome,
           p.tipo_lancamento, tl.nome as tipo_lancamento_nome, e.nome as especialista,
           p.captacao_inicio, coalesce(p.captacao_fim, p.captacao_inicio) as captacao_fim,
           p.evento_inicio, coalesce(p.evento_fim, p.evento_inicio) as evento_fim,
           p.inicio as p_inicio, coalesce(p.fim, p.inicio) as p_fim
      from mkt.projetos p
      left join mkt.unidades u on u.codigo = p.unidade
      left join mkt.tipos_lancamento tl on tl.codigo = p.tipo_lancamento
      left join mkt.especialistas e on e.id = p.especialista_id
     where p.ativo
  ), periodo as (
    select b.*,
           least(b.captacao_inicio, b.evento_inicio, case when b.captacao_inicio is null and b.evento_inicio is null then b.p_inicio end) as ini,
           greatest(b.captacao_fim, b.evento_fim, case when b.captacao_inicio is null and b.evento_inicio is null then b.p_fim end) as fi
      from base b
  )
  select pr.id, pr.etiqueta_clickup, pr.sigla, pr.nome, pr.tipo, pr.unidade, pr.unidade_nome,
         pr.tipo_lancamento, pr.tipo_lancamento_nome, pr.especialista,
         pr.ini, pr.fi,
         coalesce((
           select jsonb_agg(f.obj order by f.ordem)
             from (values
               (1, case when pr.captacao_inicio is not null then jsonb_build_object(
                     'fase', 'captacao', 'inicio', pr.captacao_inicio, 'fim', pr.captacao_fim, 'interno', false) end),
               (2, case when pr.evento_inicio is not null then jsonb_build_object(
                     'fase', 'evento', 'inicio', pr.evento_inicio, 'fim', pr.evento_fim, 'interno', false) end),
               -- Projeto antigo sem captação nem evento, só com o período geral: vira "evento" (mesmo critério do
               -- gatilho da 20261006j, que deriva inicio/fim desses dois períodos).
               (3, case when pr.captacao_inicio is null and pr.evento_inicio is null and pr.p_inicio is not null
                     then jsonb_build_object('fase', 'evento', 'inicio', pr.p_inicio, 'fim', pr.p_fim, 'interno', false) end)
             ) as f(ordem, obj)
            where f.obj is not null
         ), '[]'::jsonb),
         coalesce((
           select jsonb_agg(jsonb_build_object('nome', pg.nome, 'url', 'https://' || pg.dominio || coalesce(pg.caminho, '/'))
                            order by pg.caminho)
             from mkt.paginas pg
            where pg.projeto_id = pr.id and pg.ativa and pg.funcao = 'captura' and pg.dominio is not null
         ), '[]'::jsonb)
    from periodo pr
   where pr.ini is null                                    -- sem data: a tela lista à parte
      or (pr.ini <= p_ate and coalesce(pr.fi, pr.ini) >= p_de)
   order by pr.ini nulls last, pr.nome;
end
$$;

revoke all on function public.calendario_eventos(date, date) from public, anon;
grant execute on function public.calendario_eventos(date, date) to authenticated;

comment on function public.calendario_eventos(date, date) is
  'Calendário da empresa (home /): projetos ativos de mkt.projetos com fases e páginas de captura, só campos não '
  'sensíveis. Guarda gp_eh_equipe(). Janela máx. 400 dias. 20261007h.';

-- REVERSÃO
--   drop function public.calendario_eventos(date, date);
