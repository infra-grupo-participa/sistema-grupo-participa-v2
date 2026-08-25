// Vocabulário do desfecho da reunião comercial (F6/F7/F8, 0307/0308 no repo
// da esteira: "Reunião Finalizada exige prazo de pagamento"). Puro, sem I/O
// — mesmo padrão de ./prazo.ts.
//
// Rótulos pt-BR do motivo (trilha B, "não prometeu pagar"): Record LOCAL,
// NÃO importado de lib/reuniao-motivos.ts (repo da esteira, projeto
// separado) — duplicar 5 strings entre dois repositórios é intencional e
// acordado; acoplar os repos não é.
//
// Fonte única do módulo: antes vivia só dentro de FichaDrawer.tsx — achado
// do fable-orchestrator (2026-08-21): CardBoard.tsx mostrava o valor CRU
// (`quer_parcelar`) no chip/tooltip, a mesma classe de erro que
// scripts/test-vocabulario.ts existe para barrar no repo da esteira (o repo
// B não tem essa trava — o remédio é não ter dois lugares para o mesmo
// rótulo divergir).
export type MotivoReuniao = 'quer_parcelar' | 'vai_ver_contrato' | 'sem_condicao_agora' | 'indeciso' | 'outro';

export const LABEL_MOTIVO_REUNIAO: Record<MotivoReuniao, string> = {
  quer_parcelar: 'Quer parcelar',
  vai_ver_contrato: 'Vai ver o contrato',
  sem_condicao_agora: 'Sem condição agora',
  indeciso: 'Ainda indeciso',
  outro: 'Outro motivo',
};

/**
 * Rótulo pt-BR do motivo — nunca devolve o valor cru. `tipo` fora dos 5
 * valores conhecidos (schema pode evoluir sem esta lista acompanhar no
 * mesmo commit) cai num fallback legível, não no slug técnico.
 */
export function labelMotivoReuniao(tipo: string | null | undefined): string | null {
  if (!tipo) return null;
  return LABEL_MOTIVO_REUNIAO[tipo as MotivoReuniao] ?? 'Outro motivo (não catalogado)';
}
