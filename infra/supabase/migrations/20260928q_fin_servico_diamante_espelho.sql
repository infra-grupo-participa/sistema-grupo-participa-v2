-- 20260928q — Espelhar o "Serviço Diamante" (1462643). Pedido do João, 27/09/2026: reunir num lugar só os serviços
-- Diamante (tráfego, web design, vídeo, copy, social media, design gráfico, disparos) e ver quem contratou, quem
-- está em dia e quem deve, desde o começo.
-- Apurado no projeto "Serviços Diamante" (npqyvjhvtfahuxfmuhie, portal.hotmart_offers/hotmart_purchases): TODOS
-- os serviços são UM produto na Hotmart (1462643) com uma oferta por serviço e geração (12 ofertas). 1ª compra
-- registrada lá: 11/2017.
-- Entra com a família 'A_CLASSIFICAR' (nenhuma tela lê e o grafo de identidade exclui) até o histórico estar
-- completo e a junção de pessoas ser medida; a 20260928r promove para 'DIAMANTE'.
-- Reverter: update fin.produtos set sincroniza = false where produto_id = '1462643';
insert into fin.produtos (produto_id, nome, familia, papel, sincroniza, nota)
values ('1462643', 'Serviço Diamante', 'A_CLASSIFICAR', 'servico', true,
        'Serviços Diamante (mensalidade por serviço; uma oferta por serviço e geração). Exclusivo de Diamante/Diamante Vermelho.')
on conflict (produto_id) do nothing;

-- História inteira em janelas de 60 dias, desde 2017.
insert into fin.hotmart_sync_fila (produto_id, inicio, fim, tipo)
select '1462643', g::date, least(g::date + 59, (now() at time zone 'America/Sao_Paulo')::date), 'backfill'
  from generate_series(date '2017-01-01', (now() at time zone 'America/Sao_Paulo')::date, interval '60 days') g
on conflict do nothing;
