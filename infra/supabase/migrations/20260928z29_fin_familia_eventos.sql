-- 20260928z29 — Família EVENTOS (ingressos de Encontro THB, Congresso, Clínica, Imersão, Residência, Festa, Encontro
-- Internacional, Jornada) no espelho — item 5 da limpeza aprovada pelo João em 28/09.
-- Medido antes (simulação com rollback): 21 fusões de pessoas; 9 juntariam DOIS CPFs diferentes por e-mail ou CNPJ de
-- escritório compartilhado (Teruya Advocacia, JB Leopoldino, Molino e Rua…). Os 10 elos foram bloqueados; depois,
-- 12 fusões (e-mail + CPF da mesma pessoa) e 0 de CPFs diferentes. Taxa medida: 6% + R$ 1 (2.286), 5,3% + R$ 1 (1.427).
-- Fora, de propósito: Sessão de Viabilidade (1663254) e Croqui (1542521) — são do ESCRITÓRIO, e "Diamante" (3094430),
-- que é a mentoria.
insert into fin.identidade_bloqueio (valor, motivo)
select v, 'ligava dois CPFs diferentes (e-mail/CNPJ de escritório compartilhado) — promoção da família EVENTOS, 28/09/2026'
  from unnest(array['e:juliana@severoscalco.adv.br','e:corredeira100@gmail.com','e:advocacia.arb@gmail.com',
                    'e:leandroramalho.advogado@gmail.com','e:wsampaiojr.adv@gmail.com','e:bernadete1609@gmail.com',
                    'd:51620097000176','d:39406299000114','d:01193604000164','d:49410781000181']) v
on conflict do nothing;
update fin.produtos set familia = 'EVENTOS', sincroniza = true,
       nota = coalesce(nota || ' | ', '') || 'Família EVENTOS (ingressos de Encontro, Congresso, Clínica, Imersão, Residência) desde 28/09/2026'
 where produto_id in ('5951389','1560357','4127018','1976210','5682989','1228858','1666950','1462622','6792566','1667133',
                      '3094386','4432826','3400997','5683121','1537162','6144501','6489980','4486307')
   and familia = 'A_CLASSIFICAR';
select fin.recalcular_identidade();
