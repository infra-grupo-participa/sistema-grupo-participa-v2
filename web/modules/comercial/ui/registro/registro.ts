// Regras puras do Registro do CRM: quem vê o quê, filtros da tela, agrupamento por dia, números e CSV.
import type { AcaoLog, EntidadeLog, LogCrm } from '../../domain/types';
import { diaSP, difDias } from '../atividades/agenda';

// ── Rótulos ──

export const ACAO: Record<AcaoLog, { verbo: string; icone: string }> = {
  criou: { verbo: 'Criou', icone: 'plus' },
  editou: { verbo: 'Editou', icone: 'pencil' },
  moveu_etapa: { verbo: 'Moveu de etapa', icone: 'arrow-right' },
  trocou_dono: { verbo: 'Trocou o dono', icone: 'users' },
  marcou_perdido: { verbo: 'Marcou perdido', icone: 'x' },
  marcou_ganho: { verbo: 'Marcou ganho', icone: 'trophy' },
  arquivou: { verbo: 'Arquivou', icone: 'inbox' },
  excluiu: { verbo: 'Excluiu', icone: 'trash' },
  concluiu: { verbo: 'Concluiu', icone: 'check-circle' },
  agendou: { verbo: 'Agendou', icone: 'calendar' },
  atribuiu: { verbo: 'Atribuiu', icone: 'user-check' },
  enviou: { verbo: 'Enviou', icone: 'send' },
  aprovou: { verbo: 'Aprovou', icone: 'check' },
  reprovou: { verbo: 'Reprovou', icone: 'alert' },
  vinculou: { verbo: 'Vinculou', icone: 'link' },
  desvinculou: { verbo: 'Desvinculou', icone: 'user-x' },
  importou: { verbo: 'Importou', icone: 'download' },
};

export const ENTIDADE: Record<EntidadeLog, string> = {
  negocio: 'Negócio', contato: 'Contato', atividade: 'Atividade', mensagem: 'Mensagem', nota: 'Nota', funil: 'Funil',
  agrupador: 'Agrupador', projeto: 'Projeto', motivo: 'Motivo de perda', ficha: 'Ficha de disparo', fila: 'Fila de recuperação',
  produto: 'Produto', oferta: 'Oferta', distribuicao: 'Distribuição', link: 'Link rastreável', dashboard: 'Dashboard',
  painel: 'Painel', preferencias: 'Preferências', conversa: 'Conversa',
};

/** Nome de quem fez: "Sistema" quando foi integração/rotina (autorId null). */
export function nomeAutor(autorId: string | null, nomeDe: (id: string | null) => string): string {
  return autorId == null ? 'Sistema' : nomeDe(autorId);
}

// ── Quem vê o quê ──
// A regra mora no banco (public.crm_log + policy crm.log.log_ler, migration 20261008001436): gestor vê tudo; vendedor vê
// o que fez, os contatos que pode ver (dele, sem dono ou de negócio dele) e os negócios de que é dono. A tela não recorta.

// ── Páginas (limite e cursor no servidor) ──

/** Linhas por página pedidas ao banco (o banco não devolve mais que isso). */
export const LIMITE_PAGINA = 500;

/** Junta a página mais recente com as mais antigas já carregadas, sem repetir linha (a mais recente vence). */
export function juntarPaginas(recente: LogCrm[], antigas: LogCrm[]): LogCrm[] {
  const ids = new Set(recente.map((l) => l.id));
  return [...recente, ...antigas.filter((l) => !ids.has(l.id))];
}

/** Aviso de corte: só quando a última página veio cheia (pode haver mais antigas no banco). */
export function avisoLimite(total: number, temMais: boolean): string | null {
  if (!temMais) return null;
  return `Mostrando as ${total.toLocaleString('pt-BR')} alterações mais recentes do período. Os números e os filtros consideram só elas; carregue as anteriores para ver mais.`;
}

export const REGRA_VISIBILIDADE = {
  gestor: 'Você é gestor: vê todas as alterações do CRM, de todas as pessoas e do sistema.',
  vendedor: 'Você vê o que você fez, o que tocou os seus contatos e negócios (inclusive o que outra pessoa ou o sistema fez neles) e os contatos sem dono.',
  leitor: 'Acesso só de leitura: você vê todas as alterações do CRM, de todas as pessoas e do sistema, sem alterar nada.',
};

// ── Filtros da tela ──

export type PeriodoLog = 'hoje' | '7d' | '30d' | '90d' | 'tudo';
export const PERIODOS: { valor: PeriodoLog; rotulo: string }[] = [
  { valor: 'hoje', rotulo: 'Hoje' }, { valor: '7d', rotulo: '7 dias' }, { valor: '30d', rotulo: '30 dias' },
  { valor: '90d', rotulo: '90 dias' }, { valor: 'tudo', rotulo: 'Tudo' },
];

/** Início do período (ISO). Dias contados no fuso de Brasília (UTC−3). undefined = sem limite. */
export function inicioDoPeriodo(p: PeriodoLog, agora: Date): string | undefined {
  if (p === 'tudo') return undefined;
  const dias = p === 'hoje' ? 0 : p === '7d' ? 6 : p === '30d' ? 29 : 89;
  const [y, m, d] = diaSP(agora).split('-').map(Number);
  // Meia-noite em Brasília = 03:00 UTC.
  return new Date(Date.UTC(y, m - 1, d - dias, 3)).toISOString();
}

/** '' = todas as pessoas; 'sistema' = só o que o sistema fez; senão o id do vendedor. */
export type FiltroAutor = '' | 'sistema' | string;

export interface FiltroTela {
  periodo: PeriodoLog;
  autor: FiltroAutor;
  acao: AcaoLog | '';
  entidade: EntidadeLog | '';
  busca: string;
}

export const FILTRO_INICIAL: FiltroTela = { periodo: '7d', autor: '', acao: '', entidade: '', busca: '' };

const normalizar = (s: string) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().trim();

export function filtrarLog(logs: LogCrm[], f: FiltroTela, agora: Date): LogCrm[] {
  const desde = inicioDoPeriodo(f.periodo, agora);
  const termo = normalizar(f.busca);
  return logs.filter((l) =>
    (!desde || l.em >= desde)
    && (f.autor === '' || (f.autor === 'sistema' ? l.autorId == null : l.autorId === f.autor))
    && (!f.acao || l.acao === f.acao)
    && (!f.entidade || l.entidade === f.entidade)
    && (!termo || normalizar(l.resumo).includes(termo)));
}

export interface ChipFiltro {
  chave: keyof FiltroTela;
  rotulo: string;
}

/** Filtros aplicados (fora o período, que está sempre visível no seletor). */
export function chipsAtivos(f: FiltroTela, nomeDe: (id: string | null) => string): ChipFiltro[] {
  const c: ChipFiltro[] = [];
  if (f.autor) c.push({ chave: 'autor', rotulo: `Pessoa: ${f.autor === 'sistema' ? 'Sistema' : nomeDe(f.autor)}` });
  if (f.acao) c.push({ chave: 'acao', rotulo: `Ação: ${ACAO[f.acao].verbo}` });
  if (f.entidade) c.push({ chave: 'entidade', rotulo: `Entidade: ${ENTIDADE[f.entidade]}` });
  if (f.busca.trim()) c.push({ chave: 'busca', rotulo: `Busca: “${f.busca.trim()}”` });
  return c;
}

// ── Linha do tempo ──

export interface GrupoDia {
  dia: string;
  titulo: string;
  itens: LogCrm[];
}

/** "Hoje", "Ontem" ou a data por extenso (fuso de Brasília). */
export function tituloDia(dia: string, hoje: string): string {
  const d = difDias(hoje, dia);
  if (d === 0) return 'Hoje';
  if (d === -1) return 'Ontem';
  const [y, m, dd] = dia.split('-').map(Number);
  return new Date(y, m - 1, dd).toLocaleDateString('pt-BR', { weekday: 'long', day: 'numeric', month: 'long', year: y === Number(hoje.slice(0, 4)) ? undefined : 'numeric' });
}

/** Agrupa por dia, mais recente primeiro (dias e itens). */
export function agruparPorDia(logs: LogCrm[], agora: Date): GrupoDia[] {
  const hoje = diaSP(agora);
  const mapa = new Map<string, LogCrm[]>();
  [...logs].sort((a, b) => b.em.localeCompare(a.em)).forEach((l) => {
    const d = diaSP(l.em);
    const lista = mapa.get(d);
    if (lista) lista.push(l); else mapa.set(d, [l]);
  });
  return [...mapa.entries()].sort((a, b) => b[0].localeCompare(a[0])).map(([dia, itens]) => ({ dia, titulo: tituloDia(dia, hoje), itens }));
}

/** Hora HH:MM em Brasília. */
export function horaLog(em: string): string {
  return new Date(em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
}

// ── Números ──

export interface NumerosRegistro {
  alteracoes: number;
  pessoas: number;
  negociosMovidos: number;
  perdas: number;
}

export function numerosRegistro(logs: LogCrm[]): NumerosRegistro {
  return {
    alteracoes: logs.length,
    pessoas: new Set(logs.filter((l) => l.autorId != null).map((l) => l.autorId)).size,
    negociosMovidos: new Set(logs.filter((l) => l.acao === 'moveu_etapa').map((l) => l.entidadeId)).size,
    perdas: logs.filter((l) => l.acao === 'marcou_perdido').length,
  };
}

// ── CSV ──

const celula = (v: string | null | undefined) => {
  const s = v ?? '';
  return /[;"\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
};

/** CSV com ";" (abre direto no Excel em pt-BR) e BOM para os acentos. Uma linha por registro. */
export function gerarCsv(logs: LogCrm[], nomeDe: (id: string | null) => string): string {
  const cab = ['data_hora', 'autor', 'acao', 'entidade', 'entidade_id', 'contato_id', 'resumo', 'mudancas'];
  const linhas = logs.map((l) => [
    new Date(l.em).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo' }),
    nomeAutor(l.autorId, nomeDe),
    ACAO[l.acao]?.verbo ?? l.acao,
    ENTIDADE[l.entidade] ?? l.entidade,
    l.entidadeId,
    l.contatoId,
    l.resumo,
    l.mudancas.map((m) => `${m.campo}: ${m.antes ?? '—'} → ${m.depois ?? '—'}`).join(' | '),
  ].map(celula).join(';'));
  return '﻿' + [cab.join(';'), ...linhas].join('\r\n');
}

export function nomeArquivoCsv(agora: Date): string {
  return `registro-crm-${diaSP(agora)}.csv`;
}
