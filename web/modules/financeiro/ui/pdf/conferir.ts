// Conferência de um PDF emitido: o ARQUIVO recebido é o que foi selado?
// (decisão do Marcio após o pentest de 28/09 — só mostrar que o protocolo existe
// não prova nada sobre o papel que chegou na mão de quem confere).
//
// O hash é calculado no navegador com a MESMA função que sela (sha256Hex de
// shared/ui/pdf/gerar-pdf.ts): hex minúsculo de 64. O arquivo não sobe para
// lugar nenhum; a única chamada ao banco é verificarRelatorio (já existente).
import { sha256Hex } from '@/shared/ui/pdf/gerar-pdf';
import { dataHoraSaoPaulo } from '@/shared/ui/pdf/modelo';
import type { RelatorioVerificado } from '../../application/ports';

export type Veredito =
  | { tipo: 'identico'; texto: string }
  | { tipo: 'alterado'; texto: string }
  | { tipo: 'so_registro'; texto: string }
  | { tipo: 'aguardando_selo'; texto: string }
  | { tipo: 'nao_concluido'; texto: string };

export const TEXTO_NAO_ENCONTRADO = 'Protocolo não encontrado — nenhum relatório foi emitido com esse número.';
export const TEXTO_ALTERADO = 'Este arquivo foi alterado depois da emissão — não corresponde ao protocolo.';
export const TEXTO_SO_REGISTRO = 'Sem o arquivo, só se confirma o registro, não o conteúdo. Anexe o PDF para comparar.';

/** SHA-256 do arquivo recebido, no navegador (mesma função e formato do selo). */
export async function hashDoArquivo(arquivo: Blob): Promise<string> {
  return sha256Hex(new Uint8Array(await arquivo.arrayBuffer()));
}

/** "dd/mm/aaaa às hh:mm" no fuso de São Paulo — o mesmo horário impresso no PDF. */
export function quandoEmitido(iso: string): string {
  const { data, hora } = dataHoraSaoPaulo(iso);
  return `${data} às ${hora}`;
}

/**
 * Veredito da conferência. `hashArquivo` null = nenhum arquivo anexado:
 * confirma só o registro. Protocolo sem selo não tem com o que comparar.
 */
export function vereditoConferencia(v: RelatorioVerificado, hashArquivo: string | null): Veredito {
  if (v.situacao === 'nao_concluido' || (v.situacao === 'selado' && !v.sha256)) {
    return { tipo: 'nao_concluido', texto: 'Protocolo emitido mas não concluído — o PDF nunca foi selado, não existe documento válido com esse número.' };
  }
  if (v.situacao === 'aguardando_selo') {
    return { tipo: 'aguardando_selo', texto: 'Protocolo emitido e ainda não selado (dentro da janela de 15 min). Confira de novo em alguns minutos.' };
  }
  if (!hashArquivo) return { tipo: 'so_registro', texto: TEXTO_SO_REGISTRO };
  return hashArquivo.trim().toLowerCase() === v.sha256!.trim().toLowerCase()
    ? { tipo: 'identico', texto: `Idêntico ao documento emitido em ${quandoEmitido(v.emitido_em)} por ${v.gerado_por_nome}.` }
    : { tipo: 'alterado', texto: TEXTO_ALTERADO };
}

/** Totais gravados na emissão, em pares rótulo/valor (os valores já saíram formatados pelo mapeador). */
export function totaisParaTela(totais: Record<string, unknown> | null | undefined): { rotulo: string; valor: string }[] {
  return Object.entries(totais ?? {}).map(([rotulo, valor]) => ({
    rotulo,
    valor: typeof valor === 'number' ? valor.toLocaleString('pt-BR') : valor == null ? '—' : String(valor),
  }));
}

const RE_PROTOCOLO = /GP-REL-\d{4}-\d{6}/i;

/** O download sai como "<arquivo>-GP-REL-AAAA-NNNNNN.pdf": sugere o protocolo pelo nome. */
export function protocoloDoNomeArquivo(nome: string): string | null {
  return nome.match(RE_PROTOCOLO)?.[0].toUpperCase() ?? null;
}
