-- 20261004j — Conciliação do nível, rodada 2 (30/09/2026)
-- 4 fichas que o placar ainda acusava abaixo do maior nível declarado no Respondi e que
-- ficaram fora da rodada 1. Mesmas regras da 20261004i: nunca rebaixa, valor anterior em
-- public.cruzamentos_correcoes, update só se o valor atual não mudou.
create temp table _c (aluno_id uuid, atual text, novo text, aplica boolean, regra text, obs text) on commit drop;
insert into _c values
('a9e34a16-9241-4112-98da-8a14357a1bf1'::uuid,'profissional','ouro',true,'conc_nivel:a_confirmar','Nível ajustado de profissional para ouro em 30/09/2026: última declaração no Respondi foi ouro (07/2024), dúvida: declaração com mais de 18 meses. (a confirmar)'),
('377e4ae5-fb07-4fb9-bd5f-5c863f51ef64'::uuid,'em_formacao','profissional',false,'conc_nivel:a_confirmar','Nível mantido em em_formacao (30/09/2026): última declaração no Respondi confirma em_formacao; houve declaração maior antes (profissional) — a confirmar com o aluno.'),
('364bae0b-f615-470d-be08-fedf195e65bf'::uuid,'em_formacao','profissional',false,'conc_nivel:a_confirmar','Nível mantido em em_formacao (30/09/2026): última declaração no Respondi confirma em_formacao; houve declaração maior antes (profissional) — a confirmar com o aluno.'),
('e23bd1e9-357b-4af0-9459-8eb4c50ae05b'::uuid,'profissional','ouro',false,'conc_nivel:a_confirmar','Nível mantido em profissional (30/09/2026): última declaração no Respondi confirma profissional; houve declaração maior antes (ouro) — a confirmar com o aluno.');

insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
select c.aluno_id, 'nivel_resultado', c.atual, c.novo, c.regra
from _c c join public.thb_alunos a on a.id = c.aluno_id
where c.aplica and a.cancelado_em is null and a.nivel_resultado is not distinct from c.atual;

do $$
declare n int; m int;
begin
  update public.thb_alunos a
     set nivel_resultado = c.novo,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-09-30] ' || c.obs)
    from _c c
   where a.id = c.aluno_id and c.aplica and a.cancelado_em is null
     and a.nivel_resultado is not distinct from c.atual;
  get diagnostics n = row_count;
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-09-30] ' || c.obs)
    from _c c
   where a.id = c.aluno_id and not c.aplica and a.cancelado_em is null;
  get diagnostics m = row_count;
  raise notice 'nivel aplicado: %, só observação: %', n, m;
  if n <> 1 or m <> 3 then raise exception 'esperado 1 nível e 3 observações, deu % e %', n, m; end if;
end $$;
