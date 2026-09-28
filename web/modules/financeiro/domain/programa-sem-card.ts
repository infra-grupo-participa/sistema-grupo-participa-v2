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
