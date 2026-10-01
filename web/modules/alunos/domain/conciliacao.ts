// Conciliação da base de alunos: tradução dos códigos de public.fn_aluno_conciliacao (20261003e).
//
// A regra mora SÓ no SQL. Aqui ficam os rótulos, o destino de cada item na ficha, a ordem e a
// contagem. A RPC não devolve nome, e-mail nem documento: tudo o que chega é código, id e data.
import type { AbaFicha } from './ficha-aluno-abas';
import { SITUACAO } from './aluno-360';

// Ligada por padrão; NEXT_PUBLIC_ALUNO_CONCILIACAO=off desliga a aba, o contador e os itens na ficha
// (inlined no build — desligar pede rebuild).
export const CONCILIACAO_ATIVA = process.env.NEXT_PUBLIC_ALUNO_CONCILIACAO !== 'off';

export type GrupoConciliacao = 'vinculo' | 'identidade' | 'programa' | 'cadastro' | 'acesso' | 'fora_base';
export type Severidade = 'alta' | 'media' | 'baixa' | 'info';
export type DecisaoConciliacao = 'conferido' | 'pessoas_diferentes' | 'manter_sem_acesso';

export interface ItemConciliacao {
  /** Chave estável do item (md5 no SQL). Par de sócios = 2 linhas com o mesmo item, uma por lado. */
  item: string;
  /** Nulo = item sem aluno (comprador, usuário do SIP, placa). */
  aluno_id: string | null;
  /** O outro lado (par, cadeia, duplicado). */
  ref_aluno_id: string | null;
  /** Id não pessoal do que está fora da base; os dados só vêm por fn_aluno_conciliacao_ref, 1× por clique. */
  ref_externa: string | null;
  grupo: GrupoConciliacao | string;
  tipo: string;
  severidade: Severidade | string;
  acao: string;
  detalhe: Record<string, unknown>;
  conferido: boolean;
  /** Id da decisão vigente (bigint no banco, número aqui); nulo = item aberto. É o que o "Desfazer" passa. */
  decisao_id: number | null;
}

export const GRUPOS: readonly GrupoConciliacao[] = ['vinculo', 'identidade', 'programa', 'cadastro', 'acesso', 'fora_base'];

export const ROTULO_GRUPO: Record<GrupoConciliacao, string> = {
  vinculo: 'Vínculo de sócio',
  identidade: 'Identidade',
  programa: 'Programa',
  cadastro: 'Cadastro',
  acesso: 'Acesso',
  fora_base: 'Fora da base',
};

export const SEVERIDADES: readonly Severidade[] = ['alta', 'media', 'baixa', 'info'];
export const ROTULO_SEVERIDADE: Record<Severidade, string> = { alta: 'Alta', media: 'Média', baixa: 'Baixa', info: 'Informativo' };
const RANK_SEVERIDADE: Record<string, number> = { alta: 0, media: 1, baixa: 2, info: 3 };

export const ROTULO_TIPO: Record<string, string> = {
  socio_par_mutuo: 'Titular e sócio apontam um para o outro',
  socio_cadeia: 'Sócio ligado a quem também é sócio',
  socio_sem_vinculo: 'Marcado como sócio, sem titular ligado',
  vinculo_sem_marcacao: 'Ligado a um titular, mas não marcado como sócio',
  socio_diverge_titular: 'Cadastro diferente do titular',
  possivel_duplicado: 'Possível cadastro duplicado',
  conflito_identidade: 'E-mail e documento apontam para pessoas diferentes',
  email_vazio: 'Sem e-mail',
  programa_a_revisar: 'Programa a revisar',
  sem_programa: 'Titular sem programa identificado',
  gps_divergente: 'GPS diferente do cadastro',
  card_hm_aluno_cancelado: 'Card de HM de aluno cancelado',
  cadastro_incoerente: 'Cadastro incoerente',
  datas_incoerentes: 'Datas incoerentes',
  // Só status sem_acesso/acessos_revogados com vigência em dia ou a vencer; tratamento_manual não é revogação.
  revogado_com_vigencia: 'Marcado sem acesso ou com acessos revogados, com vigência em dia',
  situacao_desatualizada: 'Situação de acesso desatualizada',
  // Pagou programa (sinal/reserva sozinho não conta) nos últimos 12 meses e não tem aluno ativo.
  comprou_fora_da_base: 'Pagou programa e não tem aluno ativo',
  comprou_em_ativacao: 'Pagou programa, sem aluno ativo, com card na Ativação',
  sip_sem_aluno: 'Usuário do SIP sem aluno correspondente',
  placa_sem_aluno: 'Solicitação de placa sem aluno',
};

export const ROTULO_ACAO: Record<string, string> = {
  definir_titular: 'Definir quem é o titular',
  confirmar_papel: 'Confirmar se é sócio ou titular',
  alinhar_ao_titular: 'Alinhar ao cadastro do titular',
  conferir_duplicado: 'Conferir se é a mesma pessoa (não unir cadastros)',
  revisar_identidade: 'Revisar a identidade no Financeiro',
  preencher_email: 'Preencher o e-mail',
  ver_evidencias: 'Conferir as compras do aluno no Financeiro',
  confirmar_se_aluno: 'Confirmar se é aluno',
  alinhar_ao_gps: 'Alinhar o cadastro ao GPS',
  avisar_ativacao: 'Avisar a equipe de Ativação',
  corrigir_cadastro: 'Corrigir o cadastro',
  corrigir_datas: 'Corrigir as datas',
  decidir_acesso: 'Decidir se mantém sem acesso',
  aguarda_rotina: 'Aguarda a atualização automática',
  cadastrar_aluno: 'Reenviar a notificação da venda no painel da Hotmart; se não funcionar, cadastrar como novo aluno',
  corrigir_email_sip: 'Corrigir o e-mail no SIP',
  vincular_placa: 'Ligar a solicitação ao aluno',
};

/** Tipos que a tela de vínculo ("Definir quem é o titular") resolve. */
export const TIPOS_VINCULO_TITULAR: readonly string[] = ['socio_par_mutuo', 'socio_cadeia', 'socio_sem_vinculo', 'vinculo_sem_marcacao'];

/** Tipos que cobrem a pendência "Sócio sem titular informado" da ficha (a da ficha some quando um deles existe). */
export const TIPOS_COBREM_SOCIO_SEM_TITULAR: readonly string[] = ['socio_par_mutuo', 'socio_cadeia', 'socio_sem_vinculo'];

/** Códigos de `detalhe` (campos[], motivos[], sinais[]) em português. Código desconhecido: sublinhado vira espaço. */
const ROTULO_CODIGO: Record<string, string> = {
  aurum_sem_turma: 'Aurum sem turma Aurum',
  turma_aurum_sem_aurum: 'turma Aurum sem ser Aurum',
  espaco_aurum_plano_aluno: 'espaço Aurum com plano de aluno',
  sem_espaco: 'sem espaço de instrução',
  sem_turma: 'sem turma',
  plano: 'plano',
  espaco: 'espaço',
  espaco_instrucao: 'espaço',
  turma: 'turma',
  doc: 'mesmo documento',
  documento: 'mesmo documento',
  fone: 'mesmo telefone',
  telefone: 'mesmo telefone',
  pessoa_chave: 'mesma pessoa no Financeiro',
  sem_acesso: 'status sem acesso',
  acessos_revogados: 'status acessos revogados',
};

export const rotuloCodigo = (c: string): string => ROTULO_CODIGO[c] ?? c.replace(/_/g, ' ');
export const rotuloTipo = (t: string): string => ROTULO_TIPO[t] ?? t.replace(/_/g, ' ');
export const rotuloAcao = (a: string): string => ROTULO_ACAO[a] ?? a.replace(/_/g, ' ');
export const rotuloGrupo = (g: string): string => ROTULO_GRUPO[g as GrupoConciliacao] ?? g.replace(/_/g, ' ');
export const rotuloSeveridade = (s: string): string => ROTULO_SEVERIDADE[s as Severidade] ?? s;

const lista = (v: unknown): string[] => (Array.isArray(v) ? v.filter((x): x is string => typeof x === 'string') : []);
// situacao_desatualizada manda {situacao, status}; revogado_com_vigencia manda a situação crua.
const situacao = (v: unknown): string => {
  const s = v && typeof v === 'object' ? (v as Record<string, unknown>).situacao : v;
  return typeof s === 'string' ? SITUACAO[s]?.label ?? s : '—';
};
const dataBr = (v: unknown): string | null => {
  const m = typeof v === 'string' ? /^(\d{4})-(\d{2})-(\d{2})/.exec(v) : null;
  return m ? `${m[3]}/${m[2]}/${m[1]}` : null;
};

/** Resumo do `detalhe` numa linha, só com o que a tela sabe traduzir. Chave desconhecida é ignorada. */
export function resumoDetalhe(it: Pick<ItemConciliacao, 'detalhe'>, rotuloMotivo: (m: string) => string = rotuloCodigo): string {
  const d = it.detalhe || {};
  const partes: string[] = [];
  const campos = lista(d.campos);
  if (campos.length) partes.push(campos.map(rotuloCodigo).join(', '));
  const motivos = lista(d.motivos);
  if (motivos.length) partes.push(motivos.map(rotuloCodigo).join(', '));
  if (typeof d.motivo === 'string') partes.push(ROTULO_CODIGO[d.motivo] ?? rotuloMotivo(d.motivo));
  if ('gravado' in d || 'calculado' in d) partes.push(`gravado ${situacao(d.gravado)}, calculado ${situacao(d.calculado)}`);
  if (d.tem_nome_titular === true) partes.push('tem o nome do titular no cadastro');
  const paga = dataBr(d.ultima_paga_em);
  if (paga) partes.push(`última compra paga em ${paga}`);
  return partes.join(' · ');
}

/** Aba da ficha onde o item se resolve: identidade → Resumo; placa → Jornada; o resto → Programa. */
export function abaDoItem(it: Pick<ItemConciliacao, 'grupo' | 'tipo'>): Extract<AbaFicha, 'resumo' | 'programa' | 'jornada'> {
  if (it.tipo === 'placa_sem_aluno') return 'jornada';
  if (it.grupo === 'identidade' || it.grupo === 'fora_base') return 'resumo';
  return 'programa';
}

/** Decisões oferecidas ao marcar: as mesmas que fn_aluno_conciliacao_marcar aceita (pessoas_diferentes só em
 *  possivel_duplicado; manter_sem_acesso só em revogado_com_vigencia; conferido em todos). */
export function decisoesDoTipo(tipo: string): DecisaoConciliacao[] {
  if (tipo === 'possivel_duplicado') return ['conferido', 'pessoas_diferentes'];
  if (tipo === 'revogado_com_vigencia') return ['conferido', 'manter_sem_acesso'];
  return ['conferido'];
}
export const ROTULO_DECISAO: Record<DecisaoConciliacao, string> = {
  conferido: 'Conferido, está certo assim',
  pessoas_diferentes: 'São pessoas diferentes',
  manter_sem_acesso: 'Manter sem acesso',
};

/** bigint do PostgREST: número (ou texto, se o servidor serializar assim). Qualquer outra coisa = nulo. */
export function bigintNum(v: unknown): number | null {
  const n = typeof v === 'number' ? v : typeof v === 'string' && /^\d+$/.test(v) ? Number(v) : NaN;
  return Number.isSafeInteger(n) ? n : null;
}

/** Linha crua da RPC → item. Linha sem `item` ou `tipo` é descartada (não inventa pendência). */
export function normalizarItens(linhas: unknown[]): ItemConciliacao[] {
  const out: ItemConciliacao[] = [];
  for (const l of linhas) {
    if (!l || typeof l !== 'object') continue;
    const r = l as Record<string, unknown>;
    if (typeof r.item !== 'string' || typeof r.tipo !== 'string') continue;
    const str = (v: unknown) => (typeof v === 'string' && v ? v : null);
    out.push({
      item: r.item,
      aluno_id: str(r.aluno_id),
      ref_aluno_id: str(r.ref_aluno_id),
      ref_externa: str(r.ref_externa),
      grupo: String(r.grupo ?? ''),
      tipo: r.tipo,
      severidade: String(r.severidade ?? 'baixa'),
      acao: String(r.acao ?? ''),
      detalhe: r.detalhe && typeof r.detalhe === 'object' && !Array.isArray(r.detalhe) ? (r.detalhe as Record<string, unknown>) : {},
      conferido: r.conferido === true,
      decisao_id: bigintNum(r.decisao_id),
    });
  }
  return out;
}

/** Severidade (alta primeiro) → grupo na ordem de GRUPOS → tipo. Estável para o resto. */
export function ordenarItens<T extends Pick<ItemConciliacao, 'severidade' | 'grupo' | 'tipo'>>(itens: T[]): T[] {
  const g = (x: string) => { const i = GRUPOS.indexOf(x as GrupoConciliacao); return i < 0 ? 99 : i; };
  return [...itens].sort((a, b) =>
    (RANK_SEVERIDADE[a.severidade] ?? 9) - (RANK_SEVERIDADE[b.severidade] ?? 9)
    || g(a.grupo) - g(b.grupo)
    || a.tipo.localeCompare(b.tipo));
}

/** Uma linha por item: o par de sócios chega em 2 linhas (uma por lado) e na lista aparece uma vez. */
export function umaLinhaPorItem(itens: ItemConciliacao[]): ItemConciliacao[] {
  const vistos = new Set<string>();
  return itens.filter((i) => (vistos.has(i.item) ? false : (vistos.add(i.item), true)));
}

export interface Contagem { itens: number; alunos: number; conferidos: number }

/**
 * Resumo da conciliação no cliente (substitui fn_aluno_conciliacao_resumo, que reexecutaria a função inteira):
 * por grupo, tipo e severidade, itens distintos EM ABERTO (o par conta 1), alunos distintos em aberto e itens
 * distintos conferidos.
 */
export function contar(itens: ItemConciliacao[]): {
  total: Contagem; grupo: Record<string, Contagem>; tipo: Record<string, Contagem>; severidade: Record<string, Contagem>;
} {
  const acc = new Map<string, { itens: Set<string>; alunos: Set<string>; conferidos: Set<string> }>();
  const add = (k: string, it: ItemConciliacao) => {
    let e = acc.get(k);
    if (!e) acc.set(k, (e = { itens: new Set(), alunos: new Set(), conferidos: new Set() }));
    if (it.conferido) { e.conferidos.add(it.item); return; }
    e.itens.add(it.item);
    if (it.aluno_id) e.alunos.add(it.aluno_id);
  };
  for (const it of itens) { add('*', it); add(`g:${it.grupo}`, it); add(`t:${it.tipo}`, it); add(`s:${it.severidade}`, it); }
  const c = (k: string): Contagem => {
    const e = acc.get(k);
    return { itens: e?.itens.size ?? 0, alunos: e?.alunos.size ?? 0, conferidos: e?.conferidos.size ?? 0 };
  };
  const grupo: Record<string, Contagem> = {};
  const tipo: Record<string, Contagem> = {};
  const severidade: Record<string, Contagem> = {};
  for (const k of acc.keys()) {
    if (k.startsWith('g:')) grupo[k.slice(2)] = c(k);
    else if (k.startsWith('t:')) tipo[k.slice(2)] = c(k);
    else if (k.startsWith('s:')) severidade[k.slice(2)] = c(k);
  }
  return { total: c('*'), grupo, tipo, severidade };
}

/** Aplica ao estado local o efeito de marcar/desmarcar (todas as linhas do item: o par tem 2). */
export function aplicarDecisao(itens: ItemConciliacao[], item: string, conferido: boolean, decisaoId: number | null): ItemConciliacao[] {
  return itens.map((i) => (i.item === item ? { ...i, conferido, decisao_id: decisaoId } : i));
}

/** Itens em aberto por aluno (conferidos ficam de fora). Montado 1× por carga; a ficha só consulta o mapa. */
export function indexarPorAluno(itens: ItemConciliacao[]): Map<string, ItemConciliacao[]> {
  const m = new Map<string, ItemConciliacao[]>();
  for (const it of itens) {
    if (!it.aluno_id || it.conferido) continue;
    const l = m.get(it.aluno_id);
    if (l) l.push(it); else m.set(it.aluno_id, [it]);
  }
  return m;
}

/** Contador da aba de topo: itens distintos em aberto de severidade alta (é o recorte com que a área abre). */
export function contarAbertosAlta(itens: ItemConciliacao[]): number {
  return new Set(itens.filter((i) => !i.conferido && i.severidade === 'alta').map((i) => i.item)).size;
}
