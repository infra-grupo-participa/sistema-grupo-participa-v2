import { describe, expect, it } from 'vitest';
import { fichaRespondi, formatarCpf, linhaEndereco, mascararCpf, urlRede } from './respondi-ficha';

// Fixture no formato de respondi.respostas.dados (contrato do carga.py), valores anonimizados.
const DADOS = {
  email: 'fulana@exemplo.com',
  cpf: '12345678901',
  cpf_valido: true,
  telefone: '5511999990000',
  nivel_codigo: 'ouro',
  turma_codigo: 'T16',
  profissao: '  ',
  instagram: '@fulana.adv',
  facebook: 'javascript:alert(1)',
  youtube: 'https://evil.com/youtube.com',
  cep: '74000000',
  endereco: 'Rua Um',
  numero: '120',
  complemento: '',
  bairro: 'Centro',
  cidade: 'Goiânia',
  uf_sigla: 'GO',
  socio_email: 'beltrano@exemplo.com',
  socio_cpf: '98765432100',
  socio_cpf_valido: false,
  socio_aluno_id: 'a1',
};

describe('mascararCpf / formatarCpf', () => {
  it('oculta começo e verificador', () => {
    expect(mascararCpf('12345678901')).toBe('***.456.789-**');
    expect(mascararCpf('123.456.789-01')).toBe('***.456.789-**');
    expect(mascararCpf('1234')).toBe('****');
    expect(formatarCpf('12345678901')).toBe('123.456.789-01');
  });
});

describe('linhaEndereco', () => {
  it('monta numa linha e pula vazios', () => {
    expect(linhaEndereco(DADOS)).toBe('Rua Um, 120 · Centro · Goiânia/GO · CEP 74000-000');
    expect(linhaEndereco({})).toBe('');
  });
});

describe('urlRede', () => {
  it('só aceita host da rede', () => {
    expect(urlRede('instagram', '@fulana.adv')).toBe('https://www.instagram.com/fulana.adv');
    expect(urlRede('instagram', 'instagram.com/fulana')).toBe('https://instagram.com/fulana');
    expect(urlRede('facebook', 'javascript:alert(1)')).toBeNull();
    expect(urlRede('youtube', 'https://evil.com/youtube.com')).toBeNull();
    expect(urlRede('facebook', 'fulana')).toBeNull();
  });
});

describe('fichaRespondi', () => {
  it('telefone gravado como JSON sai formatado, não cru', () => {
    const f = fichaRespondi({ telefone: '{"country":"55","phone":"11999990000"}', socio_telefone: '{"country":"55","phone":"1133330000"}' }, 'socios');
    expect(f.flatMap((b) => b.campos).map((c) => c.valor)).toEqual(['+55 (11) 99999-0000', '+55 (11) 3333-0000']);
  });
  it('blocos do respondente; campo vazio e bloco vazio somem', () => {
    const f = fichaRespondi(DADOS, 'nivel');
    expect(f.map((b) => b.k)).toEqual(['identificacao', 'programa', 'endereco', 'redes']);
    expect(f[0].campos.map((c) => c.k)).toEqual(['cpf', 'email', 'telefone']);
    expect(f[1].campos.map((c) => [c.tipo, c.valor])).toEqual([['nivel', 'ouro'], ['turma', 'T16']]);
    const redes = f[3].campos.map((c) => [c.rotulo, c.href]);
    expect(redes).toEqual([
      ['Instagram', 'https://www.instagram.com/fulana.adv'],
      ['Facebook', null],
      ['YouTube', null],
    ]);
  });

  it('família socios ganha o bloco do sócio com CPF inválido marcado', () => {
    const socio = fichaRespondi(DADOS, 'socios').find((b) => b.k === 'socio');
    expect(socio?.campos.map((c) => c.k)).toEqual(['socio_cpf', 'socio_email']);
    expect(socio?.campos[0].invalido).toBe(true);
    expect(fichaRespondi(DADOS, 'nivel').some((b) => b.k === 'socio')).toBe(false);
  });

  it('dados nulo ou com objeto não quebra', () => {
    expect(fichaRespondi(null, 'socios')).toEqual([]);
    expect(fichaRespondi({ email: { x: 1 } }, 'cadastro')).toEqual([]);
  });
});
