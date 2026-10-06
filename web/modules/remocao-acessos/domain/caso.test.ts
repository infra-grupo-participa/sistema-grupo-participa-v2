import { describe, expect, it } from 'vitest';
import { filtrarCasos, filtrarLinha, linhaDoCaso, linhaDoItem, meusItensDaLinha, rotuloDataCaso, rotuloStatus, situacaoPrazo, sugestaoAjuste } from './caso';
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
  it('caso da carga (prazo nulo ou ausente) nunca fica atrasado, nem anos depois', () => {
    const muitoDepois = new Date('2030-01-01T12:00:00-03:00');
    expect(situacaoPrazo({ status: 'em_remocao', prazo_em: null }, muitoDepois)).toBe('sem_prazo');
    expect(situacaoPrazo({ status: 'em_remocao' }, muitoDepois)).toBe('sem_prazo');
    expect(situacaoPrazo({ status: 'em_remocao', prazo_em: '' }, muitoDepois)).toBe('sem_prazo');
  });
});

describe('linha do caso', () => {
  it('sem linha (banco antigo) é Holding Masters', () => {
    expect(linhaDoCaso({})).toBe('hm');
    expect(linhaDoCaso({ linha: null })).toBe('hm');
    expect(linhaDoCaso({ linha: 'hm' })).toBe('hm');
    expect(linhaDoCaso({ linha: 'acelera' })).toBe('acelera');
  });
  it('alerta do Acelera não se chama Disputa; o do HM continua', () => {
    expect(rotuloStatus({ status: 'alerta', linha: 'acelera' })).toBe('Alerta');
    expect(rotuloStatus({ status: 'alerta', linha: 'hm' })).toBe('Disputa (alerta)');
    expect(rotuloStatus({ status: 'em_remocao', linha: 'acelera' })).toBe('Removendo acessos');
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

  const mistos = [
    { ...base, id: 'h1', status: 'em_remocao', meus_pendentes: 1 },
    { ...base, id: 'h2', status: 'alerta', linha: 'hm' },
    { ...base, id: 'a1', status: 'em_remocao', linha: 'acelera', meus_pendentes: 3 },
    { ...base, id: 'a2', status: 'alerta', linha: 'acelera' },
    { ...base, id: 'a3', status: 'concluido', linha: 'acelera' },
  ] as CasoFila[];
  const idsLinha = (f: Parameters<typeof filtrarCasos>[1], l: 'hm' | 'acelera') => filtrarCasos(mistos, f, l).map((c) => c.id);
  it('separa por linha: a fila do HM não mostra caso do Acelera e vice-versa', () => {
    expect(filtrarLinha(mistos, 'hm').map((c) => c.id)).toEqual(['h1', 'h2']);
    expect(filtrarLinha(mistos, 'acelera').map((c) => c.id)).toEqual(['a1', 'a2', 'a3']);
    expect(idsLinha('todos', 'hm')).toEqual(['h1', 'h2']);
    expect(idsLinha('abertos', 'acelera')).toEqual(['a1']);
    expect(idsLinha('alertas', 'acelera')).toEqual(['a2']);
    expect(idsLinha('encerrados', 'acelera')).toEqual(['a3']);
  });
  it('"meus" respeita a linha', () => {
    expect(idsLinha('meus', 'hm')).toEqual(['h1']);
    expect(idsLinha('meus', 'acelera')).toEqual(['a1']);
  });
  it('sem linha, filtra tudo como antes', () => {
    expect(filtrarCasos(mistos, 'meus').map((c) => c.id)).toEqual(['h1', 'a1']);
  });
});

describe('meusItensDaLinha', () => {
  // O Thomas tem dois "Obvio": o rótulo não separa, a chave separa.
  const thomas = [
    { item: 'obvio', rotulo: 'Obvio' },
    { item: 'acelera_grupo_informes', rotulo: 'Grupo de informes' },
    { item: 'acelera_area_membros', rotulo: 'Área de membros (Hotmart)' },
    { item: 'acelera_obvio', rotulo: 'Obvio' },
  ];
  it('separa pela chave, mesmo com rótulo repetido', () => {
    expect(meusItensDaLinha(thomas, 'hm')).toEqual(['Obvio']);
    expect(meusItensDaLinha(thomas, 'acelera')).toEqual(['Grupo de informes', 'Área de membros (Hotmart)', 'Obvio']);
  });
  it('linha explícita vence a chave', () => {
    expect(meusItensDaLinha([{ item: 'x', rotulo: 'X', linha: 'acelera' }], 'acelera')).toEqual(['X']);
    expect(meusItensDaLinha([{ item: 'acelera_x', rotulo: 'X', linha: 'hm' }], 'acelera')).toEqual([]);
  });
  it('catálogo: linha do banco, ou pela chave quando o banco não manda', () => {
    expect(linhaDoItem({ item: 'obvio' })).toBe('hm');
    expect(linhaDoItem({ item: 'acelera_obvio' })).toBe('acelera');
    expect(linhaDoItem({ item: 'acelera_obvio', linha: null })).toBe('acelera');
    expect(linhaDoItem({ item: 'obvio', linha: 'acelera' })).toBe('acelera');
  });
  it('formato antigo (só rótulo) é todo do HM', () => {
    expect(meusItensDaLinha(['Obvio', 'Central'], 'hm')).toEqual(['Obvio', 'Central']);
    expect(meusItensDaLinha(['Obvio'], 'acelera')).toEqual([]);
    expect(meusItensDaLinha(null, 'hm')).toEqual([]);
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

describe('rotuloDataCaso', () => {
  it('caso importado mostra a data da compra', () => {
    expect(rotuloDataCaso({ origem: 'carga' })).toBe('Compra em');
  });
  it('demais origens mostram quando ocorreu', () => {
    expect(rotuloDataCaso({ origem: 'webhook' })).toBe('Ocorreu em');
    expect(rotuloDataCaso({ origem: 'compras' })).toBe('Ocorreu em');
    expect(rotuloDataCaso({})).toBe('Ocorreu em');
  });
});
