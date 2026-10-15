// Recorte da tela (funil, período, canal, aba e filtros cruzados), gravado na URL para o link abrir igual.
// Valor inválido cai no padrão, nunca quebra a tela.
import { deslocarDia, hojeEmSaoPaulo } from '@/modules/infra/atm/domain/periodo';
import type { AbaBlack, ConfigBlack, FiltroCanal, FiltroCriativos, FiltroFunil, Periodo, Recorte } from './tipos';

export const PERIODOS = ['hoje', '7d', 'desde-inicio', 'semana', 'personalizado'] as const;
export type ChavePeriodo = (typeof PERIODOS)[number];
export const ROTULO_PERIODO: Record<ChavePeriodo, string> = {
  hoje: 'Hoje', '7d': '7 dias', 'desde-inicio': 'Desde o início', semana: 'Semana do ciclo', personalizado: 'Personalizado',
};

const FUNIS_FILTRO: readonly FiltroFunil[] = ['todos', 'c1', 'c2', 'consultoria', 'iscas', 'c3'];
const CANAIS_FILTRO: readonly FiltroCanal[] = ['todos', 'meta', 'google'];
export const ABAS: readonly AbaBlack[] = ['visao', 'jornada', 'criativos', 'mensageria', 'historico', 'lives'];
const ID_RE = /^[A-Za-z0-9_-]{1,64}$/;
const ID_YOUTUBE_RE = /^[A-Za-z0-9_-]{11}$/;

export const RECORTE_PADRAO: Recorte = { funil: 'todos', canal: 'todos', periodo: 'desde-inicio', aba: 'visao', criativos: {}, historicoModo: 'dia-a-dia' };

type Params = URLSearchParams | Record<string, string | string[] | undefined>;
function ler(p: Params, k: string): string | undefined {
  if (p instanceof URLSearchParams) return p.get(k) ?? undefined;
  const v = p[k];
  return Array.isArray(v) ? v[0] : v;
}
const umDe = <T extends string>(v: string | undefined, validos: readonly T[], padrao: T): T =>
  v !== undefined && (validos as readonly string[]).includes(v) ? (v as T) : padrao;
const id = (v: string | undefined) => (v !== undefined && ID_RE.test(v) ? v : undefined);

export function lerRecorte(p: Params): Recorte {
  const criativos: FiltroCriativos = {};
  const cp = id(ler(p, 'cp')); const cj = id(ler(p, 'cj')); const cr = id(ler(p, 'cr')); const pg = id(ler(p, 'pg'));
  if (cp) criativos.campanha = cp;
  if (cj) criativos.conjunto = cj;
  if (cr) criativos.anuncio = cr;
  if (pg) criativos.pagina = pg;
  const periodo = umDe(ler(p, 'periodo'), PERIODOS, RECORTE_PADRAO.periodo);
  const de = ler(p, 'de'); const ate = ler(p, 'ate');
  const periodoPersonalizado = periodo === 'personalizado' && de && ate && diaValido(de) && diaValido(ate) && de <= ate
    ? { de, ate } : null;
  const aba = umDe(ler(p, 'aba'), ABAS, RECORTE_PADRAO.aba);
  const live = ler(p, 'live');
  return {
    funil: umDe(ler(p, 'funil'), FUNIS_FILTRO, RECORTE_PADRAO.funil),
    canal: umDe(ler(p, 'canal'), CANAIS_FILTRO, RECORTE_PADRAO.canal),
    periodo: periodo === 'personalizado' && !periodoPersonalizado ? RECORTE_PADRAO.periodo : periodo,
    ...(periodoPersonalizado ? { periodoPersonalizado } : {}),
    aba,
    ...(aba === 'lives' && live !== undefined && ID_YOUTUBE_RE.test(live) ? { live } : {}),
    criativos,
    historicoModo: ler(p, 'historico') === 'geral' ? 'geral' : 'dia-a-dia',
  };
}

/** Query string na ordem fixa (funil, periodo, canal, aba, cp, cj, cr, pg). Preserva parâmetros alheios (ex.: relogio). */
export function escreverRecorte(r: Recorte, extras?: URLSearchParams): string {
  const q = new URLSearchParams();
  q.set('funil', r.funil); q.set('periodo', r.periodo); q.set('canal', r.canal); q.set('aba', r.aba);
  if (r.historicoModo === 'geral') q.set('historico', 'geral');
  if (r.periodo === 'personalizado' && r.periodoPersonalizado) {
    q.set('de', r.periodoPersonalizado.de); q.set('ate', r.periodoPersonalizado.ate);
  }
  if (r.aba === 'lives' && r.live && ID_YOUTUBE_RE.test(r.live)) q.set('live', r.live);
  if (r.criativos.campanha) q.set('cp', r.criativos.campanha);
  if (r.criativos.conjunto) q.set('cj', r.criativos.conjunto);
  if (r.criativos.anuncio) q.set('cr', r.criativos.anuncio);
  if (r.criativos.pagina) q.set('pg', r.criativos.pagina);
  if (extras) for (const [k, v] of extras) if (!['funil', 'periodo', 'canal', 'aba', 'de', 'ate', 'cp', 'cj', 'cr', 'pg', 'live'].includes(k)) q.set(k, v);
  return q.toString();
}

const max = (a: string, b: string) => (a > b ? a : b);
const min = (a: string, b: string) => (a < b ? a : b);

/** Segunda-feira da semana (provisório: "semana do ciclo" ainda sem datas oficiais, BLOQUEIO 5 do plano). */
export function segundaDaSemana(iso: string): string {
  const [a, m, d] = iso.split('-').map(Number);
  const dow = new Date(Date.UTC(a, m - 1, d)).getUTCDay(); // 0 = domingo
  return deslocarDia(iso, -((dow + 6) % 7));
}

/**
 * Datas do período no fuso de São Paulo, presas entre o início do projeto e o fim do projeto
 * (último dia de config.semanas, ou hoje). Se hoje é antes do início, devolve o primeiro dia.
 */
export function periodoDe(chave: string, agora: Date, config: Pick<ConfigBlack, 'inicio' | 'semanas'>, personalizado?: Periodo | null): Periodo {
  const fimProjeto = config.semanas.length ? config.semanas[config.semanas.length - 1].ate : hojeEmSaoPaulo(agora);
  const hoje = max(config.inicio, min(hojeEmSaoPaulo(agora), fimProjeto));
  const k = umDe(chave, PERIODOS, 'desde-inicio');
  if (k === 'personalizado' && personalizado && diaValido(personalizado.de) && diaValido(personalizado.ate) && personalizado.de <= personalizado.ate) {
    const de = max(config.inicio, personalizado.de);
    const ate = min(hoje, personalizado.ate);
    if (de <= ate) return { de, ate };
  }
  if (k === 'hoje') return { de: hoje, ate: hoje };
  if (k === '7d') return { de: max(config.inicio, deslocarDia(hoje, -6)), ate: hoje };
  if (k === 'semana') {
    const s = config.semanas.find((x) => x.de <= hoje && hoje <= x.ate);
    return s ? { de: max(config.inicio, s.de), ate: hoje } : { de: max(config.inicio, segundaDaSemana(hoje)), ate: hoje };
  }
  return { de: config.inicio, ate: hoje };
}

function diaValido(dia: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dia)) return false;
  const d = new Date(`${dia}T00:00:00Z`);
  return Number.isFinite(d.getTime()) && d.toISOString().slice(0, 10) === dia;
}

/** Dias do período, inclusivo. */
export function diasDoPeriodo(p: Periodo): string[] {
  const out: string[] = [];
  for (let d = p.de; d <= p.ate; d = deslocarDia(d, 1)) out.push(d);
  return out;
}

/**
 * Dia (AAAA-MM-DD, São Paulo) de um instante ISO. São Paulo está em UTC-3 fixo desde 2019 (sem horário de
 * verão), então a conta é aritmética: roda em dezenas de milhares de linhas sem criar um Intl por chamada.
 */
const TRES_HORAS = 3 * 3_600_000;
export const diaDe = (iso: string) => new Date(Date.parse(iso) - TRES_HORAS).toISOString().slice(0, 10);
