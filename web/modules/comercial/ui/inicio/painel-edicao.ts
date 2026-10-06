// Edição do painel personalizável, pura e testável: padrão de fábrica, validação do widget e reordenação.
import { METRICAS } from '../../domain/metricas';
import type { AgrupamentoWidget, MetricaKey, PainelPessoa, VisualWidget, WidgetPainel } from '../../domain/types';

export const LARGURAS: WidgetPainel['largura'][] = [1, 2, 3, 4];
export const LIMITE_WIDGETS = 12;

/** Painel de quem nunca personalizou (o mesmo que o repositório devolve na primeira vez). */
export function painelPadraoInicio(vendedorId: string, gestor: boolean): PainelPessoa {
  const w = (id: string, titulo: string, metrica: MetricaKey, visual: VisualWidget, periodo: WidgetPainel['periodo'], agrupar: AgrupamentoWidget, largura: WidgetPainel['largura']): WidgetPainel =>
    ({ id: `${vendedorId}-${id}`, titulo, metrica, visual, periodo, agrupar, largura, funilId: null });
  return {
    vendedorId,
    widgets: gestor
      ? [
        w('w1', 'Vendas da semana por vendedor', 'vendas', 'barras', '7d', 'vendedor', 2),
        w('w2', 'Receita do mês', 'receita', 'numero', 'mes', 'nenhum', 1),
        w('w3', 'Prazo crítico agora', 'criticos', 'numero', 'hoje', 'nenhum', 1),
        w('w4', 'Abordados por dia', 'abordados', 'linha', '7d', 'dia', 2),
        w('w5', 'Perdidos por motivo', 'perdidos', 'pizza', '30d', 'motivo', 2),
      ]
      : [
        w('w1', 'Minhas vendas no mês', 'vendas', 'numero', 'mes', 'nenhum', 1),
        w('w2', 'Em negociação', 'em_negociacao', 'numero', 'hoje', 'nenhum', 1),
        w('w3', 'Atividades atrasadas', 'atrasadas', 'numero', 'hoje', 'nenhum', 1),
        w('w4', 'Sem próximo passo', 'sem_proximo', 'numero', 'hoje', 'nenhum', 1),
        w('w5', 'Meus abordados por dia', 'abordados', 'barras', '7d', 'dia', 4),
      ],
  };
}

/** Widget novo com valores que já fazem sentido juntos. */
export function widgetNovo(id: string): WidgetPainel {
  return { id, titulo: '', metrica: 'vendas', visual: 'numero', periodo: '7d', agrupar: 'nenhum', largura: 1, funilId: null };
}

/** Visuais que combinam com a métrica: pizza não soma porcentagem nem tempo; linha só com série por dia. */
export function visuaisPermitidos(m: MetricaKey): VisualWidget[] {
  const def = METRICAS[m];
  const out: VisualWidget[] = ['numero', 'barras', 'lista'];
  if (def.agrupamentos.includes('dia')) out.push('linha');
  if (def.formato === 'numero' || def.formato === 'moeda') out.push('pizza');
  return out;
}

/** Agrupamentos aceitos pelo visual escolhido (vem de METRICAS[m].agrupamentos). */
export function agrupamentosPermitidos(m: MetricaKey, v: VisualWidget): AgrupamentoWidget[] {
  const todos = METRICAS[m].agrupamentos;
  if (v === 'numero') return ['nenhum'];
  if (v === 'linha') return todos.filter((a) => a === 'dia');
  if (v === 'pizza' || v === 'lista') return todos.filter((a) => a !== 'nenhum' && a !== 'dia');
  return todos.filter((a) => a !== 'nenhum');
}

/**
 * Ajusta visual e agrupamento depois de trocar a métrica ou o visual: nunca deixa combinação que não desenha.
 * Mantém a escolha da pessoa quando ela ainda vale.
 */
export function coerente(w: WidgetPainel): WidgetPainel {
  const visuais = visuaisPermitidos(w.metrica);
  const visual = visuais.includes(w.visual) ? w.visual : 'numero';
  const agrupamentos = agrupamentosPermitidos(w.metrica, visual);
  const agrupar = agrupamentos.includes(w.agrupar) ? w.agrupar : agrupamentos[0] ?? 'nenhum';
  return { ...w, visual, agrupar };
}

/** Erro que impede salvar o widget, ou null. */
export function validarWidget(w: WidgetPainel): string | null {
  if (!w.titulo.trim()) return 'Dê um título ao widget.';
  if (w.titulo.trim().length > 60) return 'Título com no máximo 60 caracteres.';
  if (!visuaisPermitidos(w.metrica).includes(w.visual)) return 'Esse visual não combina com a métrica.';
  if (!agrupamentosPermitidos(w.metrica, w.visual).includes(w.agrupar)) return 'Escolha um agrupamento que a métrica aceite.';
  if (!LARGURAS.includes(w.largura)) return 'Largura entre 1 e 4 colunas.';
  return null;
}

/** Inclui (id novo) ou substitui (id existente) mantendo a posição. */
export function salvarWidget(lista: WidgetPainel[], w: WidgetPainel): WidgetPainel[] {
  return lista.some((x) => x.id === w.id) ? lista.map((x) => (x.id === w.id ? w : x)) : [...lista, w];
}

/** Move o widget `delta` posições (−1 = para trás). Fora dos limites, nada muda. */
export function moverWidget(lista: WidgetPainel[], id: string, delta: number): WidgetPainel[] {
  const i = lista.findIndex((w) => w.id === id);
  return i < 0 ? lista : moverPara(lista, i, i + delta);
}

/** Arrastar e soltar: tira de `de` e coloca em `para`. */
export function moverPara<T>(lista: T[], de: number, para: number): T[] {
  if (de === para || de < 0 || de >= lista.length || para < 0 || para >= lista.length) return lista;
  const out = [...lista];
  const [item] = out.splice(de, 1);
  out.splice(para, 0, item);
  return out;
}

/** Painel mudou em relação ao salvo? (para avisar antes de sair do modo edição) */
export function painelMudou(a: WidgetPainel[], b: WidgetPainel[]): boolean {
  return JSON.stringify(a) !== JSON.stringify(b);
}
