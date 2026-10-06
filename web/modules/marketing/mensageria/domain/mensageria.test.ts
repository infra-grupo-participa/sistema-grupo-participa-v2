import { describe, expect, it } from 'vitest';
import {
  API_FERRAMENTA, CANAIS, COLUNAS_PLANILHA, FINALIDADES, PENDENCIAS, ROTULO_API, ROTULO_CANAL, ROTULO_FINALIDADE,
  ROTULO_PENDENCIA, ROTULO_STATUS_NUMERO, ROTULO_TIPO, STATUS_NUMERO, TIPOS,
  camposAlterados, capacidadeForaDaFaixa, centavosParaCampo, dataHoraSP, fmtCentavos, hojeSP, inteiroDigitado,
  BASES_COBRANCA, ROTULO_BASE, custoExibido, fmtDuracao, fmtPrecoCentavos, haQuanto, linhaDaApi, precoReaisParaCentavos,
  resumoCusto, rotuloFonte, rotuloSituacaoPreco, situacaoFonte, situacaoPreco,
  FORMATO_COLUNA, lerPlanilha, modeloCsv, partesSP, periodoPadrao, reaisParaCentavos, rotuloPendencia, separarCsv, somarDias,
} from './mensageria';

// Intl usa espaço inseparável entre "R$" e o número.
const sp = (s: string | null) => (s == null ? s : s.replace(/ /g, ' '));

describe('listas iguais aos CHECKs do banco (20261005n + 20261005o)', () => {
  it('valores exatos', () => {
    expect(CANAIS).toEqual(['whatsapp_api', 'email', 'sms', 'ligacao', 'grupo']);
    expect(TIPOS).toEqual(['utility', 'marketing']);
    expect(FINALIDADES).toEqual(['mensageria', 'comercial', 'financeiro', 'suporte']);
    expect(STATUS_NUMERO).toEqual(['ativo', 'aquecendo', 'restrito', 'disponivel']);
    expect(API_FERRAMENTA).toEqual(['sim', 'futura', 'nao']);
    expect(PENDENCIAS).toEqual(['sem_custo', 'sem_retorno', 'conferir_zero_leitura', 'sem_preco', 'sem_projeto']);
    expect(BASES_COBRANCA).toEqual(['entregues', 'tamanho_lista', 'mensalidade']);
  });
  it('todo valor tem rótulo não vazio', () => {
    const pares: [readonly string[], Record<string, string>][] = [
      [CANAIS, ROTULO_CANAL], [TIPOS, ROTULO_TIPO], [FINALIDADES, ROTULO_FINALIDADE],
      [STATUS_NUMERO, ROTULO_STATUS_NUMERO], [API_FERRAMENTA, ROTULO_API], [PENDENCIAS, ROTULO_PENDENCIA],
      [BASES_COBRANCA, ROTULO_BASE],
    ];
    for (const [lista, rot] of pares) {
      expect(Object.keys(rot).sort()).toEqual([...lista].sort());
      for (const k of lista) expect(rot[k].trim()).not.toBe('');
    }
  });
  it('rótulos que a equipe lê', () => {
    expect(ROTULO_API.futura).toBe('Em breve');
    expect(ROTULO_API.nao).toBe('Não, registro manual');
  });
});

describe('rótulo de pendência', () => {
  it('as 5 do contrato (sem_custo agora = nem real nem estimado)', () => {
    expect(rotuloPendencia('sem_custo')).toBe('Sem custo, nem estimado');
    expect(rotuloPendencia('sem_preco')).toBe('Sem preço cadastrado');
    expect(rotuloPendencia('sem_projeto')).toBe('Sem projeto — classificar');
    expect(rotuloPendencia('sem_retorno')).toBe('Sem retorno');
    expect(rotuloPendencia('conferir_zero_leitura')).toBe('0 lidas com custo: conferir');
  });
  it('nome antigo do front parcial não existe mais', () => {
    expect(rotuloPendencia('lidas_zero_com_custo')).toBe('lidas_zero_com_custo');
  });
  it('pendência nova do banco aparece crua, não some', () => {
    expect(rotuloPendencia('outra_coisa')).toBe('outra_coisa');
  });
});

describe('centavos → R$', () => {
  it('formata centavos inteiros', () => {
    expect(sp(fmtCentavos(123456))).toBe('R$ 1.234,56');
    expect(sp(fmtCentavos(5))).toBe('R$ 0,05');
    expect(sp(fmtCentavos(9600))).toBe('R$ 96,00');
  });
  it('0 é zero; null é não lançado (null, nunca R$ 0,00)', () => {
    expect(sp(fmtCentavos(0))).toBe('R$ 0,00');
    expect(fmtCentavos(null)).toBeNull();
    expect(fmtCentavos(undefined)).toBeNull();
  });
  it('centavos → campo de edição', () => {
    expect(centavosParaCampo(123456)).toBe('1234,56');
    expect(centavosParaCampo(5)).toBe('0,05');
    expect(centavosParaCampo(0)).toBe('0,00');
    expect(centavosParaCampo(null)).toBe('');
  });
});

describe('R$ digitado → centavos', () => {
  it('formatos brasileiros', () => {
    expect(reaisParaCentavos('1.234,56')).toBe(123456);
    expect(reaisParaCentavos('1234,5')).toBe(123450);
    expect(reaisParaCentavos('R$ 90')).toBe(9000);
    expect(reaisParaCentavos('0')).toBe(0);
    expect(reaisParaCentavos('12.50')).toBe(1250);
    expect(reaisParaCentavos('1.234')).toBe(123400);
  });
  it('vazio = não lançado; lixo = inválido', () => {
    expect(reaisParaCentavos('')).toBeNull();
    expect(reaisParaCentavos('  ')).toBeNull();
    expect(reaisParaCentavos('-3')).toBeUndefined();
    expect(reaisParaCentavos('abc')).toBeUndefined();
    expect(reaisParaCentavos('1,234')).toBeUndefined();
  });
  it('inteiro digitado', () => {
    expect(inteiroDigitado('1.234')).toBe(1234);
    expect(inteiroDigitado('0')).toBe(0);
    expect(inteiroDigitado('')).toBeNull();
    expect(inteiroDigitado('1,5')).toBeUndefined();
    expect(inteiroDigitado('-1')).toBeUndefined();
  });
});

describe('datas em São Paulo', () => {
  it('instante com fuso vira hora de SP', () => {
    expect(partesSP('2026-10-05T17:30:00Z')).toEqual({ data: '2026-10-05', hora: '14:30' });
    expect(partesSP('2026-10-06T02:10:00+00:00')).toEqual({ data: '2026-10-05', hora: '23:10' });
    expect(dataHoraSP('2026-10-05T17:30:00Z')).toBe('05/10/2026 14:30');
  });
  it('hoje em SP e período padrão de 30 dias, hoje incluído', () => {
    expect(hojeSP(new Date('2026-10-06T02:00:00Z'))).toBe('2026-10-05');
    expect(periodoPadrao('2026-10-05')).toEqual({ de: '2026-09-06', ate: '2026-10-05' });
    expect(somarDias('2026-03-01', -1)).toBe('2026-02-28');
  });
  it('faixa de capacidade é só aviso', () => {
    expect(capacidadeForaDaFaixa(null)).toBe(false);
    expect(capacidadeForaDaFaixa(30)).toBe(false);
    expect(capacidadeForaDaFaixa(50)).toBe(false);
    expect(capacidadeForaDaFaixa(29)).toBe(true);
    expect(capacidadeForaDaFaixa(51)).toBe(true);
  });
});

describe('histórico: campos alterados', () => {
  it('ignora carimbos e lista só o que mudou', () => {
    const r = camposAlterados(
      { id: 1, lidas: null, custo_centavos: 100, atualizado_em: 'a' },
      { id: 1, lidas: 0, custo_centavos: 100, atualizado_em: 'b' },
    );
    expect(r).toEqual([{ campo: 'lidas', antes: null, depois: 0 }]);
  });
  it('inserção não tem antes', () => {
    expect(camposAlterados(null, { id: 1 })).toEqual([]);
  });
});

describe('planilha: separar colunas', () => {
  it('modelo: só o cabeçalho exato do contrato, com BOM, sem linha de exemplo', () => {
    const m = modeloCsv();
    expect(m.startsWith('﻿')).toBe(true);
    const linhas = m.replace(/^﻿/, '').trim().split('\r\n');
    expect(linhas).toEqual([
      'data;hora;projeto;canal;ferramenta;numero;tipo;copy_texto;copy_link;publico_lista;publico_origem;tamanho_lista;entregues;lidas;cliques;falhas;custo;disparado_por',
    ]);
    const l = lerPlanilha(m);
    expect(l.faltando).toEqual([]);
    expect(l.linhas).toEqual([]);
  });

  it('formato explicado para toda coluna do contrato', () => {
    expect(Object.keys(FORMATO_COLUNA).sort()).toEqual([...COLUNAS_PLANILHA].sort());
    for (const c of COLUNAS_PLANILHA) expect(FORMATO_COLUNA[c].trim()).not.toBe('');
  });

  it('`;` separa, aspas protegem `;`, aspas duplicadas e quebra de linha', () => {
    const t = 'a;b;c\r\n1;"x;y";"diz ""oi"""\r\n2;"linha\numa";\r\n';
    expect(separarCsv(t, ';')).toEqual([
      { n: 1, celulas: ['a', 'b', 'c'] },
      { n: 2, celulas: ['1', 'x;y', 'diz "oi"'] },
      { n: 3, celulas: ['2', 'linha\numa', ''] },
    ]);
  });

  it('vazio vira null; linha em branco é pulada e o número da linha no arquivo fica certo', () => {
    const cab = COLUNAS_PLANILHA.join(';');
    const l1 = '05/10/2026;14:30;PB26;E-mail;ActiveCampaign;;;Oi;;Inscritos;;100;;;;;;Ana';
    const t = `${cab}\n\n${l1}\n  \n${l1.replace('Ana', 'Bia')}\n`;
    const r = lerPlanilha(t);
    expect(r.linhas).toHaveLength(2);
    expect(r.linhaNoArquivo).toEqual([3, 5]);
    expect(r.linhas[0].entregues).toBeNull();
    expect(r.linhas[0].custo).toBeNull();
    expect(r.linhas[0].tipo).toBeNull();
    expect(r.linhas[0].tamanho_lista).toBe('100');
    expect(r.linhas[1].disparado_por).toBe('Bia');
  });

  it('não converte valores: "1.234" e "1.234,56" vão crus para o banco', () => {
    const t = `${COLUNAS_PLANILHA.join(';')}\n;;;;;;;;;;;1.234;;;;;1.234,56;`;
    const r = lerPlanilha(t);
    expect(r.linhas[0].tamanho_lista).toBe('1.234');
    expect(r.linhas[0].custo).toBe('1.234,56');
  });

  it('cabeçalho: ordem livre, maiúscula aceita; aponta coluna faltando e sobrando', () => {
    const r = lerPlanilha('Hora;DATA;extra\n14:30;05/10/2026;x');
    expect(r.linhas[0].data).toBe('05/10/2026');
    expect(r.linhas[0].hora).toBe('14:30');
    expect(r.faltando).toContain('projeto');
    expect(r.faltando).not.toContain('data');
    expect(r.sobrando).toEqual(['extra']);
  });

  it('colado do Excel (TAB) também separa', () => {
    const r = lerPlanilha(`${COLUNAS_PLANILHA.join('\t')}\n05/10/2026\t14:30\tPB26`);
    expect(r.faltando).toEqual([]);
    expect(r.linhas[0].projeto).toBe('PB26');
    expect(r.linhas[0].canal).toBeNull();
  });

  it('texto vazio', () => {
    const r = lerPlanilha('');
    expect(r.linhas).toEqual([]);
    expect(r.faltando).toHaveLength(COLUNAS_PLANILHA.length);
  });
});

describe('preço (centavos com 4 casas) → reais legível', () => {
  it('seed da 20261005o', () => {
    expect(sp(fmtPrecoCentavos(8))).toBe('R$ 0,08');
    expect(sp(fmtPrecoCentavos(36))).toBe('R$ 0,36');
    expect(sp(fmtPrecoCentavos(6.5))).toBe('R$ 0,065');
    expect(sp(fmtPrecoCentavos(0))).toBe('R$ 0,00');
  });
  it('4 casas e texto do numeric', () => {
    expect(sp(fmtPrecoCentavos(0.36))).toBe('R$ 0,0036');
    expect(sp(fmtPrecoCentavos('8.1234'))).toBe('R$ 0,081234');
    expect(sp(fmtPrecoCentavos(100000))).toBe('R$ 1.000,00');
  });
  it('vazio é null', () => {
    expect(fmtPrecoCentavos(null)).toBeNull();
    expect(fmtPrecoCentavos('')).toBeNull();
  });
});

describe('preço digitado em reais → centavos (texto, sem ponto flutuante)', () => {
  it('formatos aceitos', () => {
    expect(precoReaisParaCentavos('0,08')).toBe('8');
    expect(precoReaisParaCentavos('0,065')).toBe('6.5');
    expect(precoReaisParaCentavos('R$ 0,36')).toBe('36');
    expect(precoReaisParaCentavos('0.0036')).toBe('0.36');
    expect(precoReaisParaCentavos('1,5')).toBe('150');
    expect(precoReaisParaCentavos('0,081234')).toBe('8.1234');
    expect(precoReaisParaCentavos('0,1')).toBe('10');
    expect(precoReaisParaCentavos('0')).toBe('0');
  });
  it('vazio = null; fora do formato = undefined', () => {
    expect(precoReaisParaCentavos('  ')).toBeNull();
    expect(precoReaisParaCentavos('0,0000001')).toBeUndefined();
    expect(precoReaisParaCentavos('abc')).toBeUndefined();
    expect(precoReaisParaCentavos('1.000,00')).toBeUndefined();
    expect(precoReaisParaCentavos('-1')).toBeUndefined();
  });
  it('ida e volta', () => {
    for (const r of ['0,08', '0,065', '0,36', '0,0036']) expect(sp(fmtPrecoCentavos(precoReaisParaCentavos(r)))).toBe('R$ ' + r);
  });
});

describe('custo exibido na linha', () => {
  it('real prevalece, mesmo com estimado', () => {
    expect(custoExibido({ custo_centavos: 9600, custo_estimado_centavos: 9200, custo_fonte: 'real' })).toEqual({ k: 'real', c: 9600 });
    expect(custoExibido({ custo_centavos: 0, custo_estimado_centavos: 500, custo_fonte: 'real' })).toEqual({ k: 'real', c: 0 });
  });
  it('só estimado', () => {
    expect(custoExibido({ custo_centavos: null, custo_estimado_centavos: 9200, custo_fonte: 'estimado' })).toEqual({ k: 'estimado', c: 9200 });
  });
  it('sem preço nunca vira 0', () => {
    const c = custoExibido({ custo_centavos: null, custo_estimado_centavos: null, custo_fonte: 'sem_preco' });
    expect(c).toEqual({ k: 'sem_preco' });
    expect('c' in c).toBe(false);
  });
  it('custo_fonte null = preço por entregue sem entregues lançado', () => {
    expect(custoExibido({ custo_centavos: null, custo_estimado_centavos: null, custo_fonte: null })).toEqual({ k: 'falta_entregues' });
  });
  it('banco ainda na 20261005n (campo ausente) = não lançado', () => {
    expect(custoExibido({ custo_centavos: null })).toEqual({ k: 'nao_lancado' });
  });
});

describe('custo do período', () => {
  it('total = real + estimado; estimado à parte', () => {
    expect(resumoCusto({ custo_centavos: 1000, custo_estimado_centavos: 500, custo_total_centavos: 1500 })).toEqual({ total: 1500, estimado: 500 });
  });
  it('sem nada lançado: null, não 0', () => {
    expect(resumoCusto({ custo_centavos: null, custo_estimado_centavos: null, custo_total_centavos: null })).toEqual({ total: null, estimado: null });
  });
  it('banco na 20261005n: total = real', () => {
    expect(resumoCusto({ custo_centavos: 1000 })).toEqual({ total: 1000, estimado: null });
  });
});

describe('integração', () => {
  it('linha da API e rótulo da fonte', () => {
    expect(linhaDaApi({ origem: 'api' })).toBe(true);
    expect(linhaDaApi({ origem: 'manual' })).toBe(false);
    expect(rotuloFonte('unichat')).toBe('Unichat');
    expect(rotuloFonte('cs_disparos')).toBe('CS Disparos');
    expect(rotuloFonte('nova_fonte')).toBe('nova_fonte');
    expect(rotuloFonte(null)).toBe('integração');
  });
  it('tempo em linguagem leiga, pelo relógio do banco', () => {
    const agora = '2026-10-05T15:00:00-03:00';
    expect(haQuanto('2026-10-05T13:00:00-03:00', agora)).toBe('há 2 h');
    expect(haQuanto('2026-10-05T14:59:40-03:00', agora)).toBe('agora há pouco');
    expect(haQuanto('2026-10-05T14:15:00-03:00', agora)).toBe('há 45 min');
    expect(haQuanto('2026-10-02T15:00:00-03:00', agora)).toBe('há 3 dias');
    expect(haQuanto(null, agora)).toBeNull();
    expect(fmtDuracao(60)).toBe('1 h');
  });
  it('situação da fonte', () => {
    expect(situacaoFonte({ ativa: false, atrasada: false, ultima_ok_em: null })).toBe('desligada');
    expect(situacaoFonte({ ativa: true, atrasada: true, ultima_ok_em: '2026-10-05T10:00:00Z' })).toBe('atrasada');
    expect(situacaoFonte({ ativa: true, atrasada: false, ultima_ok_em: null })).toBe('aguardando');
    expect(situacaoFonte({ ativa: true, atrasada: false, ultima_ok_em: '2026-10-05T10:00:00Z' })).toBe('em_dia');
  });
});

describe('situação do preço', () => {
  const hoje = '2026-10-05';
  it('anulado, vigente, futuro, substituído', () => {
    expect(situacaoPreco({ anulado_em: '2026-10-01T10:00:00Z', vigente_hoje: false, vigente_desde: '2026-07-01' }, hoje)).toBe('anulado');
    expect(situacaoPreco({ anulado_em: null, vigente_hoje: true, vigente_desde: '2026-07-24' }, hoje)).toBe('vigente');
    expect(situacaoPreco({ anulado_em: null, vigente_hoje: false, vigente_desde: '2026-11-01' }, hoje)).toBe('futuro');
    expect(situacaoPreco({ anulado_em: null, vigente_hoje: false, vigente_desde: '2026-07-01' }, hoje)).toBe('substituido');
    expect(rotuloSituacaoPreco({ anulado_em: null, vigente_hoje: false, vigente_desde: '2026-11-01' }, hoje)).toBe('Começa em 01/11/2026');
  });
});
