// PONTO DE LIGAÇÃO do protocolo dos PDFs do Financeiro — ÚNICO lugar a mexer.
//
// Os 6 botões "Exportar PDF" (CarteiraDoBoard + ui/hotmart/*) chamam esta função.
// Enquanto ela devolve null, o botão fica travado: o PDF NUNCA sai sem protocolo
// (decisão do Marcio — sem fallback para window.print()).
//
// JUAN: implementar aqui as 2 chamadas, pelo repositório (application/ports.ts +
// infrastructure/supabase-financeiro.repository.ts), contra as RPCs da migration
// infra/supabase/migrations/20260928z50_fin_relatorios_emitidos.sql:
//   emitir → fn_fin_relatorio_emitir(p_tipo, p_nivel, p_recorte, p_linhas, p_totais)
//            devolve { protocolo, emitido_em } → { protocolo, emitidoEm }
//   selar  → fn_fin_relatorio_selar(p_protocolo, p_sha256, p_paginas) → boolean
// Erro de RPC deve LANÇAR (não devolver null): gerarPdfComProtocolo mostra a
// mensagem no botão e não baixa nada. MetaEmissao.recorte já sai no formato que
// fin.relatorio_recorte_valido aceita (sem chave 'busca'/'nome'/'email'…).
import type { ChamadasProtocolo } from '@/shared/ui/pdf/gerar-pdf';

export function chamadasProtocoloFinanceiro(): ChamadasProtocolo | null {
  return null;
}
