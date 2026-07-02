// Formatadores de exibição pt-BR — fonte única (antes copiados por módulo).

/** Moeda inteira: R$ 1.234 (valores vêm como bigint do banco). */
export function fmtBRL(n: number | null | undefined): string {
  return n == null ? '—' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
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
