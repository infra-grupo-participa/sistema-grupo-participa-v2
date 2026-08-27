// Formatadores de exibição pt-BR — fonte única (antes copiados por módulo).

/** Moeda inteira: R$ 1.234 (valores vêm como bigint do banco). */
export function fmtBRL(n: number | null | undefined): string {
  return n == null ? '—' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
}

/** Moeda com centavos: R$ 1.234,56. Para conciliação financeira, onde o centavo importa. */
export function fmtBRLc(n: number | null | undefined): string {
  return n == null ? '—' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

/** Data curta: 31/12/2025. Aceita ISO ou Date; inválida vira '—'.
 *  'YYYY-MM-DD' puro é interpretado como data local — new Date() trataria como
 *  UTC-meia-noite e, em fuso brasileiro, exibiria o dia anterior. */
export function fmtData(v: string | Date | null | undefined): string {
  if (!v) return '—';
  if (typeof v === 'string') {
    const m = v.match(/^(\d{4})-(\d{2})-(\d{2})$/);
    if (m) return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])).toLocaleDateString('pt-BR');
  }
  const d = typeof v === 'string' ? new Date(v) : v;
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('pt-BR');
}

/** Data + hora: 31/12/2025 23:59. */
export function fmtDataHora(v: string | Date | null | undefined): string {
  if (!v) return '—';
  const d = typeof v === 'string' ? new Date(v) : v;
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('pt-BR') + ' ' + d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
}

/** Data por extenso a partir de 'YYYY-MM-DD' (sem fuso): "sexta-feira, 05 de setembro". */
export function fmtDataExtenso(ymd: string): string {
  try {
    const [y, m, dd] = ymd.split('-').map(Number);
    return new Date(y, m - 1, dd).toLocaleDateString('pt-BR', { weekday: 'long', day: '2-digit', month: 'long' });
  } catch {
    return ymd;
  }
}

/** Data relativa para varredura de filas ("hoje", "ontem", "há 3 dias") + completa no title. */
export function fmtRelativo(iso: string | null | undefined): { label: string; title: string } {
  if (!iso) return { label: '—', title: '' };
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return { label: '—', title: '' };
  const hoje = new Date();
  const dias = Math.floor(
    (new Date(hoje.getFullYear(), hoje.getMonth(), hoje.getDate()).getTime() -
      new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()) / 86400000,
  );
  const title = fmtDataHora(d);
  if (dias <= 0) return { label: 'hoje', title };
  if (dias === 1) return { label: 'ontem', title };
  if (dias < 7) return { label: `há ${dias} dias`, title };
  return { label: d.toLocaleDateString('pt-BR'), title };
}

/**
 * Prazo FUTURO ("vence hoje", "vence amanhã", "vence em 5 dias", "vence 12/09/2026").
 *
 * ⚠️ Existe porque `fmtRelativo` acima é formatador de PASSADO: ele calcula
 * `hoje − data` e colapsa TODO futuro em `dias <= 0 → "hoje"`. Usá-lo num
 * vencimento fazia uma conta que vence em 14 dias exibir "vence hoje" — o
 * oposto do que a tela precisa responder ("estou atrasado?"). Achado do
 * fable-orchestrator, 2026-08-27.
 *
 * `hojeISO` é injetado (função pura, não lê relógio) — mesma disciplina de
 * proximaAcao()/faixaPrazoDe() no domínio do financeiro, e é o que torna o
 * limiar testável sem congelar o relógio do processo.
 *
 * Passado devolve `null`: quem está atrasado tem outro canal na tela (o chip
 * "Nd em atraso", com dias_atraso do banco). Devolver "há 3 dias" aqui
 * duplicaria o sinal com uma contagem calculada de forma diferente.
 */
export function fmtPrazo(iso: string | null | undefined, hojeISO: string): { label: string; title: string } | null {
  if (!iso) return null;
  const ymd = String(iso).slice(0, 10);
  if (!/^\d{4}-\d{2}-\d{2}$/.test(ymd) || !/^\d{4}-\d{2}-\d{2}$/.test(hojeISO)) return null;

  // Calendário puro (UTC dos dois lados) — sem fuso, igual a addDias() de cobranca.ts.
  const ms = (s: string) => {
    const [y, m, d] = s.split('-').map(Number);
    return Date.UTC(y, m - 1, d);
  };
  const dias = Math.round((ms(ymd) - ms(hojeISO)) / 86400000);
  if (dias < 0) return null;

  const title = fmtData(ymd);
  if (dias === 0) return { label: 'vence hoje', title };
  if (dias === 1) return { label: 'vence amanhã', title };
  if (dias <= 30) return { label: `vence em ${dias} dias`, title };
  return { label: `vence ${title}`, title };
}

/** Tempo decorrido com granularidade fina ("agora", "há 58 min", "há 3h", "há 2 dias").
 *  Para o último evento de uma linha — mais preciso que fmtRelativo (que é por dia). */
export function fmtDesde(iso: string | null | undefined): { label: string; title: string } {
  if (!iso) return { label: '—', title: '' };
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return { label: '—', title: '' };
  const seg = Math.floor((Date.now() - d.getTime()) / 1000);
  const title = fmtDataHora(d);
  if (seg < 45) return { label: 'agora', title };
  const min = Math.floor(seg / 60);
  if (min < 60) return { label: `há ${min} min`, title };
  const h = Math.floor(min / 60);
  if (h < 24) return { label: `há ${h}h`, title };
  const dias = Math.floor(h / 24);
  if (dias < 7) return { label: `há ${dias} ${dias === 1 ? 'dia' : 'dias'}`, title };
  return { label: d.toLocaleDateString('pt-BR'), title };
}
