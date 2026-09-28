// Web Worker do PDF: desenha fora da thread da tela (ver desenho-pdf.ts).
// Carregado por gerar-pdf.ts com `new Worker(new URL('./pdf.worker.ts', import.meta.url))`,
// que o Turbopack empacota como chunk próprio — a lib de PDF não entra no bundle da página.
// Avisa "pronto" depois de carregar a lib: a tela só emite o protocolo depois disso.
import { atenderPedido, type PedidoDesenho, type RespostaDesenho } from './desenho-pdf';

const escopo = self as unknown as {
  onmessage: ((e: MessageEvent<PedidoDesenho>) => void) | null;
  postMessage(mensagem: RespostaDesenho, transferir?: Transferable[]): void;
};

escopo.onmessage = (e) => {
  void atenderPedido(e.data, (r, transferir) => escopo.postMessage(r, transferir ?? []));
};
escopo.postMessage({ tipo: 'pronto' });
