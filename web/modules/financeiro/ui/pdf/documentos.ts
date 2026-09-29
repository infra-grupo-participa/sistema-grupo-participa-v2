// Mapeadores dos 7 relatórios do Financeiro para o modelo neutro do PDF.
//
// Regras:
//  - Recebem a LISTA JÁ FILTRADA da tela (a mesma do CSV/Excel) — nenhuma busca nova.
//  - Só DECLARAM o que cada coluna é (pii). Quem corta dado pessoal é aplicarNivel()
//    em shared/ui/pdf/nivel.ts; aqui nenhum mapeador decide nível.
//  - Formatação = a da tela (fmtBRL/fmtBRLc/fmtData, ROTULO_SITUACAO, statusLabel,
//    formatarCelulaTela, rotuloDocumento…), para o papel dizer o mesmo que a tela.
//  - KPIs e resumos são calculados sobre a lista recebida (o recorte impresso), não
//    sobre a base inteira: o documento declara o recorte no cabeçalho.
//  - Sem protocolo: o protocolo nasce na emissão (gerarPdfComProtocolo).
import type {
  ClassePii, ColunaPdf, ItemRecorte, KpiPdf, LinhaPdf, NivelPii, RascunhoRelatorio, SecaoPdf, TipoRelatorioPdf,
} from '@/shared/ui/pdf/modelo';
import { fmtBRL, fmtBRLc, fmtData } from '@/shared/ui/format';
import type { ContaReceber } from '../../domain/types';
import { agrupar, statusLabel } from '../../domain/financeiro';
import { calcularTotais } from '../../domain/totais';
import {
  ORDEM_SITUACAO, ROTULO_FAMILIA, ROTULO_SITUACAO, rotuloDocumento,
  type AceleraParaHM, type DivergenciaHotmart, type FamiliaHotmart, type IdentidadeRevisao,
  type PessoaHotmart, type ProrataHM, type SituacaoPessoa,
} from '../../domain/hotmart';
import type { DatasetRelatorio } from '../../application/montar-relatorio';
import { formatarCelulaTela } from '../exportar';
import { MOTIVO_SUGESTAO, ROTULO_DIVERGENCIA, rotuloEvidencia } from '../hotmart/rotulos';
import type { ContasReceberCarregado } from '../../application/carregar-contas-receber';
import { BLOCO_INFORMATIVO } from '../../domain/contas-receber';
import {
  FILTRO_BASE_PADRAO, fatorCsv, filtrarBase, pseudonimizadorBase, resumoCentroMes, rotuloSemanaDaLinha, somarBase,
} from '../receber/base-auditavel';
import { rotuloBloco, rotuloComponente, rotuloMes, rotuloSituacaoLinha } from '../receber/rotulos-receber';
import { CENARIO_RECEBER } from '../receber/textos';

/** Níveis aceitos por relatório — fonte única para o rascunho E para o seletor do botão. */
export const NIVEIS_RELATORIO: Record<TipoRelatorioPdf, NivelPii[]> = {
  board: ['completo', 'sem_dado_pessoal', 'so_numeros'],
  pessoas: ['completo', 'sem_dado_pessoal', 'so_numeros'],
  conciliacao: ['completo', 'sem_dado_pessoal', 'so_numeros'],
  // Ferramenta de auditoria interna: não existe versão anonimizada (decisão do Marcio).
  identidade: ['completo'],
  acelera: ['completo', 'sem_dado_pessoal', 'so_numeros'],
  prorata: ['completo', 'sem_dado_pessoal', 'so_numeros'],
  receber: ['completo', 'sem_dado_pessoal', 'so_numeros'],
};

const n = (v: unknown) => Number(v ?? 0) || 0;
const plural = (q: number, um: string, varios: string) => `${q.toLocaleString('pt-BR')} ${q === 1 ? um : varios}`;
const soma = <T>(xs: T[], f: (x: T) => number) => xs.reduce((s, x) => s + f(x), 0);

// ─── 1. Carteira do board ──────────────────────────────────────────────────────

/**
 * Classe de dado pessoal de CADA coluna de COLUNAS_RELATORIO (montar-relatorio.ts).
 * Coluna nova sem entrada aqui é tratada como 'identificacao' (some fora do nível
 * completo) e o teste documentos.test.ts falha até alguém classificá-la.
 */
export const PII_COLUNA_BOARD: Record<string, ClassePii> = {
  nome: 'identificacao', email: 'contato', telefone: 'contato',
  produto: 'nenhuma', canal: 'nenhuma', turma: 'nenhuma', status: 'nenhuma',
  total_pago_bruto: 'nenhuma', total_pago_liquido: 'nenhuma', saldo_a_pagar: 'nenhuma', pacote: 'nenhuma',
  credito: 'nenhuma', vencimento: 'nenhuma', dias_atraso: 'nenhuma', solicitou_cancelamento: 'nenhuma',
  oferta_codigo: 'nenhuma', ultimo_pagamento_em: 'nenhuma',
  hm_pago_bruto: 'nenhuma', hm_taxa_hotmart: 'nenhuma', hm_liquido: 'nenhuma', hm_juros: 'nenhuma',
  hm_parcelamento: 'nenhuma', hm_ultimo_pagamento: 'nenhuma', hm_devido_120: 'nenhuma', hm_diverge: 'nenhuma',
};

const PESO_BOARD: Record<string, number> = { nome: 1.6, email: 1.9, telefone: 1.1, canal: 1.2, status: 1.2, oferta_codigo: 1.1 };

/**
 * A lista da Carteira chega filtrada por PRODUTO e AÇÃO/canal (contasDoRecorte em
 * FinanceiroClient.tsx) — o cabeçalho declara os dois: filtro que encolheu a lista
 * nunca fica escondido (pentest 28/09). `acao` null = nenhuma ação escolhida.
 * Nome de ação é nome de evento/canal, não dado pessoal: vai no recorte gravado.
 * Busca e cor do board NÃO chegam aqui (não filtram a lista do relatório).
 */
export function recorteCarteira(f: { turma: string | null; produto: string; acao: string | null }): ItemRecorte[] {
  return [
    { rotulo: 'Produto', valor: f.produto },
    { rotulo: 'Ação', valor: f.acao ?? 'todas as ações' },
    { rotulo: 'Turma', valor: f.turma ?? 'Todas' },
    { rotulo: 'Base', valor: 'recorte atual do board' },
  ];
}

export function rascunhoCarteira(dataset: DatasetRelatorio, contas: ContaReceber[], recorte: ItemRecorte[]): RascunhoRelatorio {
  const colunas: ColunaPdf[] = dataset.colunas.map((c) => ({
    chave: c.key, rotulo: c.label, tipo: c.tipo, pii: PII_COLUNA_BOARD[c.key] ?? 'identificacao', peso: PESO_BOARD[c.key] ?? 1,
  }));
  const linhas: LinhaPdf[] = dataset.linhas.map((l) => ({
    celulas: Object.fromEntries(dataset.colunas.map((c) => [c.key, formatarCelulaTela(c, l.valores[c.key])])),
  }));
  const moedas = dataset.colunas.filter((c) => c.tipo === 'moeda');
  const total = moedas.length && dataset.linhas.length
    ? {
      [dataset.colunas[0].key]: dataset.colunas[0].tipo === 'moeda' ? '' : 'Total',
      ...Object.fromEntries(moedas.map((c) => [c.key, fmtBRLc(soma(dataset.linhas, (l) => n(l.valores[c.key])))])),
    }
    : undefined;

  const t = calcularTotais(contas);
  const porStatus = agrupar(contas, (c) => statusLabel(c.status_financeiro));
  const resumo: SecaoPdf = {
    titulo: 'Por status', tipo: 'resumo',
    colunas: [
      { chave: 'status', rotulo: 'Status', tipo: 'texto', pii: 'nenhuma', peso: 2 },
      { chave: 'contas', rotulo: 'Contas', tipo: 'numero', pii: 'nenhuma' },
      { chave: 'recebido', rotulo: 'Já pago (bruto)', tipo: 'moeda', pii: 'nenhuma' },
      // mesma regra de "Na rua": saldo efetivo só de conta viva (agrupar() do domínio)
      { chave: 'aReceber', rotulo: 'A receber', tipo: 'moeda', pii: 'nenhuma' },
    ],
    linhas: porStatus.map((f) => ({
      celulas: { status: f.chave, contas: String(f.alunos), recebido: fmtBRL(f.recebido), aReceber: fmtBRL(f.aReceber) },
    })),
    vazio: 'Nenhuma conta neste recorte.',
  };

  return {
    tipo: 'board', titulo: 'Carteira do board', recorte, niveisPermitidos: NIVEIS_RELATORIO.board, arquivo: 'financeiro-carteira-board', temPlanilha: true, // Excel (exportarXLSX) na Carteira
    kpis: [
      { rotulo: 'Contas', valor: contas.length.toLocaleString('pt-BR') },
      { rotulo: 'Valor esperado', valor: fmtBRL(t.esperado) },
      { rotulo: 'Na rua', valor: fmtBRL(t.naRua) },
      { rotulo: 'Em casa', valor: fmtBRL(t.emCasa) },
      { rotulo: 'Perda', valor: fmtBRL(t.perda) },
    ],
    secoes: [
      resumo,
      { titulo: plural(linhas.length, 'conta', 'contas'), tipo: 'detalhe', linhasSaoPessoas: true, colunas, linhas, total, vazio: 'Nenhuma conta neste recorte.' },
    ],
  };
}

// ─── 2. Pessoas na Hotmart ─────────────────────────────────────────────────────

export type FiltroPessoas = SituacaoPessoa | 'avisos' | 'multi' | null;

export function recortePessoas(f: {
  familia: FamiliaHotmart; filtro: FiltroPessoas; de: string; ate: string; busca: string; semCard?: boolean;
}): ItemRecorte[] {
  const itens: ItemRecorte[] = [{ rotulo: 'Família', valor: ROTULO_FAMILIA[f.familia] }];
  if (f.semCard) itens.push({ rotulo: 'Base', valor: 'pagaram na Hotmart e não estão no board' });
  itens.push({
    rotulo: 'Situação',
    valor: f.filtro == null ? 'Todas' : f.filtro === 'avisos' ? 'Com aviso' : f.filtro === 'multi' ? 'Mais de um e-mail' : ROTULO_SITUACAO[f.filtro],
  });
  if (f.de || f.ate) {
    itens.push({ rotulo: '1ª compra', valor: `${f.de ? fmtData(f.de) : 'início'} a ${f.ate ? fmtData(f.ate) : 'hoje'}` });
  }
  if (f.busca.trim()) itens.push({ rotulo: 'Busca', valor: `"${f.busca.trim()}"`, pii: true });
  return itens;
}

function atrasoPessoa(p: PessoaHotmart): string {
  return p.parcelas_atrasadas > 0 ? `${p.parcelas_atrasadas} · ${fmtBRL(n(p.valor_atrasado))}` : '—';
}

function boardPessoa(p: PessoaHotmart): string {
  const card = p.cards > 0 ? `${p.cards} card(s)${p.status_card ? ` · ${p.status_card}` : ''}` : 'sem card';
  return p.turma ? `${card}\n${p.turma}` : card;
}

/** Subconjunto legível das 15 colunas da tela (o CSV continua completo, à parte). */
export function rascunhoPessoas(lista: PessoaHotmart[], recorte: ItemRecorte[]): RascunhoRelatorio {
  const colunas: ColunaPdf[] = [
    { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao', peso: 1.5 },
    { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato', peso: 1.9 },
    { chave: 'documento', rotulo: 'Documento', tipo: 'texto', pii: 'documento', peso: 0.9 },
    { chave: 'telefone', rotulo: 'Telefone', tipo: 'texto', pii: 'contato', peso: 1 },
    { chave: 'situacao', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma', peso: 1.4 },
    { chave: 'primeira', rotulo: '1ª compra', tipo: 'data', pii: 'nenhuma', peso: 0.85 },
    { chave: 'pago', rotulo: 'Pago (bruto)', tipo: 'moeda', pii: 'nenhuma', peso: 0.85 },
    { chave: 'liquido', rotulo: 'Líquido', tipo: 'moeda', pii: 'nenhuma', peso: 0.85 },
    { chave: 'atraso', rotulo: 'Atrasado (120 dias)', tipo: 'moeda', pii: 'nenhuma', peso: 1 },
    { chave: 'ultimo', rotulo: 'Último pagamento', tipo: 'data', pii: 'nenhuma', peso: 0.85 },
    { chave: 'board', rotulo: 'Board', tipo: 'texto', pii: 'nenhuma', peso: 1.1 },
  ];
  const linhas: LinhaPdf[] = lista.map((p) => ({
    celulas: {
      nome: p.nome ?? '—',
      email: p.emails.join('\n'),
      documento: p.documentos[0] ? rotuloDocumento(p.documentos[0]) : '',
      telefone: p.telefone ?? '',
      situacao: ROTULO_SITUACAO[p.situacao] ?? p.situacao,
      primeira: p.primeira_compra ? fmtData(p.primeira_compra) : '',
      pago: fmtBRL(n(p.valor_pago)),
      liquido: fmtBRL(n(p.liquido)),
      atraso: atrasoPessoa(p),
      ultimo: p.ultima_compra_paga ? fmtData(p.ultima_compra_paga) : '',
      board: boardPessoa(p),
    },
  }));

  const totPago = soma(lista, (p) => n(p.valor_pago));
  const totLiq = soma(lista, (p) => n(p.liquido));
  const totAtraso = soma(lista, (p) => n(p.valor_atrasado));
  const comAtraso = lista.filter((p) => p.parcelas_atrasadas > 0).length;

  const resumo: SecaoPdf = {
    titulo: 'Por situação', tipo: 'resumo',
    colunas: [
      { chave: 'situacao', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma', peso: 2.4 },
      { chave: 'pessoas', rotulo: 'Pessoas', tipo: 'numero', pii: 'nenhuma' },
      { chave: 'pago', rotulo: 'Pago (bruto)', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'liquido', rotulo: 'Líquido', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'atraso', rotulo: 'Atrasado (120 dias)', tipo: 'moeda', pii: 'nenhuma' },
    ],
    linhas: ORDEM_SITUACAO.map((s) => ({ s, g: lista.filter((p) => p.situacao === s) }))
      .filter(({ g }) => g.length)
      .map(({ s, g }) => ({
        celulas: {
          situacao: ROTULO_SITUACAO[s], pessoas: String(g.length),
          pago: fmtBRL(soma(g, (p) => n(p.valor_pago))), liquido: fmtBRL(soma(g, (p) => n(p.liquido))),
          atraso: fmtBRL(soma(g, (p) => n(p.valor_atrasado))),
        },
      })),
    total: lista.length
      ? { situacao: 'Total', pessoas: String(lista.length), pago: fmtBRL(totPago), liquido: fmtBRL(totLiq), atraso: fmtBRL(totAtraso) }
      : undefined,
    vazio: 'Ninguém neste recorte.',
  };

  return {
    tipo: 'pessoas', titulo: 'Pessoas na Hotmart', recorte, niveisPermitidos: NIVEIS_RELATORIO.pessoas, arquivo: 'hotmart-pessoas', temPlanilha: true, // CSV em HotmartPessoas
    kpis: [
      { rotulo: 'Pessoas', valor: lista.length.toLocaleString('pt-BR') },
      { rotulo: 'Pago (bruto)', valor: fmtBRL(totPago) },
      { rotulo: 'Líquido', valor: fmtBRL(totLiq) },
      { rotulo: 'Atrasado (120 dias)', valor: fmtBRL(totAtraso) },
      { rotulo: 'Pessoas com atraso', valor: comAtraso.toLocaleString('pt-BR') },
    ],
    secoes: [
      resumo,
      {
        titulo: plural(lista.length, 'pessoa', 'pessoas'), tipo: 'detalhe', linhasSaoPessoas: true, colunas, linhas,
        total: lista.length ? { nome: 'Total', pago: fmtBRL(totPago), liquido: fmtBRL(totLiq), atraso: fmtBRL(totAtraso) } : undefined,
        vazio: 'Ninguém neste recorte.',
      },
    ],
  };
}

// ─── 3. Conciliação Hotmart × banco ────────────────────────────────────────────

export function recorteConciliacao(familia: FamiliaHotmart): ItemRecorte[] {
  return [{ rotulo: 'Família', valor: ROTULO_FAMILIA[familia] }];
}

const ladoConciliacao = (status: string | null, valor: number | null) =>
  `${status ?? ''}${valor != null ? `${status ? ' · ' : ''}${fmtBRL(n(valor))}` : ''}`;

export function rascunhoConciliacao(lista: DivergenciaHotmart[], recorte: ItemRecorte[]): RascunhoRelatorio {
  const tipos = Object.keys(ROTULO_DIVERGENCIA) as DivergenciaHotmart['tipo'][];
  const totHotmart = soma(lista, (d) => n(d.valor_hotmart));
  return {
    tipo: 'conciliacao', titulo: 'Conciliação Hotmart × banco', recorte, niveisPermitidos: NIVEIS_RELATORIO.conciliacao, arquivo: 'hotmart-conciliacao',
    kpis: [
      { rotulo: 'Divergências', valor: lista.length.toLocaleString('pt-BR') },
      { rotulo: 'Valor na Hotmart', valor: fmtBRL(totHotmart) },
      ...tipos.map((t) => ({ rotulo: ROTULO_DIVERGENCIA[t], valor: lista.filter((d) => d.tipo === t).length.toLocaleString('pt-BR') })),
    ],
    secoes: [
      {
        titulo: 'Por tipo', tipo: 'resumo',
        colunas: [
          { chave: 'tipo', rotulo: 'Tipo', tipo: 'texto', pii: 'nenhuma', peso: 2.4 },
          { chave: 'qtd', rotulo: 'Divergências', tipo: 'numero', pii: 'nenhuma' },
          { chave: 'hotmart', rotulo: 'Valor na Hotmart', tipo: 'moeda', pii: 'nenhuma' },
          { chave: 'banco', rotulo: 'Valor no banco', tipo: 'moeda', pii: 'nenhuma' },
        ],
        linhas: tipos.map((t) => ({ t, g: lista.filter((d) => d.tipo === t) })).filter(({ g }) => g.length).map(({ t, g }) => ({
          celulas: {
            tipo: ROTULO_DIVERGENCIA[t], qtd: String(g.length),
            hotmart: fmtBRL(soma(g, (d) => n(d.valor_hotmart))), banco: fmtBRL(soma(g, (d) => n(d.valor_banco))),
          },
        })),
        vazio: 'Hotmart e banco batem.',
      },
      {
        titulo: plural(lista.length, 'divergência', 'divergências'), tipo: 'detalhe',
        colunas: [
          { chave: 'tipo', rotulo: 'Tipo', tipo: 'texto', pii: 'nenhuma', peso: 1.4 },
          // Código HP… identifica o comprador para quem tem acesso à Hotmart (pseudônimo = dado
          // pessoal pela LGPD — pentest 28/09): só sai no nível completo.
          { chave: 'transacao', rotulo: 'Transação', tipo: 'texto', pii: 'identificacao', peso: 1.1 },
          { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato', peso: 1.7 },
          { chave: 'hotmart', rotulo: 'Hotmart', tipo: 'texto', pii: 'nenhuma', peso: 1.1 },
          { chave: 'banco', rotulo: 'Banco', tipo: 'texto', pii: 'nenhuma', peso: 1.1 },
          { chave: 'pedido', rotulo: 'Pedido', tipo: 'data', pii: 'nenhuma', peso: 0.85 },
          { chave: 'detalhe', rotulo: 'Detalhe', tipo: 'texto', pii: 'nenhuma', peso: 2.2 },
        ],
        linhas: lista.map((d) => ({
          celulas: {
            tipo: ROTULO_DIVERGENCIA[d.tipo] ?? d.tipo,
            transacao: d.transacao ?? '',
            email: d.email ?? '',
            hotmart: ladoConciliacao(d.status_hotmart, d.valor_hotmart),
            banco: ladoConciliacao(d.status_banco, d.valor_banco),
            pedido: d.pedido_em ? fmtData(d.pedido_em) : '',
            detalhe: d.detalhe,
          },
        })),
        vazio: 'Nenhuma divergência.',
      },
    ],
  };
}

// ─── 4. Mesma pessoa? (identidade) — só nível completo ─────────────────────────

const listaTexto = (v: string[] | null) => (v?.length ? v.join('\n') : '');

export function rascunhoIdentidade(dados: IdentidadeRevisao[]): RascunhoRelatorio {
  const sug = dados.filter((d) => d.tipo === 'sugestao');
  const rev = dados.filter((d) => d.tipo === 'revisao');
  return {
    tipo: 'identidade', titulo: 'Mesma pessoa? Revisão de identidade', recorte: [],
    niveisPermitidos: NIVEIS_RELATORIO.identidade, arquivo: 'hotmart-identidade',
    kpis: [
      { rotulo: 'Pares para conferir', valor: sug.length.toLocaleString('pt-BR') },
      { rotulo: 'Documentos em revisão', valor: rev.length.toLocaleString('pt-BR') },
    ],
    secoes: [
      {
        titulo: plural(sug.length, 'par que pode ser a mesma pessoa', 'pares que podem ser a mesma pessoa'), tipo: 'detalhe',
        colunas: [
          { chave: 'motivo', rotulo: 'Motivo', tipo: 'texto', pii: 'nenhuma', peso: 1 },
          // telefone/documento já saem como ···1234; em "mesmo nome" a evidência é o próprio nome
          { chave: 'evidencia', rotulo: 'Evidência', tipo: 'texto', pii: 'documento', peso: 1.1 },
          { chave: 'nomes_a', rotulo: 'Pessoa A', tipo: 'texto', pii: 'identificacao', peso: 1.4 },
          { chave: 'emails_a', rotulo: 'E-mails A', tipo: 'texto', pii: 'contato', peso: 1.7 },
          { chave: 'nomes_b', rotulo: 'Pessoa B', tipo: 'texto', pii: 'identificacao', peso: 1.4 },
          { chave: 'emails_b', rotulo: 'E-mails B', tipo: 'texto', pii: 'contato', peso: 1.7 },
          { chave: 'pago_a', rotulo: 'Pago A', tipo: 'moeda', pii: 'nenhuma', peso: 0.8 },
          { chave: 'pago_b', rotulo: 'Pago B', tipo: 'moeda', pii: 'nenhuma', peso: 0.8 },
        ],
        linhas: sug.map((d) => ({
          celulas: {
            motivo: MOTIVO_SUGESTAO[d.motivo] ?? d.motivo,
            evidencia: rotuloEvidencia(d.motivo, d.evidencia),
            nomes_a: listaTexto(d.nomes_a), emails_a: listaTexto(d.emails_a),
            nomes_b: listaTexto(d.nomes_b), emails_b: listaTexto(d.emails_b),
            pago_a: fmtBRL(n(d.pago_a)), pago_b: fmtBRL(n(d.pago_b)),
          },
        })),
        vazio: 'Nenhum par para conferir.',
      },
      {
        titulo: plural(rev.length, 'documento em revisão', 'documentos em revisão'), tipo: 'detalhe',
        colunas: [
          { chave: 'documento', rotulo: 'Documento', tipo: 'texto', pii: 'documento', peso: 1 },
          { chave: 'motivo', rotulo: 'Motivo', tipo: 'texto', pii: 'nenhuma', peso: 4 },
        ],
        linhas: rev.map((d) => ({ celulas: { documento: d.evidencia ?? '', motivo: d.motivo } })),
        vazio: 'Nada em revisão.',
      },
    ],
  };
}

// ─── 5. Acelera → HM ───────────────────────────────────────────────────────────

export type FiltroAcelera = 'subiram' | 'sem_card' | 'ja_eram' | 'nao_subiram' | null;
const ROTULO_FILTRO_ACELERA: Record<Exclude<FiltroAcelera, null>, string> = {
  subiram: 'Subiram', sem_card: 'Subiram sem card', ja_eram: 'Já eram HM', nao_subiram: 'Não subiram',
};

export function recorteAcelera(filtro: FiltroAcelera): ItemRecorte[] {
  return [{ rotulo: 'Filtro', valor: filtro ? ROTULO_FILTRO_ACELERA[filtro] : 'Todos' }];
}

function subiuAcelera(p: AceleraParaHM): string {
  if (p.subiu) return `${fmtData(p.primeira_hm_depois)}${p.dias_ate_subir != null ? `\n${p.dias_ate_subir} dia(s) depois` : ''}`;
  return p.ja_era_hm ? 'Já era HM antes' : 'Não subiu';
}

export function rascunhoAcelera(lista: AceleraParaHM[], recorte: ItemRecorte[]): RascunhoRelatorio {
  const subiram = lista.filter((p) => p.subiu);
  const comDias = subiram.filter((p) => p.dias_ate_subir != null);
  const media = comDias.length ? soma(comDias, (p) => n(p.dias_ate_subir)) / comDias.length : null;
  const totAcelera = soma(lista, (p) => n(p.acelera_pago));
  const totHm = soma(lista, (p) => n(p.hm_pago_depois));
  return {
    tipo: 'acelera', titulo: 'Acelera → HM', recorte, niveisPermitidos: NIVEIS_RELATORIO.acelera, arquivo: 'acelera-para-hm', temPlanilha: true, // CSV em AceleraParaHM
    kpis: [
      { rotulo: 'Compradores do Acelera', valor: lista.length.toLocaleString('pt-BR') },
      { rotulo: 'Subiram para o HM', valor: subiram.length.toLocaleString('pt-BR') },
      { rotulo: 'Já eram HM antes', valor: lista.filter((p) => p.ja_era_hm).length.toLocaleString('pt-BR') },
      { rotulo: 'Total pago no HM depois', valor: fmtBRLc(totHm) },
      { rotulo: 'Média de dias até subir', valor: media != null ? `${media.toFixed(0)} dias` : '—' },
      { rotulo: 'Subiram sem card no board', valor: subiram.filter((p) => !p.tem_card).length.toLocaleString('pt-BR') },
    ],
    secoes: [
      {
        titulo: plural(lista.length, 'pessoa', 'pessoas'), tipo: 'detalhe', linhasSaoPessoas: true,
        colunas: [
          { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao', peso: 1.5 },
          { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato', peso: 1.9 },
          { chave: 'primeira', rotulo: '1ª compra Acelera', tipo: 'data', pii: 'nenhuma', peso: 0.9 },
          { chave: 'funil', rotulo: 'Funil Acelera', tipo: 'texto', pii: 'nenhuma', peso: 1.1 },
          { chave: 'pago_acelera', rotulo: 'Pago Acelera', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'subiu', rotulo: 'Subiu?', tipo: 'texto', pii: 'nenhuma', peso: 1 },
          { chave: 'pago_hm', rotulo: 'Pago no HM depois', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'caminho', rotulo: 'Caminho HM', tipo: 'texto', pii: 'nenhuma', peso: 1.2 },
          { chave: 'card', rotulo: 'Card no board', tipo: 'texto', pii: 'nenhuma', peso: 0.6 },
        ],
        linhas: lista.map((p) => ({
          celulas: {
            nome: p.nome ?? '—', email: p.email ?? '',
            primeira: p.primeira_acelera ? fmtData(p.primeira_acelera) : '',
            funil: p.acelera_funil ?? '', pago_acelera: fmtBRLc(n(p.acelera_pago)),
            subiu: subiuAcelera(p), pago_hm: fmtBRLc(n(p.hm_pago_depois)), caminho: p.hm_caminho ?? '',
            card: p.tem_card ? 'Sim' : 'Não',
          },
        })),
        total: lista.length ? { nome: 'Total', pago_acelera: fmtBRLc(totAcelera), pago_hm: fmtBRLc(totHm) } : undefined,
        vazio: 'Ninguém neste recorte.',
      },
    ],
  };
}

// ─── 6. Pro rata do HM ─────────────────────────────────────────────────────────

export type FiltroProrata = 'credito' | 'vence60' | 'vencido' | 'gps' | 'sem_hotmart' | null;
const ROTULO_FILTRO_PRORATA: Record<Exclude<FiltroProrata, null>, string> = {
  credito: 'Com crédito', vence60: 'Vence em até 60 dias', vencido: 'Já vencido', gps: 'No GPS',
  sem_hotmart: 'Sem pagamento de HM na Hotmart',
};

export function recorteProrata(filtro: FiltroProrata, busca: string): ItemRecorte[] {
  const itens: ItemRecorte[] = [{ rotulo: 'Filtro', valor: filtro ? ROTULO_FILTRO_PRORATA[filtro] : 'Todos' }];
  if (busca.trim()) itens.push({ rotulo: 'Busca', valor: `"${busca.trim()}"`, pii: true });
  return itens;
}

export function rascunhoProrata(lista: ProrataHM[], recorte: ItemRecorte[]): RascunhoRelatorio {
  const totPago = soma(lista, (p) => n(p.pago_no_ciclo));
  const totCredito = soma(lista, (p) => n(p.credito));
  const totPagar = soma(lista, (p) => n(p.diferenca));
  return {
    tipo: 'prorata', titulo: 'Pro rata do HM', recorte, niveisPermitidos: NIVEIS_RELATORIO.prorata, arquivo: 'prorata-hm', temPlanilha: true, // CSV em ProrataHM
    kpis: [
      { rotulo: 'Pessoas', valor: lista.length.toLocaleString('pt-BR') },
      { rotulo: 'Com crédito', valor: lista.filter((p) => n(p.credito) > 0).length.toLocaleString('pt-BR') },
      { rotulo: 'Soma dos créditos', valor: fmtBRLc(totCredito) },
      { rotulo: 'Soma do valor a pagar', valor: fmtBRLc(totPagar) },
    ],
    secoes: [
      {
        titulo: plural(lista.length, 'pessoa', 'pessoas'), tipo: 'detalhe', linhasSaoPessoas: true,
        colunas: [
          { chave: 'nome', rotulo: 'Nome', tipo: 'texto', pii: 'identificacao', peso: 1.5 },
          { chave: 'email', rotulo: 'E-mail', tipo: 'texto', pii: 'contato', peso: 1.9 },
          { chave: 'turma', rotulo: 'Turma', tipo: 'texto', pii: 'nenhuma', peso: 0.8 },
          { chave: 'vence', rotulo: 'Vence em', tipo: 'data', pii: 'nenhuma', peso: 0.85 },
          { chave: 'meses', rotulo: 'Meses restantes', tipo: 'numero', pii: 'nenhuma', peso: 0.7 },
          { chave: 'pago', rotulo: 'Pago no ciclo', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'formas', rotulo: 'Formas', tipo: 'texto', pii: 'nenhuma', peso: 1.3 },
          { chave: 'credito', rotulo: 'Crédito', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'pagar', rotulo: 'Valor a pagar', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
          { chave: 'card', rotulo: 'Card no board', tipo: 'texto', pii: 'nenhuma', peso: 0.6 },
        ],
        linhas: lista.map((p) => ({
          celulas: {
            nome: p.nome ?? '—', email: p.email ?? '', turma: p.turma ?? '',
            vence: fmtData(p.vencimento), meses: String(p.meses_restantes),
            pago: fmtBRLc(n(p.pago_no_ciclo)),
            formas: p.ultimo_pagamento == null ? 'sem pagamento na Hotmart' : (p.formas ?? ''),
            credito: fmtBRLc(n(p.credito)), pagar: fmtBRLc(n(p.diferenca)),
            card: p.tem_card ? 'Sim' : 'Não',
          },
        })),
        total: lista.length ? { nome: 'Total', pago: fmtBRLc(totPago), credito: fmtBRLc(totCredito), pagar: fmtBRLc(totPagar) } : undefined,
        vazio: 'Ninguém neste recorte.',
      },
    ],
  };
}

// ─── 7. Contas a receber (Previsão de caixa, F5) ───────────────────────────────
// Sai das linhas JÁ CARREGADAS do cenário ativo (a mesma resposta de fn_fin_receber_semanal que monta a grade e a Base
// auditável): nenhuma consulta nova além da emissão do protocolo. Semanas, soma e resumo por centro de custo vêm das
// MESMAS funções da tela (domain/contas-receber.ts, ui/receber/base-auditavel.ts). Só 'a_receber' soma.
// Dado pessoal: a única coluna pessoal é a Descrição do anexo (nome do contrato, cliente do informado, nome do card);
// no nível sem_dado_pessoal ela vira "Pessoa N" estável por contrato/cadastro (pseudonimizadorBase, a regra do CSV).

/** Valor da grade: zero sai como travessão (igual ao '–' da tela). */
const moedaGrade = (v: number) => (Math.round(v * 100) === 0 ? '' : fmtBRLc(v));
const ddmm = (d: string) => `${d.slice(8, 10)}/${d.slice(5, 7)}`;
const centavos = (v: number) => Math.round(v * 100);
const qtd = (v: number) => v.toLocaleString('pt-BR');

export function rascunhoReceber(dados: ContasReceberCarregado): RascunhoRelatorio {
  const g = dados.grade;
  const sems = g.semanas;
  const cenario = CENARIO_RECEBER[dados.cenario] ?? dados.cenario;
  const inicio = sems[0]?.inicio ?? dados.hojeISO;
  const fim = sems[sems.length - 1]?.fim ?? dados.hojeISO;
  const recorte: ItemRecorte[] = [
    { rotulo: 'Cenário', valor: cenario },
    { rotulo: 'Corte', valor: fmtData(dados.hojeISO) },
    { rotulo: 'Horizonte', valor: `${fmtData(inicio)} a ${fmtData(fim)} · ${plural(sems.length, 'semana', 'semanas')}` },
  ];

  // Resumo mensal certo × estimado (os meses da grade; a semana nunca cruza mês).
  let acum = 0;
  const porMes = g.meses.map((m) => {
    const certo = m.semanas.reduce((x, i) => x + centavos(g.certoPorSemana[i]), 0);
    const est = m.semanas.reduce((x, i) => x + centavos(g.estimadoPorSemana[i]), 0);
    acum += certo + est;
    return { mes: m.mes, certo: certo / 100, est: est / 100, total: (certo + est) / 100, acum: acum / 100 };
  });
  const resumoMensal: SecaoPdf = {
    titulo: 'Resumo mensal: certo × estimado', tipo: 'resumo',
    colunas: [
      { chave: 'mes', rotulo: 'Mês', tipo: 'texto', pii: 'nenhuma' },
      { chave: 'certo', rotulo: 'Certo', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'estimado', rotulo: 'Estimado', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'total', rotulo: 'Total do mês', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'acumulado', rotulo: 'Acumulado', tipo: 'moeda', pii: 'nenhuma' },
    ],
    linhas: porMes.map((m) => ({
      celulas: {
        mes: rotuloMes(m.mes), certo: moedaGrade(m.certo), estimado: moedaGrade(m.est), total: moedaGrade(m.total), acumulado: fmtBRLc(m.acum),
      },
    })),
    total: porMes.length
      ? { mes: 'Total', certo: fmtBRLc(g.certoTotal), estimado: fmtBRLc(g.estimadoTotal), total: fmtBRLc(g.total) }
      : undefined,
    vazio: 'Nada a receber no período.',
  };

  // Por centro de custo: linhas = mês, colunas = centro (o horizonte pode passar de 12 meses; os centros são poucos).
  const cc = resumoCentroMes(dados.linhas);
  const colCentro = (i: number) => `cc${i}`;
  const resumoCentro: SecaoPdf = {
    titulo: 'Entradas por centro de custo × mês (valor esperado)', tipo: 'resumo',
    colunas: [
      { chave: 'mes', rotulo: 'Mês', tipo: 'texto', pii: 'nenhuma' },
      ...cc.linhas.map((l, i): ColunaPdf => ({
        chave: colCentro(i), rotulo: l.centro ?? 'Sem centro de custo', tipo: 'moeda', pii: 'nenhuma', peso: 1.3,
      })),
      { chave: 'total', rotulo: 'Total de entradas', tipo: 'moeda', pii: 'nenhuma' },
    ],
    linhas: cc.meses.map((m, j) => ({
      celulas: {
        mes: rotuloMes(m),
        ...Object.fromEntries(cc.linhas.map((l, i) => [colCentro(i), moedaGrade(l.porMes[j])])),
        total: moedaGrade(cc.totalPorMes[j]),
      },
    })),
    total: cc.meses.length
      ? { mes: 'Total', ...Object.fromEntries(cc.linhas.map((l, i) => [colCentro(i), fmtBRLc(l.total)])), total: fmtBRLc(cc.total) }
      : undefined,
    vazio: 'Nenhuma linha a receber com data de caixa.',
  };

  // Grade semana × bloco: linhas = semana, colunas = bloco (as semanas de domain/contas-receber.ts).
  // Uma coluna por (bloco, seção), a mesma divisão da tela: a seção vem da `certeza` das linhas (grade.blocos), e o bloco 7
  // pode ter a parte certa (assinados) e a estimada (sem contrato assinado) — aí o rótulo diz qual é qual.
  const temEstimado = g.blocos.some((b) => b.secao === 'estimado');
  const dividido = (bloco: number) => g.blocos.filter((x) => x.bloco === bloco).length > 1;
  const colBloco = (b: { bloco: number; secao: string }) =>
    `b${b.bloco}${dividido(b.bloco) ? (b.secao === 'estimado' ? 'e' : 'c') : ''}`;
  const rotuloColBloco = (b: { bloco: number; secao: string }) =>
    `${b.bloco}. ${rotuloBloco(b.bloco)}${dividido(b.bloco) ? (b.secao === 'estimado' ? ' (estimado)' : ' (certo)') : ''}`;
  const info = g.informativo;
  const colunasGrade: ColunaPdf[] = [
    { chave: 'semana', rotulo: 'Semana', tipo: 'texto', pii: 'nenhuma', peso: 0.6 },
    { chave: 'periodo', rotulo: 'Período', tipo: 'texto', pii: 'nenhuma', peso: 1.2 },
    ...g.blocos.map((b): ColunaPdf => ({ chave: colBloco(b), rotulo: rotuloColBloco(b), tipo: 'moeda', pii: 'nenhuma' })),
  ];
  if (temEstimado) {
    colunasGrade.push(
      { chave: 'certo', rotulo: 'Certo', tipo: 'moeda', pii: 'nenhuma' },
      { chave: 'estimado', rotulo: 'Estimado', tipo: 'moeda', pii: 'nenhuma' },
    );
  }
  colunasGrade.push(
    { chave: 'total', rotulo: 'Total', tipo: 'moeda', pii: 'nenhuma' },
    { chave: 'acumulado', rotulo: 'Acumulado', tipo: 'moeda', pii: 'nenhuma' },
  );
  if (info) colunasGrade.push({ chave: 'info', rotulo: `${BLOCO_INFORMATIVO}. Informativo (fora da soma)`, tipo: 'moeda', pii: 'nenhuma' });
  const gradeSemana: SecaoPdf = {
    titulo: 'Semana × bloco (valor esperado)', tipo: 'resumo',
    colunas: colunasGrade,
    linhas: sems.map((s, i) => ({
      celulas: {
        semana: `S${s.n}`,
        periodo: s.inicio === s.fim ? ddmm(s.inicio) : `${ddmm(s.inicio)} a ${ddmm(s.fim)}`, // o ano está no horizonte
        ...Object.fromEntries(g.blocos.map((b) => [colBloco(b), moedaGrade(b.porSemana[i])])),
        ...(temEstimado ? { certo: moedaGrade(g.certoPorSemana[i]), estimado: moedaGrade(g.estimadoPorSemana[i]) } : {}),
        total: moedaGrade(g.totalPorSemana[i]),
        acumulado: fmtBRLc(g.acumuladoPorSemana[i]),
        ...(info ? { info: moedaGrade(info.porSemana[i]) } : {}),
      },
    })),
    total: sems.length
      ? {
        semana: 'Total',
        ...Object.fromEntries(g.blocos.map((b) => [colBloco(b), fmtBRLc(b.total)])),
        ...(temEstimado ? { certo: fmtBRLc(g.certoTotal), estimado: fmtBRLc(g.estimadoTotal) } : {}),
        total: fmtBRLc(g.total),
        ...(info ? { info: fmtBRLc(info.total) } : {}),
      }
      : undefined,
    vazio: 'Nada a receber no período.',
  };

  // O que não soma aparece contado, nunca some em silêncio.
  const somaBase = somarBase(dados.linhas);
  const fora: LinhaPdf[] = [
    // 'sem_base' sai abaixo, grupo a grupo (com o porquê), em vez de uma contagem só.
    ...somaBase.foraDaSoma.filter((f) => f.situacao !== 'sem_base')
      .map((f) => ({ celulas: { situacao: rotuloSituacaoLinha(f.situacao), linhas: qtd(f.linhas) } })),
    ...(g.semDataCaixa.linhas
      ? [{ celulas: { situacao: 'A receber sem data de caixa', linhas: qtd(g.semDataCaixa.linhas), valor: fmtBRLc(g.semDataCaixa.valor) } }]
      : []),
    ...(g.foraDoPeriodo.linhas
      ? [{ celulas: { situacao: 'A receber fora do período', linhas: qtd(g.foraDoPeriodo.linhas), valor: fmtBRLc(g.foraDoPeriodo.valor) } }]
      : []),
    ...g.semBase.map((x) => ({
      celulas: {
        situacao: `Sem base medida: ${x.bloco}. ${x.grupo}${x.tratamento ? ` (${x.tratamento})` : ''}`,
        linhas: qtd(dados.linhas.filter((l) => l.situacao === 'sem_base' && l.bloco === x.bloco && l.grupo === x.grupo).length),
      },
    })),
  ];
  const foraDaSoma: SecaoPdf = {
    titulo: 'Fora da soma', tipo: 'resumo',
    colunas: [
      { chave: 'situacao', rotulo: 'Situação', tipo: 'texto', pii: 'nenhuma', peso: 3 },
      { chave: 'linhas', rotulo: 'Linhas', tipo: 'numero', pii: 'nenhuma' },
      // Só o que tem data de caixa e valor (a receber fora da grade); o resto é contagem, como na Base auditável.
      { chave: 'valor', rotulo: 'Valor esperado', tipo: 'moeda', pii: 'nenhuma' },
    ],
    linhas: fora,
    vazio: 'Todas as linhas carregadas estão na soma.',
  };

  // Anexo: base auditável, só as linhas a_receber (as que somam), na ordem da tela.
  const base = filtrarBase(dados.linhas, FILTRO_BASE_PADRAO);
  const pseudonimo = pseudonimizadorBase();
  const anexo: SecaoPdf = {
    titulo: `Anexo: base auditável (${plural(base.length, 'linha a receber', 'linhas a receber')})`, tipo: 'detalhe',
    colunas: [
      { chave: 'data', rotulo: 'Data de caixa', tipo: 'data', pii: 'nenhuma', peso: 0.85 },
      { chave: 'semana', rotulo: 'Semana', tipo: 'texto', pii: 'nenhuma', peso: 0.55 },
      { chave: 'bloco', rotulo: 'Bloco', tipo: 'texto', pii: 'nenhuma', peso: 0.45 },
      { chave: 'grupo', rotulo: 'Grupo', tipo: 'texto', pii: 'nenhuma', peso: 1.4 },
      { chave: 'componente', rotulo: 'Componente', tipo: 'texto', pii: 'nenhuma', peso: 0.9 },
      { chave: 'descricao', rotulo: 'Descrição', tipo: 'texto', pii: 'identificacao', anonimavel: true, peso: 1.6 },
      { chave: 'produto', rotulo: 'Produto', tipo: 'texto', pii: 'nenhuma', peso: 1.1 },
      { chave: 'esperado', rotulo: 'Valor esperado', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
      { chave: 'bruto', rotulo: 'Valor bruto', tipo: 'moeda', pii: 'nenhuma', peso: 0.9 },
      { chave: 'fator', rotulo: 'Fator', tipo: 'numero', pii: 'nenhuma', peso: 0.55 },
      { chave: 'centro', rotulo: 'Centro de custo', tipo: 'texto', pii: 'nenhuma', peso: 1.2 },
      { chave: 'tratamento', rotulo: 'Tratamento', tipo: 'texto', pii: 'nenhuma', peso: 1.8 },
    ],
    linhas: base.map((l) => ({
      celulas: {
        data: l.data_caixa ? fmtData(l.data_caixa) : '',
        semana: rotuloSemanaDaLinha(sems, l.data_caixa),
        bloco: String(l.bloco),
        grupo: l.grupo,
        componente: rotuloComponente(l.componente),
        descricao: l.rotulo ?? '',
        produto: l.produto ?? '',
        esperado: fmtBRLc(l.valor),
        bruto: fmtBRLc(l.valor_bruto),
        fator: fatorCsv(l.fator),
        centro: l.centro_custo ?? '',
        tratamento: l.tratamento ?? '',
      },
      anonimas: { descricao: pseudonimo(l) },
    })),
    total: base.length
      ? { data: 'Total', esperado: fmtBRLc(somaBase.aReceber.valor), bruto: fmtBRLc(somaBase.aReceber.bruto) }
      : undefined,
    vazio: 'Nenhuma linha a receber.',
  };

  const kpis: KpiPdf[] = [
    { rotulo: 'A receber no período', valor: fmtBRLc(g.total) },
    { rotulo: 'Certo', valor: fmtBRLc(g.certoTotal) },
    { rotulo: 'Estimado', valor: fmtBRLc(g.estimadoTotal) },
  ];
  if (centavos(g.brutoTotal) !== centavos(g.total)) kpis.push({ rotulo: 'Bruto (sem perda)', valor: fmtBRLc(g.brutoTotal) });
  kpis.push({ rotulo: 'Linhas a receber', valor: qtd(somaBase.aReceber.linhas) });
  if (info) kpis.push({ rotulo: 'Informativo, fora da soma', valor: fmtBRLc(info.total) });

  return {
    tipo: 'receber', titulo: 'Contas a receber: previsão de caixa', recorte, niveisPermitidos: NIVEIS_RELATORIO.receber,
    arquivo: `financeiro-contas-a-receber-${dados.cenario}`, temPlanilha: true, // CSV da Base auditável, na mesma tela
    kpis,
    secoes: [resumoMensal, resumoCentro, gradeSemana, foraDaSoma, anexo],
  };
}
