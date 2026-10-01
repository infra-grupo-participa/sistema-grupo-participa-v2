-- 20261004l — Conciliação, fechamento da rodada 3 (01/10/2026)
-- Depois da 20261004k o placar ficou com 79 falhas sem observação. Esta migration:
--  1. num_socios do titular: sobe para a contagem de sócios ativos vinculados quando ela é MAIOR
--     que o gravado (o vínculo foi resolvido na 20261004k); quando é menor, só observação.
--  2. observação [conc:<checagem>] em toda falha restante sem explicação (documento repetido,
--     UF sem estado com CEP e cidade em conflito, vencimento passado ainda a_vencer, nível).
-- Nada de PII literal (repo público): as observações citam só ids.
do $$
declare k int; m int; o int;
begin
  -- 1a. num_socios: contagem ativa maior que o gravado → aplica
  with nsoc as (select socio_de_aluno_id t, count(*) n from public.thb_alunos
                 where cancelado_em is null and socio_de_aluno_id is not null group by 1),
  alvo as (select a.id, a.num_socios antes, n.n novo from public.thb_alunos a join nsoc n on n.t = a.id
            where a.cancelado_em is null and not a.eh_socio and n.n > coalesce(a.num_socios, 0)),
  au as (insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
         select id, 'num_socios', antes::text, novo::text, 'conc_num_socios:certo' from alvo returning aluno_id)
  update public.thb_alunos a
     set num_socios = alvo.novo,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:num_socios] número de sócios = sócios ativos vinculados (' || coalesce(alvo.antes::text, 'vazio') || ' → ' || alvo.novo || ')')
    from alvo where a.id = alvo.id;
  get diagnostics k = row_count;

  -- 1b. num_socios: gravado maior que os vinculados → observação
  with nsoc as (select socio_de_aluno_id t, count(*) n from public.thb_alunos
                 where cancelado_em is null and socio_de_aluno_id is not null group by 1)
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:num_socios] ficha diz ' || a.num_socios || ' sócio(s), ' || coalesce(n.n, 0)
           || ' vinculado(s): sócio sem ficha ou sem vínculo (a confirmar)')
    from public.thb_alunos b left join nsoc n on n.t = b.id
   where a.id = b.id and a.cancelado_em is null and not a.eh_socio
     and coalesce(a.num_socios, 0) > coalesce(n.n, 0)
     and coalesce(a.obs_central, '') !~ '\[conc:num_socios\]';
  get diagnostics m = row_count;

  -- 2. observação nas falhas restantes
  o := 0;
  -- documento repetido em outra ficha ativa
  with d as (select id, regexp_replace(documento, '\D', '', 'g') doc from public.thb_alunos
              where cancelado_em is null and documento is not null and length(regexp_replace(documento, '\D', '', 'g')) >= 11),
  dup as (select doc from d group by 1 having count(*) > 1),
  alvo as (select d.id, (select string_agg(left(e.id::text, 8), ', ' order by e.id) from d e where e.doc = d.doc and e.id <> d.id) outros
             from d where d.doc in (select doc from dup))
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:documento_unico] mesmo documento nas fichas ' || alvo.outros || ': duplicata ou documento trocado (a confirmar)')
    from alvo where a.id = alvo.id and coalesce(a.obs_central, '') !~ '\[conc:documento_unico\]';
  get diagnostics k = row_count; o := o + k;
  -- CEP sem estado: faixa do CEP e cidade não concordam (ou endereço fora do Brasil)
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:uf] estado vazio: faixa do CEP e cidade não concordam ou endereço fora do Brasil (a confirmar)')
   where a.cancelado_em is null and a.cep is not null and a.estado is null and coalesce(a.obs_central, '') !~ '\[conc:uf\]';
  get diagnostics k = row_count; o := o + k;
  -- expiração já passou e a situação segue a_vencer/em_dia: não mexo em acesso sem conferir renovação
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:vencimento] expiração ' || to_char(a.data_expiracao, 'DD/MM/YYYY') || ' já passou e a situação segue ' || a.situacao_acesso || ': conferir renovação antes de mudar (a confirmar)')
   where a.cancelado_em is null and a.situacao_acesso in ('em_dia', 'a_vencer') and a.data_expiracao < current_date
     and coalesce(a.obs_central, '') !~ '\[conc:vencimento\]';
  get diagnostics k = row_count; o := o + k;
  -- nível: única declaração descartada (nome diferente no mesmo cadastro)
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''),
           '[2026-10-01] [conc:nivel] nível declarado não aplicado: declaração com outro nome no mesmo cadastro (a confirmar)')
   where a.id = '0c6019c1-7bf9-4936-ac96-3e4cf1cc32ac' and a.cancelado_em is null and coalesce(a.obs_central, '') !~ '\[conc:nivel\]';
  get diagnostics k = row_count; o := o + k;

  raise notice 'num_socios aplicados: %, num_socios com obs: %, outras obs: %', (select count(*) from public.cruzamentos_correcoes where regra = 'conc_num_socios:certo'), m, o;
  if (select count(*) from public.cruzamentos_correcoes where regra = 'conc_num_socios:certo') < 55 or m < 4 or o < 14 then
    raise exception 'contagem abaixo do esperado (61 num_socios, 4 obs, 14 outras): %, %', m, o;
  end if;
end $$;
