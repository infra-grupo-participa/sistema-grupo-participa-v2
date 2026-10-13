/*
 * Regras puras dos modais de pessoas do funil do ATM (Leads, Pré-checkout, Vendas), 13/10/2026.
 * Os três modais têm as mesmas 4 abas (pessoas, Grupo, Evolução, Resumo) e o contador de cada um usa o MESMO critério do
 * card que o abre, para card e modal baterem:
 *   - Leads: linhas de `dados_atm_leads` sem teste = `dados_atm_resumo.leads`;
 *   - Pré-checkout: linhas de `dados_atm_pre_checkout` sem teste = `dados_atm_resumo.pre_checkout_pessoas`;
 *   - Vendas: linhas de `dados_atm_sv_vendas` sem teste com `aprovado_em` no período aplicado = `dados_atm_resumo.vendas`
 *     (o banco conta `dados.atm_vendas` com `aprovado_em` em [de 00:00, ate + 1 dia 00:00) de São Paulo; a RPC da lista
 *     não recebe período, então o recorte é feito aqui com a mesma regra).
 */
import { chaveTelefone } from '@/modules/comercial/domain/regras';
import type { NumeroGrupoAtm } from './dashboard';

const FUSO = 'America/Sao_Paulo';

/** Contador do modal: linhas que contam (sem teste). É o número que tem de bater com o card. */
export function contadorDoModalAtm(itens: readonly { teste: boolean }[]): number {
  return itens.reduce((n, item) => n + (item.teste ? 0 : 1), 0);
}

/** Dia (AAAA-MM-DD) de um instante em America/Sao_Paulo. Texto inválido ou nulo = null. */
export function diaEmSaoPaulo(iso: string | null | undefined): string | null {
  if (!iso) return null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(iso)) return iso;
  const data = new Date(iso);
  if (Number.isNaN(data.getTime())) return null;
  const partes = new Intl.DateTimeFormat('en-CA', { timeZone: FUSO, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(data);
  const v = (tipo: string) => partes.find((p) => p.type === tipo)?.value ?? '';
  return `${v('year')}-${v('month')}-${v('day')}`;
}

/**
 * Vendas no período aplicado, pela regra do card (`aprovado_em` em São Paulo entre `de` e `ate`, inclusive; nulo = sem
 * limite daquele lado). Venda sem `aprovado_em` fica fora, como no banco (comparação com nulo não passa).
 */
export function vendasNoPeriodoAtm<T extends { aprovadoEm: string | null }>(vendas: readonly T[], de: string | null, ate: string | null): T[] {
  return vendas.filter((venda) => {
    const dia = venda.aprovadoEm ? diaEmSaoPaulo(venda.aprovadoEm) : null;
    if (!dia) return false;
    return (de === null || dia >= de) && (ate === null || dia <= ate);
  });
}

/**
 * Chave de cruzamento com o grupo de WhatsApp: os 8 últimos dígitos da chave de telefone (`chaveTelefone`, igual a
 * `controle.fone_key` = DDD + 8 dígitos). É a regra do banco: `dados.grupo_participantes.fone8 = right(fone_key, 8)`.
 */
export function chaveGrupoAtm(telefone: string | null | undefined): string | null {
  const chave = chaveTelefone(telefone);
  return chave ? chave.slice(-8) : null;
}

/** Situação de uma pessoa do conjunto no grupo. `semTelefone` = não dá para cruzar (nunca vira "Não"). */
export type SituacaoGrupoAtm = { semTelefone: true } | { semTelefone: false; numero: NumeroGrupoAtm | null };

/**
 * Cruza cada pessoa com a lista de números do grupo pela chave de 8 dígitos. Com mais de um número na mesma chave,
 * fica o de entrada mais antiga (a primeira vez que a pessoa entrou).
 */
export function cruzarComGrupoAtm<T extends { id: string }>(itens: readonly T[], telefoneDe: (item: T) => string | null, numeros: readonly NumeroGrupoAtm[]): Map<string, SituacaoGrupoAtm> {
  const porChave = new Map<string, NumeroGrupoAtm>();
  for (const numero of numeros) {
    const k = chaveGrupoAtm(numero.foneKey);
    if (!k) continue;
    const atual = porChave.get(k);
    if (!atual || (numero.entrouEm ?? '9999') < (atual.entrouEm ?? '9999')) porChave.set(k, numero);
  }
  const out = new Map<string, SituacaoGrupoAtm>();
  for (const item of itens) {
    const k = chaveGrupoAtm(telefoneDe(item));
    out.set(item.id, k ? { semTelefone: false, numero: porChave.get(k) ?? null } : { semTelefone: true });
  }
  return out;
}

export type DiaSerieAtm = { dia: string; quantidade: number };

/**
 * Barras por dia do conjunto (sem teste), a partir da data de cada pessoa em São Paulo. Dias sem ninguém entre o primeiro
 * e o último aparecem com zero (zero medido). Com `de`/`ate`, o eixo cobre o período aplicado, limitado a `hoje`.
 */
export function serieDiariaAtm<T extends { teste: boolean }>(itens: readonly T[], dataDe: (item: T) => string | null, de: string | null = null, ate: string | null = null, hoje: string | null = null): DiaSerieAtm[] {
  const contagem = new Map<string, number>();
  for (const item of itens) {
    if (item.teste) continue;
    const dia = diaEmSaoPaulo(dataDe(item));
    if (dia) contagem.set(dia, (contagem.get(dia) ?? 0) + 1);
  }
  const dias = [...contagem.keys()].sort();
  const primeiro = dias[0] ?? null;
  const ultimo = dias[dias.length - 1] ?? null;
  let inicio = de ?? primeiro;
  let fim = ate ?? ultimo;
  if (fim && hoje && fim > hoje) fim = hoje;
  if (primeiro && (!inicio || primeiro < inicio)) inicio = primeiro;
  if (ultimo && (!fim || ultimo > fim)) fim = ultimo;
  if (!inicio || !fim) return [];
  const out: DiaSerieAtm[] = [];
  for (let dia = inicio; dia <= fim && out.length < 400; dia = proximoDia(dia)) out.push({ dia, quantidade: contagem.get(dia) ?? 0 });
  return out;
}

function proximoDia(iso: string): string {
  const [a, m, d] = iso.split('-').map(Number);
  return new Date(Date.UTC(a, m - 1, d + 1)).toISOString().slice(0, 10);
}

export type FatiaAtm = { rotulo: string; quantidade: number };

/** Distribuição de um campo no conjunto (sem teste), na ordem de quantidade. O rótulo é o valor exato da fonte. */
export function distribuicaoAtm<T extends { teste: boolean }>(itens: readonly T[], valor: (item: T) => string): FatiaAtm[] {
  const contagem = new Map<string, number>();
  for (const item of itens) {
    if (item.teste) continue;
    const k = valor(item);
    contagem.set(k, (contagem.get(k) ?? 0) + 1);
  }
  return [...contagem.entries()].map(([rotulo, quantidade]) => ({ rotulo, quantidade })).sort((a, b) => b.quantidade - a.quantidade);
}
