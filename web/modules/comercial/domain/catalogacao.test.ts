import { describe, expect, it } from 'vitest';
import {
  casaRegra, fraseRegra, linhasComoEntrou, mqlDoEvento, nomeProjeto, normCatalogo, rascunhoRegra, resolverProjeto, validarRegra,
  type RegraCatalogo,
} from './catalogacao';
import { paginarContatos, passaFiltro, resumirContatos, type ContatoLinha } from './contatos';
import type { Contato } from './types';

const regra = (id: number, campo: RegraCatalogo['campo'], operador: RegraCatalogo['operador'], padrao: string, projeto: string | null,
  extra: Partial<RegraCatalogo> = {}): RegraCatalogo => ({
  id, campo, operador, padrao, projeto, valeDe: null, valeAte: null, prioridade: 100, ativo: true, nota: null, ...extra,
});

// Mesmas regras-semente da migration 20261007141044 (amostra).
const REGRAS: RegraCatalogo[] = [
  regra(1, 'ac_lista', 'comeca', 'Patrimônio Brasil', 'seminario-conjunto-2026-11'),
  regra(2, 'ac_tag', 'igual', 'LEAD PB', 'seminario-conjunto-2026-11'),
  regra(3, 'ac_tag', 'comeca', 'PB ', 'seminario-conjunto-2026-11'),
  regra(4, 'ac_tag', 'contem', 'BLACK FRIDAY', 'black-friday-2026-10', { prioridade: 110 }),
  regra(5, 'hotmart_oferta', 'igual', '3mcmh0eu', 'imersao-holding-total-2026-09', { valeDe: '2026-09-01', valeAte: '2026-09-30' }),
  regra(6, 'hotmart_oferta', 'igual', 'jqigl9li', 'imersao-holding-total-2026-09'),
  regra(7, 'ac_lista', 'igual', '403', null, { prioridade: 200 }),
  regra(8, 'funil', 'igual', 'Clint · SESSÃO 22/09', 'seminario-elaine-2026-09'),
  regra(9, 'ac_tag', 'comeca', '[CNHF - AGO/2026]', 'cnhf-2026-08'),
];
const LISTAS = [{ id: '603', nome: 'Patrimônio Brasil - Geral' }, { id: '403', nome: 'Holding Total' }];

describe('casaRegra / normCatalogo', () => {
  it('compara sem acento, sem maiúscula e com espaços colapsados', () => {
    expect(normCatalogo('  Patrimônio   BRASIL ')).toBe('patrimonio brasil');
    expect(casaRegra('igual', 'lead pb', 'LEAD  PB')).toBe(true);
    expect(casaRegra('comeca', 'PB ', 'PB MQL')).toBe(true);
    expect(casaRegra('comeca', 'PB ', 'PBX')).toBe(false);
    expect(casaRegra('contem', 'black friday', 'LISTA DE ESPERA BLACK FRIDAY')).toBe(true);
    expect(casaRegra('igual', 'x', null)).toBe(false);
  });
});

describe('resolverProjeto (mesma ordem de crm.catalogo_resolver)', () => {
  const op = { listas: LISTAS, chavesConhecidas: ['black-friday-2026-10'] };
  it('tag PB e lista do PB pelo nome', () => {
    expect(resolverProjeto({ ac_tag: 'PB MQL' }, REGRAS, op).projeto).toBe('seminario-conjunto-2026-11');
    expect(resolverProjeto({ ac_lista: '603' }, REGRAS, op)).toMatchObject({ projeto: 'seminario-conjunto-2026-11', regraId: 1, motivo: 'regra', campo: 'ac_lista' });
  });
  it('lista 0 não é lista; sem nada = sem_dado', () => {
    expect(resolverProjeto({ ac_lista: '0' }, REGRAS, op)).toMatchObject({ projeto: null, motivo: 'sem_dado' });
  });
  it('regra "sem projeto" não para: o próximo campo pode ligar', () => {
    expect(resolverProjeto({ ac_lista: '403', ac_tag: 'PB NAO MQL' }, REGRAS, op).projeto).toBe('seminario-conjunto-2026-11');
    expect(resolverProjeto({ ac_lista: '403' }, REGRAS, op)).toMatchObject({ projeto: null, motivo: 'regra_sem_projeto', regraId: 7 });
  });
  it('utm_campaign igual a uma chave conhecida liga sozinha; desconhecida não', () => {
    expect(resolverProjeto({ utm_campaign: 'Black-Friday-2026-10' }, REGRAS, op)).toMatchObject({ projeto: 'black-friday-2026-10', motivo: 'utm' });
    expect(resolverProjeto({ utm_campaign: 'qualquer-coisa' }, REGRAS, op)).toMatchObject({ projeto: null, motivo: 'sem_regra' });
  });
  it('janela de datas: a oferta reaproveitada só vale dentro dela', () => {
    expect(resolverProjeto({ hotmart_oferta: '3mcmh0eu' }, REGRAS, { quando: '2026-09-12T10:00:00Z' }).projeto).toBe('imersao-holding-total-2026-09');
    expect(resolverProjeto({ hotmart_oferta: '3mcmh0eu' }, REGRAS, { quando: '2026-05-02T10:00:00Z' }).motivo).toBe('sem_regra');
  });
  it('produto sozinho não diz o projeto', () => {
    expect(resolverProjeto({ hotmart_produto: '1560865' }, REGRAS).motivo).toBe('sem_regra');
  });
  it('funil com projeto conhecido liga pelo funil; regra de funil pelo nome', () => {
    expect(resolverProjeto({ funil: 'X · Ativação', funil_projeto: 'black-friday-2026-10' }, REGRAS, op)).toMatchObject({ projeto: 'black-friday-2026-10', motivo: 'funil' });
    expect(resolverProjeto({ funil: 'clint · sessão 22/09' }, REGRAS).projeto).toBe('seminario-elaine-2026-09');
  });
  it('desempate: igual antes de começa; regra desativada não vale', () => {
    const r = [regra(20, 'ac_tag', 'comeca', 'PB', 'a-projeto'), regra(21, 'ac_tag', 'igual', 'PB MQL', 'b-projeto')];
    expect(resolverProjeto({ ac_tag: 'PB MQL' }, r).projeto).toBe('b-projeto');
    expect(resolverProjeto({ ac_tag: 'PB MQL' }, [{ ...r[1], ativo: false }, r[0]]).projeto).toBe('a-projeto');
  });
});

describe('validarRegra', () => {
  it('exige valor e projeto (ou "sem projeto"), chave no formato', () => {
    expect(validarRegra({ ...rascunhoRegra(), padrao: ' ' })).toEqual({ ok: false, erro: 'Escreva o valor ou o pedaço do nome.' });
    expect(validarRegra({ ...rascunhoRegra(), padrao: 'x' }).ok).toBe(false);
    expect(validarRegra({ ...rascunhoRegra(), padrao: 'x', projeto: 'Patrimônio Brasil' }).ok).toBe(false);
    const ok = validarRegra({ ...rascunhoRegra(), padrao: ' 603 ', projeto: 'Seminario-Conjunto-2026-11' });
    expect(ok).toEqual({ ok: true, regra: expect.objectContaining({ padrao: '603', projeto: 'seminario-conjunto-2026-11', prioridade: 100 }) });
    expect(validarRegra({ ...rascunhoRegra(), padrao: '403', semProjeto: true })).toEqual({ ok: true, regra: expect.objectContaining({ projeto: null }) });
  });
  it('janela invertida e prioridade fora da faixa', () => {
    expect(validarRegra({ ...rascunhoRegra(), padrao: 'x', projeto: 'abc', valeDe: '2026-10-01', valeAte: '2026-09-01' }).ok).toBe(false);
    expect(validarRegra({ ...rascunhoRegra(), padrao: 'x', projeto: 'abc', prioridade: '2000' }).ok).toBe(false);
  });
  it('rascunho de regra existente sem projeto vem marcado "sem projeto"', () => {
    expect(rascunhoRegra(REGRAS[6]).semProjeto).toBe(true);
    expect(rascunhoRegra(REGRAS[0]).semProjeto).toBe(false);
  });
});

describe('nomes e frases', () => {
  it('nome do projeto: cadastro, senão a chave legível', () => {
    expect(nomeProjeto('seminario-conjunto-2026-11', 'Patrimônio Brasil 2026')).toBe('Patrimônio Brasil 2026');
    expect(nomeProjeto('cnhf-2026-08')).toBe('Cnhf · 2026-08');
    expect(nomeProjeto('webijama-seminario')).toBe('Webijama seminario');
    expect(nomeProjeto(null)).toBe('Sem projeto');
  });
  it('frase da regra', () => {
    expect(fraseRegra({ ...REGRAS[4], projetoNome: null })).toBe('Oferta da Hotmart é igual a "3mcmh0eu" (de 2026-09-01 a 2026-09-30) → Imersao holding total · 2026-09');
    expect(fraseRegra(REGRAS[6])).toContain('→ sem projeto');
  });
  it('"Como entrou": a fonte de entrada primeiro', () => {
    const l = linhasComoEntrou({
      canal: 'clint',
      detalhe: {
        hotmart: { produto: 'Holding Total', ofertaCodigo: '4vn5e2td', classe: 'cartao_recusado', primeiraEm: '2026-02-01' },
        clint: { funil: 'Clint · MQLS', primeiraEm: '2026-09-23' },
        activecampaign: { tipo: 'update', primeiraEm: '2026-10-07' },
      },
    });
    expect(l.map((x) => x.fonte)).toEqual(['Clint', 'Hotmart', 'ActiveCampaign']);
    expect(l[1].texto).toBe('Holding Total · oferta 4vn5e2td (cartao recusado)');
    expect(l[2].texto).toBe('atualização de contato, sem lista nem tag');
  });
});

describe('filtro por canal e projeto (mesmo de crm_contatos_pagina)', () => {
  const base: Contato = {
    id: 'c1', nome: 'A', email: null, telefone: null, cidade: null, uf: null, perfil: null, atuaComHolding: null, donoId: null,
    tags: [], utm: {}, score: null, ehAluno: false, optOut: false, criadoEm: '2026-10-01T00:00:00Z',
  };
  const linha = (c: Partial<Contato>): ContatoLinha => ({ ...base, ...c, lancamentos: 0, ultimaInteracaoEm: null, abertos: [] });
  const pb = linha({ id: 'pb', origem: { canal: 'activecampaign', entrouEm: '', projeto: 'seminario-conjunto-2026-11', projetoNome: 'PB', linha: null } });
  const ht = linha({ id: 'ht', origem: { canal: 'hotmart', entrouEm: '', projeto: null, projetoNome: null, linha: 'ht' } });
  const sem = linha({ id: 'sem' });
  it('canal, projeto e "sem"', () => {
    expect(passaFiltro(pb, { canal: 'activecampaign' })).toBe(true);
    expect(passaFiltro(ht, { canal: 'activecampaign' })).toBe(false);
    expect(passaFiltro(sem, { canal: 'sistema' })).toBe(true);
    expect(paginarContatos([pb, ht, sem], { projeto: 'sem' }).itens.map((x) => x.id).sort()).toEqual(['ht', 'sem']);
    expect(paginarContatos([pb, ht, sem], { projeto: 'seminario-conjunto-2026-11' }).total).toBe(1);
  });
  it('resumo conta canais, projetos e sem projeto', () => {
    const r = resumirContatos([pb, ht, sem]);
    expect(r.canais).toEqual([{ canal: 'activecampaign', total: 1 }, { canal: 'hotmart', total: 1 }, { canal: 'sistema', total: 1 }]);
    expect(r.projetos).toEqual([{ chave: 'seminario-conjunto-2026-11', nome: 'PB', total: 1 }]);
    expect(r.semProjeto).toBe(2);
  });
});

describe('MQL por regra (mesma de crm.catalogo_mql)', () => {
  const regras = [...REGRAS, regra(30, 'ac_tag', 'igual', 'PB MQL', 'seminario-conjunto-2026-11', { tipo: 'mql' })];
  it('"PB MQL" é MQL; "PB NAO MQL" e "LEAD PB" não; projeto continua PB', () => {
    expect(mqlDoEvento({ ac_tag: 'PB MQL' }, regras)?.projeto).toBe('seminario-conjunto-2026-11');
    expect(mqlDoEvento({ ac_tag: 'PB NAO MQL' }, regras)).toBeNull();
    expect(mqlDoEvento({ ac_tag: 'LEAD PB' }, regras)).toBeNull();
    expect(resolverProjeto({ ac_tag: 'PB NAO MQL' }, regras).projeto).toBe('seminario-conjunto-2026-11');
  });
  it('regra de MQL exige tag/lista e projeto; frase marca MQL', () => {
    expect(validarRegra({ ...rascunhoRegra(), tipo: 'mql', campo: 'hotmart_oferta', padrao: 'x', projeto: 'abc' }).ok).toBe(false);
    expect(validarRegra({ ...rascunhoRegra(), tipo: 'mql', campo: 'ac_tag', padrao: 'x', semProjeto: true }).ok).toBe(false);
    expect(validarRegra({ ...rascunhoRegra(), tipo: 'mql', campo: 'ac_tag', padrao: 'PB MQL', projeto: 'seminario-conjunto-2026-11' }))
      .toEqual({ ok: true, regra: expect.objectContaining({ tipo: 'mql', projeto: 'seminario-conjunto-2026-11' }) });
    expect(fraseRegra(regras[regras.length - 1])).toContain('· MQL');
  });
});
