import { describe, expect, it } from 'vitest';
import fs from 'node:fs';
import path from 'node:path';
import { DDD_UF, dddDoTelefone, ufDoTelefone } from './ddd-uf';
import { UFS } from './geo-brasil';

const MIGRATION = fs.readFileSync(
  path.resolve(__dirname, '../../../../../infra/supabase/migrations/20261008161000_dados_criar_modelo_seminario_atm.sql'),
  'utf8',
);

/** Lê os pares ('DD','UF') do insert em dados.ddd_uf. */
function paresDaMigration(): [string, string][] {
  const m = MIGRATION.match(/insert into dados\.ddd_uf \(ddd, uf\) values([\s\S]*?)on conflict/);
  if (!m) throw new Error('insert de dados.ddd_uf não encontrado na migration');
  return [...m[1].matchAll(/\('(\d{2})','([A-Z]{2})'\)/g)].map((x) => [x[1], x[2]]);
}

describe('DDD_UF espelha dados.ddd_uf', () => {
  it('mesmas linhas, mesmo valor, nada a mais', () => {
    const pares = paresDaMigration();
    expect(pares.length).toBeGreaterThan(60);
    for (const [ddd, uf] of pares) expect(DDD_UF[ddd], `DDD ${ddd}`).toBe(uf);
    expect(Object.keys(DDD_UF).sort()).toEqual(pares.map((p) => p[0]).sort());
  });
  it('toda UF da tabela existe na malha do IBGE', () => {
    const siglas = new Set(UFS.map((u) => u.sigla));
    for (const uf of Object.values(DDD_UF)) expect(siglas.has(uf), uf).toBe(true);
  });
});

describe('dddDoTelefone: país pelo comprimento', () => {
  it('sem 55 (10 e 11 dígitos)', () => {
    expect(dddDoTelefone('(21) 00000-0001')).toBe('21');
    expect(dddDoTelefone('2133334444')).toBe('21');
  });
  it('com 55 (12 e 13 dígitos)', () => {
    expect(dddDoTelefone('+55 (21) 00000-0001')).toBe('21');
    expect(dddDoTelefone('552133334444')).toBe('21');
  });
  it('DDD 55 do RS não é confundido com o código do país', () => {
    expect(dddDoTelefone('(55) 00000-0002')).toBe('55');
    expect(ufDoTelefone('(55) 00000-0002')).toBe('RS');
    expect(ufDoTelefone('5555000000002')).toBe('RS');
  });
  it('lixo, vazio, curto e longo = null', () => {
    for (const t of ['', null, undefined, 'abc', '123', '(21) 0000', '99999999999999', '0000000000']) {
      expect(dddDoTelefone(t as string | null | undefined), String(t)).toBeNull();
    }
  });
  it('DDD bem formado fora da tabela = Outros', () => {
    expect(ufDoTelefone('(20) 00000-0001')).toBe('Outros');
  });
});
