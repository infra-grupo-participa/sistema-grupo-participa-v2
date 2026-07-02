import { describe, it, expect } from 'vitest';
import { CARGO_ORDEM, FUNCAO_META, SETOR_META, cargosGrantaveis, podeEditarUsuario } from './cargos';

describe('FUNCAO_META', () => {
  it('toda chave é prefixada pelo próprio setor (gramática exigida por podeEditar/tem_permissao)', () => {
    for (const [key, meta] of Object.entries(FUNCAO_META)) {
      expect(key.startsWith(meta.setor + '.')).toBe(true);
      expect(SETOR_META[meta.setor]).toBeDefined();
    }
  });
});

describe('cargosGrantaveis', () => {
  it('dev atribui qualquer cargo, inclusive dev', () => {
    expect(cargosGrantaveis('dev')).toEqual(CARGO_ORDEM);
  });

  it('admin atribui tudo exceto dev', () => {
    expect(cargosGrantaveis('admin')).toEqual(['admin', 'gestor', 'operador', 'visualizador']);
  });

  it('gestor/operador/visualizador não atribuem nada', () => {
    expect(cargosGrantaveis('gestor')).toEqual([]);
    expect(cargosGrantaveis('operador')).toEqual([]);
    expect(cargosGrantaveis('visualizador')).toEqual([]);
  });
});

describe('podeEditarUsuario', () => {
  it('dev edita qualquer um, inclusive outro dev', () => {
    expect(podeEditarUsuario('dev', 'dev')).toBe(true);
    expect(podeEditarUsuario('dev', 'admin')).toBe(true);
  });

  it('ninguém além de dev edita um dev', () => {
    expect(podeEditarUsuario('admin', 'dev')).toBe(false);
    expect(podeEditarUsuario('gestor', 'dev')).toBe(false);
  });

  it('admin edita não-devs; demais cargos não editam ninguém', () => {
    expect(podeEditarUsuario('admin', 'admin')).toBe(true);
    expect(podeEditarUsuario('admin', 'visualizador')).toBe(true);
    expect(podeEditarUsuario('gestor', 'operador')).toBe(false);
    expect(podeEditarUsuario('operador', 'visualizador')).toBe(false);
    expect(podeEditarUsuario('visualizador', 'visualizador')).toBe(false);
  });
});
