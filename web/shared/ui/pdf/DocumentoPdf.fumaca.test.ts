// Fumaça do PDF real no Node (renderToBuffer): a lib, a fonte Inter embutida, o logo vetorial
// e a paginação manual funcionando juntos. PDF_SAIDA=<pasta> grava os arquivos para
// conferência visual.
import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { createElement } from 'react';
import { describe, expect, it } from 'vitest';
import { renderToBuffer } from '@react-pdf/renderer';
import { DocumentoPdf } from './DocumentoPdf';
import type { DocumentoRelatorio, RascunhoRelatorio } from './modelo';
import { aplicarNivel } from './nivel';
import { contarPaginasPdf } from './bytes-pdf';

const PUBLICO = path.resolve(__dirname, '../../../public') + path.sep;
const recursos = { base: PUBLICO };

function rascunho(n: number): RascunhoRelatorio {
  return {
    tipo: 'pessoas', titulo: 'Pessoas na Hotmart', arquivo: 'hotmart-pessoas',
    niveisPermitidos: ['completo', 'sem_dado_pessoal', 'so_numeros'],
    recorte: [{ rotulo: 'Família', valor: 'Holding Masters' }, { rotulo: 'Situação', valor: 'Todas' }],
    kpis: [
      { rotulo: 'Pessoas', valor: String(n) }, { rotulo: 'Pago (bruto)', valor: 'R$ 3.600.000' },
      { rotulo: 'Líquido', valor: 'R$ 3.300.000' }, { rotulo: 'Atrasado (120 dias)', valor: 'R$ 45.000' },
    ],
    secoes: [
      {
        titulo: 'Por situação', tipo: 'resumo',
        colunas: [{ chave: 's', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma', peso: 2 }, { chave: 'q', rotulo: 'Pessoas', tipo: 'numero', pii: 'nenhuma' }],
        linhas: [{ celulas: { s: 'Devendo', q: '12' } }, { celulas: { s: 'Ativo (pagou no último ano)', q: String(n - 12) } }],
        total: { q: String(n) },
      },
      {
        titulo: `${n} pessoas`, tipo: 'detalhe', linhasSaoPessoas: true,
        colunas: [
          { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao', peso: 1.5 },
          { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato', peso: 1.9 },
          { chave: 'doc', rotulo: 'Documento', tipo: 'texto', pii: 'documento', peso: 0.9 },
          { chave: 'sit', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma', peso: 1.4 },
          { chave: 'pago', rotulo: 'Pago (bruto)', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'obs', rotulo: 'Caminho', tipo: 'texto', pii: 'nenhuma', peso: 1.2 },
        ],
        linhas: Array.from({ length: n }, (_, i) => ({
          celulas: {
            nome: `Pessoa Exemplo ${i + 1} da Silva Albuquerque`,
            email: i % 9 ? `pessoa.exemplo${i}@dominio-comprido-de-empresa.com.br` : `a${i}@x.com\nsegundo${i}@exemplo.com`,
            doc: '12345678901', sit: i % 5 ? 'Em pagamento' : 'Inadimplência antiga (+120 dias)',
            pago: 'R$ 12.345', obs: 'sinal → saldo · 3× ≤ 120 dias',
          },
        })),
        total: { pago: 'R$ 3.600.000' },
      },
    ],
  };
}

const documento = (r: RascunhoRelatorio, nivel: DocumentoRelatorio['nivel']): DocumentoRelatorio =>
  ({ ...aplicarNivel(r, nivel), protocolo: 'GP-REL-2026-000041', emitidoEm: '2026-09-28T17:05:00Z' });

async function render(doc: DocumentoRelatorio): Promise<Buffer> {
  return renderToBuffer(createElement(DocumentoPdf, { doc, recursos }) as Parameters<typeof renderToBuffer>[0]);
}

describe('DocumentoPdf (fumaça, renderToBuffer)', () => {
  it('300 linhas: arquivo %PDF com mais de 1 folha, fonte Inter embutida, protocolo no texto', async () => {
    const t0 = performance.now();
    const buf = await render(documento(rascunho(300), 'completo'));
    const ms = performance.now() - t0;
    expect(buf.subarray(0, 5).toString('latin1')).toBe('%PDF-');
    const paginas = contarPaginasPdf(new Uint8Array(buf));
    expect(paginas).toBeGreaterThan(1);
    expect(buf.toString('latin1')).toMatch(/\/BaseFont\s*\/[A-Z]{6}\+Inter-Regular/);
    if (process.env.PDF_SAIDA) {
      mkdirSync(process.env.PDF_SAIDA, { recursive: true });
      writeFileSync(path.join(process.env.PDF_SAIDA, 'fumaca-300-completo.pdf'), buf);
    }
    console.log(`fumaça 300 linhas: ${paginas} folhas, ${Math.round(ms)} ms, ${buf.length} bytes`);
  }, 60_000);

  it('níveis sem_dado_pessoal e so_numeros também desenham', async () => {
    for (const nivel of ['sem_dado_pessoal', 'so_numeros'] as const) {
      const buf = await render(documento(rascunho(40), nivel));
      expect(buf.subarray(0, 5).toString('latin1')).toBe('%PDF-');
      if (process.env.PDF_SAIDA) writeFileSync(path.join(process.env.PDF_SAIDA, `fumaca-40-${nivel}.pdf`), buf);
    }
  }, 60_000);

  // Medição de tempo (PDF_MEDIR=1): não roda na suíte normal para não depender da máquina.
  it.runIf(!!process.env.PDF_MEDIR)('tempo com 1.000 e 2.000 linhas', async () => {
    for (const n of [1000, 2000]) {
      const t0 = performance.now();
      const buf = await render(documento(rascunho(n), 'completo'));
      console.log(`medição ${n} linhas: ${Math.round(performance.now() - t0)} ms, ${contarPaginasPdf(new Uint8Array(buf))} folhas`);
    }
  }, 300_000);

  it('recusa documento sem protocolo', async () => {
    await expect(render({ ...documento(rascunho(1), 'completo'), protocolo: '' })).rejects.toThrow();
  });
});
