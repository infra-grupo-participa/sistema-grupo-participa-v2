// Visão geral em HTML estático (renderToStaticMarkup, sem navegador): prova conteúdo, links e estados. Geometria, clique
// no "Detalhar" e a carga ao abrir a aba não se provam aqui (não há DOM no projeto).
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { VisaoGeral } from './VisaoGeral';
import { Recorrencias } from './Recorrencias';
import { Eventos } from './Eventos';
import { Informados, type RepoInformados } from './Informados';
import { montarContasReceber } from '../../application/carregar-contas-receber';
import type { VisaoReceberCarregada } from '../../application/carregar-visao-receber';
import { cobrancasRecorrentes, normalizarLinhaReceber } from '../../domain/contas-receber';
import { normalizarEventoPlanejado } from '../../domain/eventos-planejados';
import { normalizarFoto, normalizarMudanca, normalizarPrevistoRealizado } from '../../domain/visao-receber';

const L = (p: Record<string, unknown>) => normalizarLinhaReceber({
  bloco: 1, grupo: 'Vendas já realizadas', componente: 'antecipacao', situacao: 'a_receber', valor: 0, ...p,
});
const HOJE = '2026-09-28';
const AGORA = new Date('2026-09-28T15:00:00Z'); // segunda, 12:00 em São Paulo (a foto das 06:11 já passou)
const F1 = normalizarFoto({ foto_em: '2026-09-28T12:00:00+00:00', dia: '2026-09-28', cenario: 'base', linhas: 900, soma_a_receber: 1000 });
const F2 = normalizarFoto({ foto_em: '2026-10-05T09:11:00+00:00', dia: '2026-10-05', cenario: 'base', linhas: 910, soma_a_receber: 1100 });

const linhas = [
  L({ data_caixa: '2026-09-30', valor: 100 }),
  L({ bloco: 2, grupo: 'Parcelas a vencer HM', componente: 'cheio', situacao: 'em_atraso_fora', ref: 'r', origem_dia: '2026-09-01', valor: 40 }),
  L({ bloco: 3, grupo: 'HM avulso', data_caixa: '2026-10-06', valor: 30 }),
];
const dados = montarContasReceber(linhas, HOJE);

const umaFoto: VisaoReceberCarregada = {
  fotos: { dados: [F1], erro: null }, mudancas: null, comparacao: null,
  previsto: { dados: [normalizarPrevistoRealizado({ linha: 'semana', semana_de: '2026-09-21', semana_ate: '2026-09-27', nota: 'sem foto base no início da semana' })], erro: null },
};

const render = (p: Partial<Parameters<typeof VisaoGeral>[0]>) => renderToStaticMarkup(createElement(VisaoGeral, {
  dados, erroReceber: null, onTentarReceber: () => {}, visao: umaFoto, onTentarVisao: () => {}, eventos: [], erroEventos: null, agora: AGORA, ...p,
}));

describe('VisaoGeral', () => {
  it('4 semanas: certo × estimado × total, números levam à grade (#receber)', () => {
    const html = render({});
    expect(html).toContain('Próximas 4 semanas');
    expect(html).toContain('28/09–04/10');
    expect(html).toContain('19/10–25/10');
    expect(html).toMatch(/href="#receber"[^>]*>R\$\s100,00</);
    expect(html).toMatch(/href="#receber"[^>]*>R\$\s30,00</);
    expect(html).toMatch(/href="#receber"[^>]*>R\$\s130,00</);
  });
  it('alertas: fora da projeção leva a Recorrências JÁ filtrada; zero fica neutro, sem link', () => {
    const html = render({});
    expect(html).toContain('href="#receber?ver=recorrencias&amp;situacao=em_atraso_fora"');
    expect(html).toContain('1 cobrança · R$');
    expect(html).not.toContain('situacao=em_atraso_cobrar'); // nenhum informado a cobrar: sem link
    expect(html).toContain('Projeção do estimado');
    expect(html).toContain('ligada');
  });
  it('projeção desligada (sem blocos 3, 4, 6, 8): estimado "desligado" e alerta com link para Premissas', () => {
    const html = render({ dados: montarContasReceber([L({ data_caixa: '2026-09-30', valor: 100 })], HOJE) });
    expect(html).toContain('desligado</td>');
    expect(html).toContain('href="#receber?ver=premissas"');
    expect(html).toContain('desligada: o estimado não entra na previsão');
  });
  it('eventos encerrados sem arquivar: contados, link para Eventos filtrado', () => {
    const ev = normalizarEventoPlanejado({ id: 1, nome: 'Imersão', abertura: '2026-08-01', evento_ref_id: 2, situacao: 'encerrado' });
    expect(render({ eventos: [ev] })).toContain('href="#receber?ver=eventos&amp;situacao=encerrado"');
    expect(render({ eventos: null })).toContain('carregando…');
  });
  it('1 foto: diz quando sai a 1ª comparação (segunda 05/10 às 06h11) e o 1º previsto × realizado', () => {
    const html = render({});
    expect(html).toContain('A primeira comparação aparece depois da próxima foto, segunda 05/10 às 06h11.');
    expect(html).toContain('O primeiro previsto × realizado (semana 28/09 a 04/10) aparece na segunda 05/10.');
    expect(html).not.toContain('<table class="w-full border-collapse text-xs"><caption class="sr-only">O que mudou');
  });
  it('2 fotos: tabela do que mudou com motivos em texto; "saiu por atraso" do bloco 2 leva a Recorrências filtrada', () => {
    const visao: VisaoReceberCarregada = {
      ...umaFoto, fotos: { dados: [F2, F1], erro: null }, comparacao: { anterior: F1, recente: F2 },
      mudancas: { dados: [
        normalizarMudanca({ bloco: 2, grupo: 'Parcelas a vencer HM', valor_a: 500, valor_b: 420, delta: -80,
          motivos: [{ motivo: 'saiu_pagamento', itens: 3, valor: -60 }, { motivo: 'saiu_atraso', itens: 1, valor: -20 }] }),
        normalizarMudanca({ bloco: 1, grupo: 'Vendas já realizadas', valor_a: 5, valor_b: 5, delta: 0, motivos: [] }),
      ], erro: null },
    };
    const html = render({ visao });
    expect(html).toContain('saiu porque foi pago: 3 itens');
    expect(html).toMatch(/href="#receber\?ver=recorrencias&amp;situacao=em_atraso_fora"[^>]*>saiu por atraso: 1 item/);
    expect(html).toContain('1 grupo sem mudança.');
  });
  it('erro de uma parte: mensagem e "tentar de novo" só nela; as outras seguem', () => {
    const visao: VisaoReceberCarregada = { ...umaFoto, previsto: { dados: null, erro: 'Sem permissão para ver o financeiro.' } };
    const html = render({ visao });
    expect(html).toContain('Sem permissão para ver o financeiro.');
    expect(html).toContain('A primeira comparação aparece');
  });
  it('previsto × realizado com semana medida: acerto e botão Detalhar (aria-expanded); perda com link para Premissas', () => {
    const P = (p: Record<string, unknown>) => normalizarPrevistoRealizado({ linha: 'semana', semana_de: '2026-09-28', semana_ate: '2026-10-04',
      foto_em: F1.foto_em, ...p });
    const visao: VisaoReceberCarregada = { ...umaFoto, previsto: { dados: [
      P({ bloco: 1, grupo: 'Vendas já realizadas', previsto: 100, realizado: 90, acerto_pct: 90 }),
      normalizarPrevistoRealizado({ linha: 'perda', bloco: 2, grupo: 'Parcelas a vencer HM', perda_medida: 0.05, premissa_atual: 0.03,
        cobrancas_resolvidas: 20, cobrancas_perdidas: 1, valor_resolvido: 2000, valor_perdido: 100 }),
    ], erro: null } };
    const html = render({ visao });
    expect(html).toContain('90%');
    expect(html).toContain('aria-expanded="false"');
    expect(html).toContain('5%');
    expect(html).toContain('aria-label="Ajustar a perda de Parcelas a vencer HM em Premissas"');
  });
  it('sem carga base: erro uma vez (4 semanas) e alertas dizem que dependem dela', () => {
    const html = render({ dados: null, erroReceber: 'Falhou.' });
    expect(html.match(/Falhou\./g)).toHaveLength(1);
    expect(html).toContain('Os alertas dependem da previsão');
  });
});

describe('sub-abas nascem filtradas pelo link', () => {
  it('Recorrências com filtroInicial em_atraso_fora', () => {
    const html = renderToStaticMarkup(createElement(Recorrencias, { cobrancas: cobrancasRecorrentes(linhas), filtroInicial: 'em_atraso_fora' }));
    expect(html).toMatch(/aria-pressed="true"[^>]*>Fora da projeção/);
  });
  it('Eventos com filtroInicial encerrado', () => {
    const html = renderToStaticMarkup(createElement(Eventos, {
      eventos: [], erro: null, candidatos: null, erroCandidatos: null, canEdit: false, hojeISO: HOJE, onPedirCandidatos: vi.fn(),
      filtroInicial: 'encerrado',
    }));
    expect(html).toMatch(/<option value="encerrado" selected=""/);
  });
  it('Informados com filtroInicial em_atraso_cobrar', () => {
    const repo: RepoInformados = {
      loadInformados: vi.fn(async () => []),
      salvarInformado: vi.fn(async () => ({ ok: true })),
      baixarInformado: vi.fn(async () => ({ ok: true })),
      arquivarInformado: vi.fn(async () => ({ ok: true })),
      importarInformados: vi.fn(async () => ({ ok: true, linhas: [] })),
    };
    const html = renderToStaticMarkup(createElement(Informados, {
      repo, canEdit: false, canVerDoc: false, inicial: [], filtroInicial: 'em_atraso_cobrar',
    }));
    expect(html).toMatch(/aria-pressed="true"[^>]*>Em atraso — cobrar/);
  });
});
