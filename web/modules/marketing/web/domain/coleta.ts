// Marketing > Web: a porta da coleta (rota pública /api/web/coletar). Regras puras da primeira barreira, antes do
// banco: método, tamanho, origem cadastrada e robô. O banco (public.mkt_web_coletar) confere tudo de novo e aplica o
// limite por IP e por sessão que vale para todos os processos.

/** maior pacote aceito (sem vídeo, um pacote do gravador fica bem abaixo; o banco recusa acima disto também) */
export const LIMITE_BYTES = 65536;

/** limite em memória por IP, por minuto (primeira barreira; o do banco é o que vale) */
export const LIMITE_IP_MINUTO = 600;

/** respostas que o gravador entende (o banco devolve as mesmas) */
export type RespostaColeta =
  | 'ok' | 'repetido' | 'pausado' | 'limite' | 'projeto' | 'dominio' | 'identificador' | 'tamanho' | 'json' | 'erro' | 'metodo';

/** host da origem do navegador, sem porta e sem www. (o domínio em mkt.paginas não tem www); vazio se inválida */
export function hostDaOrigem(origem: string | null | undefined): string {
  const v = (origem || '').trim();
  if (!v) return '';
  try {
    const u = new URL(v);
    if (u.protocol !== 'https:' && u.protocol !== 'http:') return '';
    return u.hostname.toLowerCase().replace(/^www\./, '');
  } catch {
    return '';
  }
}

// a mesma lista do radar.robo (banco/014 do Radar), mais os testes do Google
const ROBO = /(googlebot|adsbot-google|mediapartners-google|google-inspectiontool|googleother|storebot-google|feedfetcher-google|google page speed|chrome-lighthouse|bingbot|bingpreview|msnbot|yandexbot|yandexmobilebot|baiduspider|duckduckbot|applebot|petalbot|seznambot|ahrefsbot|semrushbot|mj12bot|dotbot|dataforseobot|rogerbot|screaming frog|gptbot|oai-searchbot|chatgpt-user|claudebot|claude-web|anthropic-ai|perplexitybot|bytespider|amazonbot|ccbot|facebookexternalhit|facebookcatalog|meta-externalagent|meta-externalfetcher|telegrambot|twitterbot|linkedinbot|slackbot|discordbot|pinterestbot|headlesschrome|phantomjs|ptst\/|gtmetrix|pingdom|uptimerobot|statuscake|site24x7|python-requests|python-urllib|curl\/|wget\/|go-http-client|node-fetch|axios\/)/i;

/** robô não é visita (o teste do PageSpeed se passa por "moto g power (2022)") */
export function ehRobo(ua: string | null | undefined): boolean {
  const s = ua || '';
  if (!s.trim()) return true;
  if (/moto g power \(2022\)\) AppleWebKit/.test(s)) return true;
  return ROBO.test(s);
}

export interface Pedido {
  metodo: string;
  origem: string | null;
  /** content-length declarado (pode faltar); o corpo lido é conferido de novo depois */
  tamanhoDeclarado: number | null;
  userAgent: string | null;
}

export type Avaliacao =
  | { ok: true; host: string }
  | { ok: false; resposta: RespostaColeta; status: number; registrar: boolean };

/**
 * A primeira barreira. `dominios` = os domínios aceitos agora (páginas ativas de projetos com a coleta ligada).
 * Robô recebe "pausado" (o gravador para por 30 min) e não vai ao banco.
 */
export function avaliarPedido(p: Pedido, dominios: ReadonlySet<string>): Avaliacao {
  if (p.metodo !== 'POST') return { ok: false, resposta: 'metodo', status: 405, registrar: false };
  if (p.tamanhoDeclarado != null && p.tamanhoDeclarado > LIMITE_BYTES) {
    return { ok: false, resposta: 'tamanho', status: 413, registrar: false };
  }
  const host = hostDaOrigem(p.origem);
  if (!host || !dominios.has(host)) return { ok: false, resposta: 'dominio', status: 403, registrar: false };
  if (ehRobo(p.userAgent)) return { ok: false, resposta: 'pausado', status: 200, registrar: false };
  return { ok: true, host };
}

/** o corpo de verdade (o content-length pode mentir ou faltar) */
export function corpoValido(corpo: string): RespostaColeta | null {
  if (new TextEncoder().encode(corpo).length > LIMITE_BYTES) return 'tamanho';
  if (!corpo.trim().startsWith('{')) return 'json';
  return null;
}

const RESPOSTAS: ReadonlySet<string> = new Set(['ok', 'repetido', 'pausado', 'limite', 'projeto', 'dominio', 'identificador', 'tamanho', 'json', 'erro']);
/** o banco só devolve texto da lista; qualquer outra coisa vira "erro" */
export const respostaDoBanco = (v: unknown): RespostaColeta => (typeof v === 'string' && RESPOSTAS.has(v) ? (v as RespostaColeta) : 'erro');

/** A linha de instalação que vai no <head> da página. `base` = origem do nosso sistema (sem barra no fim). */
export function linhaDoGravador(sigla: string, base: string, arquivo = 'radar-v1.js'): string {
  return `<script src="${base}/web/${arquivo}" data-projeto="${sigla}" async></script>`;
}
