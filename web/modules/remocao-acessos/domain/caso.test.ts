import { describe, expect, it } from 'vitest';
import { filtrarCasos, situacaoPrazo } from './caso';
import type { CasoFila } from './types';

const agora = new Date('2026-09-16T15:00:00-03:00');

describe('situacaoPrazo', () => {
  it('caso encerrado não tem prazo correndo', () => {
    expect(situacaoPrazo({ status: 'concluido', prazo_em: '2026-09-01T12:00:00-03:00' }, agora)).toBe('encerrado');
    expect(situacaoPrazo({ status: 'alerta', prazo_em: null }, agora)).toBe('encerrado');
  });
  it('passou da hora = atrasado', () => {
    expect(situacaoPrazo({ status: 'em_remocao', prazo_em: '2026-09-16T14:59:00-03:00' }, agora)).toBe('atrasado');
  });
  it('mais tarde no mesmo dia (horário de Brasília) = vence hoje', () => {
    expect(situacaoPrazo({ status: 'aguardando_triagem', prazo_em: '2026-09-16T17:30:00-03:00' }, agora)).toBe('vence_hoje');
  });
  it('outro dia = no prazo, mesmo quando em UTC já é o dia seguinte', () => {
    expect(situacaoPrazo({ status: 'aguardando_triagem', prazo_em: '2026-09-17T09:00:00-03:00' }, agora)).toBe('no_prazo');
    const noite = new Date('2026-09-16T22:30:00-03:00'); // 01:30 UTC do dia 17
    expect(situacaoPrazo({ status: 'em_remocao', prazo_em: '2026-09-16T23:00:00-03:00' }, noite)).toBe('vence_hoje');
  });
  it('sem prazo gravado', () => {
    expect(situacaoPrazo({ status: 'em_remocao', prazo_em: null }, agora)).toBe('sem_prazo');
  });
});

describe('filtrarCasos', () => {
  const base = { meus_pendentes: 0 } as CasoFila;
  const casos = [
    { ...base, id: '1', status: 'aguardando_triagem' },
    { ...base, id: '2', status: 'em_remocao', meus_pendentes: 2 },
    { ...base, id: '3', status: 'alerta' },
    { ...base, id: '4', status: 'concluido' },
    { ...base, id: '5', status: 'mantem_acesso' },
  ] as CasoFila[];
  const ids = (f: Parameters<typeof filtrarCasos>[1]) => filtrarCasos(casos, f).map((c) => c.id);
  it('separa abertos, meus, alertas e encerrados', () => {
    expect(ids('abertos')).toEqual(['1', '2']);
    expect(ids('meus')).toEqual(['2']);
    expect(ids('alertas')).toEqual(['3']);
    expect(ids('encerrados')).toEqual(['4', '5']);
    expect(ids('todos')).toHaveLength(5);
  });
});
