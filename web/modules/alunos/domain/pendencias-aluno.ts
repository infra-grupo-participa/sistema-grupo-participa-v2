// Pendências da ficha do aluno (bloco do Resumo + contador nas abas).
//
// Regra: NÃO há critério novo aqui. Cada item corresponde a um sinal que a ficha
// já pinta de amarelo ou vermelho — se a pintura mudar, esta lista muda junto:
//   · renovação NÃO entra: pinta 93% da base (1.758 de 1.883 ativos em 30/09) — é estado, não fila.
//     O aviso continua visível na aba Programa;
//   · tratamento_manual → faixa amarela em Acesso ao Curso, aba Programa;
//   · sócio sem titular → badge amarelo do cabeçalho / "Titular não informado", aba Programa;
//   · placa → chip do processo em "correção" (sp-regularizacao) ou "Rejeitado" (sp-encerrado), aba Jornada.
import { type Aluno360, parseInstrucao } from './aluno-360';
import { computeDisplayStatus, type SolicitacaoLike } from '@/modules/placas/domain/solicitacao';

export type AbaPendencia = 'programa' | 'jornada';

export interface PendenciaAluno {
  aba: AbaPendencia;
  texto: string;
  /** Mesmo tom que a ficha usa no sinal de origem. */
  tom: 'amarelo' | 'vermelho';
}

export interface ContextoPendencias {
  /** Vínculo de sócio já resolvido pela ficha (`vinculoSocio`). */
  socio: { titularNome: string | null; titular: { nome: string | null } | null };
  /** Solicitação de placa mais recente, quando o histórico já carregou. */
  placa: SolicitacaoLike | null;
}

type AlunoPendencia = Pick<Aluno360, 'turma_codigo' | 'tratamento_manual' | 'instrucao' | 'espaco_instrucao' | 'eh_socio'>;

export function pendenciasAluno(a: AlunoPendencia, ctx: ContextoPendencias): PendenciaAluno[] {
  const out: PendenciaAluno[] = [];

  const manual = (a.tratamento_manual || '').trim();
  if (manual) out.push({ aba: 'programa', texto: `Tratamento manual: ${manual}`, tom: 'amarelo' });

  // Cabeçalho: badge amarelo quando a instrução diz sócio e não há `socio_de_nome`.
  // Acesso ao Curso: "Titular não informado" quando é sócio (eh_socio ou titular achado pela FK)
  // e nenhum nome resolve. Qualquer um dos dois pintado conta uma vez só.
  const { titularNome, titular } = ctx.socio;
  const semNome = !titularNome;
  const pintaCabecalho = Boolean(parseInstrucao(a)?.ehSocio) && semNome;
  const pintaVinculo = (Boolean(a.eh_socio) || Boolean(titular)) && semNome && !titular?.nome;
  if (pintaCabecalho || pintaVinculo) out.push({ aba: 'programa', texto: 'Sócio sem titular informado', tom: 'amarelo' });

  if (ctx.placa) {
    const d = computeDisplayStatus(ctx.placa);
    if (d.cls === 'sp-regularizacao') out.push({ aba: 'jornada', texto: `Placa: ${d.label}`, tom: 'amarelo' });
    else if (d.cls === 'sp-encerrado') out.push({ aba: 'jornada', texto: `Placa: ${d.label}`, tom: 'vermelho' });
  }

  return out;
}

export function contarPorAba(ps: PendenciaAluno[]): Record<AbaPendencia, number> {
  const c: Record<AbaPendencia, number> = { programa: 0, jornada: 0 };
  for (const p of ps) c[p.aba] += 1;
  return c;
}
