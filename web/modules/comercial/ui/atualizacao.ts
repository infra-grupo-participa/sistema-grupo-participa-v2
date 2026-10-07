// Atualização sozinha das telas do WhatsApp do CRM (sem F5): lógica pura, testável sem React nem navegador.
//
// Intervalos (só com a aba do navegador visível; oculta = pausa; ao voltar o foco busca na hora):
//   conversa aberta 3 s · lista de conversas 10 s · sino 30 s.
// Carga por pessoa com a caixa aberta: 20 crm_mensagens + 6 crm_conversas + 2 crm_notificacoes = 28 chamadas/min.
// 2 vendedores + 3 gestores com a caixa aberta o dia todo ≈ 140 chamadas/min (≈ 2,3/s), cada uma uma RPC STABLE
// pequena (≤ 500 mensagens de UMA pessoa; ≤ 300 conversas). Aba oculta = zero.
// Com o Realtime (Broadcast) ligado, o aviso do banco antecipa a busca; o intervalo continua de reserva.

export const INTERVALO = {
  conversaAberta: 3_000,
  listaConversas: 10_000,
  sino: 30_000,
} as const;

/** Chamadas por minuto de uma pessoa, dados os intervalos ativos (ms). Para a conta de carga. */
export function chamadasPorMinuto(intervalosMs: number[]): number {
  return intervalosMs.reduce((s, ms) => s + Math.floor(60_000 / ms), 0);
}

/** O que o atualizador precisa do navegador (injetável no teste). */
export interface AmbienteAtualizacao {
  visivel(): boolean;
  /** Assina "a aba voltou a ficar visível / ganhou foco". Devolve o cancelamento. */
  aoVoltar(cb: () => void): () => void;
  /** Assina "a aba ficou oculta". Devolve o cancelamento. */
  aoOcultar(cb: () => void): () => void;
  setTimeout(cb: () => void, ms: number): unknown;
  clearTimeout(id: unknown): void;
  agora(): number;
}

export interface Atualizador {
  /** Busca já (aviso do Realtime, volta do foco). Respeita a pausa e não sobrepõe chamadas. */
  cutucar(): void;
  parar(): void;
}

/**
 * Laço de busca periódica:
 * - nunca sobrepõe chamadas (a próxima só agenda quando a atual termina);
 * - aba oculta = nada agendado; ao voltar busca na hora (se a última foi há mais de `folgaMs`) e retoma o ritmo;
 * - `cutucar()` antecipa a busca (com a mesma folga, para foco + visibilidade + Realtime não virarem 3 chamadas).
 */
export function criarAtualizador(
  executar: () => Promise<unknown> | unknown,
  intervaloMs: number,
  amb: AmbienteAtualizacao,
  folgaMs = 1_000,
): Atualizador {
  let timer: unknown = null;
  let emVoo = false;
  let pendente = false; // pediram busca enquanto outra estava em voo
  let ultima = amb.agora(); // a tela acabou de carregar: a primeira busca é a do useDados
  let parado = false;

  const limpar = () => { if (timer !== null) { amb.clearTimeout(timer); timer = null; } };
  const agendar = () => {
    limpar();
    if (parado || !amb.visivel()) return;
    timer = amb.setTimeout(rodar, intervaloMs);
  };
  async function rodar() {
    timer = null;
    if (parado || !amb.visivel()) return;
    if (emVoo) { pendente = true; return; }
    emVoo = true;
    ultima = amb.agora();
    try { await executar(); } catch { /* o erro fica com a tela (useDados); o laço segue */ }
    emVoo = false;
    if (pendente) { pendente = false; ultima = 0; return rodar(); }
    agendar();
  }
  const cutucar = () => {
    if (parado || !amb.visivel()) return;
    if (emVoo) { pendente = true; return; }
    if (amb.agora() - ultima < folgaMs) return;
    limpar();
    void rodar();
  };

  const sairVoltar = amb.aoVoltar(cutucar);
  const sairOcultar = amb.aoOcultar(limpar);
  agendar();

  return {
    cutucar,
    parar() { parado = true; limpar(); sairVoltar(); sairOcultar(); },
  };
}

/** Ambiente real (navegador). */
export function ambienteNavegador(): AmbienteAtualizacao {
  return {
    visivel: () => typeof document === 'undefined' || document.visibilityState !== 'hidden',
    aoVoltar(cb) {
      const vis = () => { if (document.visibilityState === 'visible') cb(); };
      document.addEventListener('visibilitychange', vis);
      window.addEventListener('focus', cb);
      window.addEventListener('online', cb);
      return () => {
        document.removeEventListener('visibilitychange', vis);
        window.removeEventListener('focus', cb);
        window.removeEventListener('online', cb);
      };
    },
    aoOcultar(cb) {
      const vis = () => { if (document.visibilityState === 'hidden') cb(); };
      document.addEventListener('visibilitychange', vis);
      return () => document.removeEventListener('visibilitychange', vis);
    },
    setTimeout: (cb, ms) => window.setTimeout(cb, ms),
    clearTimeout: (id) => window.clearTimeout(id as number),
    agora: () => Date.now(),
  };
}

// ── Reaproveitar o que não mudou (sem piscar, sem re-render à toa) ──

function chaveDe(x: unknown): string | null {
  if (!x || typeof x !== 'object') return null;
  const o = x as { id?: unknown; contatoId?: unknown };
  if (typeof o.id === 'string') return o.id;
  if (typeof o.contatoId === 'string') return o.contatoId;
  return null;
}

/**
 * Junta o resultado novo com o anterior:
 * - tudo igual → devolve o ANTERIOR (mesma referência: React não re-renderiza);
 * - lista de itens com `id`/`contatoId` → sem duplicar a chave (fica a última versão, na posição da 1ª), e cada
 *   item igual ao anterior mantém a referência antiga (bolha/mídia não remonta);
 * - qualquer outra coisa → o novo.
 */
export function reaproveitar<T>(antes: T | null | undefined, novo: T): T {
  if (antes === undefined || antes === null) return dedup(novo);
  if (JSON.stringify(antes) === JSON.stringify(novo)) return antes;
  if (Array.isArray(novo)) {
    const velhos = new Map<string, { item: unknown; json: string }>();
    if (Array.isArray(antes)) for (const it of antes) { const k = chaveDe(it); if (k) velhos.set(k, { item: it, json: JSON.stringify(it) }); }
    const lista = dedup(novo) as unknown as unknown[];
    let mudou = !Array.isArray(antes) || antes.length !== lista.length;
    const out = lista.map((it, i) => {
      const k = chaveDe(it);
      const v = k ? velhos.get(k) : undefined;
      const r = v && v.json === JSON.stringify(it) ? v.item : it;
      if (!mudou && (antes as unknown[])[i] !== r) mudou = true;
      return r;
    });
    return (mudou ? out : antes) as T;
  }
  return novo;
}

function dedup<T>(v: T): T {
  if (!Array.isArray(v)) return v;
  const pos = new Map<string, number>();
  const out: unknown[] = [];
  for (const it of v) {
    const k = chaveDe(it);
    if (k === null) { out.push(it); continue; }
    const i = pos.get(k);
    if (i === undefined) { pos.set(k, out.length); out.push(it); } else out[i] = it;
  }
  return (out.length === v.length ? v : out) as T;
}

// ── Rolagem ──

/** O vendedor está no fim da conversa (com folga)? Só então a mensagem nova rola a tela sozinha. */
export function estaNoFim(scrollTop: number, scrollHeight: number, clientHeight: number, folgaPx = 80): boolean {
  return scrollHeight - scrollTop - clientHeight <= folgaPx;
}
