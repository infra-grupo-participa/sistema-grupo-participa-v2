// Quem pagou oferta do Programa (desde 25/06/2026) e não tem card no board (fn_fin_programa_sem_card, 28/09/2026).
// Criar o card é do sistema de ativação; o financeiro só não deixa essa gente invisível.
export interface PagouSemCard {
  nome: string | null;
  email: string;
  telefone: string | null;
  primeira: string;
  valor: number;
  ofertas: string;
  fora_do_catalogo: boolean;
  acao: string | null;
}

/** Oferta paga fora do catálogo (fn_fin_ofertas_sem_catalogo): o card não nasce até ela ser cadastrada. */
export interface OfertaSemCatalogo {
  oferta: string;
  familia: 'HM' | 'AURUM';
  produto: string | null;
  pagamentos: number;
  pessoas: number;
  valor: number;
  primeira: string;
  ultima: string;
  nomes: string | null;
}
