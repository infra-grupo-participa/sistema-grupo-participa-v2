// ─────────────────────────────────────────────────────────────────────────────
// Modelo autoritativo do Holding Masters (HM) — FONTE ÚNICA no código (app web).
//
// Espelha o blueprint `docs/hm-ecosystem.md` e o Obsidian
// (`Oferta-Holding-Masters`, transcrição da Aula 6 — "é lei"). Mude o modelo
// AQUI; nunca espalhe estes números soltos pelo domínio/UI.
//
// Nota de ecossistema: SQL (funções `cs.*`/`fn_*`) e o webhook (Deno) têm suas
// próprias cópias destas regras — runtimes separados não compartilham este módulo.
// A autoridade cross-runtime é o blueprint. Ao mudar um número aqui, confira lá.
// ─────────────────────────────────────────────────────────────────────────────

// ── Valores do honorário (parceria / Programa de Implementação Assistida) ──────

/** Sinal de reserva de vaga (R$). Reembolsável e abatido do total na Reunião de Contratação. */
export const SINAL_RESERVA = 300;

/** 1ª metade do honorário (R$). Paga no início — NUNCA à vista, 12x (com juros). */
export const PRIMEIRA_METADE = 15_000;

/** 2ª metade do honorário (R$). CONDICIONAL: só devida após o parceiro faturar o MARCO. */
export const SEGUNDA_METADE = 15_000;

/** Honorário total da parceria (R$) = 20% de R$ 150.000. */
export const HONORARIO_TOTAL = PRIMEIRA_METADE + SEGUNDA_METADE; // 30.000

/** Faturamento do parceiro (R$) que torna a 2ª metade devida. */
export const MARCO_FATURAMENTO = 150_000;

/**
 * Marco em CENTAVOS — `thb_placas_auditoria.faturamento` grava o faturamento
 * confirmado em centavos. É essa a fonte do gatilho da 2ª metade (casa por aluno_id).
 */
export const MARCO_FATURAMENTO_CENTAVOS = MARCO_FATURAMENTO * 100; // 15.000.000

// ── Regras de cálculo ─────────────────────────────────────────────────────────

/**
 * Tolerância de centavos (R$). O arredondamento das 12x deixa resíduo de
 * R$ 0,01–0,04 no saldo mesmo com o aluno quitado: |saldo| < isto conta como 0.
 */
export const TOLERANCIA_CENTAVOS = 1;

/**
 * Corte da esteira HM (`cs.hm_config.cutoff`). Compras aprovadas ANTES disto são
 * legado (onboarding antigo) e ficam fora do financeiro/esteira novos, por design.
 */
export const CUTOFF_ESTEIRA = '2026-06-25';

// ── Produtos e ofertas (Hotmart) ──────────────────────────────────────────────

/** Produto core do HM. */
export const PRODUTO_HM_CORE = '5064314';
/** Produto de renovação/downsell do HM (renovação REAL vive aqui). */
export const PRODUTO_HM_RENOVACAO = '3507214';

/**
 * Categorias de oferta (`public.hm_product_catalog.categoria`). Toda oferta HM
 * precisa cair em uma destas; oferta sem categoria = furo (fica fora da esteira/razão).
 */
export type CategoriaOferta = 'sinal' | 'compra_cheia' | 'diferenca' | 'renovacao' | 'reserva';

export const CATEGORIA_OFERTA: Record<CategoriaOferta, { label: string; descricao: string }> = {
  sinal:        { label: 'Sinal',        descricao: 'Reserva de vaga (R$ 300 entrada, ou ~R$ 2k no evento)' },
  compra_cheia: { label: 'Compra cheia', descricao: 'Pacote pago cheio (não passou por sinal + saldo)' },
  diferenca:    { label: 'Saldo',        descricao: 'Pacote − sinal, à vista ou parcelado' },
  renovacao:    { label: 'Renovação',    descricao: 'Renovação real (produto 3507214)' },
  reserva:      { label: 'Reserva',      descricao: 'Downsell reserva (~R$ 2k, produto 3507214)' },
};

// ── Invariantes (guarda-corpos — quebrar = erro no ecossistema) ────────────────
// Documentadas por extenso em docs/hm-ecosystem.md §7. Resumo p/ quem lê o código:
//  I-1 Parcela ≠ renovação (anual ancorado na 1ª compra + 365; renovação real = 3507214).
//  I-2 Sinal-only = reserva de vaga, não aluno.
//  I-3 Reembolso propaga (compra estornada cancela card + aluno).
//  I-4 Boleto confirma no pagamento (não na geração).
//  I-5 Toda oferta HM catalogada.
//  I-6 Cascata completa (cliente pagou / juros / bruto / taxa / líquido).
//  I-7 Fuso America/Sao_Paulo nos agregados.
//  I-8 Uma fonte de "quitado" (tolerância de centavos concilia base × financeiro).
