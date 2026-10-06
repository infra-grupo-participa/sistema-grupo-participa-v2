import { describe, expect, it } from 'vitest';
import type { TokenMcp } from '../../domain/types';
import {
  ativosDe, comandoClaudeCode, configClaudeDesktop, ehRespostaMcpDesligado, escoposDoNovoToken, estadoMcp, ordenarTokens,
  podeReprocessar, resumoHotmart, rotuloClasseHotmart, rotuloResultadoHotmart, situacaoToken, textoErroHotmart, URL_MCP,
  validarNovoToken,
} from './regras-integracoes';

const agora = new Date('2026-10-06T12:00:00Z');
const tok = (p: Partial<TokenMcp>): TokenMcp => ({
  id: 't', nome: 'x', prefixo: 'gpc_1234', escopos: ['ler'], perfilId: 'ana', perfilNome: 'Ana', criadoEm: '2026-10-01T00:00:00Z',
  expiraEm: '2026-12-01T00:00:00Z', revogadoEm: null, ultimoUsoEm: null, ativo: true, ...p,
});

describe('painel Hotmart', () => {
  it('soma por resultado, independente de fonte e classe', () => {
    const r = resumoHotmart({ porResultado: [
      { fonte: 'webhook', classe: 'carrinho_abandonado', resultado: 'negocio_criado', n: 3 },
      { fonte: 'sync', classe: 'cartao_recusado', resultado: 'negocio_criado', n: 2 },
      { fonte: 'webhook', classe: 'compra_aprovada', resultado: 'ganho', n: 4 },
      { fonte: 'webhook', classe: 'compra_aprovada', resultado: 'erro', n: 1 },
    ] });
    expect(r).toMatchObject({ total: 10, negocios: 5, ganhos: 4, erros: 1 });
    expect(r.porResultado[0]).toEqual({ resultado: 'negocio_criado', rotulo: 'Criou negócio', n: 5 });
  });
  it('vazio é zero de verdade (o erro de acesso não chega aqui: vira exceção)', () => {
    expect(resumoHotmart({ porResultado: [] })).toMatchObject({ total: 0, porResultado: [] });
  });
  it('rótulos conhecidos e o texto cru para o resto', () => {
    expect(rotuloResultadoHotmart('duplicado')).toBe('Repetido');
    expect(rotuloResultadoHotmart('novo_x')).toBe('novo_x');
    expect(rotuloClasseHotmart('classe_nova')).toBe('classe nova');
  });
  it('tira o prefixo "erro:" do texto', () => {
    expect(textoErroHotmart('erro: 22003 numeric')).toBe('22003 numeric');
    expect(textoErroHotmart('erro')).toBe('Erro sem detalhe.');
  });
  it('reprocessar: gestor e integração ligada', () => {
    expect(podeReprocessar({ hotmartLigado: true }, true)).toBe(true);
    expect(podeReprocessar({ hotmartLigado: false }, true)).toBe(false);
    expect(podeReprocessar({ hotmartLigado: true }, false)).toBe(false);
  });
});

describe('MCP: estado do interruptor', () => {
  it('resposta "desligado" vence; sem o campo é desconhecido', () => {
    expect(estadoMcp(null, false)).toBe('desconhecido');
    expect(estadoMcp(undefined, true)).toBe('desligado');
    expect(estadoMcp(true, true)).toBe('desligado');
    expect(estadoMcp(true, false)).toBe('ligado');
    expect(estadoMcp(false, false)).toBe('desligado');
  });
  it('reconhece a mensagem do banco', () => {
    expect(ehRespostaMcpDesligado('MCP do Comercial desligado.')).toBe(true);
    expect(ehRespostaMcpDesligado('Validade entre 1 e 180 dias.')).toBe(false);
    expect(ehRespostaMcpDesligado(undefined)).toBe(false);
  });
});

describe('MCP: novo token', () => {
  it('mesmas regras do banco', () => {
    expect(validarNovoToken({ nome: ' ', operar: false, dias: 90 }, 0)).toMatch(/nome/);
    expect(validarNovoToken({ nome: 'x'.repeat(61), operar: false, dias: 90 }, 0)).toMatch(/60/);
    expect(validarNovoToken({ nome: 'ok', operar: false, dias: 181 }, 0)).toMatch(/180/);
    expect(validarNovoToken({ nome: 'ok', operar: false, dias: 90 }, 5)).toMatch(/Limite/);
    expect(validarNovoToken({ nome: 'ok', operar: true, dias: 180 }, 4)).toBeNull();
  });
  it('ler sempre vai; operar só se marcado', () => {
    expect(escoposDoNovoToken(false)).toEqual(['ler']);
    expect(escoposDoNovoToken(true)).toEqual(['ler', 'operar']);
  });
});

describe('MCP: lista de tokens', () => {
  it('situação pelo carimbo e pela validade', () => {
    expect(situacaoToken(tok({}), agora)).toBe('ativo');
    expect(situacaoToken(tok({ expiraEm: '2026-10-01T00:00:00Z' }), agora)).toBe('expirado');
    expect(situacaoToken(tok({ revogadoEm: '2026-10-02T00:00:00Z' }), agora)).toBe('revogado');
  });
  it('ativos primeiro e conta só os meus ativos', () => {
    const l = [tok({ id: 'r', revogadoEm: '2026-10-02T00:00:00Z' }), tok({ id: 'a' }), tok({ id: 'b', perfilId: 'bia' })];
    expect(ordenarTokens(l, agora).map((t) => t.id).slice(-1)).toEqual(['r']);
    expect(ativosDe(l, 'ana', agora)).toBe(1);
  });
});

describe('MCP: como conectar', () => {
  it('Claude Code com o token preenchido', () => {
    const c = comandoClaudeCode('gpc_abc');
    expect(c).toContain(URL_MCP);
    expect(c).toContain('Bearer gpc_abc');
  });
  it('Claude Desktop: JSON válido com mcp-remote', () => {
    const j = JSON.parse(configClaudeDesktop(null));
    expect(j.mcpServers.comercial.args).toContain('mcp-remote');
    expect(j.mcpServers.comercial.env.GP_MCP_TOKEN).toBe('gpc_SEU_TOKEN');
  });
});
