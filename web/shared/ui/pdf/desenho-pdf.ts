// Desenho do PDF: documento (já com protocolo) → bytes, SHA-256 e número de folhas.
//
// No navegador isto roda DENTRO do Web Worker (pdf.worker.ts): com a Pessoas do HM
// (9.228 linhas medidas em produção, 28/09) o desenho leva mais de um minuto e, na
// thread da tela, congelaria a aba inteira. Emitir e selar ficam na tela (precisam da
// sessão do Supabase); daqui só saem bytes, hash e progresso.
//
// Importa @react-pdf estaticamente: só entra pelo worker ou por `await import()`.
import { createElement } from 'react';
import { pdf } from '@react-pdf/renderer';
import { DocumentoPdf, ligarAvisoDePalavra, type SinaisDesenho } from './DocumentoPdf';
import type { DocumentoRelatorio } from './modelo';
import { contarPaginasPdf, sha256Hex } from './bytes-pdf';

/**
 * Progresso real, tirado do motor (DocumentoPdf → SinaisDesenho):
 *  - montando: folha estimada pela fração de palavras já diagramadas (o motor diagrama
 *    folha a folha, então palavras feitas / palavras totais acompanha as folhas);
 *  - numerando: as 2 passadas do motor pelos rodapés ("Página X de Y"), feito/total;
 *  - gravando: escrita do arquivo e SHA-256.
 */
export type ProgressoDesenho =
  | { etapa: 'montando'; folha: number; folhas: number }
  | { etapa: 'numerando'; feito: number; total: number }
  | { etapa: 'gravando'; folhas: number };

export interface Desenho {
  bytes: Uint8Array;
  sha256: string;
  paginas: number;
}

export async function desenharDocumento(
  doc: DocumentoRelatorio, base: string, aoProgresso?: (p: ProgressoDesenho) => void,
): Promise<Desenho> {
  let folhas = 0;
  let palavrasTotal = 1;
  let palavras = 0;
  let passada = 0;
  // Um aviso por folha que muda (no máximo 3 × folhas mensagens no documento inteiro).
  let ultimaChave = '';
  const avisar = (p: ProgressoDesenho, chave: string) => {
    if (!aoProgresso || chave === ultimaChave) return;
    ultimaChave = chave;
    aoProgresso(p);
  };

  const sinais: SinaisDesenho = {
    aoPaginar(n, estimadas) {
      folhas = n;
      palavrasTotal = Math.max(estimadas, 1);
    },
    aoNumerarFolha(folha) {
      if (folha === 1) passada += 1;
      const feito = Math.min((passada - 1) * folhas + folha, 2 * folhas);
      avisar({ etapa: 'numerando', feito, total: 2 * folhas }, `n${feito}`);
    },
  };

  // Uma palavra diagramada (o motor chama a hifenização palavra a palavra, folha a folha).
  // Depois que a numeração começa, o motor ainda diagrama o texto do rodapé: não volta a "montando".
  ligarAvisoDePalavra(() => {
    if (passada > 0) return;
    palavras += 1;
    const folha = Math.min(folhas, Math.max(1, Math.ceil((palavras / palavrasTotal) * folhas)));
    avisar({ etapa: 'montando', folha, folhas }, `m${folha}`);
  });
  let blob: Blob;
  try {
    blob = await pdf(createElement(DocumentoPdf, { doc, recursos: { base }, sinais }) as Parameters<typeof pdf>[0]).toBlob();
  } finally {
    ligarAvisoDePalavra(null);
  }
  avisar({ etapa: 'gravando', folhas }, 'g');
  const bytes = new Uint8Array(await blob.arrayBuffer());
  return { bytes, sha256: await sha256Hex(bytes), paginas: contarPaginasPdf(bytes) };
}

// ─── Protocolo de mensagens tela ↔ worker ─────────────────────────────────────

export type PedidoDesenho = { tipo: 'desenhar'; doc: DocumentoRelatorio; base: string };

export type RespostaDesenho =
  | { tipo: 'pronto' }
  | { tipo: 'progresso'; progresso: ProgressoDesenho }
  | { tipo: 'feito'; bytes: ArrayBuffer; sha256: string; paginas: number }
  | { tipo: 'erro'; mensagem: string };

/** O que o worker faz com um pedido. Separado do arquivo do worker para o teste exercitar o mesmo código. */
export async function atenderPedido(
  pedido: PedidoDesenho, responder: (r: RespostaDesenho, transferir?: Transferable[]) => void,
): Promise<void> {
  try {
    const d = await desenharDocumento(pedido.doc, pedido.base, (progresso) => responder({ tipo: 'progresso', progresso }));
    const buf = d.bytes.buffer as ArrayBuffer; // Uint8Array inteiro de blob.arrayBuffer(): o buffer é só dele
    responder({ tipo: 'feito', bytes: buf, sha256: d.sha256, paginas: d.paginas }, [buf]);
  } catch (e) {
    responder({ tipo: 'erro', mensagem: e instanceof Error ? e.message : 'Falha ao desenhar o PDF.' });
  }
}
