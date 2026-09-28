// Rótulos de tela das visões da Hotmart que também saem no PDF (ui/pdf/documentos.ts).
// Moram aqui, e não dentro do componente, para tela e PDF lerem a MESMA fonte.
import type { DivergenciaHotmart } from '../../domain/hotmart';

export const ROTULO_DIVERGENCIA: Record<DivergenciaHotmart['tipo'], string> = {
  falta_no_banco: 'Pago na Hotmart, ausente no banco',
  produto_sem_webhook: 'Produto sem webhook',
  status_diferente: 'Status diferente',
  valor_diferente: 'Valor diferente',
};

export const MOTIVO_SUGESTAO: Record<string, string> = {
  mesmo_telefone: 'Mesmo telefone', mesmo_nome: 'Mesmo nome', mesmo_documento_tentativa: 'Mesmo CPF em tentativa',
};

/** Evidência do par como a tela mostra: telefone/documento só com os 4 últimos dígitos; nome inteiro. */
export function rotuloEvidencia(motivo: string, evidencia: string | null): string {
  if (!evidencia) return '';
  return motivo !== 'mesmo_nome' ? `···${evidencia.slice(-4)}` : evidencia;
}
