// Junção emitir → desenhar → selar → baixar (gerarPdfComProtocolo), com o desenho REAL
// (@react-pdf + Inter + DocumentoPdf de verdade) e só três trocas:
//  - ChamadasProtocolo é um stub que registra a ordem e o que recebeu;
//  - o download (URL.createObjectURL + <a>.click) é interceptado para o teste ver os
//    bytes que saíram. Nenhuma mudança no código de produção para isso;
//  - o caminho das fontes: no navegador é '/', no Node é web/public.
//
// Roda nos DOIS caminhos de gerar-pdf.ts:
//  - "worker": o Node não tem Web Worker; WorkerFalso faz o papel do navegador — clona
//    cada mensagem com structuredClone (transferindo o ArrayBuffer, como postMessage) e
//    entrega o pedido ao MESMO atenderPedido que pdf.worker.ts chama. Fica de fora só o
//    arquivo pdf.worker.ts (4 linhas: liga onmessage e avisa "pronto") e a thread de
//    verdade — esses são provados no navegador (next build + Chrome), não aqui;
//  - "mesma thread": sem Worker no ambiente, desenha na thread de quem chamou.
import path from 'node:path';
import { createHash } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { NivelPii, RascunhoRelatorio } from './modelo';
import type { ChamadasProtocolo, MetaEmissao } from './gerar-pdf';
import { gerarPdfComProtocolo, recorteParaEmissao } from './gerar-pdf';
import { paginar } from './paginar';
import { aplicarNivel } from './nivel';
import type { PessoaHotmart, ProrataHM } from '@/modules/financeiro/domain/hotmart';
import { rascunhoPessoas, rascunhoProrata, recortePessoas, recorteProrata } from '@/modules/financeiro/ui/pdf/documentos';
import { atenderPedido, type PedidoDesenho, type RespostaDesenho } from './desenho-pdf';
import type { ProgressoPdf } from './gerar-pdf';

const PUBLICO = path.resolve(__dirname, '../../../public') + path.sep;

vi.mock('./DocumentoPdf', async (original) => {
  const real = await original<typeof import('./DocumentoPdf')>();
  return {
    ...real,
    DocumentoPdf: (p: Parameters<typeof real.DocumentoPdf>[0]) => real.DocumentoPdf({ ...p, recursos: { base: PUBLICO } }),
  };
});

// ─── Interceptação do download ────────────────────────────────────────────────
let eventos: string[];
let baixados: { nome: string; bytes: Uint8Array }[];

beforeEach(() => {
  eventos = [];
  baixados = [];
  const blobs = new Map<string, Blob>();
  vi.spyOn(URL, 'createObjectURL').mockImplementation((b) => {
    const url = `blob:teste/${blobs.size}`;
    blobs.set(url, b as Blob);
    return url;
  });
  vi.spyOn(URL, 'revokeObjectURL').mockImplementation(() => {});
  const pendentes: Promise<void>[] = [];
  vi.stubGlobal('document', {
    createElement: (tag: string) => {
      const a = { tag, href: '', download: '', click: vi.fn() };
      a.click.mockImplementation(() => {
        eventos.push('baixar');
        const blob = blobs.get(a.href)!;
        pendentes.push(blob.arrayBuffer().then((ab) => { baixados.push({ nome: a.download, bytes: new Uint8Array(ab) }); }));
      });
      return a;
    },
  });
  esperarDownloads = () => Promise.all(pendentes).then(() => undefined);
});

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

let esperarDownloads: () => Promise<void>;

// ─── Worker falso (ver o topo do arquivo) ─────────────────────────────────────
class WorkerFalso {
  static criados: WorkerFalso[] = [];
  static falharAoCarregar = false;
  onmessage: ((e: { data: RespostaDesenho }) => void) | null = null;
  onerror: ((e: { message: string; preventDefault(): void }) => void) | null = null;
  onmessageerror: (() => void) | null = null;
  encerrado = false;
  pedidos = 0;
  constructor(readonly url: URL | string, readonly opcoes?: { type?: string }) {
    WorkerFalso.criados.push(this);
    setTimeout(() => {
      if (WorkerFalso.falharAoCarregar) this.onerror?.({ message: 'chunk do worker não carregou', preventDefault() {} });
      else this.entregar({ tipo: 'pronto' });
    });
  }
  private entregar(r: RespostaDesenho, transferir?: Transferable[]) {
    if (this.encerrado) return;
    const data = structuredClone(r, { transfer: transferir });
    setTimeout(() => { if (!this.encerrado) this.onmessage?.({ data }); });
  }
  postMessage(pedido: PedidoDesenho) {
    this.pedidos += 1;
    void atenderPedido(structuredClone(pedido), (r, t) => this.entregar(r, t));
  }
  terminate() { this.encerrado = true; }
}

// ─── Stub do protocolo ────────────────────────────────────────────────────────
function stub(opcoes: { selou?: boolean; emitirLanca?: boolean } = {}) {
  const metas: MetaEmissao[] = [];
  const selos: { protocolo: string; sha256: string; paginas: number }[] = [];
  const chamadas: ChamadasProtocolo = {
    async emitir(meta) {
      eventos.push('emitir');
      metas.push(meta);
      if (opcoes.emitirLanca) throw new Error('RPC fora do ar');
      return { protocolo: 'GP-REL-2026-000123', emitidoEm: '2026-09-28T17:05:00Z' };
    },
    async selar(selo) {
      eventos.push('selar');
      selos.push(selo);
      return opcoes.selou ?? true;
    },
  };
  return { chamadas, metas, selos };
}

// Espiona o desenho sem trocá-lo: marca "render" quando o DocumentoPdf real é chamado.
async function marcarRender() {
  const mod = await import('./DocumentoPdf');
  const original = mod.DocumentoPdf;
  vi.spyOn(mod, 'DocumentoPdf').mockImplementation((p) => { eventos.push('render'); return original(p); });
}

function rascunho(n: number): RascunhoRelatorio {
  return {
    tipo: 'pessoas', titulo: 'Pessoas na Hotmart', arquivo: 'hotmart-pessoas',
    niveisPermitidos: ['completo', 'sem_dado_pessoal', 'so_numeros'],
    recorte: [{ rotulo: 'Família', valor: 'Holding Masters' }],
    kpis: [{ rotulo: 'Pessoas', valor: String(n) }],
    secoes: [{
      titulo: `${n} pessoas`, tipo: 'detalhe', linhasSaoPessoas: true,
      colunas: [
        { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao', peso: 1.5 },
        { chave: 'sit', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma' },
        { chave: 'pago', rotulo: 'Pago (bruto)', tipo: 'moeda', pii: 'nenhuma' },
      ],
      linhas: Array.from({ length: n }, (_, i) => ({ celulas: { nome: `Pessoa ${i + 1}`, sit: 'Em pagamento', pago: 'R$ 1.000,00' } })),
    }],
  };
}

const sha256Node = (b: Uint8Array) => createHash('sha256').update(b).digest('hex');

/** Contagem do próprio PDF: /Count do nó /Pages raiz (o que o leitor usa). */
function contagemDeclarada(bytes: Uint8Array): number {
  const texto = Buffer.from(bytes).toString('latin1');
  const contagens = [...texto.matchAll(/\/Type\s*\/Pages\b[^>]*?\/Count\s+(\d+)|\/Count\s+(\d+)[^>]*?\/Type\s*\/Pages\b/g)]
    .map((m) => Number(m[1] ?? m[2]));
  return Math.max(...contagens);
}

for (const modo of ['worker', 'mesma thread'] as const) describe(`gerarPdfComProtocolo — ${modo}`, () => {
  beforeEach(() => {
    WorkerFalso.criados = [];
    WorkerFalso.falharAoCarregar = false;
    if (modo === 'worker') vi.stubGlobal('Worker', WorkerFalso);
  });
  const workerUsado = () => {
    if (modo === 'mesma thread') { expect(WorkerFalso.criados).toHaveLength(0); return; }
    expect(WorkerFalso.criados).toHaveLength(1);
    const w = WorkerFalso.criados[0];
    expect(String(w.url)).toMatch(/pdf.worker.ts$/);
    expect(w.opcoes?.type).toBe('module');
    expect(w.encerrado).toBe(true); // o worker não fica vivo depois da geração
  };

  it('ordem emitir → desenhar → selar → baixar; hash e páginas do selo são os do arquivo baixado', async () => {
    await marcarRender();
    const { chamadas, selos } = stub();
    const r = rascunho(120);
    const esperado = paginar(r.kpis, aplicarNivel(r, 'completo').secoes).length;
    expect(esperado).toBeGreaterThan(1);

    const progresso: ProgressoPdf[] = [];
    const saida = await gerarPdfComProtocolo(r, 'completo', chamadas, (p) => progresso.push(p));
    await esperarDownloads();
    workerUsado();

    // progresso: etapas na ordem e folha que sobe até o total
    const etapas = progresso.map((p) => p.etapa).filter((e, i, a) => e !== a[i - 1]);
    expect(etapas).toEqual(['preparando', 'emitindo', 'montando', 'numerando', 'gravando', 'selando']);
    const montando = progresso.flatMap((p) => (p.etapa === 'montando' ? [p] : []));
    expect(montando.length).toBeGreaterThan(1);
    expect(montando.every((p, i) => p.folhas === esperado && (i === 0 || p.folha >= montando[i - 1].folha))).toBe(true);
    const numerando = progresso.flatMap((p) => (p.etapa === 'numerando' ? [p] : []));
    expect(numerando.at(-1)).toEqual({ etapa: 'numerando', feito: 2 * esperado, total: 2 * esperado });

    expect(eventos).toEqual(['emitir', 'render', 'selar', 'baixar']);
    expect(baixados).toHaveLength(1);
    const { nome, bytes } = baixados[0];
    expect(nome).toBe('hotmart-pessoas-GP-REL-2026-000123.pdf');
    expect(Buffer.from(bytes.subarray(0, 5)).toString('latin1')).toBe('%PDF-');

    expect(selos).toHaveLength(1);
    expect(selos[0].protocolo).toBe('GP-REL-2026-000123');
    expect(selos[0].sha256).toBe(sha256Node(bytes));
    expect(selos[0].paginas).toBe(contagemDeclarada(bytes));
    expect(selos[0].paginas).toBe(esperado);
    expect(saida).toEqual({ protocolo: 'GP-REL-2026-000123', paginas: esperado });
  }, 60_000);

  it('selar devolvendo false: lança e nada é baixado', async () => {
    const { chamadas } = stub({ selou: false });
    await expect(gerarPdfComProtocolo(rascunho(3), 'completo', chamadas)).rejects.toThrow(/não foi selado/);
    await esperarDownloads();
    expect(eventos).toEqual(['emitir', 'selar']);
    expect(baixados).toEqual([]);
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    workerUsado();
  }, 60_000);

  it('emitir lançando: não desenha, não sela, não baixa', async () => {
    await marcarRender();
    const { chamadas } = stub({ emitirLanca: true });
    await expect(gerarPdfComProtocolo(rascunho(3), 'completo', chamadas)).rejects.toThrow('RPC fora do ar');
    await esperarDownloads();
    expect(eventos).toEqual(['emitir']);
    expect(baixados).toEqual([]);
    expect(URL.createObjectURL).not.toHaveBeenCalled();
    workerUsado();
    if (modo === 'worker') expect(WorkerFalso.criados[0].pedidos).toBe(0);
  }, 60_000);

  it.runIf(modo === 'worker')('worker que não carrega: falha ANTES de emitir (nenhum protocolo consumido)', async () => {
    WorkerFalso.falharAoCarregar = true;
    const { chamadas } = stub();
    await expect(gerarPdfComProtocolo(rascunho(3), 'completo', chamadas)).rejects.toThrow(/gerador de PDF falhou/);
    expect(eventos).toEqual([]);
    expect(baixados).toEqual([]);
    workerUsado();
  });
});

// ─── Busca livre nunca chega ao banco ─────────────────────────────────────────
const TERMO = 'Mariana Teixeira';

const pessoa = { pessoa_chave: 'p1', nome: TERMO, emails: ['mariana@exemplo.com'], documentos: [], situacao: 'devendo' } as unknown as PessoaHotmart;
const prorata = { pessoa_chave: 'p1', nome: TERMO, email: 'mariana@exemplo.com', turma: 'T38', vencimento: '2027-01-31' } as unknown as ProrataHM;

describe('recorte gravado na emissão: termo de busca em lugar nenhum', () => {
  const casos: [string, RascunhoRelatorio][] = [
    ['Pessoas', rascunhoPessoas([], recortePessoas({ familia: 'HM', filtro: 'devendo', de: '', ate: '', busca: ` ${TERMO} ` }))],
    ['Pro rata', rascunhoProrata([], recorteProrata('credito', ` ${TERMO} `))],
  ];

  for (const [nome, r] of casos) {
    it(`${nome}: recorteParaEmissao marca busca_aplicada e não leva o termo (nem dentro de filtros)`, () => {
      expect(r.recorte.some((i) => i.valor.includes(TERMO))).toBe(true); // o rascunho tem o termo
      const recorte = recorteParaEmissao(r);
      expect(recorte.busca_aplicada).toBe(true);
      expect(recorte.filtros.length).toBeGreaterThan(0);
      for (const f of recorte.filtros) {
        expect(f).not.toContain('Mariana');
        expect(f).not.toMatch(/^Busca/);
      }
      expect(JSON.stringify(recorte)).not.toMatch(/Mariana|Teixeira|busca"\s*:\s*"/i);
    });

    for (const nivel of ['completo', 'sem_dado_pessoal'] as NivelPii[]) {
      it(`${nome} · ${nivel}: a MetaEmissao inteira que chega a emitir() não carrega o termo`, async () => {
        const { chamadas, metas } = stub({ emitirLanca: true }); // para na emissão: só interessa o que foi enviado
        await expect(gerarPdfComProtocolo(r, nivel, chamadas)).rejects.toThrow();
        expect(metas).toHaveLength(1);
        expect(JSON.stringify(metas[0])).not.toMatch(/Mariana|Teixeira/);
      });
    }
  }

  // controle: fixtures com pessoa na lista também não vazam o nome pela emissão (só KPIs e contagem)
  it('Pessoas e Pro rata com linhas: emissão leva contagem e KPIs, nenhum nome', async () => {
    for (const r of [
      rascunhoPessoas([pessoa], recortePessoas({ familia: 'HM', filtro: null, de: '', ate: '', busca: TERMO })),
      rascunhoProrata([prorata], recorteProrata(null, TERMO)),
    ]) {
      const { chamadas, metas } = stub({ emitirLanca: true });
      await expect(gerarPdfComProtocolo(r, 'completo', chamadas)).rejects.toThrow();
      expect(metas[0].linhas).toBe(1);
      expect(JSON.stringify(metas[0])).not.toMatch(/Mariana|Teixeira/);
    }
  });
});

// ─── Limite de linhas (LINHAS_MAX_NO_PDF): o que sai no papel e o que o protocolo grava ──
// Espelho de fin.relatorio_recorte_valido (migration 20260928z50): objeto, ≤ 4 KB, sem estas chaves.
const CHAVES_PROIBIDAS = ['busca', 'q', 'search', 'texto', 'termo', 'pesquisa', 'nome', 'email', 'cpf', 'documento', 'telefone'];
// jsonb::text põe espaço depois de ':' e ','; margem de 2 bytes por caractere de pontuação cobre isso.
const bytesJsonb = (o: unknown) => { const s = JSON.stringify(o); return Buffer.byteLength(s) + 2 * (s.match(/[:,]/g)?.length ?? 0); };

describe('limite de linhas do PDF', () => {
  const muitas = (n: number) => Array.from({ length: n }, (_, i) => ({ ...pessoa, pessoa_chave: `p${i}`, nome: `${TERMO} ${i}` }) as PessoaHotmart);

  for (const nivel of ['completo', 'sem_dado_pessoal'] as NivelPii[]) {
    it(`Pessoas com 2.001 linhas · ${nivel}: PDF só com totais e aviso; protocolo grava 0 linhas e linhas_da_lista 2.001`, async () => {
      const docs: { secoes: { tipo: string }[]; avisoSoTotais?: string }[] = [];
      const mod = await import('./DocumentoPdf');
      const original = mod.DocumentoPdf;
      vi.spyOn(mod, 'DocumentoPdf').mockImplementation((p) => { docs.push(p.doc); return original(p); });
      const { chamadas, metas, selos } = stub();
      const r = rascunhoPessoas(muitas(2001), recortePessoas({ familia: 'HM', filtro: null, de: '', ate: '', busca: TERMO }));

      await gerarPdfComProtocolo(r, nivel, chamadas);
      await esperarDownloads();

      expect(metas[0].linhas).toBe(0);
      expect(metas[0].recorte).toEqual({ filtros: ['Família: Holding Masters', 'Situação: Todas'], busca_aplicada: true, linhas_da_lista: 2001 });
      expect(Object.keys(metas[0].recorte).filter((k) => CHAVES_PROIBIDAS.includes(k))).toEqual([]);
      expect(bytesJsonb(metas[0].recorte)).toBeLessThanOrEqual(4096);
      expect(bytesJsonb(metas[0].totais)).toBeLessThanOrEqual(8192);

      expect(docs).toHaveLength(1);
      expect(docs[0].secoes.map((s) => s.tipo)).toEqual(['resumo']);
      expect(docs[0].avisoSoTotais).toBe('Lista completa com 2.001 linhas disponível na exportação em planilha deste relatório.');
      expect(JSON.stringify(docs[0])).not.toMatch(/Mariana|Teixeira|mariana@/);
      expect(selos[0].paginas).toBe(1); // cabeçalho + KPIs + aviso + resumo cabem numa folha
      expect(baixados).toHaveLength(1);
    }, 60_000);
  }

  it('Pessoas com 2.000 linhas · completo: emissão grava as 2.000 linhas impressas (PDF completo)', async () => {
    const { chamadas, metas } = stub({ emitirLanca: true }); // só a emissão interessa aqui (desenhar 2.000 linhas leva ~14 s)
    await expect(gerarPdfComProtocolo(rascunhoPessoas(muitas(2000), []), 'completo', chamadas)).rejects.toThrow();
    expect(metas[0]).toMatchObject({ linhas: 2000, recorte: { linhas_da_lista: 2000 } });
  });

  it('só números: emissão grava 0 linhas impressas e o tamanho da lista', async () => {
    const { chamadas, metas } = stub({ emitirLanca: true });
    await expect(gerarPdfComProtocolo(rascunhoPessoas(muitas(30), []), 'so_numeros', chamadas)).rejects.toThrow();
    expect(metas[0]).toMatchObject({ linhas: 0, recorte: { linhas_da_lista: 30 } });
  });
});
