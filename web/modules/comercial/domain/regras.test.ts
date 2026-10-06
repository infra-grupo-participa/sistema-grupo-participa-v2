import { describe, expect, it } from 'vitest';
import {
  bloqueioMudancaEtapa, calcularScore, camposFaltando, chaveTelefone, escolherDono, faixaDoScore, faixaLiberada,
  fmtTelefone, montarSck, motivoSupressao, situacaoSla, tempoNaEtapa,
} from './regras';
import type { Vendedor } from './types';

const agora = new Date('2026-10-05T15:00:00-03:00');
const minAtras = (m: number) => new Date(agora.getTime() - m * 60000).toISOString();

describe('situacaoSla', () => {
  it('primeiro contato: 5 min atenção, 15 min crítico', () => {
    expect(situacaoSla({ etapa: 'primeiro_contato', etapaDesde: minAtras(3), status: 'aberto' }, agora)).toBe('ok');
    expect(situacaoSla({ etapa: 'primeiro_contato', etapaDesde: minAtras(6), status: 'aberto' }, agora)).toBe('atencao');
    expect(situacaoSla({ etapa: 'primeiro_contato', etapaDesde: minAtras(15), status: 'aberto' }, agora)).toBe('critico');
  });
  it('negociar: 72 h atenção, 7 dias crítico', () => {
    expect(situacaoSla({ etapa: 'negociar', etapaDesde: minAtras(73 * 60), status: 'aberto' }, agora)).toBe('atencao');
    expect(situacaoSla({ etapa: 'negociar', etapaDesde: minAtras(7 * 24 * 60), status: 'aberto' }, agora)).toBe('critico');
  });
  it('fechado e negócio encerrado não têm alerta', () => {
    expect(situacaoSla({ etapa: 'fechado', etapaDesde: minAtras(99999), status: 'aberto' }, agora)).toBe('sem_sla');
    expect(situacaoSla({ etapa: 'qualificar', etapaDesde: minAtras(99999), status: 'perdido' }, agora)).toBe('sem_sla');
  });
});

describe('tempoNaEtapa', () => {
  it('minutos, horas e dias', () => {
    expect(tempoNaEtapa(minAtras(12), agora)).toBe('12 min');
    expect(tempoNaEtapa(minAtras(180), agora)).toBe('3 h');
    expect(tempoNaEtapa(minAtras(24 * 60), agora)).toBe('1 dia');
    expect(tempoNaEtapa(minAtras(3 * 24 * 60), agora)).toBe('3 dias');
  });
});

describe('mudança de etapa', () => {
  it('qualificar exige os três campos de qualificação', () => {
    expect(camposFaltando({ campos: {} }, 'qualificar')).toEqual(['perfil_profissional', 'atua_com_holding', 'produto_interesse']);
    expect(camposFaltando({ campos: { perfil_profissional: 'advogado', atua_com_holding: 'sim', produto_interesse: 'hm' } }, 'qualificar')).toEqual([]);
  });
  it('pular etapas cobra os campos das etapas puladas', () => {
    expect(camposFaltando({ campos: {} }, 'negociar')).toContain('perfil_profissional');
    expect(camposFaltando({ campos: {} }, 'negociar')).toContain('objecao_principal');
  });
  it('fechado só pela Hotmart: ganho é pagamento aprovado', () => {
    expect(bloqueioMudancaEtapa({ campos: {}, status: 'aberto' }, 'fechado')).toBe('ganho_so_com_pagamento');
  });
  it('negócio encerrado não muda de etapa', () => {
    expect(bloqueioMudancaEtapa({ campos: {}, status: 'perdido' }, 'qualificar')).toBe('negocio_encerrado');
  });
  it('primeiro contato não exige campo', () => {
    expect(bloqueioMudancaEtapa({ campos: {}, status: 'aberto' }, 'primeiro_contato')).toBeNull();
  });
});

describe('escolherDono', () => {
  const v = (id: string, percentual: number, ativo = true): Vendedor => ({
    id, nome: id, sigla: id, papel: 'vendedor', ativo, percentual, disparaApi: false,
  });
  const time = [v('marcos', 50), v('ronan', 50), v('jonathan', 0)];

  it('contato com dono mantém o dono', () => {
    expect(escolherDono({ donoId: 'ronan' }, time, { marcos: 0, ronan: 10 })).toBe('ronan');
  });
  it('dono inativo não segura o contato', () => {
    expect(escolherDono({ donoId: 'ze' }, [...time, v('ze', 0, false)], {})).toBe('marcos');
  });
  it('sem dono: vai para quem está mais abaixo da cota', () => {
    expect(escolherDono({ donoId: null }, time, { marcos: 3, ronan: 1 })).toBe('ronan');
  });
  it('respeita percentuais diferentes ao longo do ciclo', () => {
    const t = [v('a', 75), v('b', 25)];
    const rec: Record<string, number> = {};
    for (let i = 0; i < 8; i++) {
      const d = escolherDono({ donoId: null }, t, rec)!;
      rec[d] = (rec[d] ?? 0) + 1;
    }
    expect(rec).toEqual({ a: 6, b: 2 });
  });
  it('ninguém elegível: sem dono', () => {
    expect(escolherDono({ donoId: null }, [v('x', 0)], {})).toBeNull();
  });
});

describe('score de recuperação', () => {
  it('comportamento de compra conta só o maior', () => {
    expect(calcularScore(['boleto_aberto', 'carrinho'])).toBe(40);
    expect(calcularScore(['carrinho'])).toBe(24);
  });
  it('soma os sinais e respeita o teto de 100', () => {
    expect(calcularScore(['ficha_completa', 'senhas', 'advogado_contador'])).toBe(40);
    expect(calcularScore(['boleto_aberto', 'ficha_completa', 'senhas', 'chat', 'workbook', 'pesquisa', 'quer_parceria'])).toBe(100);
  });
  it('faixas A ≥ 60, B 40–59, C 25–39, D < 25', () => {
    expect([60, 59, 40, 39, 25, 24].map(faixaDoScore)).toEqual(['A', 'B', 'B', 'C', 'C', 'D']);
  });
  it('C e D só depois de A e B zeradas', () => {
    expect(faixaLiberada('C', 3)).toBe(false);
    expect(faixaLiberada('C', 0)).toBe(true);
    expect(faixaLiberada('A', 3)).toBe(true);
  });
});

describe('motivoSupressao', () => {
  const base = { contato: { id: '1', optOut: false }, negociosAbertosEtapas: [], ultimoDisparoEm: null, produtosComprados: [] };
  it('livre passa', () => {
    expect(motivoSupressao(base, 'hm', agora)).toBeNull();
  });
  it('as quatro supressões', () => {
    expect(motivoSupressao({ ...base, contato: { id: '1', optOut: true } }, 'hm', agora)).toBe('opt_out');
    expect(motivoSupressao({ ...base, produtosComprados: ['hm'] }, 'hm', agora)).toBe('ja_comprou');
    expect(motivoSupressao({ ...base, negociosAbertosEtapas: ['aguardar_pagamento'] }, 'hm', agora)).toBe('em_negociacao');
    expect(motivoSupressao({ ...base, ultimoDisparoEm: minAtras(47 * 60) }, 'hm', agora)).toBe('disparo_48h');
  });
  it('disparo há mais de 48 h não suprime; comprou outro produto não suprime', () => {
    expect(motivoSupressao({ ...base, ultimoDisparoEm: minAtras(49 * 60), produtosComprados: ['ht'] }, 'hm', agora)).toBeNull();
  });
});

describe('rastreabilidade e telefone', () => {
  it('SCK no padrão produto-acao-data-canal-sigla', () => {
    expect(montarSck('hm', 'Recuperação', new Date(2026, 9, 5), 'WhatsApp', 'MP')).toBe('hm-recuperacao-20261005-whatsapp-mp');
  });
  it('chave por últimos 8 dígitos', () => {
    expect(chaveTelefone('+55 (11) 98765-4321')).toBe('87654321');
    expect(chaveTelefone('1234')).toBeNull();
  });
  it('formata celular e fixo', () => {
    expect(fmtTelefone('5511987654321')).toBe('(11) 98765-4321');
    expect(fmtTelefone('1133334444')).toBe('(11) 3333-4444');
    expect(fmtTelefone(null)).toBe('—');
  });
});

describe('situacaoSla com alerta da etapa personalizada', () => {
  it('usa o sla do negócio quando vem', () => {
    const n = { etapa: 'qualificar' as const, etapaDesde: minAtras(20), status: 'aberto' as const };
    expect(situacaoSla({ ...n, sla: { atencaoMin: 10, criticoMin: 30 } }, agora)).toBe('atencao');
    expect(situacaoSla({ ...n, sla: null }, agora)).toBe('sem_sla');
    expect(situacaoSla(n, agora)).toBe('ok'); // padrão do playbook: 24 h
  });
});
