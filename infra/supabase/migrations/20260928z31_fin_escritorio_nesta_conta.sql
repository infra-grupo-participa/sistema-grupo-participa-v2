-- 20260928z31 — O histórico do ESCRITÓRIO de 2021–2024 está NESTA conta Hotmart (achado de 28/09): Sessão de Viabilidade
-- 571 pagas (R$ 871 mil) e Croqui 244 (R$ 1,45 mi). A conta mcsmarciosa vale de 2025 em diante.
-- Família ESCRITORIO (1 fusão de identidade medida, legítima); SV como oferta dos seminários; "conta não conectada" só
-- para seminário de 2025 em diante. Conferência 2022: S1 22 × 23 vendas; S2 R$ 31.256 × R$ 32.004; S3 R$ 54.974 × R$ 54.828.
update fin.produtos set familia = 'ESCRITORIO', sincroniza = true,
       nota = coalesce(nota || ' | ', '') || 'Família ESCRITORIO (Sessão de Viabilidade/Croqui 2021–2024 vendidos nesta conta; de 2025 em diante na conta mcsmarciosa) — 28/09/2026'
 where produto_id in ('1663254','1542521','1664749') and familia = 'A_CLASSIFICAR';
insert into fin.evento_produtos (categoria, produto_id, papel)
select c, p, 'oferta' from unnest(array['seminario_marcio','seminario_elaine']) c, unnest(array['1663254','1664749']) p
on conflict do nothing;
-- fn_fin_funis: conta_ausente = (setor = 'escritorio' and inicio >= 2025-01-01) — aplicado por replace sobre a função vigente.
select fin.recalcular_identidade();
