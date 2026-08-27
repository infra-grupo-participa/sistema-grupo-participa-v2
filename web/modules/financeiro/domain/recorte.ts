// Recorte ativo do board (produto → canal → busca → cor) — função PURA, sem I/O e
// sem React. Existia só como string montada dentro de RodapeTotais.tsx:43
// (`[produtoAtivo, filtroAtivo, termo].filter(Boolean).join(' · ')`); a barra
// nova acima do mosaico (N1, 2026-08-27) precisa do MESMO recorte, decomposto
// em chips removíveis — então a montagem sai do componente e os dois lugares
// passam a consumir esta função, em vez de cada um ter sua própria lógica de
// texto (era assim que os mapas de cor divergiam, ver ui/cor.ts).
//
// Produto NUNCA vira chip removível: HM/AURUM é uma ABA (ProdutoTabs), não um
// filtro — não existe estado "nenhum produto" (ver FinanceiroClient.tsx,
// `produtoAtivo` sempre 'HM' | 'AURUM'). Por isso ele entra só no RÓTULO
// completo (rotuloRecorte), nunca em `itensRecorte` (os removíveis).

export interface RecorteAtivo {
  /** Rótulo do produto ativo (ex.: "Holding Masters") — sempre presente. */
  produtoLabel: string;
  /** Rótulo legível do canal/ação ativo (null = nenhum filtro de canal). */
  canalLabel: string | null;
  /** Termo de busca ativo, já aparado (string vazia = sem busca). */
  busca: string;
  /** Rótulo da cor filtrada (null = sem filtro de cor). O filtro de cor
   *  (N4) MEXE nos totais como qualquer outro — se ele não entrasse aqui, o
   *  rodapé diria "só de Holding Masters — 37 cards" com HM tendo 264, e a
   *  BarraRecorte não ofereceria como remover. Achado do fable-orchestrator,
   *  2026-08-27. */
  corLabel?: string | null;
}

export type ItemRecorte =
  | { tipo: 'canal'; label: string }
  | { tipo: 'busca'; label: string }
  | { tipo: 'cor'; label: string };

/** Chips removíveis do recorte — só o que tem estado "nenhum" (canal, busca).
 *  Produto fica de fora de propósito (ver nota do arquivo). Ordem fixa:
 *  canal → busca → cor, a mesma ordem em que os filtros se empilham
 *  (ver FinanceiroClient.tsx) — a barra lê como o funil, de cima para baixo. */
export function itensRecorte(r: RecorteAtivo): ItemRecorte[] {
  const itens: ItemRecorte[] = [];
  if (r.canalLabel) itens.push({ tipo: 'canal', label: r.canalLabel });
  const termo = r.busca.trim();
  if (termo) itens.push({ tipo: 'busca', label: `busca "${termo}"` });
  if (r.corLabel) itens.push({ tipo: 'cor', label: r.corLabel });
  return itens;
}

/** Rótulo completo do recorte (produto sempre presente + itens removíveis),
 *  no formato "HM · Captação T40 · busca "maria"" — o texto que RodapeTotais
 *  mostrava antes de virar chips. */
export function rotuloRecorte(r: RecorteAtivo): string {
  const itens = itensRecorte(r).map((i) => i.label);
  return [r.produtoLabel, ...itens].join(' · ');
}
