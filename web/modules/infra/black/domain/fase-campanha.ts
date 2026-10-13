import type { Fase } from './tipos';

// Fase da campanha pelo NOME (Victor, 13/10/2026). O nome vem em blocos separados por "|", por exemplo
// "CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY". Procura o bloco que diz a fase:
//   ANTECIPAÇÃO → antecipação · AQUECIMENTO → aquecimento · LEAD ou LEADS → captação.
// Qualquer outro nome fica sem fase (aparece em "campanhas sem fase", não some). Dois blocos que apontam
// fases diferentes também ficam sem fase, para não chutar. Não usa a etapa (C1/C2/C3), que é funil.

const BLOCO_FASE: Readonly<Record<string, Fase>> = {
  ANTECIPACAO: 'antecipacao',
  AQUECIMENTO: 'aquecimento',
  LEAD: 'captacao',
  LEADS: 'captacao',
};

const semAcento = (s: string): string => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '');

export function faseDoNome(nome: string | null | undefined): Fase | null {
  if (!nome) return null;
  const achadas = new Set<Fase>();
  for (const bloco of nome.split('|')) {
    const fase = BLOCO_FASE[semAcento(bloco).trim().toUpperCase()];
    if (fase) achadas.add(fase);
  }
  return achadas.size === 1 ? [...achadas][0] : null;
}
