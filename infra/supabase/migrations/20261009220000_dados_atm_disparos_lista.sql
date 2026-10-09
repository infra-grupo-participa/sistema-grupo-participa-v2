-- 20261009220000: lista de disparos (um por linha) do dashboard ATM, para o bloco "Disparos" de "Esta edição"
--
-- STATUS: ver 20261009220000.explain.md.
-- POR QUE: pedido do Victor (09/10/2026, card 17tya50fudb): ver "os disparos em si" (data, hora, título, copy,
--   quantidade, entregabilidade e custo), não só a visão por canal (dados_atm_disparos_canais).
-- O QUE FAZ: cria public.dados_atm_disparos_lista(p_chave, p_de, p_ate): mesmo gate (dados.atm_cadastro), período
--   (dados.periodo, por coalesce(enviado_em, criado_em)) e filtro (projeto do dashboard, sem arquivados) de
--   dados_atm_disparos_canais. Uma linha por disparo, com o nome da ferramenta e o número remetente (join simples).
--   NÃO há coluna de título nem de assunto na fonte: a tela usa `campanha`. Nulo segue nulo (sem dado), nunca zero.
--   canal_pago = canal fora de email e grupo (mesma regra de 20261009210000).
-- GRANTS: só authenticated (como dados_atm_disparos_canais); sem service_role.
-- AS 5 PERGUNTAS: escala dezenas de disparos por edição; índice: o mesmo de dados_atm_disparos_canais (projeto_id);
--   frequência: a cada abertura da aba; repetição: leitura pura; reversão: 20261009220000_reversao.sql.
-- IDEMPOTENTE: create or replace.

set local lock_timeout = '5s';
set local statement_timeout = '30s';

create or replace function public.dados_atm_disparos_lista(p_chave text, p_de date default null, p_ate date default null)
 returns table (disparo_id bigint, data_hora timestamptz, enviado_em timestamptz, canal text, canal_pago boolean,
                tipo text, ferramenta text, numero text, campanha text, publico_lista text, publico_origem text,
                copy_texto text, copy_link text, tamanho_lista integer, entregues integer, lidas integer, cliques integer,
                falhas integer, custo_centavos integer, origem text, retorno_em timestamptz)
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
#variable_conflict use_column
declare
  d dados.dashboards := dados.atm_cadastro(p_chave);
  v_ini timestamptz; v_fim timestamptz;
begin
  select x.ini, x.fim into v_ini, v_fim from dados.periodo(d.periodo_inicio, d.periodo_fim, p_de, p_ate) x;
  return query
  select x.id, coalesce(x.enviado_em, x.criado_em), x.enviado_em, x.canal, x.canal not in ('email', 'grupo'),
         x.tipo, f.nome, n.numero, x.campanha, x.publico_lista, x.publico_origem,
         x.copy_texto, x.copy_link, x.tamanho_lista, x.entregues, x.lidas, x.cliques,
         x.falhas, x.custo_centavos, x.origem, x.retorno_em
    from mkt_mensageria.disparos x
    left join mkt_mensageria.ferramentas f on f.id = x.ferramenta_id
    left join mkt_mensageria.numeros n on n.id = x.numero_id
   where x.projeto_id = d.projeto_id and x.arquivado_em is null
     and coalesce(x.enviado_em, x.criado_em) >= v_ini and coalesce(x.enviado_em, x.criado_em) < v_fim
   order by coalesce(x.enviado_em, x.criado_em), x.id;
end
$function$;
revoke all on function public.dados_atm_disparos_lista(text, date, date) from public, anon, service_role;
grant execute on function public.dados_atm_disparos_lista(text, date, date) to authenticated;

do $c$
begin
  if has_function_privilege('anon', 'public.dados_atm_disparos_lista(text,date,date)', 'execute')
     or has_function_privilege('service_role', 'public.dados_atm_disparos_lista(text,date,date)', 'execute')
     or not has_function_privilege('authenticated', 'public.dados_atm_disparos_lista(text,date,date)', 'execute') then
    raise exception '20261009220000: permissões erradas';
  end if;
end
$c$;
