import { describe, expect, it } from 'vitest';
import { itensResposta, textoResposta } from './respondi-texto';

// Fixture no formato de respondi.respostas.respostas (valores anonimizados, formas reais do banco).
const RESPOSTAS = [
  { p: 'Nome completo', v: 'Fulana de Tal' },
  { p: 'E-mail', v: 'fulana@exemplo.com' },
  { p: 'Telefone', v: '{"country":"55","phone":"11999990000"}' },
  { p: 'Qual a sua turma?', v: '["T16"]' },
  { p: 'Em qual nível você está?', v: '["Ouro","Platina"]' },
  { p: 'Comentário', v: '' },
  { p: '', v: 'sem pergunta' },
  { p: 'Comprovante', v: '{quebrado' },
];

describe('textoResposta', () => {
  it('lista em string vira itens separados por vírgula', () => {
    expect(textoResposta('["T16"]')).toBe('T16');
    expect(textoResposta('["Ouro","Platina"]')).toBe('Ouro, Platina');
  });
  it('telefone em JSON sai formatado', () => {
    expect(textoResposta('{"country":"55","phone":"11999990000"}')).toBe('+55 (11) 99999-0000');
    expect(textoResposta('{"country":"55","phone":"1133330000"}')).toBe('+55 (11) 3333-0000');
    expect(textoResposta('{"country":"351","phone":"912345678"}')).toBe('+351 912345678');
    expect(textoResposta('{"country":"55","phone":""}')).toBe('');
  });
  it('moeda em JSON sai em reais', () => {
    expect(textoResposta('{"currency":"BRL","value":150000}').replace(/\s/g, ' ')).toBe('R$ 150.000,00');
  });
  it('outro objeto em string vira os valores', () => {
    expect(textoResposta('{"rua":"A","numero":"1"}')).toBe('A 1');
  });
  it('JSON quebrado fica como texto cru', () => {
    expect(textoResposta('{quebrado')).toBe('{quebrado');
    expect(textoResposta('[a')).toBe('[a');
  });
  it('nulo e vazio viram string vazia', () => {
    expect(textoResposta(null)).toBe('');
    expect(textoResposta(undefined)).toBe('');
    expect(textoResposta('  ')).toBe('');
  });
});

describe('itensResposta', () => {
  it('descarta pergunta vazia e valor vazio, mantém a ordem', () => {
    expect(itensResposta(RESPOSTAS)).toEqual([
      { q: 'Nome completo', v: 'Fulana de Tal' },
      { q: 'E-mail', v: 'fulana@exemplo.com' },
      { q: 'Telefone', v: '+55 (11) 99999-0000' },
      { q: 'Qual a sua turma?', v: 'T16' },
      { q: 'Em qual nível você está?', v: 'Ouro, Platina' },
      { q: 'Comprovante', v: '{quebrado' },
    ]);
  });
  it('lista nula vira vazia', () => {
    expect(itensResposta(null)).toEqual([]);
  });
});
