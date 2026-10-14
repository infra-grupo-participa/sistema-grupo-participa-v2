import { describe, expect, it } from 'vitest';
import { AJUDA_EQUIPE, CARDS_COMPARECIMENTO } from './comparecimento';

describe('cards de comparecimento do ATM', () => {
  it('lê as colunas da RPC dados_atm_comparecimento, na ordem da tela', () => {
    expect(CARDS_COMPARECIMENTO.map((c) => c.chave)).toEqual([
      'total_leads', 'total_grupo', 'pico_audiencia', 'equipe_na_sala', 'pico_sobre_grupo_pct',
      'pico_sobre_leads_pct', 'vendas', 'conversao_pct', 'conversao_grupo_pct', 'conversao_pico_pct',
    ]);
  });
  it('rótulos e ordem pedidos pelo Victor (14/10/2026)', () => {
    expect(CARDS_COMPARECIMENTO.map((c) => c.rotulo)).toEqual([
      'Total de leads', 'Total no grupo', 'Pico da audiência', 'Pessoas da equipe na sala', 'Comparecimento do grupo',
      'Comparecimento dos leads', 'Vendas', 'Conversão', 'Conversão no grupo', 'Conversão sobre pico',
    ]);
  });
  it('comparecimento é percentual do pico, não contagem de presentes do Zoom', () => {
    const c = Object.fromEntries(CARDS_COMPARECIMENTO.map((x) => [x.rotulo, x]));
    expect(c['Comparecimento dos leads']).toMatchObject({ chave: 'pico_sobre_leads_pct', tipo: 'percentual' });
    expect(c['Comparecimento do grupo']).toMatchObject({ chave: 'pico_sobre_grupo_pct', tipo: 'percentual' });
    expect(CARDS_COMPARECIMENTO.some((x) => x.chave.startsWith('presentes'))).toBe(false);
  });
  it('a ajuda diz que a equipe está fora da conta', () => {
    expect(AJUDA_EQUIPE).toContain('sem as pessoas da equipe');
    expect(CARDS_COMPARECIMENTO.find((x) => x.chave === 'equipe_na_sala')?.ajuda).toContain('Fora do pico');
  });
});
