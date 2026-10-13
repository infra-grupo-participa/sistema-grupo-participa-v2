import { describe, expect, it } from 'vitest';
import { BOM, celula, csvForaPadrao, csvPrincipal, filtrarBusca, grupoSaida, haQuanto, LISTAS, nomeArquivo, type PessoaLista } from './listas';
import { mapearLista, mapearResumo } from '../infrastructure/listas-supabase';

const p = (o: Partial<PessoaLista> = {}): PessoaLista => ({
  nome: 'Ana Teste', email: 'ana@exemplo.com', telefone: '5511900000001', telefoneComoVeio: null, motivo: null,
  segmento: 'advogado', semProfissao: false, grupoBlack: 'nunca', grupoConsultoria: 'nunca', saiuBlackDe: null, saiuConsultoriaDe: null,
  fontes: ['captacao'], ...o,
});
const preset = (id: string) => LISTAS.find((l) => l.id === id)!;

describe('listas de disparo', () => {
  it('CSV principal: BOM, cabeçalho Nome, Email, Telefone e escape', () => {
    const csv = csvPrincipal(preset('live_consultoria'), [p({ nome: 'Silva, "Zé"' })]);
    expect(csv.startsWith(BOM)).toBe(true);
    expect(csv.slice(1).split('\r\n')).toEqual(['Nome,Email,Telefone', '"Silva, ""Zé""",ana@exemplo.com,5511900000001']);
  });
  it('saíram do grupo: colunas grupo de onde saiu e segmento', () => {
    const csv = csvPrincipal(preset('sairam_grupo'), [p({ grupoConsultoria: 'saiu', saiuConsultoriaDe: 'Método Perfeito - 03/11 #1', segmento: 'outros' })]);
    expect(csv.slice(1).split('\r\n')).toEqual(['Nome,Email,Telefone,Grupo de onde saiu,Segmento', 'Ana Teste,ana@exemplo.com,5511900000001,Consultoria: Método Perfeito - 03/11 #1,Outros']);
  });
  it('fora do padrão: telefone como veio e motivo', () => {
    const csv = csvForaPadrao([p({ telefone: null, telefoneComoVeio: '351900000002', motivo: 'DDI fora do Brasil (prefixo 351)' })]);
    expect(csv.slice(1).split('\r\n')[1]).toBe('Ana Teste,ana@exemplo.com,351900000002,DDI fora do Brasil (prefixo 351)');
  });
  it('nome do arquivo no horário de Brasília', () => {
    const d = new Date('2026-10-13T21:05:00Z'); // 18h05 em Brasília
    expect(nomeArquivo(preset('fora_grupo'), 'advogado', d)).toBe('black_fora-do-grupo_advogado_2026-10-13_18h05.csv');
    expect(nomeArquivo(preset('live_consultoria'), 'geral', d)).toBe('black_live-consultoria_2026-10-13_18h05.csv');
    expect(nomeArquivo(preset('fora_grupo'), 'geral', d, true)).toBe('black_fora-do-grupo_fora-do-padrao_2026-10-13_18h05.csv');
  });
  it('grupo de saída junta Black e consultoria', () => {
    expect(grupoSaida(p({ grupoBlack: 'saiu', saiuBlackDe: 'BF26 - Live 03/11 - Outros', grupoConsultoria: 'saiu', saiuConsultoriaDe: null })))
      .toBe('Black: BF26 - Live 03/11 - Outros; Consultoria: grupo da consultoria');
  });
  it('busca sem acento por nome, e-mail e telefone', () => {
    const l = [p({ nome: 'José Antônio' }), p({ nome: 'Maria', email: 'm@x.com', telefone: '5521988887777' })];
    expect(filtrarBusca(l, 'jose').length).toBe(1);
    expect(filtrarBusca(l, '8888').length).toBe(1);
    expect(filtrarBusca(l, '').length).toBe(2);
  });
  it('célula sem caractere especial fica como está', () => { expect(celula('abc')).toBe('abc'); expect(celula(null)).toBe(''); });
  it('há quanto tempo', () => {
    const a = new Date('2026-10-13T12:00:00Z');
    expect(haQuanto(new Date('2026-10-13T11:57:00Z'), a)).toBe('há 3 min');
    expect(haQuanto(null, a)).toBe('sem horário');
  });
  it('mapeadores aceitam resposta parcial sem quebrar', () => {
    expect(mapearResumo({ listas: { 'fora_grupo:geral': { linhas: 5, fora_padrao: 1, sem_profissao: 2 } }, turma_especial: 0 }).listas['fora_grupo:geral'])
      .toEqual({ linhas: 5, foraPadrao: 1, semProfissao: 2 });
    const l = mapearLista({ linhas: [{ nome: 'A', segmento: 'xx', grupo_black: 'saiu', fontes: ['isca', 3] }] });
    expect(l.linhas[0]).toMatchObject({ nome: 'A', segmento: 'outros', grupoBlack: 'saiu', grupoConsultoria: 'nunca', fontes: ['isca'] });
    expect(mapearLista(null).linhas).toEqual([]);
  });
});
