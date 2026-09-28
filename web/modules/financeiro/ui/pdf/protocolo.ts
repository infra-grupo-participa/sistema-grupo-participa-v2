// PONTO DE LIGAÇÃO do protocolo dos PDFs do Financeiro — ÚNICO lugar a mexer.
//
// Os 6 botões "Exportar PDF" (CarteiraDoBoard + ui/hotmart/*) chamam esta função.
// Implementado contra as RPCs da migration
// infra/supabase/migrations/20260928z50_fin_relatorios_emitidos.sql, via
// application/ports.ts + infrastructure/supabase-financeiro.repository.ts:
//   emitir → fn_fin_relatorio_emitir(p_tipo, p_nivel, p_recorte, p_linhas, p_totais)
//            devolve { protocolo, emitido_em } → { protocolo, emitidoEm }
//   selar  → fn_fin_relatorio_selar(p_protocolo, p_sha256, p_paginas) → boolean
// Erro de RPC LANÇA (não devolve null): gerarPdfComProtocolo mostra a mensagem
// no botão e não baixa nada. MetaEmissao.recorte já sai no formato que
// fin.relatorio_recorte_valido aceita (sem chave 'busca'/'nome'/'email'…).
import type { ChamadasProtocolo } from '@/shared/ui/pdf/gerar-pdf';
import { SupabaseFinanceiroRepository } from '../../infrastructure/supabase-financeiro.repository';

// Instância própria (mesmo padrão de FinanceiroClient.tsx): este módulo só
// chama RPC via repositório, nunca Supabase direto.
const repo = new SupabaseFinanceiroRepository();

export function chamadasProtocoloFinanceiro(): ChamadasProtocolo {
  return {
    async emitir(meta) {
      const r = await repo.emitirRelatorio(meta.tipo, meta.nivel, meta.recorte, meta.linhas, meta.totais);
      return { protocolo: r.protocolo, emitidoEm: r.emitido_em };
    },
    async selar(selo) {
      return repo.selarRelatorio(selo.protocolo, selo.sha256, selo.paginas);
    },
  };
}
