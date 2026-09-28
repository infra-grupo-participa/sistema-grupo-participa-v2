import { describe, expect, it } from 'vitest';
import { resumirTrajetoria, type PassoTrajetoria } from './trajetoria';

const p = (x: Partial<PassoTrajetoria>): PassoTrajetoria => ({
  dia: '2026-01-01', familia: 'HM', produto: 'X', oferta: null, situacao: 'pago', valor: 100, parcelas: 1,
  papel: 'compra', evento_id: null, evento: null, evento_categoria: null, turma: null, regra_evento: null, ...x,
});

describe('resumirTrajetoria', () => {
  it('agrupa por evento, conta participou/comprou e soma o pago', () => {
    const r = resumirTrajetoria([
      p({ dia: '2026-09-26', papel: 'programa', situacao: 'em aberto', valor: 15000, evento_id: 9, evento: 'HT32' }),
      p({ dia: '2025-05-14', papel: 'ingresso', valor: 495, evento_id: 1, evento: 'HT13' }),
      p({ dia: '2025-05-14', papel: 'ingresso', valor: 195, evento_id: 1, evento: 'HT13' }),
      p({ dia: '2025-10-05', papel: 'compra', valor: 1997, evento_id: 2, evento: 'HT16' }),
      p({ dia: '2025-11-01', papel: 'compra', situacao: 'estornado', valor: 300 }),
    ]);
    expect(r.etapas.map((e) => e.evento)).toEqual(['HT13', 'HT16', null, 'HT32']);
    expect(r.etapas[0].passos).toHaveLength(2);
    expect(r.funisParticipou).toBe(2);
    expect(r.funisComprou).toBe(1);
    expect(r.totalPago).toBe(2687);
    expect(r.estornado).toBe(300);
    expect(r.noPrograma).toBe(true);
    expect(r.primeiroContato).toBe('2025-05-14');
  });
  it('vazio', () => {
    expect(resumirTrajetoria([])).toMatchObject({ primeiroContato: null, funisParticipou: 0, etapas: [] });
  });
});
