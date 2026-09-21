import { describe, expect, it } from 'vitest';
import { filtrarCasos, situacaoPrazo, sugestaoAjuste } from './caso';
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
    { ...base, id: '6', status: 'ajustando_acesso' },
  ] as CasoFila[];
  const ids = (f: Parameters<typeof filtrarCasos>[1]) => filtrarCasos(casos, f).map((c) => c.id);
  it('separa abertos, meus, alertas e encerrados', () => {
    expect(ids('abertos')).toEqual(['1', '2', '6']);
    expect(ids('meus')).toEqual(['2']);
    expect(ids('alertas')).toEqual(['3']);
    expect(ids('encerrados')).toEqual(['4', '5']);
    expect(ids('todos')).toHaveLength(6);
  });
});

describe('sugestaoAjuste', () => {
  const aluno = { instrucao: 'THB IMPLEMENTAÇÃO', espaco: null, turma: null, data_expiracao: '2027-08-31',
    data_entrada_thb: null, status_central: null, eh_socio: false };
  it('pega a data de antes da mudança que levou à expiração atual', () => {
    const r = sugestaoAjuste({ aluno, historico_expiracao: [
      { de: '2026-12-31', para: '2027-08-31', origem: 'x', em: '2026-09-10' },
      { de: '2026-06-30', para: '2026-12-31', origem: 'x', em: '2026-01-10' },
    ] });
    expect(r).toEqual({ expiracao: '2026-12-31', instrucao: 'THB' });
  });
  it('sem histórico que bata, não inventa data', () => {
    expect(sugestaoAjuste({ aluno: { ...aluno, instrucao: 'THB' }, historico_expiracao: [] })).toEqual({ expiracao: '', instrucao: '' });
    expect(sugestaoAjuste(null)).toEqual({ expiracao: '', instrucao: '' });
  });
});
