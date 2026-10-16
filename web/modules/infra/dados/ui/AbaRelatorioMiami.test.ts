import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';
import { estadoInicialRelatorio, type EstadoRelatorioMiami } from '../application/relatorio-miami-estado';
import { conteudoExemplo, diamantes, kpiDadosIniciais, kpiParticipacao } from '../domain/relatorio-miami.fixture';
import type { ConteudoRelatorioMiami } from '../domain/relatorio-miami';
import { ModalLinhaRelatorio } from './ModalLinhaRelatorio';
import { COLUNAS_CONTATO, TabelaRelatorioMiami } from './TabelaRelatorioMiami';
import { AbaRelatorioMiami, abasRelatorioMiami, ehSecaoRelatorioMiami, type SecaoRelatorioMiami } from './AbaRelatorioMiami';

const comCopia = (extra: Partial<EstadoRelatorioMiami> = {}): EstadoRelatorioMiami => ({
  ...estadoInicialRelatorio('clinica-miami-2026-12'), carregando: false, conteudo: conteudoExemplo, md5: 'md5-a', lidoEm: '2026-10-16T17:00:00Z', ...extra,
});
const html = (secao: SecaoRelatorioMiami, estado: EstadoRelatorioMiami) => renderToStaticMarkup(createElement(AbaRelatorioMiami, { secao, estado }));
const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#x27;');

describe('abas da cópia da planilha', () => {
  it('registra as quatro abas na ordem do pedido', () => {
    expect(abasRelatorioMiami.map((a) => a.l)).toEqual(['Relatório', 'Diamantes', 'Compradores', 'Presença por evento']);
    expect(ehSecaoRelatorioMiami('presenca')).toBe(true);
    expect(ehSecaoRelatorioMiami('interesse')).toBe(false);
  });
});

describe('estados da aba', () => {
  it('carregando mostra o indicador, sem número', () => {
    const h = html('relatorio', estadoInicialRelatorio('k'));
    expect(h).toContain('Carregando o relatório da planilha');
  });

  it('sem cópia no banco mostra aviso claro e nenhum número', () => {
    const h = html('relatorio', { ...estadoInicialRelatorio('k'), carregando: false, semCopia: true });
    expect(h).toContain('O relatório da planilha ainda não está no banco');
    expect(h).not.toContain('Pessoas na Lista Diamantes');
  });

  it('função fora do banco, sem cópia: mensagem de erro em alerta, as outras abas não dependem disso', () => {
    const h = html('diamantes', { ...estadoInicialRelatorio('k'), carregando: false, erroTela: 'Esta função ainda não está no banco. Avise quem cuida do sistema.', permanente: true });
    expect(h).toContain('role="alert"');
    expect(h).toContain('ainda não está no banco');
  });

  it('erro com cópia boa: mantém os números, avisa com a data e esmaece', () => {
    const h = html('relatorio', comCopia({ erroTela: 'Não foi possível carregar agora.' }));
    expect(h).toContain('Não foi possível carregar agora. Exibindo a última cópia carregada.');
    expect(h).toContain('opacity-70');
    expect(h).toContain('Pessoas na Lista Diamantes');
  });

  it('erro do leitor da planilha mostra o código e a data da cópia exibida', () => {
    const h = html('relatorio', comCopia({ erroLeitor: 'google_leitura' }));
    expect(h).toContain('google_leitura');
    expect(h).toContain('Exibindo a cópia de');
    expect(h).toContain('opacity-70');
  });

  it('cópia sem erro não esmaece e diz de qual aba e quando foi lida', () => {
    const h = html('relatorio', comCopia());
    expect(h).not.toContain('opacity-70');
    expect(h).toContain('Cópia da aba “Relatório” da planilha');
    expect(h).toContain('lida em');
  });

  it('avisos do leitor aparecem com o texto exato, sem esconder', () => {
    const c: ConteudoRelatorioMiami = { ...conteudoExemplo, avisos: [{ codigo: 'aba_truncada', texto: 'A aba tinha mais linhas do que o limite.' }] };
    expect(html('relatorio', comCopia({ conteudo: c }))).toContain('A aba tinha mais linhas do que o limite.');
  });
});

describe('aba Relatório', () => {
  it('mostra cada rótulo e valor exatos dos blocos de indicadores', () => {
    const h = html('relatorio', comCopia());
    for (const bloco of [kpiDadosIniciais, conteudoExemplo.blocos.time_formulario, kpiParticipacao]) {
      expect(h).toContain(esc(bloco.titulo));
      for (const item of bloco.itens) {
        expect(h).toContain(esc(item.rotulo));
        if (item.valor) expect(h).toContain(`>${esc(item.valor)}<`);
      }
    }
  });

  it('subgrupo de contagens vira rosca; percentual vira barra', () => {
    const h = html('relatorio', comCopia());
    expect(h).toContain('Situação de quem respondeu');
    expect(h).toContain('role="progressbar"');
  });
});

describe('aba Diamantes e Compradores', () => {
  it('Diamantes: título e contagem de linhas da fonte, com cabeçalho exato', () => {
    const h = html('diamantes', comCopia());
    expect(h).toContain(esc(diamantes.titulo));
    expect(h).toContain(`de ${diamantes.linhas.length} linhas`);
    expect(h).toContain('Situação para os eventos nos EUA');
    expect(h).toContain('Pessoa Teste 1');
  });

  it('Compradores existe e lista as linhas', () => {
    const h = html('compradores', comCopia());
    expect(h).toContain(`de ${conteudoExemplo.blocos.compradores.linhas.length} linhas`);
    expect(h).toContain('Comprador Teste 1');
  });

  it('contato_visivel verdadeiro mostra e-mail e telefone; falso esconde as colunas de contato (tabela com todas as colunas)', () => {
    const tabela = (contatoVisivel: boolean) => renderToStaticMarkup(createElement(TabelaRelatorioMiami, { bloco: diamantes, contatoVisivel }));
    const visivel = tabela(true);
    expect(visivel).toContain('title="E-mail"');
    expect(visivel).toContain('pessoa1@exemplo.invalido');
    const escondido = tabela(false);
    expect(escondido).not.toContain('E-mail');
    expect(escondido).not.toContain('Telefone');
    expect(escondido).not.toContain('exemplo.invalido');
  });

  it('visão padrão das Diamantes não traz contato na tabela (fica no detalhe e em "Todas as colunas")', () => {
    expect(html('diamantes', comCopia())).not.toContain('exemplo.invalido');
  });

  it('detalhe da linha: contato some quando oculto, e vazio vira "—"', () => {
    const modal = (ocultar: string[]) => renderToStaticMarkup(createElement(ModalLinhaRelatorio, { titulo: diamantes.titulo, colunas: diamantes.colunas, celulas: diamantes.linhas[2], ocultar, onClose: () => {} }));
    expect(modal([])).toContain('pessoa3@exemplo.invalido');
    expect(modal(COLUNAS_CONTATO)).not.toContain('pessoa3@exemplo.invalido');
    expect(modal(COLUNAS_CONTATO)).toContain('Pessoa Teste 3');
  });

  it('tabela vazia na planilha mostra estado vazio, não zero', () => {
    const c: ConteudoRelatorioMiami = { ...conteudoExemplo, blocos: { ...conteudoExemplo.blocos, compradores: { ...conteudoExemplo.blocos.compradores, linhas: [] } } };
    expect(html('compradores', comCopia({ conteudo: c }))).toContain('Esta tabela está vazia na planilha');
  });
});

describe('aba Presença por evento', () => {
  it('mostra os eventos, o "—" onde a planilha não tem dado e as camisas com o Total', () => {
    const h = html('presenca', comCopia());
    expect(h).toContain('Festa dos Iates');
    expect(h).toContain('Reunião do Diamante Vermelho');
    expect(h).toContain('—');
    expect(h).toContain(esc(conteudoExemplo.blocos.camisas.titulo));
    expect(h).toContain('>Total<');
    expect(h).toContain('sem dado na planilha');
  });
});
