// Junção emitir → desenhar → selar → baixar (gerarPdfComProtocolo), com o renderizarPdf
// REAL (@react-pdf + Inter + DocumentoPdf de verdade) e só duas trocas:
//  - ChamadasProtocolo é um stub que registra a ordem e o que recebeu;
//  - o download (URL.createObjectURL + <a>.click) é interceptado para o teste ver os
//    bytes que saíram. Nenhuma mudança no código de produção para isso.
// A única troca no desenho é o caminho das fontes: no navegador é '/', no Node é web/public.
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

describe('gerarPdfComProtocolo — junção com o renderizarPdf real', () => {
  it('ordem emitir → desenhar → selar → baixar; hash e páginas do selo são os do arquivo baixado', async () => {
    await marcarRender();
    const { chamadas, selos } = stub();
    const r = rascunho(120);
    const esperado = paginar(r.kpis, aplicarNivel(r, 'completo').secoes).length;
    expect(esperado).toBeGreaterThan(1);

    const saida = await gerarPdfComProtocolo(r, 'completo', chamadas);
    await esperarDownloads();

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
  }, 60_000);

  it('emitir lançando: não desenha, não sela, não baixa', async () => {
    await marcarRender();
    const { chamadas } = stub({ emitirLanca: true });
    await expect(gerarPdfComProtocolo(rascunho(3), 'completo', chamadas)).rejects.toThrow('RPC fora do ar');
    await esperarDownloads();
    expect(eventos).toEqual(['emitir']);
    expect(baixados).toEqual([]);
    expect(URL.createObjectURL).not.toHaveBeenCalled();
  }, 60_000);
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
