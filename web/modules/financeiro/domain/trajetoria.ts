// Trajetória da pessoa (fn_fin_trajetoria, 28/09/2026). João: "a origem de todo mundo, de onde veio, qual funil já
// participou, qual funil já comprou, o que fez em cada funil". Uma linha por compra, com o evento/funil em que ela
// aconteceu; o programa começa em 25/06/2026 (live fechada) — antes disso é histórico.

export interface PassoTrajetoria {
  dia: string;
  familia: string;
  produto: string | null;
  oferta: string | null;
  situacao: 'pago' | 'estornado' | 'em atraso' | 'em aberto';
  valor: number;
  parcelas: number | null;
  papel: 'ingresso' | 'programa' | 'compra';
  evento_id: number | null;
  evento: string | null;
  evento_categoria: string | null;
  turma: string | null;
  regra_evento: string | null;
}

export interface EtapaTrajetoria {
  chave: string;
  evento: string | null;
  inicio: string;
  participou: boolean;
  comprou: boolean;
  passos: PassoTrajetoria[];
}

export interface ResumoTrajetoria {
  primeiroContato: string | null;
  funisParticipou: number;
  funisComprou: number;
  totalPago: number;
  estornado: number;
  noPrograma: boolean;
  etapas: EtapaTrajetoria[];
}

/** Agrupa as compras por evento/funil, em ordem de data. Compra sem evento fica sozinha ("fora de evento"). */
export function resumirTrajetoria(passos: PassoTrajetoria[]): ResumoTrajetoria {
  const etapas: EtapaTrajetoria[] = [];
  const porChave = new Map<string, EtapaTrajetoria>();
  let totalPago = 0;
  let estornado = 0;
  for (const p of [...passos].sort((a, b) => a.dia.localeCompare(b.dia))) {
    const chave = p.evento_id != null ? `e${p.evento_id}` : `d${p.dia}`;
    let et = porChave.get(chave);
    if (!et) {
      et = { chave, evento: p.evento, inicio: p.dia, participou: false, comprou: false, passos: [] };
      porChave.set(chave, et);
      etapas.push(et);
    }
    et.passos.push(p);
    if (p.papel === 'ingresso') et.participou = true;
    if (p.papel !== 'ingresso' && p.situacao === 'pago') et.comprou = true;
    if (p.situacao === 'pago') totalPago += p.valor;
    if (p.situacao === 'estornado') estornado += p.valor;
  }
  const comEvento = etapas.filter((e) => e.evento);
  return {
    primeiroContato: etapas[0]?.inicio ?? null,
    funisParticipou: comEvento.filter((e) => e.participou || e.comprou).length,
    funisComprou: comEvento.filter((e) => e.comprou).length,
    totalPago,
    estornado,
    noPrograma: passos.some((p) => p.papel === 'programa'),
    etapas,
  };
}

export const ROTULO_PAPEL: Record<PassoTrajetoria['papel'], string> = {
  ingresso: 'Ingresso',
  programa: 'Programa',
  compra: 'Compra',
};
