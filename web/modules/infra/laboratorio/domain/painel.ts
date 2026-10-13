// Números do início do Laboratório (puros, testáveis).
import type { Experimento } from './types';

const hojeIso = (agora: Date) => {
  const d = new Date(agora.getTime() - 3 * 3600_000); // America/Sao_Paulo (sem horário de verão)
  return d.toISOString().slice(0, 10);
};

const somaDias = (iso: string, dias: number) => {
  const d = new Date(`${iso}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
};

export function painel(lista: Experimento[], agora = new Date()) {
  const hoje = hojeIso(agora);
  const limite = somaDias(hoje, 2);
  const ativos = lista.filter((e) => e.status === 'no_ar' || e.status === 'em_leitura');
  const leiturasVencendo = ativos.filter((e) => e.nivel > 1 && e.leitura_em && e.leitura_em <= limite)
    .sort((a, b) => (a.leitura_em ?? '').localeCompare(b.leitura_em ?? ''));
  const revisoesPendentes = ativos.filter((e) => e.nivel === 1 && e.revisao_em && e.revisao_em <= limite)
    .sort((a, b) => (a.revisao_em ?? '').localeCompare(b.revisao_em ?? ''));
  const revisados = lista.filter((e) => e.nivel === 1 && e.revisao_bateu);
  const acertos = revisados.filter((e) => e.revisao_bateu === 'sim').length;
  const decidiveis = revisados.filter((e) => e.revisao_bateu !== 'nao_sabe').length;
  const concluidos = lista.filter((e) => e.status === 'concluido' && e.nivel > 1);
  return {
    hoje,
    ativos,
    leiturasVencendo,
    revisoesPendentes,
    rascunhos: lista.filter((e) => e.status === 'rascunho'),
    taxaAcerto: decidiveis > 0 ? acertos / decidiveis : null,
    revisados: revisados.length,
    vencedores: concluidos.filter((e) => e.resultado === 'vencedor').length,
    concluidos: concluidos.length,
    vencida: (e: Experimento) => {
      const d = e.nivel === 1 ? e.revisao_em : e.leitura_em;
      return !!d && d < hoje;
    },
  };
}

/** CSV do log (seção 11). Separador ";" para abrir direto no Excel em português. */
export function logCsv(lista: Experimento[]): string {
  const cab = ['Criado em', 'Área', 'Nível', 'Decisão ou teste', 'Hipótese com número', 'Leitura em', 'Status', 'Resultado', 'Confiança', 'O que fizemos', 'O que aprendemos'];
  const esc = (v: unknown) => {
    const s = v == null ? '' : String(v);
    return /[;"\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  };
  const linhas = lista.map((e) => [
    e.criado_em.slice(0, 10), e.area, e.nivel, e.titulo, e.hipotese, e.nivel === 1 ? e.revisao_em : e.leitura_em, e.status,
    e.resultado ?? (e.revisao_bateu ? `previsão bateu: ${e.revisao_bateu}` : ''),
    e.confianca != null ? `${(e.confianca * 100).toFixed(1)}%` : '', e.o_que_fizemos, e.aprendizado,
  ].map(esc).join(';'));
  return [cab.join(';'), ...linhas].join('\n');
}
