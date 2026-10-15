import { describe, expect, it } from 'vitest';
import { acumularSerie, alternarFiltroGrafico, aplicarFiltrosGraficos, janelaDaEvolucao, removerFiltroGrafico, valorFiltrado, type CampoFiltravel } from './filtro-graficos';
import { serieDiariaAtm } from './modal-pessoas';

type L = { id: string; teste: boolean; canal: string; estado: string; quando: string | null };
const l = (id: string, canal: string, estado: string, quando: string | null = '2026-10-14T15:00:00Z'): L => ({ id, teste: false, canal, estado, quando });
const campos: CampoFiltravel<L>[] = [{ nome: 'utm_source', valor: (x) => x.canal }, { nome: 'Estado', valor: (x) => x.estado }];
const base = [l('1', 'Unnichat', 'SP'), l('2', 'Unnichat', 'RJ'), l('3', 'Unnichat', 'SP'), l('4', 'Unnichat', 'SP'), l('5', 'SendFlow', 'SP'), l('6', 'SendFlow', 'RJ')];

describe('filtro cruzado dos gráficos', () => {
  it('clicar seleciona, clicar de novo desfaz, clicar em outro valor do mesmo campo troca', () => {
    const a = alternarFiltroGrafico([], 'utm_source', 'Unnichat');
    expect(a).toEqual([{ campo: 'utm_source', valor: 'Unnichat' }]);
    expect(alternarFiltroGrafico(a, 'utm_source', 'Unnichat')).toEqual([]);
    expect(alternarFiltroGrafico(a, 'utm_source', 'SendFlow')).toEqual([{ campo: 'utm_source', valor: 'SendFlow' }]);
  });

  it('campos diferentes se somam e removerFiltroGrafico tira só o campo pedido', () => {
    const f = alternarFiltroGrafico(alternarFiltroGrafico([], 'utm_source', 'Unnichat'), 'Estado', 'SP');
    expect(f).toHaveLength(2);
    expect(valorFiltrado(f, 'Estado')).toBe('SP');
    expect(removerFiltroGrafico(f, 'Estado')).toEqual([{ campo: 'utm_source', valor: 'Unnichat' }]);
    expect(valorFiltrado([], 'Estado')).toBeNull();
  });

  it('exemplo do pedido: 4 do Unnichat e 2 do SendFlow; filtrar Unnichat deixa os 4', () => {
    const f = alternarFiltroGrafico([], 'utm_source', 'Unnichat');
    expect(aplicarFiltrosGraficos(base, campos, f).map((x) => x.id)).toEqual(['1', '2', '3', '4']);
    expect(aplicarFiltrosGraficos(base, campos, [])).toHaveLength(6);
  });

  it('o gráfico do próprio campo ignora o filtro dele, os outros respeitam', () => {
    const f = alternarFiltroGrafico([], 'utm_source', 'Unnichat');
    expect(aplicarFiltrosGraficos(base, campos, f, 'utm_source')).toHaveLength(6);
    expect(aplicarFiltrosGraficos(base, campos, f, 'Estado')).toHaveLength(4);
  });

  it('dois filtros somam (E) e filtro de campo desconhecido não filtra nada', () => {
    const f = alternarFiltroGrafico(alternarFiltroGrafico([], 'utm_source', 'Unnichat'), 'Estado', 'RJ');
    expect(aplicarFiltrosGraficos(base, campos, f).map((x) => x.id)).toEqual(['2']);
    expect(aplicarFiltrosGraficos(base, campos, [{ campo: 'nao-existe', valor: 'x' }])).toHaveLength(6);
  });

  it('valor que não existe mais devolve lista vazia, sem erro', () => {
    expect(aplicarFiltrosGraficos(base, campos, [{ campo: 'utm_source', valor: 'Outro' }])).toEqual([]);
  });

  it('acumulado corre dia a dia e fecha no total', () => {
    const serie = [{ dia: '2026-10-13', quantidade: 0 }, { dia: '2026-10-14', quantidade: 3 }, { dia: '2026-10-15', quantidade: 1 }];
    expect(acumularSerie(serie).map((d) => d.acumulado)).toEqual([0, 3, 4]);
    expect(acumularSerie([])).toEqual([]);
  });

  it('janela: 1 dia de dado vira a semana terminando em hoje; período longo começa no primeiro lead', () => {
    const hoje = '2026-10-15';
    expect(janelaDaEvolucao(base, (x) => x.quando, hoje)).toEqual({ de: '2026-10-09', ate: '2026-10-15' });
    const longo = [l('a', 'x', 'y', '2026-09-20T15:00:00Z'), l('b', 'x', 'y', '2026-10-14T15:00:00Z')];
    expect(janelaDaEvolucao(longo, (x) => x.quando, hoje)).toEqual({ de: '2026-09-20', ate: '2026-10-15' });
    expect(janelaDaEvolucao([l('c', 'x', 'y', null)], (x: L) => x.quando, hoje)).toBeNull();
    expect(janelaDaEvolucao([] as L[], (x) => x.quando, hoje)).toBeNull();
  });

  it('a série com a janela cobre todos os dias, inclusive os zerados, e filtrada mantém o mesmo eixo', () => {
    const hoje = '2026-10-15';
    const janela = janelaDaEvolucao(base, (x) => x.quando, hoje)!;
    const cheia = serieDiariaAtm(base, (x) => x.quando, janela.de, janela.ate, hoje);
    const filtrada = serieDiariaAtm(aplicarFiltrosGraficos(base, campos, [{ campo: 'utm_source', valor: 'SendFlow' }]), (x) => x.quando, janela.de, janela.ate, hoje);
    expect(cheia).toHaveLength(7);
    expect(filtrada.map((d) => d.dia)).toEqual(cheia.map((d) => d.dia));
    expect(acumularSerie(cheia).at(-1)?.acumulado).toBe(6);
    expect(acumularSerie(filtrada).at(-1)?.acumulado).toBe(2);
  });
});
