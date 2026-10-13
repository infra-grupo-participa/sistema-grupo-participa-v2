// Listas de disparo da Black (Fase 1, decisões do Victor de 13/10; desenho em docs/dashboard-black/README.md, seção
// "Listas para disparo"). Puro: sem rede, sem React. Quem decide quem entra em cada lista é o banco
// (dados.black_lista, migration 20261013180931); aqui ficam só os presets da tela, o CSV e o nome do arquivo.

export type ListaId = 'live_consultoria' | 'fora_grupo' | 'sairam_grupo';
export type Segmento = 'geral' | 'advogado' | 'contador' | 'outros';
export type SituacaoGrupo = 'no_grupo' | 'saiu' | 'nunca';

export interface PresetLista {
  id: ListaId;
  nome: string;
  /** Uma linha: para que serve. */
  paraQue: string;
  /** Nome curto no arquivo: black_<arquivo>[_<segmento>]_AAAA-MM-DD_HHhMM.csv */
  arquivo: string;
  segmentos: readonly Segmento[];
  /** Colunas a mais no CSV principal, além de Nome, Email e Telefone. */
  extras: readonly ('grupo_saida' | 'segmento')[];
  aviso?: string;
}

export const LISTAS: readonly PresetLista[] = [
  {
    id: 'live_consultoria', nome: 'Live de consultoria', arquivo: 'live-consultoria',
    paraQue: 'Todo mundo: captação, isca, consultoria (página e Respondi) e os dois grupos. Disparo de terça e quinta.',
    segmentos: ['geral'], extras: [],
  },
  {
    id: 'fora_grupo', nome: 'Fora do grupo da Black', arquivo: 'fora-do-grupo',
    paraQue: 'Convite para entrar no grupo da Black. Quem saiu do grupo também está aqui.',
    segmentos: ['geral', 'advogado', 'contador', 'outros'], extras: [],
    aviso: 'Fora do grupo = sem registro de entrada no grupo da Black. Não é certeza de que a pessoa não entrou.',
  },
  {
    id: 'sairam_grupo', nome: 'Saíram do grupo', arquivo: 'sairam-do-grupo',
    paraQue: 'Quem entrou e saiu do grupo da Black ou do da consultoria, com o grupo de onde saiu.',
    segmentos: ['geral', 'advogado', 'contador', 'outros'], extras: ['grupo_saida', 'segmento'],
  },
];

export const ROTULO_SEGMENTO: Record<Segmento, string> = {
  geral: 'Geral', advogado: 'Advogado', contador: 'Contador', outros: 'Outros',
};
/** Advogado inclui estudante de direito; Outros inclui quem não tem profissão (decisão do Victor, 13/10). */
export const DICA_SEGMENTO: Record<Segmento, string> = {
  geral: 'Todos os segmentos',
  advogado: 'Advogado e estudante de direito',
  contador: 'Contador',
  outros: 'Outra profissão e quem não tem profissão (só entrou no grupo, sem formulário)',
};
export const ROTULO_SITUACAO: Record<SituacaoGrupo, string> = { no_grupo: 'No grupo', saiu: 'Saiu', nunca: 'Fora' };
export const ROTULO_FONTE: Record<string, string> = {
  captacao: 'Captação', isca: 'Isca', pagina_consultoria: 'Página da consultoria', respondi_consultoria: 'Respondi da consultoria',
  grupo_black: 'Grupo da Black', grupo_consultoria: 'Grupo da consultoria',
};

export interface PessoaLista {
  nome: string | null;
  email: string | null;
  telefone: string | null;
  telefoneComoVeio: string | null;
  motivo: string | null;
  segmento: Exclude<Segmento, 'geral'>;
  semProfissao: boolean;
  grupoBlack: SituacaoGrupo;
  grupoConsultoria: SituacaoGrupo;
  saiuBlackDe: string | null;
  saiuConsultoriaDe: string | null;
  fontes: string[];
}

/** "Black: <subgrupo>; Consultoria: <subgrupo>" (só os grupos de onde a pessoa saiu). */
export function grupoSaida(p: PessoaLista): string {
  const partes: string[] = [];
  if (p.grupoBlack === 'saiu') partes.push(`Black: ${p.saiuBlackDe ?? 'grupo da Black'}`);
  if (p.grupoConsultoria === 'saiu') partes.push(`Consultoria: ${p.saiuConsultoriaDe ?? 'grupo da consultoria'}`);
  return partes.join('; ');
}

/** Escape de CSV (vírgula como separador): aspas em volta quando há vírgula, ponto e vírgula, aspas ou quebra de linha. */
export function celula(v: unknown): string {
  const s = String(v ?? '');
  return /[",;\n\r]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
}

/** BOM: sem ele o Excel abre o acento quebrado. */
export const BOM = '﻿';

export function csvPrincipal(preset: PresetLista, linhas: readonly PessoaLista[]): string {
  const cab = ['Nome', 'Email', 'Telefone'];
  if (preset.extras.includes('grupo_saida')) cab.push('Grupo de onde saiu');
  if (preset.extras.includes('segmento')) cab.push('Segmento');
  const corpo = linhas.map((p) => {
    const l: unknown[] = [p.nome, p.email, p.telefone];
    if (preset.extras.includes('grupo_saida')) l.push(grupoSaida(p));
    if (preset.extras.includes('segmento')) l.push(ROTULO_SEGMENTO[p.segmento]);
    return l.map(celula).join(',');
  });
  return BOM + [cab.join(','), ...corpo].join('\r\n');
}

/** Arquivo à parte: telefone fora do padrão (DDI estrangeiro, número quebrado, sem o 9, sem telefone), com o motivo. */
export function csvForaPadrao(linhas: readonly PessoaLista[]): string {
  const corpo = linhas.map((p) => [p.nome, p.email, p.telefoneComoVeio ?? p.telefone, p.motivo].map(celula).join(','));
  return BOM + [['Nome', 'Email', 'Telefone (como veio)', 'Motivo'].join(','), ...corpo].join('\r\n');
}

/** black_<lista>[_<segmento>][_fora-do-padrao]_AAAA-MM-DD_HHhMM.csv, no horário de Brasília. */
export function nomeArquivo(preset: PresetLista, segmento: Segmento, agora: Date, foraPadrao = false): string {
  const p = Object.fromEntries(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23',
  }).formatToParts(agora).map((x) => [x.type, x.value]));
  const seg = segmento === 'geral' ? '' : `_${segmento}`;
  return `black_${preset.arquivo}${seg}${foraPadrao ? '_fora-do-padrao' : ''}_${p.year}-${p.month}-${p.day}_${p.hour}h${p.minute}.csv`;
}

/** Busca da gaveta: nome, e-mail ou telefone (só dígitos), sem acento e sem caixa. */
export function filtrarBusca(linhas: readonly PessoaLista[], termo: string): PessoaLista[] {
  const norm = (s: string) => s.normalize('NFD').replace(/\p{Mn}/gu, '').toLowerCase();
  const t = norm(termo.trim());
  if (!t) return [...linhas];
  const dig = t.replace(/\D/g, '');
  return linhas.filter((p) =>
    norm(p.nome ?? '').includes(t) || norm(p.email ?? '').includes(t) || (dig.length >= 3 && (p.telefone ?? p.telefoneComoVeio ?? '').includes(dig)));
}

/** "há 3 min", "há 2 h", "agora". */
export function haQuanto(de: Date | null, agora: Date): string {
  if (!de) return 'sem horário';
  const min = Math.max(0, Math.floor((agora.getTime() - de.getTime()) / 60000));
  if (min < 1) return 'agora';
  if (min < 60) return `há ${min} min`;
  return `há ${Math.floor(min / 60)} h`;
}
