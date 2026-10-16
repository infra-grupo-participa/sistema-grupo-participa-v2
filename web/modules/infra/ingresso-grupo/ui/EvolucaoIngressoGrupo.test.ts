import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { EvolucaoIngressoGrupo } from './EvolucaoIngressoGrupo';

const html = (serie: Parameters<typeof EvolucaoIngressoGrupo>[0]['serie']) => renderToStaticMarkup(createElement(EvolucaoIngressoGrupo, { serie }));

describe('EvolucaoIngressoGrupo', () => {
  it('mostra a tabela por data com o acumulado e a taxa', () => {
    const saida = html({ data: [{ dia: '2026-10-01', leads: 100, grupo_entradas: 50 }, { dia: '2026-10-02', leads: 100, grupo_entradas: 10 }] });
    expect(saida).toContain('01/10/2026');
    expect(saida).toContain('02/10/2026');
    expect(saida).toContain('Entradas no dia');
    expect(saida).toContain('% ingresso no grupo');
    expect(saida).toContain('30,0%');
  });

  it('sem fonte de grupo diz isso e não mostra 0%', () => {
    const saida = html({ data: [{ dia: '2026-10-01', leads: 10, grupo_entradas: null }] });
    expect(saida).toContain('Sem fonte de grupo');
    expect(saida).not.toContain('0,0%');
  });

  it('erro sem dado anterior mostra o erro; série vazia mostra estado vazio', () => {
    expect(html({ data: null, erro: 'Falha de leitura.' })).toContain('Falha de leitura.');
    expect(html({ data: [] })).toContain('Sem dias no período');
  });
});
