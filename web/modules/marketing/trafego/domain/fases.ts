// Fase da campanha (Victor, 05/10/2026). Domínio puro; a mesma regra do banco (mkt_trafego.fase_efetiva, 20261006g).
//   1. a correção à mão na campanha prevalece;
//   2. senão, a fase do OBJETIVO do nome (mapa mkt_trafego.objetivo_fase, configurável);
//   3. senão, "sem fase".
// O mapa mora no banco e chega por parâmetro (config.objetivo_fase). Hoje: LEADS e VENDAS → captação, LEMBRETE →
// lembrete, REMARKETING → remarketing, CARRINHO → abertura de carrinho, AQUECIMENTO → aquecimento. DISTRIBUIÇÃO não tem
// fase automática (pode ou não ser aquecimento): fica sem fase até alguém marcar à mão.

export function faseDaCampanha(objetivo: string | null, manual: string | null, mapa: Record<string, string>): string | null {
  if (manual) return manual;
  if (!objetivo) return null;
  return mapa[objetivo] ?? null;
}

/** De onde veio a fase, para a tela explicar. */
export function origemDaFase(objetivo: string | null, manual: string | null, mapa: Record<string, string>): 'manual' | 'objetivo' | null {
  if (manual) return 'manual';
  return objetivo && mapa[objetivo] ? 'objetivo' : null;
}
