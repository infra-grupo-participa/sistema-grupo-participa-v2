import { describe, expect, it } from 'vitest';
import { baseFicticia } from '../infrastructure/fixtures/gerador';
import { PAGINAS } from '../infrastructure/fixtures/catalogo';
import {
  aplicarPerfil, alternarPerfil, contarPor, DIMENSOES_PERFIL, porUf, raioBolha, regiaoDaUf, SEM_VALOR, trilhaPerfil, type FiltroPerfil,
} from './perfil';

const b = baseFicticia();
const ctx = { paginas: new Map(PAGINAS.map((p) => [p.id, p])) };
const iscas = b.linhas.filter((l) => l.porta === 'isca');

describe('perfil dos leads', () => {
  it('cada dimensão soma o total do recorte (Não informado incluso)', () => {
    for (const d of DIMENSOES_PERFIL) {
      const soma = contarPor(iscas, d.id, [], ctx).reduce((s, c) => s + c.quantidade, 0);
      expect(soma, d.id).toBe(iscas.length);
    }
  });
  it('por isca → advogado → Sudeste → RJ fecha a soma a cada passo', () => {
    let f: FiltroPerfil = [];
    f = alternarPerfil(f, { dim: 'isca', valor: 'Checkup' });
    f = alternarPerfil(f, { dim: 'profissao', valor: 'advogado' });
    f = alternarPerfil(f, { dim: 'regiao', valor: 'Sudeste' });
    f = alternarPerfil(f, { dim: 'uf', valor: 'RJ' });
    const trilha = trilhaPerfil(iscas, f, ctx);
    expect(trilha.map((p) => p.rotulo)).toEqual(['Todos', 'Isca: Checkup', 'Profissão: Advogado', 'Região: Sudeste', 'Estado: RJ']);
    for (let i = 1; i < trilha.length; i += 1) expect(trilha[i].quantidade).toBeLessThanOrEqual(trilha[i - 1].quantidade);
    // Filtro cruzado: as UFs do Sudeste, com os outros filtros, somam o passo "Região: Sudeste".
    const ufs = contarPor(iscas, 'uf', f, ctx);
    expect(ufs.reduce((s, c) => s + c.quantidade, 0)).toBe(trilha[3].quantidade);
    expect(ufs.every((c) => regiaoDaUf(c.valor) === 'Sudeste')).toBe(true);
    expect(aplicarPerfil(iscas, f)).toHaveLength(trilha[4].quantidade);
    expect(trilha[4].quantidade).toBeGreaterThan(0);
  });
  it('clicar de novo desliga; trocar a região solta a UF de outra; tirar a região tira a UF', () => {
    let f: FiltroPerfil = [{ dim: 'regiao', valor: 'Sudeste' }, { dim: 'uf', valor: 'RJ' }];
    expect(alternarPerfil(f, { dim: 'regiao', valor: 'Sul' })).toEqual([{ dim: 'regiao', valor: 'Sul' }]);
    expect(alternarPerfil(f, { dim: 'regiao', valor: 'Sudeste' })).toEqual([]);
    f = [{ dim: 'profissao', valor: 'contador' }];
    expect(alternarPerfil(f, { dim: 'profissao', valor: 'contador' })).toEqual([]);
  });
  it('Não informado vai para o fim e o rótulo da página é a URL', () => {
    const c = contarPor(b.linhas, 'uf', [], ctx);
    expect(c[c.length - 1].valor).toBe(SEM_VALOR);
    expect(c[c.length - 1].rotulo).toBe('Não informado');
    const pag = contarPor(b.linhas, 'pagina', [], ctx).filter((x) => x.valor !== SEM_VALOR);
    expect(pag.every((x) => PAGINAS.some((p) => p.url === x.rotulo))).toBe(true);
  });
  it('mapa: por UF + sem UF + outros = total; raio da bolha proporcional à raiz', () => {
    const r = porUf(b.linhas);
    const soma = [...r.porUf.values()].reduce((s, n) => s + n, 0);
    expect(soma + r.semUf + r.outros).toBe(b.linhas.length);
    expect(raioBolha(100, 100)).toBe(28);
    expect(raioBolha(25, 100)).toBe(14);
    expect(raioBolha(0, 100)).toBe(0);
  });
});
