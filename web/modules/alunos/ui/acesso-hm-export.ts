// Exportação da lista filtrada de Acesso HM em CSV, com os dados de pagamento
// (fn_hm_pagamentos) unidos aos itens da fila. Colunas agrupadas: aluno → compra →
// pagamento → liberação.

import {
  type HmFilaItem,
  type HmPagamento,
  HM_CATEGORIA_LABEL,
  HM_METODO_LABEL,
  alunoExcecao,
  hmSituacao,
} from '../domain/acesso-hm';
import { loadHmPagamentos } from './acesso-hm-data';

type Linha = HmFilaItem & { pg: HmPagamento | undefined };

/** Data + hora local, vazio quando nulo (planilha não deve mostrar '—'). */
function dataHora(v: string | null | undefined): string {
  if (!v) return '';
  const d = new Date(v);
  return Number.isNaN(d.getTime())
    ? ''
    : `${d.toLocaleDateString('pt-BR')} ${d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}`;
}

/** Número com vírgula decimal — Excel pt-BR lê como número. */
function num(v: number | null | undefined): string {
  return v == null ? '' : Number(v).toLocaleString('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

const sim = (v: boolean | null | undefined) => (v ? 'Sim' : 'Não');

const EXPORT_COLS: [string, (l: Linha) => unknown][] = [
  // Aluno
  ['Nome', (l) => l.nome],
  ['E-mail', (l) => l.email],
  ['Telefone', (l) => l.telefone],
  ['CPF/CNPJ', (l) => l.documento],
  ['Turma', (l) => l.turmaCodigo],
  ['Aluno novo', (l) => sim(l.alunoNovo)],
  ['Exceção (já cadastrado)', (l) => sim(alunoExcecao(l))],
  // Compra
  ['Data da compra', (l) => dataHora(l.dataCompra)],
  ['Data de aprovação', (l) => dataHora(l.pg?.data_aprovacao)],
  ['Transação Hotmart', (l) => l.pg?.hotmart_transaction],
  ['Produto', (l) => l.pg?.produto_nome],
  ['Código da oferta', (l) => l.offerCode],
  ['Oferta', (l) => l.ofertaLabel],
  ['Categoria', (l) => (l.categoria ? HM_CATEGORIA_LABEL[l.categoria]?.label ?? l.categoria : '')],
  // Pagamento
  ['Método de pagamento', (l) => (l.pg?.metodo_pagamento ? HM_METODO_LABEL[l.pg.metodo_pagamento] ?? l.pg.metodo_pagamento : '')],
  ['Parcelas', (l) => l.pg?.parcelas],
  ['Moeda', (l) => l.pg?.moeda],
  ['Valor pago', (l) => num(l.preco)],
  ['Valor original', (l) => num(l.pg?.preco_original)],
  ['Desconto', (l) => num(l.pg?.desconto)],
  ['Cupom', (l) => l.pg?.cupom],
  ['Status Hotmart', (l) => l.pg?.status],
  ['Assinatura', (l) => sim(l.pg?.is_assinatura)],
  ['Nº da recorrência', (l) => l.pg?.numero_recorrencia],
  // Liberação
  ['Situação', (l) => hmSituacao(l)],
  ['Liberado em', (l) => dataHora(l.acessoEm)],
  ['Liberado por', (l) => l.acessoPorNome],
  ['Ignorado em', (l) => dataHora(l.ignoradoEm)],
  ['Observação', (l) => l.obs],
];

/**
 * Exporta a lista visível (aba + filtros já aplicados) para CSV.
 * Separador ';' + BOM UTF-8 → abre direto no Excel pt-BR.
 */
export async function exportarCsvHm(rows: HmFilaItem[], sufixo: string) {
  const pagamentos = await loadHmPagamentos(rows.map((r) => r.compraId));
  const linhas: Linha[] = rows.map((r) => ({ ...r, pg: pagamentos.get(r.compraId) }));

  const esc = (v: unknown) => {
    const s = v == null ? '' : String(v);
    return /[";\r\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const csv = [
    EXPORT_COLS.map((c) => c[0]).join(';'),
    ...linhas.map((l) => EXPORT_COLS.map((c) => esc(c[1](l))).join(';')),
  ].join('\r\n');

  const blob = new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = `acesso-hm-${sufixo}-${new Date().toISOString().slice(0, 10)}.csv`;
  link.click();
  URL.revokeObjectURL(url);
}
