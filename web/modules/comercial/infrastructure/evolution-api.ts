// Cliente da Evolution API v2 — SÓ servidor (lê env de servidor; nunca importar em Client Component) (Route Handlers de /api/comercial/canais). A chave global nunca vai ao browser.
// URL e chave: env (EVOLUTION_API_URL / EVOLUTION_API_KEY) ou, vazio, o Vault (evolution-credenciais.ts).
// Doc: docs/projetos/comercial/whatsapp-qr-evolution.md
import { credenciaisEvolution } from './evolution-credenciais';
import {
  corpoCriarInstancia, corpoWebhookEvolution, estadoDaResposta, INSTANCIA_RE, numeroDaInstancia, qrDaResposta,
} from '../domain/canais-whatsapp';

const TIMEOUT_MS = 15_000;

export type RespostaEvolution = { http: number; dados: unknown };

export class EvolutionIndisponivel extends Error {}

export class EvolutionApi {
  private constructor(private readonly base: string, private readonly chave: string) {}

  /** null = Evolution não configurada (rota responde 503). Chamar só depois de autorizar o gestor. */
  static async resolver(): Promise<EvolutionApi | null> {
    const c = await credenciaisEvolution();
    return c ? new EvolutionApi(c.base, c.chave) : null;
  }

  private async chamar(metodo: 'GET' | 'POST' | 'DELETE', caminho: string, corpo?: unknown): Promise<RespostaEvolution> {
    try {
      const r = await fetch(this.base + caminho, {
        method: metodo,
        headers: { apikey: this.chave, Accept: 'application/json', ...(corpo ? { 'Content-Type': 'application/json' } : {}) },
        body: corpo ? JSON.stringify(corpo) : undefined,
        signal: AbortSignal.timeout(TIMEOUT_MS),
        cache: 'no-store',
      });
      return { http: r.status, dados: await r.json().catch(() => null) };
    } catch {
      throw new EvolutionIndisponivel('Evolution fora do ar ou lenta.');
    }
  }

  private static inst(instancia: string): string {
    if (!INSTANCIA_RE.test(instancia)) throw new Error('instância inválida');
    return encodeURIComponent(instancia);
  }

  /** Cria a instância (403/409 = já existe: segue). Devolve o QR se já veio. */
  async criar(instancia: string): Promise<{ ok: boolean; qr: string | null; http: number }> {
    const r = await this.chamar('POST', '/instance/create', corpoCriarInstancia(instancia));
    const jaExiste = r.http === 403 || r.http === 409;
    return { ok: (r.http >= 200 && r.http < 300) || jaExiste, qr: qrDaResposta(r.dados), http: r.http };
  }

  async configurarWebhook(instancia: string, url: string, chave: string): Promise<boolean> {
    const r = await this.chamar('POST', `/webhook/set/${EvolutionApi.inst(instancia)}`, corpoWebhookEvolution(url, chave));
    return r.http >= 200 && r.http < 300;
  }

  /** Pede um QR novo (conectar/reconectar). */
  async qr(instancia: string): Promise<{ qr: string | null; http: number }> {
    const r = await this.chamar('GET', `/instance/connect/${EvolutionApi.inst(instancia)}`);
    return { qr: qrDaResposta(r.dados), http: r.http };
  }

  async estado(instancia: string): Promise<{ estado: 'open' | 'close' | 'connecting' | null; http: number }> {
    const r = await this.chamar('GET', `/instance/connectionState/${EvolutionApi.inst(instancia)}`);
    return { estado: estadoDaResposta(r.dados), http: r.http };
  }

  async numero(instancia: string): Promise<string | null> {
    const r = await this.chamar('GET', `/instance/fetchInstances?instanceName=${EvolutionApi.inst(instancia)}`);
    return r.http >= 200 && r.http < 300 ? numeroDaInstancia(r.dados, instancia) : null;
  }

  /** Desconecta o aparelho (o número continua no celular e na Clint). Sessão já fechada também conta como ok. */
  async sair(instancia: string): Promise<boolean> {
    const r = await this.chamar('DELETE', `/instance/logout/${EvolutionApi.inst(instancia)}`);
    return (r.http >= 200 && r.http < 300) || r.http === 400 || r.http === 404;
  }
}
