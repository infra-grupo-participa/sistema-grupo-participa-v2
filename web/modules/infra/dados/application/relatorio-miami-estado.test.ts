import { describe, expect, it } from 'vitest';
import { conteudoExemplo, respostaExemplo } from '../domain/relatorio-miami.fixture';
import type { ConteudoRelatorioMiami } from '../domain/relatorio-miami';
import type { ResultadoRelatorio } from '../infrastructure/relatorio-miami-data';
import { aplicarLeitura, estadoInicialRelatorio } from './relatorio-miami-estado';

const ok = (extra: Parameters<typeof respostaExemplo>[0] = {}): ResultadoRelatorio => ({ data: respostaExemplo(extra), erro: null, permanente: false });
const falha = (erro: string, permanente = false): ResultadoRelatorio => ({ data: null, erro, permanente });
const T0 = 1_000;

describe('aplicarLeitura', () => {
  it('primeira leitura com cópia guarda conteúdo e md5', () => {
    const e = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    expect(e).toMatchObject({ md5: 'md5-a', carregando: false, semCopia: false, erroTela: null, erroLeitor: null, verificadoEm: T0, lidoEm: '2026-10-16T17:00:00Z' });
    expect(e.conteudo).toBe(conteudoExemplo);
  });

  it('sem cópia ainda: marca semCopia e não inventa conteúdo nem data', () => {
    const e = aplicarLeitura(estadoInicialRelatorio('k'), ok({ disponivel: false, md5: null, conteudo: null, lido_em: null }), T0);
    expect(e).toMatchObject({ semCopia: true, conteudo: null, lidoEm: null, carregando: false });
  });

  it('cópia igual não rebaixa: mantém a mesma referência de conteúdo e só atualiza a conferência', () => {
    const a = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    const b = aplicarLeitura(a, ok({ igual: true, conteudo: null }), T0 + 60_000);
    expect(b.conteudo).toBe(a.conteudo);
    expect(b.verificadoEm).toBe(T0 + 60_000);
  });

  it('cópia nova substitui o conteúdo e o md5', () => {
    const a = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    const novo: ConteudoRelatorioMiami = { ...conteudoExemplo, avisos: [{ codigo: 'x', texto: 'aviso' }] };
    const b = aplicarLeitura(a, ok({ md5: 'md5-b', conteudo: novo }), T0 + 1);
    expect(b.conteudo).toBe(novo);
    expect(b.md5).toBe('md5-b');
  });

  it('falha de chamada segura o último valor e só marca o erro', () => {
    const a = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    const b = aplicarLeitura(a, falha('Não foi possível carregar agora.'), T0 + 1);
    expect(b.conteudo).toBe(a.conteudo);
    expect(b.md5).toBe('md5-a');
    expect(b).toMatchObject({ erroTela: 'Não foi possível carregar agora.', permanente: false });
  });

  it('falha permanente (função fora do banco) sem cópia: sem conteúdo, erro claro, polling deve parar', () => {
    const e = aplicarLeitura(estadoInicialRelatorio('k'), falha('Esta função ainda não está no banco. Avise quem cuida do sistema.', true), T0);
    expect(e).toMatchObject({ conteudo: null, permanente: true, carregando: false, semCopia: false });
    expect(e.erroTela).toContain('ainda não está no banco');
  });

  it('erro de leitura da planilha chega com a cópia anterior e aparece como erroLeitor', () => {
    const a = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    const b = aplicarLeitura(a, ok({ igual: true, conteudo: null, erro: 'google_leitura', tentado_em: '2026-10-16T17:10:00Z' }), T0 + 1);
    expect(b).toMatchObject({ erroLeitor: 'google_leitura', tentadoEm: '2026-10-16T17:10:00Z', lidoEm: '2026-10-16T17:00:00Z' });
    expect(b.conteudo).toBe(a.conteudo);
  });

  it('a leitura boa seguinte limpa o erro', () => {
    const a = aplicarLeitura(aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0), falha('x'), T0 + 1);
    const b = aplicarLeitura(a, ok({ igual: true, conteudo: null }), T0 + 2);
    expect(b.erroTela).toBeNull();
    expect(b.erroLeitor).toBeNull();
  });

  it('cópia some do banco depois de a tela ter uma: mantém a que tem e avisa', () => {
    const a = aplicarLeitura(estadoInicialRelatorio('k'), ok(), T0);
    const b = aplicarLeitura(a, ok({ disponivel: false, md5: null, conteudo: null }), T0 + 1);
    expect(b.conteudo).toBe(a.conteudo);
    expect(b.erroTela).toContain('deixou de estar disponível');
  });

  it('"igual" para um md5 que a tela não tem esquece o md5, para a próxima leitura trazer tudo', () => {
    const b = aplicarLeitura(estadoInicialRelatorio('k'), ok({ igual: true, conteudo: null }), T0);
    expect(b.conteudo).toBeNull();
    expect(b.md5).toBeNull();
    expect(b.erroTela).not.toBeNull();
  });

  it('contato_visivel falso do banco passa para a tela', () => {
    expect(aplicarLeitura(estadoInicialRelatorio('k'), ok({ contato_visivel: false }), T0).contatoVisivel).toBe(false);
  });
});
