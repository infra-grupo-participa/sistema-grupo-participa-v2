import { describe, expect, it } from 'vitest';
import { METRICAS } from '../../domain/metricas';
import type { Dashboard, MetricaKey } from '../../domain/types';
import { validarWidget } from '../inicio/painel-edicao';
import {
  aplicar, atualizarWidget, criarHistorico, desfazer, duplicarWidget, fecharPasso, GRUPOS_BIBLIOTECA, inserir, larguraPorArraste,
  LIMITE_HISTORICO, MODELOS, moverParaPonto, moverParaPosicao, moverPorDelta, mudarAltura, nomeDeCopia, podeEditarDashboard,
  pontoDeSoltura, redimensionar, refazer, removerWidget, renovarIds, separarDashboards, solturaInocua, validarDashboard,
  widgetDaMetrica, widgetsDoModelo, widgetsMudaram, type WidgetDash,
} from './layout';

const w = (id: string, extra: Partial<WidgetDash> = {}): WidgetDash => ({
  id, titulo: id, metrica: 'vendas', visual: 'numero', periodo: '7d', agrupar: 'nenhum', largura: 1, funilId: null, ...extra,
});
const ids = (l: { id: string }[]) => l.map((x) => x.id).join('');
const L = [w('a'), w('b'), w('c'), w('d')];

describe('biblioteca', () => {
  it('cada métrica aparece em exatamente um grupo', () => {
    const todas = GRUPOS_BIBLIOTECA.flatMap((g) => g.metricas);
    expect(new Set(todas).size).toBe(todas.length);
    expect(todas.sort()).toEqual((Object.keys(METRICAS) as MetricaKey[]).sort());
  });

  it('widget criado da métrica é sempre válido', () => {
    for (const m of Object.keys(METRICAS) as MetricaKey[]) {
      const x = widgetDaMetrica(m, 'x');
      expect(validarWidget(x), m).toBeNull();
      expect(x.titulo).toBe(METRICAS[m].nome);
    }
  });

  it('métrica que agrupa por vendedor já nasce em barras por vendedor', () => {
    const x = widgetDaMetrica('vendas', 'x');
    expect([x.visual, x.agrupar, x.largura]).toEqual(['barras', 'vendedor', 2]);
    expect(widgetDaMetrica('sem_dono', 'y').visual).toBe('numero');
  });
});

describe('inserir e mover', () => {
  it('insere na posição e no fim por padrão', () => {
    expect(ids(inserir(L, w('x'), 1))).toBe('axbcd');
    expect(ids(inserir(L, w('x')))).toBe('abcdx');
    expect(ids(inserir(L, w('x'), -3))).toBe('xabcd');
    expect(ids(inserir(L, w('x'), 99))).toBe('abcdx');
  });

  it('move pelo ponto de inserção contado antes de tirar o item', () => {
    expect(ids(moverParaPonto(L, 0, 3))).toBe('bcad'); // a cai antes de d
    expect(ids(moverParaPonto(L, 0, 4))).toBe('bcda'); // a vai para o fim
    expect(ids(moverParaPonto(L, 3, 0))).toBe('dabc');
    expect(ids(moverParaPonto(L, 2, 1))).toBe('acbd');
  });

  it('soltar no próprio lugar não muda a lista', () => {
    expect(moverParaPonto(L, 1, 1)).toBe(L);
    expect(moverParaPonto(L, 1, 2)).toBe(L);
    expect(solturaInocua(1, 1)).toBe(true);
    expect(solturaInocua(1, 2)).toBe(true);
    expect(solturaInocua(1, 3)).toBe(false);
    expect(solturaInocua(null, 1)).toBe(false);
  });

  it('ponto de soltura pelo lado do alvo', () => {
    expect(pontoDeSoltura(2, 'antes')).toBe(2);
    expect(pontoDeSoltura(2, 'depois')).toBe(3);
  });

  it('mover para posição final (menu "mover para…")', () => {
    expect(ids(moverParaPosicao(L, 0, 2))).toBe('bcad');
    expect(ids(moverParaPosicao(L, 3, 0))).toBe('dabc');
    expect(ids(moverParaPosicao(L, 1, 99))).toBe('acdb');
    expect(moverParaPosicao(L, 9, 0)).toBe(L);
  });

  it('setas movem uma posição e param nas pontas', () => {
    expect(ids(moverPorDelta(L, 'b', -1))).toBe('bacd');
    expect(ids(moverPorDelta(L, 'b', 1))).toBe('acbd');
    expect(ids(moverPorDelta(L, 'a', -1))).toBe('abcd');
    expect(ids(moverPorDelta(L, 'd', 1))).toBe('abcd');
  });
});

describe('tamanho e edição', () => {
  it('redimensiona entre 1 e 4', () => {
    expect(redimensionar(L, 'a', 3)[0].largura).toBe(3);
    expect(redimensionar(L, 'a', 9)[0].largura).toBe(4);
    expect(redimensionar(L, 'a', 0)[0].largura).toBe(1);
  });

  it('alça: cada quarto da grade arrastado soma 1', () => {
    expect(larguraPorArraste(1, 0, 1200)).toBe(1);
    expect(larguraPorArraste(1, 310, 1200)).toBe(2);
    expect(larguraPorArraste(2, 650, 1200)).toBe(4);
    expect(larguraPorArraste(3, -400, 1200)).toBe(2);
    expect(larguraPorArraste(2, -5000, 1200)).toBe(1);
    expect(larguraPorArraste(2, 100, 0)).toBe(2);
  });

  it('altura normal/alta', () => {
    expect(mudarAltura(L, 'b', 'alta')[1].altura).toBe('alta');
  });

  it('trocar métrica mantém o widget coerente', () => {
    const l = [w('a', { metrica: 'perdidos', visual: 'pizza', agrupar: 'motivo' })];
    const r = atualizarWidget(l, 'a', { metrica: 'tempo_primeiro_contato' })[0];
    expect(r.visual).not.toBe('pizza');
    expect(validarWidget(r)).toBeNull();
  });

  it('filtro por vendedor e altura sobrevivem à edição', () => {
    const r = atualizarWidget([w('a', { vendedorId: 'v1', altura: 'alta' })], 'a', { titulo: 'Novo' })[0];
    expect(r.vendedorId).toBe('v1');
    expect(r.altura).toBe('alta');
  });

  it('duplica logo depois, com id e título novos', () => {
    const r = duplicarWidget(L, 'b', 'b2');
    expect(ids(r)).toBe('abb2cd');
    expect(r[2].titulo).toBe('b (cópia)');
    expect(duplicarWidget(L, 'zz', 'q')).toBe(L);
  });

  it('remove', () => {
    expect(ids(removerWidget(L, 'c'))).toBe('abd');
  });
});

describe('desfazer / refazer', () => {
  it('desfaz e refaz na ordem', () => {
    let h = criarHistorico('A');
    h = aplicar(h, 'B');
    h = aplicar(h, 'C');
    h = desfazer(h);
    expect(h.presente).toBe('B');
    h = desfazer(h);
    expect(h.presente).toBe('A');
    expect(desfazer(h)).toBe(h);
    h = refazer(h);
    expect(h.presente).toBe('B');
    h = aplicar(h, 'D');
    expect(h.futuro).toEqual([]);
    expect(refazer(h)).toBe(h);
  });

  it('mesma chave seguida vira um passo só (digitar título)', () => {
    let h = criarHistorico('');
    h = aplicar(h, 'V', 'titulo:a');
    h = aplicar(h, 'Ve', 'titulo:a');
    h = aplicar(h, 'Ven', 'titulo:a');
    expect(desfazer(h).presente).toBe('');
    h = fecharPasso(h);
    h = aplicar(h, 'Vend', 'titulo:a');
    expect(desfazer(h).presente).toBe('Ven');
  });

  it('mudança igual não empilha; pilha tem limite', () => {
    let h = criarHistorico(0);
    expect(aplicar(h, 0)).toBe(h);
    for (let i = 1; i <= LIMITE_HISTORICO + 10; i++) h = aplicar(h, i);
    expect(h.passado.length).toBe(LIMITE_HISTORICO);
  });
});

describe('dashboards', () => {
  const dash = (id: string, nome: string, donoId: string): Dashboard => ({
    id, nome, descricao: null, donoId, compartilhado: true, widgets: [], criadoEm: '', atualizadoEm: '',
  });

  it('modelos prontos são válidos e com ids únicos', () => {
    for (const m of MODELOS) {
      const ws = widgetsDoModelo(m.key, `p-${m.key}`);
      expect(ws.length).toBeGreaterThan(3);
      expect(new Set(ws.map((x) => x.id)).size).toBe(ws.length);
      expect(validarDashboard(m.nome, ws), m.key).toBeNull();
    }
  });

  it('valida nome e widgets', () => {
    expect(validarDashboard('  ', [])).toMatch(/nome/);
    expect(validarDashboard('x'.repeat(61), [])).toMatch(/60/);
    expect(validarDashboard('Ok', [w('a', { titulo: ' ' })])).toMatch(/título/);
    expect(validarDashboard('Ok', [])).toBeNull();
  });

  it('só dono e gestor editam', () => {
    const d = dash('1', 'X', 'v1');
    expect(podeEditarDashboard(d, { vendedorId: 'v1', papel: 'vendedor' })).toBe(true);
    expect(podeEditarDashboard(d, { vendedorId: 'v2', papel: 'vendedor' })).toBe(false);
    expect(podeEditarDashboard(d, { vendedorId: 'v2', papel: 'gestor' })).toBe(true);
    expect(podeEditarDashboard(d, null)).toBe(false);
  });

  it('separa meus e compartilhados, por nome', () => {
    const r = separarDashboards([dash('1', 'Zeta', 'v1'), dash('2', 'Alfa', 'v2'), dash('3', 'Beta', 'v1')], 'v1');
    expect(r.meus.map((d) => d.nome)).toEqual(['Beta', 'Zeta']);
    expect(r.compartilhados.map((d) => d.nome)).toEqual(['Alfa']);
  });

  it('nome de cópia não repete', () => {
    expect(nomeDeCopia('Time', [])).toBe('Cópia de Time');
    expect(nomeDeCopia('Time', ['Cópia de Time'])).toBe('Cópia de Time (2)');
    expect(nomeDeCopia('Time', ['cópia de time', 'Cópia de Time (2)'])).toBe('Cópia de Time (3)');
  });

  it('renova ids e detecta mudança', () => {
    const r = renovarIds(L, 'n');
    expect(ids(r)).toBe('n-1n-2n-3n-4');
    expect(widgetsMudaram(L, [...L])).toBe(false);
    expect(widgetsMudaram(L, r)).toBe(true);
  });
});
