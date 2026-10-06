import { describe, expect, it } from 'vitest';
import {
  casaBusca, conflitosCadastro, mapaDuplicados, resumoAbertos, utmEmLinha, validarNovoContato,
} from './regras-contatos';

describe('mapaDuplicados', () => {
  it('liga contatos com o mesmo DDD + últimos 8 dígitos, com ou sem DDI', () => {
    const m = mapaDuplicados([
      { id: 'a', telefone: '5511987654321' },
      { id: 'b', telefone: '(11) 98765-4321' },
      { id: 'c', telefone: '5521912345678' },
    ]);
    expect(m.get('a')).toEqual(['b']);
    expect(m.get('b')).toEqual(['a']);
    expect(m.has('c')).toBe(false);
  });

  it('ignora telefone vazio ou curto demais', () => {
    const m = mapaDuplicados([
      { id: 'a', telefone: null },
      { id: 'b', telefone: null },
      { id: 'c', telefone: '1234' },
      { id: 'd', telefone: '1234' },
    ]);
    expect(m.size).toBe(0);
  });

  it('agrupa três ou mais', () => {
    const m = mapaDuplicados([
      { id: 'a', telefone: '5511987654321' },
      { id: 'b', telefone: '11987654321' },
      { id: 'c', telefone: '551187654321' }, // sem o 9
      { id: 'd', telefone: '987654321' },    // sem DDD: sem chave
    ]);
    expect(m.get('c')).toEqual(['a', 'b']);
    expect(m.has('d')).toBe(false);
  });
});

describe('casaBusca', () => {
  const c = { nome: 'Fábio Macedo', email: 'fabio.macedo@exemplo.com.br', telefone: '5511987654321' };

  it('acha por nome sem acento e por e-mail', () => {
    expect(casaBusca(c, 'fabio')).toBe(true);
    expect(casaBusca(c, 'MACEDO@')).toBe(true);
    expect(casaBusca(c, 'renata')).toBe(false);
  });

  it('acha por telefone em qualquer formato', () => {
    expect(casaBusca(c, '(11) 98765-4321')).toBe(true);
    expect(casaBusca(c, '4321')).toBe(true);
    expect(casaBusca(c, '+55 11 8765-4321')).toBe(true);   // mesmo DDD + últimos 8, sem o 9
    expect(casaBusca(c, '+55 21 9 8765-4321')).toBe(false); // DDD diferente não junta
    expect(casaBusca(c, '1111-2222')).toBe(false);
  });

  it('termo vazio casa com todos', () => {
    expect(casaBusca(c, '  ')).toBe(true);
  });
});

describe('utmEmLinha', () => {
  it('junta source / medium / campaign e pula vazios', () => {
    expect(utmEmLinha({ source: 'instagram', medium: 'cpc', campaign: 'ht33' })).toBe('instagram / cpc / ht33');
    expect(utmEmLinha({ source: 'google', medium: null, campaign: ' ' })).toBe('google');
  });
  it('sem UTM é direto', () => {
    expect(utmEmLinha({})).toBe('direto');
  });
});

describe('resumoAbertos', () => {
  it('mostra o primeiro e conta o resto', () => {
    expect(resumoAbertos([])).toBeNull();
    expect(resumoAbertos([
      { produtoNome: 'Holding Masters', etapaNome: 'Negociar' },
      { produtoNome: 'Aurum', etapaNome: 'Contato' },
    ])).toEqual({ texto: 'Holding Masters · Negociar', resto: 1 });
  });
});

describe('validarNovoContato', () => {
  it('exige nome e um canal', () => {
    expect(validarNovoContato({ nome: '', telefone: '11987654321', email: '' })).toBe('Informe o nome.');
    expect(validarNovoContato({ nome: 'Ana', telefone: '', email: '' })).toBe('Informe telefone ou e-mail.');
  });
  it('confere telefone e e-mail', () => {
    expect(validarNovoContato({ nome: 'Ana', telefone: '98765', email: '' })).toMatch(/DDD/);
    expect(validarNovoContato({ nome: 'Ana', telefone: '', email: 'ana@' })).toBe('E-mail inválido.');
    expect(validarNovoContato({ nome: 'Ana', telefone: '(11) 98765-4321', email: 'ana@x.com' })).toBeNull();
  });
});

describe('conflitosCadastro', () => {
  const base = [
    { id: 'a', email: 'Ana@X.com', telefone: '5511987654321' },
    { id: 'b', email: null, telefone: '11 98765-4321' },
    { id: 'c', email: 'c@x.com', telefone: '5521912345678' },
  ];
  it('separa mesmo e-mail (bloqueia) de mesmo final de telefone (aviso)', () => {
    const r = conflitosCadastro({ email: ' ana@x.com ', telefone: '+55 11 9 8765-4321' }, base);
    expect(r.mesmoEmail.map((c) => c.id)).toEqual(['a']);
    expect(r.mesmoTelefone.map((c) => c.id)).toEqual(['b']);
  });
  it('sem dados não acusa nada', () => {
    expect(conflitosCadastro({ email: '', telefone: '' }, base)).toEqual({ mesmoEmail: [], mesmoTelefone: [] });
  });
});
