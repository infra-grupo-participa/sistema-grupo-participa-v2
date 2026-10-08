export type PresetPeriodoAtm = 'evento' | 'hoje' | 'ontem' | '3d' | '7d';

export type DatasPeriodoAtm = { p_de: string | null; p_ate: string | null };

const FUSO = 'America/Sao_Paulo';

export function hojeEmSaoPaulo(agora = new Date()): string {
  const partes = new Intl.DateTimeFormat('en-CA', {
    timeZone: FUSO,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(agora);
  const valor = (tipo: string) => partes.find((parte) => parte.type === tipo)?.value ?? '';
  return `${valor('year')}-${valor('month')}-${valor('day')}`;
}

export function deslocarDia(iso: string, dias: number): string {
  const [ano, mes, dia] = iso.split('-').map(Number);
  return new Date(Date.UTC(ano, mes - 1, dia + dias)).toISOString().slice(0, 10);
}

export function datasDoPeriodo(preset: PresetPeriodoAtm, agora = new Date()): DatasPeriodoAtm {
  if (preset === 'evento') return { p_de: null, p_ate: null };
  const hoje = hojeEmSaoPaulo(agora);
  if (preset === 'hoje') return { p_de: hoje, p_ate: hoje };
  if (preset === 'ontem') {
    const ontem = deslocarDia(hoje, -1);
    return { p_de: ontem, p_ate: ontem };
  }
  const dias = preset === '3d' ? 2 : 6;
  return { p_de: deslocarDia(hoje, -dias), p_ate: hoje };
}

export function dataPtBr(iso: string | null | undefined): string {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return 'Não lançado';
  const [ano, mes, dia] = iso.split('-');
  return `${dia}/${mes}/${ano}`;
}
