'use client';

// Geração do PDF no navegador. A lib (@react-pdf/renderer + fontes) só é baixada
// no clique, por `await import()` — mesmo padrão do `xlsx` em exportar.ts.
//
// Protocolo NUNCA é opcional (decisão do Marcio): gerarPdfComProtocolo() emite,
// desenha, calcula o SHA-256, sela e só então baixa. Qualquer falha em emitir
// ou selar lança erro e o arquivo não sai. Não existe caminho sem protocolo e
// não existe fallback para window.print().
import { createElement } from 'react';
import type { DocumentoRelatorio, NivelPii, RascunhoRelatorio } from './modelo';
import { aplicarNivel, contarLinhasDetalhe } from './nivel';

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

/** Monta o recorte que vai para o banco a partir do rascunho (busca livre nunca vai). */
export function recorteParaEmissao(r: RascunhoRelatorio): MetaEmissao['recorte'] {
  const filtros = r.recorte.filter((i) => !i.pii).map((i) => `${i.rotulo}: ${i.valor}`);
  return r.recorte.some((i) => i.pii) ? { filtros, busca_aplicada: true } : { filtros };
}

/** Conta as folhas do PDF gerado (objetos /Type /Page — o /Pages raiz não entra). */
export function contarPaginasPdf(bytes: Uint8Array): number {
  let texto = '';
  const passo = 0x8000;
  for (let i = 0; i < bytes.length; i += passo) texto += String.fromCharCode(...bytes.subarray(i, i + passo));
  return (texto.match(/\/Type\s*\/Page(?![a-zA-Z])/g) ?? []).length;
}

export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');
}

async function carregarLib() {
  const [lib, mod] = await Promise.all([import('@react-pdf/renderer'), import('./DocumentoPdf')]);
  return { pdf: lib.pdf, DocumentoPdf: mod.DocumentoPdf };
}

/** Desenha o documento (já com protocolo) e devolve os bytes. Base '/' = web/public servido pelo Next. */
export async function renderizarPdf(doc: DocumentoRelatorio): Promise<Uint8Array> {
  const { pdf, DocumentoPdf } = await carregarLib();
  const blob = await pdf(createElement(DocumentoPdf, { doc, recursos: { base: '/' } }) as Parameters<typeof pdf>[0]).toBlob();
  return new Uint8Array(await blob.arrayBuffer());
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
 * Fluxo completo: nível → emitir → desenhar → SHA-256 → selar → baixar.
 * A lib é carregada ANTES de emitir: falha de rede no import não consome protocolo.
 */
export async function gerarPdfComProtocolo(
  rascunho: RascunhoRelatorio, nivel: NivelPii, chamadas: ChamadasProtocolo,
): Promise<{ protocolo: string; paginas: number }> {
  const nivelado = aplicarNivel(rascunho, nivel); // lança se o relatório não aceita o nível
  await carregarLib();

  const emissao = await chamadas.emitir({
    tipo: rascunho.tipo,
    nivel,
    recorte: recorteParaEmissao(rascunho),
    linhas: contarLinhasDetalhe(rascunho),
    totais: Object.fromEntries((rascunho.kpis ?? []).map((k) => [k.rotulo, k.valor])),
  });
  if (!emissao?.protocolo) throw new Error('A emissão não devolveu protocolo.');

  const doc: DocumentoRelatorio = { ...nivelado, protocolo: emissao.protocolo, emitidoEm: emissao.emitidoEm };
  const bytes = await renderizarPdf(doc);
  const paginas = contarPaginasPdf(bytes);
  const sha256 = await sha256Hex(bytes);

  const selou = await chamadas.selar({ protocolo: emissao.protocolo, sha256, paginas });
  if (!selou) throw new Error(`O protocolo ${emissao.protocolo} não foi selado. O PDF não foi gerado.`);

  baixarPdf(bytes, `${doc.arquivo}-${doc.protocolo}.pdf`);
  return { protocolo: emissao.protocolo, paginas };
}
