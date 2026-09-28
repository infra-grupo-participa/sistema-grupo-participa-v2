import { createHash } from 'node:crypto';
import path from 'node:path';
import { createElement } from 'react';
import { describe, expect, it } from 'vitest';
import { renderToBuffer } from '@react-pdf/renderer';
import { aplicarNivel } from '@/shared/ui/pdf/nivel';
import { DocumentoPdf } from '@/shared/ui/pdf/DocumentoPdf';
import { sha256Hex } from '@/shared/ui/pdf/bytes-pdf';
import type { RelatorioVerificado } from '../../application/ports';
import {
  TEXTO_ALTERADO, TEXTO_SO_REGISTRO, hashDoArquivo, protocoloDoNomeArquivo, quandoEmitido, totaisParaTela, vereditoConferencia,
} from './conferir';
import { rascunhoAcelera, recorteAcelera } from './documentos';

const verificado = (over: Partial<RelatorioVerificado> = {}): RelatorioVerificado => ({
  protocolo: 'GP-REL-2026-000041', tipo: 'acelera', nivel: 'so_numeros', recorte: { filtros: [] }, linhas: 1,
  totais: { 'Compradores do Acelera': '1', 'Total pago no HM depois': 'R$ 15.000,00' },
  emitido_em: '2026-09-28T17:05:00Z', gerado_por_nome: 'Marcio', selado_em: '2026-09-28T17:05:04Z', paginas: 1,
  sha256: 'a'.repeat(64), situacao: 'selado', ...over,
});

async function pdfReal(): Promise<Uint8Array> {
  const r = rascunhoAcelera([{
    pessoa_chave: 'p1', nome: 'Fulano', email: 'f@x.com', primeira_acelera: '2025-01-10', acelera_pago: 497, acelera_funil: 'Funil A',
    ja_era_hm: false, subiu: true, primeira_hm_depois: '2025-03-01', dias_ate_subir: 50, hm_pago_depois: 15000, hm_caminho: 'sinal', tem_card: false,
  }], recorteAcelera(null));
  const doc = { ...aplicarNivel(r, 'so_numeros'), protocolo: 'GP-REL-2026-000041', emitidoEm: '2026-09-28T17:05:00Z' };
  const publico = path.resolve(__dirname, '../../../../public') + path.sep;
  const buf = await renderToBuffer(createElement(DocumentoPdf, { doc, recursos: { base: publico } }) as Parameters<typeof renderToBuffer>[0]);
  return new Uint8Array(buf);
}

describe('conferir o ARQUIVO contra o protocolo', () => {
  it('PDF real: idêntico com os bytes selados; 1 byte alterado vira "alterado"', async () => {
    const bytes = await pdfReal();
    const selado = await sha256Hex(bytes); // o que gerarPdfComProtocolo grava no selo
    expect(selado).toMatch(/^[0-9a-f]{64}$/);
    expect(selado).toBe(createHash('sha256').update(bytes).digest('hex'));

    const v = verificado({ sha256: selado });
    const doArquivo = await hashDoArquivo(new Blob([bytes as BlobPart], { type: 'application/pdf' }));
    expect(doArquivo).toBe(selado);
    expect(vereditoConferencia(v, doArquivo)).toEqual({
      tipo: 'identico', texto: 'Idêntico ao documento emitido em 28/09/2026 às 14:05 por Marcio.',
    });

    const mexido = bytes.slice();
    mexido[Math.floor(mexido.length / 2)] ^= 0x01;
    const hashMexido = await hashDoArquivo(new Blob([mexido as BlobPart]));
    expect(hashMexido).not.toBe(selado);
    expect(vereditoConferencia(v, hashMexido)).toEqual({ tipo: 'alterado', texto: TEXTO_ALTERADO });
  }, 30_000);

  it('PDF íntegro de OUTRO protocolo: não acusa alteração, diz que não é o documento deste protocolo', () => {
    const outro = verificado({ protocolo: 'GP-REL-2026-000042', sha256: 'b'.repeat(64) });
    const veredito = vereditoConferencia(outro, 'a'.repeat(64)); // hash do PDF selado no 000041
    expect(veredito.tipo).toBe('alterado');
    expect(veredito.texto).toBe('Este arquivo não é o documento selado com este protocolo (foi alterado ou é de outro protocolo).');
    expect(veredito.texto).not.toMatch(/foi alterado depois/);
  });

  it('selo gravado em maiúsculas ainda compara (formato canônico é hex minúsculo)', () => {
    expect(vereditoConferencia(verificado({ sha256: 'AB'.repeat(32) }), 'ab'.repeat(32)).tipo).toBe('identico');
  });

  it('sem arquivo: confirma só o registro e diz isso', () => {
    expect(vereditoConferencia(verificado(), null)).toEqual({ tipo: 'so_registro', texto: TEXTO_SO_REGISTRO });
  });

  it('protocolo não concluído ou aguardando selo nunca dá "idêntico", mesmo com arquivo', () => {
    expect(vereditoConferencia(verificado({ situacao: 'nao_concluido', sha256: null }), 'a'.repeat(64)).tipo).toBe('nao_concluido');
    expect(vereditoConferencia(verificado({ situacao: 'aguardando_selo', sha256: null }), 'a'.repeat(64)).tipo).toBe('aguardando_selo');
    expect(vereditoConferencia(verificado({ sha256: null }), 'a'.repeat(64)).tipo).toBe('nao_concluido');
  });

  it('data da emissão no fuso de São Paulo, como o PDF imprime', () => {
    expect(quandoEmitido('2026-09-28T02:30:00Z')).toBe('27/09/2026 às 23:30');
  });

  it('totais gravados viram pares rótulo/valor, texto já formatado passa igual', () => {
    expect(totaisParaTela({ Contas: '12', 'Na rua': 'R$ 1.500', n: 3, x: null })).toEqual([
      { rotulo: 'Contas', valor: '12' }, { rotulo: 'Na rua', valor: 'R$ 1.500' }, { rotulo: 'n', valor: '3' }, { rotulo: 'x', valor: '—' },
    ]);
    expect(totaisParaTela(null)).toEqual([]);
  });

  it('protocolo sugerido pelo nome do download', () => {
    expect(protocoloDoNomeArquivo('hotmart-pessoas-GP-REL-2026-000041.pdf')).toBe('GP-REL-2026-000041');
    expect(protocoloDoNomeArquivo('relatorio (1).pdf')).toBeNull();
  });
});
