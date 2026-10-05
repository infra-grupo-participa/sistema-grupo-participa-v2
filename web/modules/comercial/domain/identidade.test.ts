import { describe, expect, it } from 'vitest';
import {
  chaveNomeCep, chaveTelefone, documentoValido, mascararEmail, mascararFim, nomesCompativeis, normalizarDocumento,
  normalizarEmail, normalizarNome, normalizarTelefone, resolverIdentidade, temIdentificador, type Conhecida,
} from './identidade';

// Os mesmos casos do passo 2 do ensaio 20261005o (o banco tem de dar o mesmo resultado).
describe('identidade: normalização', () => {
  it('documento: pontuação, zero à esquerda perdido, dígito verificador, repetido, CNPJ', () => {
    expect(normalizarDocumento('529.982.247-25')).toBe('52998224725');
    expect(normalizarDocumento('1234567890')).toBe('01234567890');
    expect(normalizarDocumento('529.982.247-24')).toBeNull();
    expect(normalizarDocumento('111.111.111-11')).toBeNull();
    expect(normalizarDocumento('11.222.333/0001-81')).toBe('11222333000181');
    expect(normalizarDocumento('12345')).toBeNull();
    expect(normalizarDocumento(null)).toBeNull();
    expect(documentoValido('00000000000')).toBe(false);
  });
  it('telefone: +55, 0 de longa distância, 8 e 9 dígitos casam pela chave DDD + 8', () => {
    expect(normalizarTelefone('+55 (11) 98765-4321')).toBe('11987654321');
    expect(normalizarTelefone('011 98765-4321')).toBe('11987654321');
    expect(normalizarTelefone('(11) 8765-4321')).toBe('1187654321');
    expect(chaveTelefone(normalizarTelefone('(11) 98765-4321'))).toBe(chaveTelefone(normalizarTelefone('11 8765-4321')));
    expect(chaveTelefone(normalizarTelefone('(11) 98765-4321'))).toBe('1187654321');
  });
  it('telefone inválido: celular de 9 dígitos sem 9 na frente, DDD com zero, sem DDD', () => {
    expect(normalizarTelefone('(11) 88765-4321')).toBeNull();
    expect(normalizarTelefone('(00) 98765-4321')).toBeNull();
    expect(normalizarTelefone('98765-4321')).toBeNull();
    expect(chaveTelefone(null)).toBeNull();
  });
  it('e-mail, nome e nome + CEP', () => {
    expect(normalizarEmail('  Ana.Ensaio@Exemplo.INVALID ')).toBe('ana.ensaio@exemplo.invalid');
    expect(normalizarEmail('ana@')).toBeNull();
    expect(normalizarNome('  José  da   Silva-Ávila ')).toBe('JOSE DA SILVA AVILA');
    expect(chaveNomeCep('Ana Ensaio Silva', '01001-000')).toBe('ANA ENSAIO SILVA|01001000');
    expect(chaveNomeCep('Ana', '01001-000')).toBeNull();
    expect(chaveNomeCep('Ana Silva', '0100')).toBeNull();
  });
  it('nomes compatíveis = mesmo primeiro nome; sem nome não contradiz', () => {
    expect(nomesCompativeis('Ana Silva', 'ANA E. SILVA')).toBe(true);
    expect(nomesCompativeis('Ana', 'Bruno')).toBe(false);
    expect(nomesCompativeis(null, 'Bruno')).toBe(true);
  });
  it('máscaras', () => {
    expect(mascararFim('52998224725')).toBe('*******4725');
    expect(mascararEmail('ana@x.com')).toBe('a***@x.com');
    expect(mascararFim(null)).toBeNull();
  });
  it('identificador forte obrigatório', () => {
    expect(temIdentificador({ nome: 'Só Nome' })).toBe(false);
    expect(temIdentificador({ documento: '529.982.247-24' })).toBe(false);
    expect(temIdentificador({ telefone: '(11) 98765-4321' })).toBe(true);
  });
});

describe('identidade: cascata (mesmos cenários do passo 4 do ensaio)', () => {
  const base: Conhecida[] = [
    { id: 'A1', nome: 'Ana Ensaio Silva', email: 'ana.ensaio@exemplo.invalid', telefone: '(11) 98888-0001', documento: '529.982.247-25', cep: '01001-000' },
    { id: 'A2', nome: 'Bruno Ensaio Costa', email: 'bruno.ensaio@exemplo.invalid', telefone: '(21) 97777-0002', documento: '012.345.678-90' },
    { id: 'D', nome: 'Diego Ensaio Ramos', email: 'diego.ensaio@exemplo.invalid', telefone: '+55 11 96666-0003' },
  ];
  it('pessoa nova quando nada bate', () => {
    expect(resolverIdentidade({ nome: 'Nova Pessoa', email: 'nova@exemplo.invalid' }, base)).toEqual({ pessoaId: null, como: 'nova', revisao: null, candidatos: [] });
  });
  it('mesmo lead pelo telefone sem o 9: não duplica', () => {
    expect(resolverIdentidade({ nome: 'Diego Ramos', telefone: '(11) 6666-0003' }, base)).toMatchObject({ pessoaId: 'D', como: 'telefone' });
  });
  it('e-mail com maiúsculas casa com o aluno', () => {
    expect(resolverIdentidade({ nome: 'Ana E. Silva', email: 'ANA.ENSAIO@exemplo.invalid' }, base)).toMatchObject({ pessoaId: 'A1', como: 'email' });
  });
  it('documento sem o zero à esquerda casa', () => {
    expect(resolverIdentidade({ nome: 'Bruno Costa', documento: '1234567890' }, base)).toMatchObject({ pessoaId: 'A2', como: 'documento' });
  });
  it('documento é o primeiro passo: vence o e-mail de outra pessoa (e o e-mail vira conflito no banco)', () => {
    expect(resolverIdentidade({ nome: 'Bruno', documento: '01234567890', email: 'diego.ensaio@exemplo.invalid' }, base))
      .toMatchObject({ pessoaId: 'A2', como: 'documento' });
  });
  it('documento com nome diferente: pessoa nova em revisão', () => {
    expect(resolverIdentidade({ nome: 'Zeca Outro Nome', documento: '012.345.678-90', email: 'zeca@exemplo.invalid' }, base))
      .toEqual({ pessoaId: null, como: 'nova', revisao: 'documento_nome_diferente', candidatos: ['A2'] });
  });
  it('telefone com nome diferente: não funde', () => {
    expect(resolverIdentidade({ nome: 'Paulo Ensaio Lima', telefone: '11 98888-0001' }, base))
      .toEqual({ pessoaId: null, como: 'nova', revisao: 'telefone_nome_diferente', candidatos: ['A1'] });
  });
  it('telefone com nome diferente, mas o e-mail resolve: casa e deixa a dúvida para revisão', () => {
    expect(resolverIdentidade({ nome: 'Paulo', telefone: '11 98888-0001', email: 'diego.ensaio@exemplo.invalid' }, base))
      .toEqual({ pessoaId: 'D', como: 'email', revisao: 'telefone_nome_diferente', candidatos: ['A1'] });
  });
  it('nome + CEP', () => {
    expect(resolverIdentidade({ nome: 'Ana Ensaio Silva', cep: '01001-000', email: 'ana.nova@exemplo.invalid' }, base))
      .toMatchObject({ pessoaId: 'A1', como: 'nome_cep' });
  });
  it('só o nome bate: pessoa nova em revisão, nunca funde', () => {
    expect(resolverIdentidade({ nome: 'Bruno Ensaio Costa', email: 'bruno.outro@exemplo.invalid' }, base))
      .toEqual({ pessoaId: null, como: 'nova', revisao: 'so_nome', candidatos: ['A2'] });
  });
  it('nome de uma palavra só não abre revisão por nome', () => {
    expect(resolverIdentidade({ nome: 'Bruno', email: 'b@exemplo.invalid' }, base).revisao).toBeNull();
  });
  it('telefone dividido por duas pessoas: o nome escolhe; sem nome, conflito', () => {
    const fam: Conhecida[] = [{ id: 'X', nome: 'Maria Souza', telefone: '11 91234-5678' }, { id: 'Y', nome: 'João Souza', telefone: '11 91234-5678' }];
    expect(resolverIdentidade({ nome: 'João S.', telefone: '(11) 91234-5678' }, fam)).toMatchObject({ pessoaId: 'Y', como: 'telefone' });
    expect(resolverIdentidade({ telefone: '(11) 91234-5678' }, fam)).toMatchObject({ pessoaId: null, revisao: 'conflito' });
  });
});
