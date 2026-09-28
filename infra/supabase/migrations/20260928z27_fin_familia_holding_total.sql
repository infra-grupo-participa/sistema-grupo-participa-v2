-- 20260928z27 — Holding Total vira família (HT) no espelho (João, 28/09: "o Holding Total é a entrada para o HM — tipo
-- um ingresso para o show do HM; precisa estar mapeado; coloca no Faturamento da Hotmart: Holding Total, Acelera,
-- Holding Masters, Aurum e Serviço Diamante, nessa ordem").
-- Medido antes (simulação com rollback): promover o HT funde 50 pessoas que hoje estão separadas no grafo de identidade;
-- 38 são e-mail + CPF da mesma pessoa e 6 são CPF + CNPJ da própria empresa (corretos), mas 6 juntariam DOIS CPFs
-- diferentes por um e-mail/CNPJ compartilhado (escritório, contador, compra para terceiros). Os 6 elos são bloqueados
-- (fin.identidade_bloqueio) — depois disso, 0 fusões de CPFs diferentes.
insert into fin.identidade_bloqueio (valor, motivo) values
  ('e:pedro@audicon.cnt.br', 'e-mail compartilhado ligava dois CPFs diferentes (promoção do HT, 28/09/2026)'),
  ('e:sa.holding.familiar@gmail.com', 'e-mail compartilhado ligava dois CPFs diferentes (promoção do HT, 28/09/2026)'),
  ('e:ramalhoimoveis1@gmail.com', 'e-mail compartilhado ligava dois CPFs diferentes (promoção do HT, 28/09/2026)'),
  ('e:maurilio.leonel@gmail.com', 'e-mail compartilhado ligava dois CPFs diferentes (promoção do HT, 28/09/2026)'),
  ('e:luizcabral@aasp.org.br', 'e-mail compartilhado ligava dois CPFs diferentes (promoção do HT, 28/09/2026)'),
  ('d:56439966000184', 'CNPJ usado por duas pessoas ligava dois CPFs diferentes (promoção do HT, 28/09/2026)')
on conflict do nothing;

update fin.produtos set familia = 'HT', sincroniza = true,
       nota = coalesce(nota || ' | ', '') || 'Família HT (Holding Total — entrada do HM) desde 28/09/2026'
 where produto_id in ('1560865','2414291','3094402','2413141','6990981','1561551','7273256','6989616','5022814','6992157','6991156')
   and familia = 'A_CLASSIFICAR';

select fin.recalcular_identidade();
