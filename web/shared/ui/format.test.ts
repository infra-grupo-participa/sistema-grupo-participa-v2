// Trava do bug achado em 2026-08-27 (fable-orchestrator): a faixa de destaque
// da ficha e o card do board usavam `fmtRelativo` — formatador de PASSADO — em
// campo de VENCIMENTO. Como fmtRelativo colapsa `dias <= 0` em "hoje", toda
// conta com vencimento futuro exibia "vence hoje", justamente na tela que
// existe para responder "estou atrasado?".
//
// Estes testes existem para o formatador de futuro nunca regredir para o de
// passado. `hojeISO` é injetado — nenhum teste aqui depende do relógio.
import { describe, expect, it } from 'vitest';
import { fmtPrazo, fmtRelativo } from './format';

const HOJE = '2026-08-27';

describe('fmtPrazo — prazo futuro', () => {
  it('vence no próprio dia', () => {
    expect(fmtPrazo('2026-08-27', HOJE)?.label).toBe('vence hoje');
  });

  it('vence amanhã', () => {
    expect(fmtPrazo('2026-08-28', HOJE)?.label).toBe('vence amanhã');
  });

  it('É O BUG: futuro próximo não pode virar "hoje"', () => {
    // fmtRelativo devolvia 'hoje' para TODOS estes.
    expect(fmtPrazo('2026-08-29', HOJE)?.label).toBe('vence em 2 dias');
    expect(fmtPrazo('2026-09-03', HOJE)?.label).toBe('vence em 7 dias');
    expect(fmtPrazo('2026-09-10', HOJE)?.label).toBe('vence em 14 dias');
  });

  it('acima de 30 dias mostra a data, não a contagem', () => {
    // "vence em 87 dias" não ajuda ninguém a agir; a data, sim.
    expect(fmtPrazo('2026-12-25', HOJE)?.label).toMatch(/^vence \d{2}\/\d{2}\/\d{4}$/);
  });

  it('passado devolve null — quem está atrasado tem o chip de atraso', () => {
    expect(fmtPrazo('2026-08-26', HOJE)).toBeNull();
    expect(fmtPrazo('2025-01-01', HOJE)).toBeNull();
  });

  it('entrada ausente ou inválida devolve null, nunca quebra o render', () => {
    expect(fmtPrazo(null, HOJE)).toBeNull();
    expect(fmtPrazo(undefined, HOJE)).toBeNull();
    expect(fmtPrazo('', HOJE)).toBeNull();
    expect(fmtPrazo('não é data', HOJE)).toBeNull();
  });

  it('aceita timestamp completo, usando só a parte da data', () => {
    expect(fmtPrazo('2026-08-29T23:59:00Z', HOJE)?.label).toBe('vence em 2 dias');
  });

  it('não desliza um dia por fuso (calendário puro, sem UTC-meia-noite)', () => {
    // 'YYYY-MM-DD' via new Date() vira UTC-meia-noite e, em fuso brasileiro,
    // exibia o dia anterior — a mesma armadilha que fmtData() já documenta.
    expect(fmtPrazo('2026-01-01', '2026-01-01')?.label).toBe('vence hoje');
    expect(fmtPrazo('2026-03-01', '2026-02-28')?.label).toBe('vence amanhã');
  });

  it('atravessa virada de mês e de ano', () => {
    expect(fmtPrazo('2026-09-01', '2026-08-31')?.label).toBe('vence amanhã');
    expect(fmtPrazo('2027-01-01', '2026-12-31')?.label).toBe('vence amanhã');
  });
});

describe('fmtRelativo — formatador de PASSADO (contrato preservado)', () => {
  it('continua sendo passado — é por isso que não serve para vencimento', () => {
    // Documenta o contrato que causou o bug: qualquer futuro vira 'hoje'.
    const futuro = new Date(Date.now() + 14 * 86400000).toISOString();
    expect(fmtRelativo(futuro).label).toBe('hoje');
  });
});
