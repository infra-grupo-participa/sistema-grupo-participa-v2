# Hotmart sem negócio retroativo e lista do vendedor enxuta (06/10/2026)

> Decisão do Victor em 06/10/2026 (recomendação aprovada). Migration `20261006191824_crm_hotmart_sem_retroativo.sql`
> (**NÃO APLICADA**), ensaio `20261006191824_ensaio.sql`, notas `20261006191824.explain.md`, todos em
> `infra/supabase/migrations/`. Mais a busca no servidor na tela Contatos (`web/modules/comercial`).

## O que aconteceu

Em 06/10/2026 às 09:39 (Brasília) a Hotmart foi ligada no CRM com data de corte 01/01/2026 (`crm.log` id 1920721:
`hotmart_ligado` para true, `hotmart_desde` = 2026-01-01). O processamento reprocessou o ano inteiro e, em 2 minutos,
criou **2.640 negócios ganhos** (origem `compra_aprovada`, sem dono) nos funis "Checkout e recuperação · HT" (1.580),
"· HM" (551), "· Acelera" (400) e "· Aurum" (109), um por compra aprovada desde janeiro, e 1.742 contatos sem dono só de
compra. Isso contraria a D8 do Arthur ("sem negócio retroativo"), infla as vendas do comercial e fazia cada vendedor
enxergar 1.800 contatos sem dono.

## O que foi decidido

1. **Tirar os 2.640 ganhos retroativos**, com backup completo em `arquivo.*_20261006`. Nenhum tinha dono, atividade, nota
   ou mudança feita por vendedor (conferido; a seleção exige isso).
2. **As pessoas continuam.** Contatos comerciais não mudam (2.648). A compra fica como histórico na ficha (jornada).
3. **Daqui para frente**, compra aprovada **sem** negócio aberto da pessoa na mesma linha **não cria negócio ganho** (nem
   contato comercial): só entra na jornada. **Com** negócio aberto, ele vira ganho (como antes). Carrinho abandonado,
   cartão recusado, boleto/pix e pagamento expirado continuam criando negócio aberto para o vendedor. Quem comprou a linha
   nos últimos 30 dias continua fora da recuperação (agora contando também a compra na jornada).
4. **Lista do vendedor**: contato sem dono e sem negócio aberto não aparece na lista. Continua aparecendo na **busca**
   (nome, e-mail ou telefone, a partir de 3 letras) e a ficha abre normalmente. Gestor vê tudo. Máscara de e-mail e
   telefone não mudou. Exceção para não quebrar a gaveta do negócio: sem dono com negócio sem dono (57 perdidos da
   Clint) continua na lista, porque o vendedor já vê esse negócio no funil.
5. **Linhas por unidade** (registro): Holding Total, Holding Masters, Acelera, ETHB e Aurum são **CSM**; Sessão de
   Viabilidade é do **Escritório**. `crm.linha` não tem coluna de unidade e nada no CRM usa unidade hoje: **pendência**,
   sem coluna nova até existir uso.

## Números do ensaio no banco real (06/10/2026, desfeito no fim)

| | Antes | Depois |
|---|---|---|
| Negócios | 3.666 (967 abertos, 2.640 ganhos, 59 perdidos) | 1.026 (967 abertos, 0 ganhos, 59 perdidos) |
| Contatos comerciais | 2.648 | 2.648 |
| Lista do gestor | 2.648 | 2.648 |
| Lista do vendedor mp | 2.247 (1.800 sem dono) | 505 (58 sem dono) |
| Lista do vendedor ro | 2.201 (1.800 sem dono) | 459 (58 sem dono) |

Os 1.026 negócios que ficam saíram idênticos (966 com dono, 967 abertos). Compra simulada no ensaio: sem negócio aberto,
"jornada: compra sem negócio aberto (não cria ganho)" e nenhum negócio; carrinho abandonado abriu negócio e a compra
seguinte converteu esse mesmo negócio em ganho; cartão recusado de quem acabou de comprar não abriu recuperação.

## Backup (schema `arquivo`, fora da API)

`crm_negocio_retro_20261006` (2.640), `crm_hotmart_processado_retro_20261006` (2.642), `crm_log_retro_20261006` (2.641),
`crm_slack_fila_retro_20261006` (2), `crm_atividade_retro_20261006`, `crm_nota_retro_20261006` e
`crm_notificacao_retro_20261006` (0, criadas para a prova ficar completa). Para desfazer: bloco REVERSÃO no fim da migration.

## Como aplicar

1. Deploy do front desta branch (a busca no servidor da tela Contatos) junto com a migration.
2. `python3 "Central-de-Alunos/scripts/thb-implementacao/aplica_sql.py" aplicar infra/supabase/migrations/20261006191824_crm_hotmart_sem_retroativo.sql`
3. Conferir: `select status, count(*) from crm.negocio group by 1` (esperado 0 ganhos) e a lista de um vendedor (~500).
4. Trocar o STATUS no topo da migration e do `.explain.md` para APLICADA.

## Front (tela Contatos)

- `repo.buscarContatos(texto)`: uma chamada a `crm_contatos` com `p_busca` (até 50), a partir de 3 letras e 400 ms depois
  da última tecla. Os achados entram só no resultado da busca (não nos números do topo).
- A ficha aberta a partir da busca usa o contato achado (`contatoReserva` + `reservaDaBusca`), sem o aviso de "contato de
  demonstração".
- Balão de "Contatos sem dono" explica que, para o vendedor, a lista traz só os sem dono com negócio aberto.
