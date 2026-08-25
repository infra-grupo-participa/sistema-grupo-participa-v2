import { describe, it, expect } from 'vitest';
import { casaBusca, normalizar } from './busca';

const alvo = (nome: string | null, vendedor: string | null = null) => ({ nome, vendedor });

describe('normalizar', () => {
  it('remove acento, caixa e espaco duplicado', () => {
    expect(normalizar('  Maria   da CONCEICAO ')).toBe('maria da conceicao');
    expect(normalizar('Conceicao')).toBe(normalizar('Conceicao'));
  });

  it('achata acento para a letra base', () => {
    // O caso que motiva a normalizacao: ninguem digita cedilha na pressa.
    expect(normalizar('Conceição')).toBe('conceicao');
    expect(normalizar('Júlio Ângelo')).toBe('julio angelo');
  });
});

describe('casaBusca', () => {
  it('consulta vazia casa com tudo — "nao filtrei" nunca vira "nada encontrado"', () => {
    expect(casaBusca(alvo('Maria'), '')).toBe(true);
    expect(casaBusca(alvo('Maria'), '   ')).toBe(true);
    expect(casaBusca(alvo(null), '')).toBe(true);
  });

  it('acha por pedaco do nome, ignorando acento e caixa', () => {
    expect(casaBusca(alvo('Maria da Conceição'), 'conceicao')).toBe(true);
    expect(casaBusca(alvo('Maria da Conceição'), 'CONCEIÇÃO')).toBe(true);
  });

  it('termos fora de ordem casam (AND, nao frase literal)', () => {
    expect(casaBusca(alvo('Maria da Silva'), 'silva maria')).toBe(true);
    expect(casaBusca(alvo('Maria da Silva'), 'maria silva')).toBe(true);
  });

  it('cruza nome com vendedor — os dois campos formam um feno so', () => {
    expect(casaBusca(alvo('Maria', 'Joao'), 'maria joao')).toBe(true);
    expect(casaBusca(alvo('Maria', 'Joao'), 'joao')).toBe(true);
  });

  it('todo termo precisa casar — um termo estranho reprova', () => {
    expect(casaBusca(alvo('Maria da Silva', 'Joao'), 'maria pedro')).toBe(false);
  });

  it('nao casa quem nao tem o termo', () => {
    expect(casaBusca(alvo('Maria'), 'rodrigo')).toBe(false);
  });

  it('nome nulo nao explode e nao casa termo', () => {
    expect(casaBusca(alvo(null, null), 'maria')).toBe(false);
  });

  it('NAO busca por e-mail/documento — campos fora do card por LGPD', () => {
    // Guard de regressao: se alguem acrescentar email ao feno, este teste cai.
    // O board esconde e-mail de proposito; a busca nao pode devolve-lo pela
    // porta dos fundos (bastaria digitar um dominio para varrer a carteira).
    const comEmail = { nome: 'Maria', vendedor: 'Joao' } as Record<string, unknown>;
    comEmail.email = 'maria@exemplo.com';
    comEmail.documento = '12345678900';
    expect(casaBusca(comEmail as { nome: string; vendedor: string }, 'exemplo.com')).toBe(false);
    expect(casaBusca(comEmail as { nome: string; vendedor: string }, '12345678900')).toBe(false);
  });
});
