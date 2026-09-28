// Eventos planejados do Contas a Receber (z67, bloco 4) — funções PURAS, sem I/O.
// Fonte: fn_fin_eventos_planejados_listar() (com a curva do evento de referência já calculada no banco) e
// fn_fin_funis() (candidatos a evento de referência). A regra (curva, tamanho × referência, pausa do avulso, faixas)
// mora no banco; aqui só: tipar, filtrar candidatos com as MESMAS travas da RPC de salvar e validar antes de enviar —
// a validação do cliente só poupa uma ida ao banco, a trava de verdade é fn_fin_evento_planejado_salvar.
import type { CenarioReceber } from './contas-receber';
import type { Funil } from './funis';

export type SituacaoEventoPlanejado = 'ativo' | 'encerrado' | 'arquivado';

/** Um dia da curva do evento de referência. d = dias desde a abertura (0 = abertura). */
export interface PontoCurva {
  d: number;
  liquido: number;
  /** Fração do total (0–1). NULL quando o total é zero. */
  participacao: number | null;
}

export interface EventoPlanejado {
  id: number;
  nome: string;
  abertura: string;
  /** Abertura + duração das vendas da referência. */
  fim_vendas: string | null;
  evento_ref_id: number;
  evento_ref_nome: string;
  evento_ref_abertura: string | null;
  evento_ref_venda_ate: string | null;
  /** Líquido total da referência (1ª cobrança, paga ou estornada depois). NULL = sem venda medida. */
  total_ref: number | null;
  curva: PontoCurva[];
  tamanho_base: number;
  tamanho_conservador: number;
  tamanho_otimista: number;
  pausa_avulso: boolean;
  observacao: string | null;
  situacao: SituacaoEventoPlanejado;
  criado_em: string | null;
  criado_por_nome: string | null;
  atualizado_em: string | null;
  atualizado_por_nome: string | null;
  arquivado_em: string | null;
  arquivado_por_nome: string | null;
  arquivado_motivo: string | null;
}

/** Payload de fn_fin_evento_planejado_salvar. Sem id = cria. A RPC exige TODAS as chaves na alteração. */
export interface EventoPlanejadoEntrada {
  id?: number;
  nome: string;
  abertura: string;
  evento_ref_id: number;
  tamanho_base: number;
  tamanho_conservador: number;
  tamanho_otimista: number;
  pausa_avulso: boolean;
  observacao: string | null;
}

const num = (v: unknown): number => Number(v ?? 0) || 0;
const numOuNull = (v: unknown): number | null => (v == null || v === '' || !Number.isFinite(Number(v)) ? null : Number(v));
const texto = (v: unknown): string | null => (v == null || v === '' ? null : String(v));
const diaOuNull = (v: unknown): string | null => (v == null || v === '' ? null : String(v).slice(0, 10));

function lerCurva(v: unknown): PontoCurva[] {
  let bruto: unknown = v;
  if (typeof bruto === 'string') {
    try { bruto = JSON.parse(bruto); } catch { return []; }
  }
  if (!Array.isArray(bruto)) return [];
  return bruto
    .map((x) => {
      const o = (x ?? {}) as Record<string, unknown>;
      return { d: num(o.d), liquido: num(o.liquido), participacao: numOuNull(o.participacao) };
    })
    .sort((a, b) => a.d - b.d);
}

export function normalizarEventoPlanejado(r: Record<string, unknown>): EventoPlanejado {
  const sit = String(r.situacao ?? '');
  return {
    id: num(r.id),
    nome: String(r.nome ?? ''),
    abertura: String(r.abertura ?? '').slice(0, 10),
    fim_vendas: diaOuNull(r.fim_vendas),
    evento_ref_id: num(r.evento_ref_id),
    evento_ref_nome: String(r.evento_ref_nome ?? ''),
    evento_ref_abertura: diaOuNull(r.evento_ref_abertura),
    evento_ref_venda_ate: diaOuNull(r.evento_ref_venda_ate),
    total_ref: numOuNull(r.total_ref),
    curva: lerCurva(r.curva),
    tamanho_base: num(r.tamanho_base),
    tamanho_conservador: num(r.tamanho_conservador),
    tamanho_otimista: num(r.tamanho_otimista),
    pausa_avulso: r.pausa_avulso === true || r.pausa_avulso === 'true',
    observacao: texto(r.observacao),
    // Situação fora do contrato: mantida crua (a tela mostra como veio, não disfarça).
    situacao: sit as SituacaoEventoPlanejado,
    criado_em: texto(r.criado_em),
    criado_por_nome: texto(r.criado_por_nome),
    atualizado_em: texto(r.atualizado_em),
    atualizado_por_nome: texto(r.atualizado_por_nome),
    arquivado_em: texto(r.arquivado_em),
    arquivado_por_nome: texto(r.arquivado_por_nome),
    arquivado_motivo: texto(r.arquivado_motivo),
  };
}

export const tamanhoDoCenario = (e: Pick<EventoPlanejado, 'tamanho_base' | 'tamanho_conservador' | 'tamanho_otimista'>, c: CenarioReceber) =>
  c === 'conservador' ? e.tamanho_conservador : c === 'otimista' ? e.tamanho_otimista : e.tamanho_base;

/**
 * Venda total esperada do evento no cenário = tamanho × líquido total da referência (em centavos, sem resíduo).
 * É venda (líquido), não caixa: o caixa passa por D+2/retido e só os dias depois do corte entram na previsão.
 * NULL = referência sem venda medida.
 */
export function totalEsperado(e: Pick<EventoPlanejado, 'tamanho_base' | 'tamanho_conservador' | 'tamanho_otimista' | 'total_ref'>,
  c: CenarioReceber): number | null {
  if (e.total_ref == null) return null;
  return Math.round(tamanhoDoCenario(e, c) * e.total_ref * 100) / 100;
}

/** YYYY-MM-DD + n dias (calendário puro). */
export function somarDiasISO(iso: string, n: number): string {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d + n)).toISOString().slice(0, 10);
}
const diasEntre = (a: string, b: string) => {
  const t = (s: string) => { const [y, m, d] = s.split('-').map(Number); return Date.UTC(y, m - 1, d); };
  return Math.round((t(b) - t(a)) / 86_400_000);
};

/** Mesmo teto da RPC: evento de referência com até 31 dias de venda (venda_ate − abertura ≤ 30). */
export const REFERENCIA_MAX_DIAS = 30;

/**
 * Candidatos a evento de referência, com as travas da RPC de salvar: educação (a conta do escritório não está no
 * espelho), vendas já encerradas (venda_ate < hoje) e curva curta. Mais recente primeiro. A RPC ainda recusa o que não
 * tem venda no espelho — isso só o banco sabe.
 */
export function candidatosReferencia(funis: Funil[], hojeISO: string): Funil[] {
  return funis
    .filter((f) => {
      if (f.setor !== 'educacao' || !f.venda_ate) return false;
      const ab = (f.carrinho_inicio ?? f.inicio ?? '').slice(0, 10);
      const ate = f.venda_ate.slice(0, 10);
      return !!ab && ate < hojeISO && diasEntre(ab, ate) <= REFERENCIA_MAX_DIAS;
    })
    .sort((a, b) => b.venda_ate.localeCompare(a.venda_ate) || a.nome.localeCompare(b.nome, 'pt-BR'));
}

/** Tamanho digitado ("1,3", "0.7"). NULL = não é número. */
export function lerTamanho(t: string): number | null {
  const s = t.trim().replace(',', '.');
  if (!/^\d+(\.\d+)?$/.test(s)) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}

export interface FormEvento {
  id?: number;
  nome: string;
  abertura: string;
  evento_ref_id: string;
  tamanho_conservador: string;
  tamanho_base: string;
  tamanho_otimista: string;
  pausa_avulso: boolean;
  observacao: string;
}

export type ValidacaoEvento = { ok: true; entrada: EventoPlanejadoEntrada } | { ok: false; erros: string[] };

/** Mesmas regras da fn_fin_evento_planejado_salvar (z67), com as mesmas mensagens. */
export function validarEvento(f: FormEvento, hojeISO: string): ValidacaoEvento {
  const erros: string[] = [];
  const nome = f.nome.trim();
  if (!nome || nome.length > 120) erros.push('Nome obrigatório (até 120 caracteres).');
  if (!/^\d{4}-\d{2}-\d{2}$/.test(f.abertura) || f.abertura < somarDiasISO(hojeISO, -31) || f.abertura > somarDiasISO(hojeISO, 400)) {
    erros.push('Abertura entre 31 dias atrás e 400 dias à frente.');
  }
  const ref = Number(f.evento_ref_id);
  if (!f.evento_ref_id || !Number.isInteger(ref) || ref <= 0) erros.push('Escolha o evento de referência.');
  const tc = lerTamanho(f.tamanho_conservador);
  const tb = lerTamanho(f.tamanho_base);
  const to = lerTamanho(f.tamanho_otimista);
  if (tc == null || tb == null || to == null || Math.min(tc, tb, to) <= 0 || Math.max(tc, tb, to) > 20 || !(tc <= tb && tb <= to)) {
    erros.push('Tamanhos maiores que 0 e até 20, com conservador ≤ base ≤ otimista.');
  }
  const obs = f.observacao.trim();
  if (obs.length > 500) erros.push('Observação até 500 caracteres.');
  if (erros.length) return { ok: false, erros };
  return {
    ok: true,
    entrada: {
      ...(f.id != null ? { id: f.id } : {}),
      nome, abertura: f.abertura, evento_ref_id: ref,
      tamanho_base: tb as number, tamanho_conservador: tc as number, tamanho_otimista: to as number,
      pausa_avulso: f.pausa_avulso, observacao: obs || null,
    },
  };
}

/** Mesma faixa da fn_fin_evento_planejado_arquivar. */
export function validarMotivoArquivar(m: string): string | null {
  const t = m.trim();
  return t.length < 3 || t.length > 500 ? 'Motivo entre 3 e 500 caracteres.' : null;
}
