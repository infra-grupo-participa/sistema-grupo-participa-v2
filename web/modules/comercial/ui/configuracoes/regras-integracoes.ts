// Regras de tela das integrações (painel Hotmart e tokens do MCP), puras e testáveis.
// As validações repetem as do banco (crm_mcp_criar_token, crm_hotmart_painel) só para avisar antes; quem decide é o banco.
import { ROTULO_ORIGEM } from '../../domain/catalogo';
import type { EscopoMcp, OrigemTipo, PainelHotmart, TokenMcp } from '../../domain/types';

// ── Hotmart ──

/** Rótulo do resultado gravado pelo banco (primeira parte de `resultado`). Desconhecido: o próprio texto. */
const ROTULO_RESULTADO: Record<string, string> = {
  ganho: 'Fechou ganho',
  negocio_criado: 'Criou negócio',
  jornada: 'Só na jornada',
  ignorado: 'Ignorado',
  duplicado: 'Repetido',
  desligado: 'Recebido desligado',
  processando: 'Processando',
  erro: 'Erro',
};

export function rotuloResultadoHotmart(r: string): string {
  return ROTULO_RESULTADO[r] ?? r;
}

export function rotuloClasseHotmart(classe: string): string {
  return (ROTULO_ORIGEM as Partial<Record<string, string>>)[classe as OrigemTipo] ?? classe.replace(/_/g, ' ');
}

export interface ResumoHotmart {
  total: number;
  negocios: number;
  ganhos: number;
  erros: number;
  /** Por resultado, maior primeiro (para a lista de "o que aconteceu"). */
  porResultado: { resultado: string; rotulo: string; n: number }[];
}

export function resumoHotmart(p: Pick<PainelHotmart, 'porResultado'>): ResumoHotmart {
  const soma = new Map<string, number>();
  for (const x of p.porResultado) soma.set(x.resultado, (soma.get(x.resultado) ?? 0) + x.n);
  const n = (k: string) => soma.get(k) ?? 0;
  return {
    total: [...soma.values()].reduce((a, b) => a + b, 0),
    negocios: n('negocio_criado'),
    ganhos: n('ganho'),
    erros: n('erro'),
    porResultado: [...soma.entries()]
      .map(([resultado, q]) => ({ resultado, rotulo: rotuloResultadoHotmart(resultado), n: q }))
      .sort((a, b) => b.n - a.n || a.rotulo.localeCompare(b.rotulo)),
  };
}

/** "erro: oferta sem produto" → "oferta sem produto" (o "erro" já está no selo). */
export function textoErroHotmart(resultado: string): string {
  const t = resultado.replace(/^erro\s*:?\s*/i, '').trim();
  return t || 'Erro sem detalhe.';
}

/** Reprocessar só faz sentido com a integração ligada (o banco recusa desligada). */
export function podeReprocessar(p: Pick<PainelHotmart, 'hotmartLigado'>, gestor: boolean): boolean {
  return gestor && p.hotmartLigado;
}

export const PERIODOS_HOTMART = [1, 7, 30, 90] as const;

// ── MCP ──

export const URL_MCP = 'https://grupoparticipa.app.br/api/mcp';
export const VALIDADES_TOKEN = [7, 30, 90, 180] as const;
export const MAX_TOKENS_ATIVOS = 5;

export type EstadoMcp = 'ligado' | 'desligado' | 'desconhecido';

/**
 * Estado do interruptor do MCP para a tela. O banco ainda não expõe `mcp_ligado` na leitura: sem o campo,
 * a resposta "MCP do Comercial desligado." ao criar token é o que revela o estado.
 */
export function estadoMcp(mcpLigado: boolean | null | undefined, respostaDesligado: boolean): EstadoMcp {
  if (respostaDesligado) return 'desligado';
  if (mcpLigado === true) return 'ligado';
  if (mcpLigado === false) return 'desligado';
  return 'desconhecido';
}

export function ehRespostaMcpDesligado(msg: string | undefined): boolean {
  return !!msg && /MCP do Comercial desligado/i.test(msg);
}

export interface NovoToken {
  nome: string;
  operar: boolean;
  dias: number;
}

/** Mesmas regras de `crm_mcp_criar_token`. null = pode enviar. */
export function validarNovoToken(t: NovoToken, ativosMeus: number): string | null {
  const nome = t.nome.trim();
  if (!nome) return 'Dê um nome ao token (ex.: "Claude Code notebook").';
  if (nome.length > 60) return 'Nome com até 60 caracteres.';
  if (!Number.isInteger(t.dias) || t.dias < 1 || t.dias > 180) return 'Validade entre 1 e 180 dias.';
  if (ativosMeus >= MAX_TOKENS_ATIVOS) return `Limite de ${MAX_TOKENS_ATIVOS} tokens ativos: revogue um antes.`;
  return null;
}

/** `ler` sempre vai; `operar` só quando marcado. */
export function escoposDoNovoToken(operar: boolean): EscopoMcp[] {
  return operar ? ['ler', 'operar'] : ['ler'];
}

export type SituacaoToken = 'ativo' | 'expirado' | 'revogado';

export function situacaoToken(t: Pick<TokenMcp, 'revogadoEm' | 'expiraEm'>, agora: Date): SituacaoToken {
  if (t.revogadoEm) return 'revogado';
  return new Date(t.expiraEm).getTime() > agora.getTime() ? 'ativo' : 'expirado';
}

/** Ativos primeiro (mais recentes no topo), depois expirados e revogados. */
export function ordenarTokens(lista: TokenMcp[], agora: Date): TokenMcp[] {
  const peso: Record<SituacaoToken, number> = { ativo: 0, expirado: 1, revogado: 2 };
  return [...lista].sort((a, b) => peso[situacaoToken(a, agora)] - peso[situacaoToken(b, agora)] || b.criadoEm.localeCompare(a.criadoEm));
}

export function ativosDe(lista: TokenMcp[], perfilId: string | undefined, agora: Date): number {
  return lista.filter((t) => t.perfilId === perfilId && situacaoToken(t, agora) === 'ativo').length;
}

export function rotuloEscopos(e: EscopoMcp[]): string {
  return e.includes('operar') ? 'Ler e operar' : 'Só leitura';
}

/** Comando do Claude Code com o token já preenchido (ou o marcador, quando ainda não há token). */
export function comandoClaudeCode(token: string | null): string {
  return `claude mcp add --transport http comercial ${URL_MCP} \\\n  --header "Authorization: Bearer ${token ?? 'gpc_SEU_TOKEN'}"`;
}

/** Trecho do claude_desktop_config.json (via mcp-remote). */
export function configClaudeDesktop(token: string | null): string {
  return JSON.stringify({
    mcpServers: {
      comercial: {
        command: 'npx',
        args: ['-y', 'mcp-remote', URL_MCP, '--header', 'Authorization: Bearer ${GP_MCP_TOKEN}'],
        env: { GP_MCP_TOKEN: token ?? 'gpc_SEU_TOKEN' },
      },
    },
  }, null, 2);
}
