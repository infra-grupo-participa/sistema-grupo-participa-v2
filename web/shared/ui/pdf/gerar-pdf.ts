'use client';

// Geração do PDF no navegador. A lib (@react-pdf/renderer + fontes) só é baixada
// no clique, e roda num Web Worker (pdf.worker.ts → desenho-pdf.ts): a Pessoas do HM
// tem 9.228 linhas em produção e o desenho leva mais de um minuto — na thread da
// tela, a aba congelaria. Sem Worker no ambiente (teste em Node), desenha aqui mesmo.
//
// Protocolo NUNCA é opcional (decisão do Marcio): gerarPdfComProtocolo() emite,
// desenha, calcula o SHA-256, sela e só então baixa. Qualquer falha em emitir,
// desenhar ou selar lança erro e o arquivo não sai. Não existe caminho sem
// protocolo e não existe fallback para window.print().
import type { DocumentoRelatorio, NivelPii, RascunhoRelatorio } from './modelo';
import { aplicarNivel, contarLinhasDetalhe } from './nivel';
import type { Desenho, PedidoDesenho, ProgressoDesenho, RespostaDesenho } from './desenho-pdf';

/** Dados que a emissão grava (fn_fin_relatorio_emitir: p_tipo, p_nivel, p_recorte, p_linhas, p_totais). */
export interface MetaEmissao {
  tipo: RascunhoRelatorio['tipo'];
  nivel: NivelPii;
  /**
   * Objeto de 1º nível SEM chave de busca/dado pessoal (fin.relatorio_recorte_valido recusa
   * 'busca','nome','email','cpf'…). O termo de busca livre nunca vai: só `busca_aplicada: true`.
   */
  recorte: { filtros: string[]; busca_aplicada?: true };
  linhas: number;
  /** KPIs do documento em texto (≤ 8 KB). */
  totais: Record<string, string>;
}

export interface EmissaoProtocolo {
  protocolo: string;
  /** ISO timestamptz da emissão (vai impresso no cabeçalho e no rodapé). */
  emitidoEm: string;
}

/** As chamadas ao banco. Quem liga ao repositório implementa (ver modules/financeiro/ui/pdf/protocolo.ts). */
export interface ChamadasProtocolo {
  emitir(meta: MetaEmissao): Promise<EmissaoProtocolo>;
  /** true = selou. false (fora da janela, já selado, não é seu) = falha: o PDF não sai. */
  selar(selo: { protocolo: string; sha256: string; paginas: number }): Promise<boolean>;
}

/** Etapas mostradas no botão enquanto gera. */
export type ProgressoPdf =
  | { etapa: 'preparando' }
  | { etapa: 'emitindo' }
  | ProgressoDesenho
  | { etapa: 'selando' };

/** Monta o recorte que vai para o banco a partir do rascunho (busca livre nunca vai). */
export function recorteParaEmissao(r: RascunhoRelatorio): MetaEmissao['recorte'] {
  const filtros = r.recorte.filter((i) => !i.pii).map((i) => `${i.rotulo}: ${i.valor}`);
  return r.recorte.some((i) => i.pii) ? { filtros, busca_aplicada: true } : { filtros };
}

// ─── Quem desenha ─────────────────────────────────────────────────────────────

interface Desenhista {
  /** Resolve quando a lib de PDF está carregada. Falha aqui não consome protocolo. */
  preparar(): Promise<void>;
  desenhar(doc: DocumentoRelatorio, aoProgresso?: (p: ProgressoDesenho) => void): Promise<Desenho>;
  encerrar(): void;
}

function desenhistaEmWorker(): Desenhista {
  const worker = new Worker(new URL('./pdf.worker.ts', import.meta.url), { type: 'module', name: 'gerador-pdf' });
  let aoPronto: () => void = () => {};
  let aoFalharCarga: (e: Error) => void = () => {};
  const pronto = new Promise<void>((resolve, reject) => { aoPronto = resolve; aoFalharCarga = reject; });
  let pendente: { resolver(d: Desenho): void; rejeitar(e: Error): void; aoProgresso?: (p: ProgressoDesenho) => void } | null = null;

  worker.onmessage = (e: MessageEvent<RespostaDesenho>) => {
    const r = e.data;
    if (r.tipo === 'pronto') { aoPronto(); return; }
    if (!pendente) return;
    if (r.tipo === 'progresso') pendente.aoProgresso?.(r.progresso);
    else if (r.tipo === 'feito') pendente.resolver({ bytes: new Uint8Array(r.bytes), sha256: r.sha256, paginas: r.paginas });
    else pendente.rejeitar(new Error(r.mensagem));
  };
  const falhar = (mensagem: string) => {
    const erro = new Error(mensagem);
    aoFalharCarga(erro);
    pendente?.rejeitar(erro);
  };
  worker.onerror = (e) => { e.preventDefault?.(); falhar(`O gerador de PDF falhou${e.message ? `: ${e.message}` : '.'}`); };
  worker.onmessageerror = () => falhar('O gerador de PDF devolveu uma mensagem ilegível.');

  return {
    preparar: () => pronto,
    desenhar: (doc, aoProgresso) => new Promise<Desenho>((resolver, rejeitar) => {
      pendente = { resolver, rejeitar, aoProgresso };
      const pedido: PedidoDesenho = { tipo: 'desenhar', doc, base: '/' };
      worker.postMessage(pedido);
    }),
    encerrar: () => worker.terminate(),
  };
}

/** Sem Worker no ambiente: desenha na mesma thread (Base '/' = web/public servido pelo Next). */
function desenhistaLocal(): Desenhista {
  let mod: typeof import('./desenho-pdf') | null = null;
  return {
    async preparar() { mod = await import('./desenho-pdf'); },
    desenhar: (doc, aoProgresso) => mod!.desenharDocumento(doc, '/', aoProgresso),
    encerrar() {},
  };
}

// Não exportada de propósito: o único caminho que baixa é gerarPdfComProtocolo,
// depois do selo. Exportar "baixar" permitiria um PDF com protocolo não selado.
function baixarPdf(bytes: Uint8Array, nome: string): void {
  const url = URL.createObjectURL(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = nome;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 10_000);
}

/**
 * Fluxo completo: nível → (lib carregada) → emitir → desenhar + SHA-256 (worker) → selar → baixar.
 * A lib é carregada ANTES de emitir: falha de rede no carregamento não consome protocolo.
 */
export async function gerarPdfComProtocolo(
  rascunho: RascunhoRelatorio, nivel: NivelPii, chamadas: ChamadasProtocolo,
  aoProgresso?: (p: ProgressoPdf) => void,
): Promise<{ protocolo: string; paginas: number }> {
  const nivelado = aplicarNivel(rascunho, nivel); // lança se o relatório não aceita o nível
  aoProgresso?.({ etapa: 'preparando' });
  const desenhista = typeof Worker === 'undefined' ? desenhistaLocal() : desenhistaEmWorker();
  try {
    await desenhista.preparar();

    aoProgresso?.({ etapa: 'emitindo' });
    const emissao = await chamadas.emitir({
      tipo: rascunho.tipo,
      nivel,
      recorte: recorteParaEmissao(rascunho),
      linhas: contarLinhasDetalhe(rascunho),
      totais: Object.fromEntries((rascunho.kpis ?? []).map((k) => [k.rotulo, k.valor])),
    });
    if (!emissao?.protocolo) throw new Error('A emissão não devolveu protocolo.');

    const doc: DocumentoRelatorio = { ...nivelado, protocolo: emissao.protocolo, emitidoEm: emissao.emitidoEm };
    const { bytes, sha256, paginas } = await desenhista.desenhar(doc, aoProgresso);

    aoProgresso?.({ etapa: 'selando' });
    const selou = await chamadas.selar({ protocolo: emissao.protocolo, sha256, paginas });
    if (!selou) throw new Error(`O protocolo ${emissao.protocolo} não foi selado. O PDF não foi gerado.`);

    baixarPdf(bytes, `${doc.arquivo}-${doc.protocolo}.pdf`);
    return { protocolo: emissao.protocolo, paginas };
  } finally {
    desenhista.encerrar();
  }
}
