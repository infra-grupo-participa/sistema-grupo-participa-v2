// Mapeamento puro: linha da RPC → item da LinhaDoTempo compartilhada. Separado do componente para ser testável.
import { fmtBRL } from '@/shared/ui/format';
import type { BadgeLinhaDoTempo, DimensaoLinhaDoTempo, ItemLinhaDoTempo } from '@/shared/ui/timeline/linha-do-tempo';
import {
  DIMENSOES_TRAJETORIA, ROTULO_DIMENSAO, TIPOS_ALERTA, TIPO_VOLTA, ordenarTrajetoria,
  type LinhaTrajetoriaAluno,
} from '../domain/trajetoria-aluno';

export const DIMENSOES_CHIPS: DimensaoLinhaDoTempo[] = DIMENSOES_TRAJETORIA.map((d) => ({ chave: d, rotulo: ROTULO_DIMENSAO[d] }));

const ROTULO_TIPO: Record<string, string> = { saida: 'saída', estorno: 'estorno', cancelamento: 'cancelamento', volta: 'volta' };

function badges(l: LinhaTrajetoriaAluno): BadgeLinhaDoTempo[] {
  const out: BadgeLinhaDoTempo[] = [{ rotulo: ROTULO_DIMENSAO[l.dimensao] ?? l.dimensao, tom: 'neutral' }];
  if (TIPOS_ALERTA.has(l.tipo)) out.push({ rotulo: ROTULO_TIPO[l.tipo], tom: 'danger' });
  else if (l.tipo === TIPO_VOLTA) out.push({ rotulo: ROTULO_TIPO.volta, tom: 'success' });
  if (l.situacao) out.push({ rotulo: l.situacao, tom: 'neutral' });
  return out;
}

/** Ordena do mais recente para o mais antigo e converte. `valor` null não gera nada na tela. */
export function paraItensLinhaDoTempo(linhas: LinhaTrajetoriaAluno[]): ItemLinhaDoTempo[] {
  return ordenarTrajetoria(linhas).map((l, i) => ({
    id: `${l.dia}|${l.dimensao}|${l.tipo}|${l.ref ?? ''}|${i}`,
    dia: l.dia,
    titulo: l.titulo,
    detalhe: l.detalhe ?? undefined,
    nota: l.regra,
    dimensao: l.dimensao,
    badges: badges(l),
    valor: l.valor == null ? undefined : fmtBRL(l.valor),
    tom: TIPOS_ALERTA.has(l.tipo) ? 'danger' : l.tipo === TIPO_VOLTA ? 'success' : 'accent',
  }));
}
