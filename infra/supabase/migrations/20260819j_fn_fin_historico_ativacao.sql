-- APLICADA EM PRODUÇÃO 2026-08-19 — este arquivo é o registro do que rodou.
--
-- O histórico do comercial na ficha do financeiro.
--
-- ── Como apareceu ────────────────────────────────────────────────────────────
-- O Marcio perguntou se a integração com a ativação estava redonda. Testei
-- ponta a ponta (cada gesto do comercial numa transação com rollback) e quase
-- tudo refletia — menos isto: a ficha carregava extrato, compras e cobranças,
-- mas NÃO as interações da ativação.
--
-- São 2.822 registros de card (1.427 mudanças de estágio, 215 notas do
-- operador) que o financeiro nunca via.
--
-- É o elo que responde à pergunta central do pedido original: "o porquê aquele
-- aluno ainda não pagou" e "cobrar uma posição do comercial mediante aquele
-- aluno". Sem isso, o financeiro vê o saldo mas não vê a conversa que explica
-- o saldo.
--
-- Exemplo real (um card): a entrevista foi REAGENDADA 3 VEZES pela mesma
-- operadora antes de ser finalizada. É exatamente o tipo de coisa que muda a
-- conversa entre financeiro e comercial.
--
-- ── Desenho ──────────────────────────────────────────────────────────────────
-- Fonte: cs.interacoes (tipos: disparo | resposta | nota | mudanca_estagio |
-- sistema). Índice cs_interacoes_contato_hm_idx (contato_hm_id) já existe.
--
-- Limite 100: a ficha é 1 card por vez, sob clique. O maior card hoje tem ~40
-- interações; 100 cobre com folga e evita payload sem teto se algum virar caso
-- extremo.
--
-- `autor` em cs.interacoes é TEXTO LIVRE (nome da pessoa, 'sistema' ou
-- 'hotmart'), não FK — devolvido como está, sem inventar valor quando null.
--
-- `estagio_de`/`estagio_para` resolvidos para o nome legível do estágio; sem
-- isso o financeiro veria só ids. Preenchidos apenas em tipo='mudanca_estagio'.

create or replace function public.fn_fin_historico_ativacao(p_contato_hm_id uuid)
returns table (
  id uuid,
  quando timestamptz,
  tipo text,
  canal text,
  descricao text,
  autor text,
  estagio_de text,
  estagio_para text
)
language sql stable security definer set search_path to 'public', 'cs'
as $$
  select i.id,
         i.criado_em                as quando,
         i.tipo,
         i.canal,
         i.descricao,
         i.autor,
         ea.nome                    as estagio_de,
         en.nome                    as estagio_para
    from cs.interacoes i
    left join cs.estagios ea on ea.id = i.estagio_anterior_id
    left join cs.estagios en on en.id = i.estagio_novo_id
   where public.gp_pode_ver_financeiro()
     and i.contato_hm_id = p_contato_hm_id
   order by i.criado_em desc
   limit 100;
$$;

revoke all on function public.fn_fin_historico_ativacao(uuid) from public, anon;
grant execute on function public.fn_fin_historico_ativacao(uuid) to authenticated;

comment on function public.fn_fin_historico_ativacao(uuid) is
  'Histórico do comercial (cs.interacoes) para a ficha do financeiro — o que o '
  'operador fez no card: mudanças de estágio, notas, disparos, respostas. '
  'Responde "por que esse aluno ainda não pagou". 1 card por vez, sob clique, '
  'limite 100. autor é texto livre na origem (não FK).';
