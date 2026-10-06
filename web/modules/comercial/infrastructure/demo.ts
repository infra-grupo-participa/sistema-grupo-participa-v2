// Comercial: MODO DE DEMONSTRAÇÃO (só desenvolvimento local). Pessoas, negócios e compras INVENTADOS, em memória, para
// ver as telas sem dado real. Nunca é usado em produção: comercial-data.ts só liga com NEXT_PUBLIC_COMERCIAL_DEMO=1 E
// NODE_ENV diferente de 'production', e a tela mostra a faixa "Dados de demonstração". Recarregar a página volta ao começo.
// Pipelines e etapas = a semente da migration 20261005o (proposta); projetos = a semente da 20261005m. O resto é ficção:
// nomes com sobrenome "Exemplo", e-mails @exemplo.invalid, telefones 0000, responsáveis genéricos.
import {
  type ConfigCrm, type Etapa, type Negocio, type Pipeline, MSG_MOVIMENTO, statusDaEtapa, validarMovimento,
} from '../domain/crm';
import {
  type Conhecida, type Entrada, chaveTelefone, mascararEmail, mascararFim, normalizarDocumento, normalizarEmail, normalizarNome,
  normalizarTelefone, resolverIdentidade, temIdentificador,
} from '../domain/identidade';
import type { Evento, Ficha, ItemBusca, Origem, Resposta, RevisaoPendente } from '../domain/pessoas';

const etapa = (id: number, nome: string, ordem: number, tipo: Etapa['tipo']): Etapa => ({ id, nome, ordem, tipo, ativa: true });

const PIPELINES: Pipeline[] = [
  { id: 1, tipo: 'ativacao', nome: 'Ativação', ativo: true,
    descricao: 'Contato sem intenção de vender: ajudar a pessoa a entrar no evento ou na área de membros (ex.: ingresso do HT).',
    etapas: [etapa(1, 'A contatar', 1, 'aberta'), etapa(2, 'Em contato', 2, 'aberta'), etapa(3, 'Ativado', 3, 'ganho'), etapa(4, 'Não ativado', 4, 'perdido')] },
  { id: 2, tipo: 'vendas', nome: 'Vendas', descricao: null, ativo: true,
    etapas: [etapa(5, 'Novo', 1, 'aberta'), etapa(6, 'Em contato', 2, 'aberta'), etapa(7, 'Negociação', 3, 'aberta'), etapa(8, 'Ganho', 4, 'ganho'), etapa(9, 'Perdido', 5, 'perdido')] },
  { id: 3, tipo: 'recuperacao_carrinho', nome: 'Recuperação de carrinho', descricao: null, ativo: true,
    etapas: [etapa(10, 'A contatar', 1, 'aberta'), etapa(11, 'Em contato', 2, 'aberta'), etapa(12, 'Recuperado', 3, 'ganho'), etapa(13, 'Não recuperado', 4, 'perdido')] },
  { id: 4, tipo: 'recuperacao_venda', nome: 'Recuperação de venda', descricao: null, ativo: true,
    etapas: [etapa(14, 'A contatar', 1, 'aberta'), etapa(15, 'Em contato', 2, 'aberta'), etapa(16, 'Recuperado', 3, 'ganho'), etapa(17, 'Não recuperado', 4, 'perdido')] },
];

const PROJETOS = [
  { id: 1, sigla: 'PB26', nome: 'Patrimônio Brasil 2026', ativo: true },
  { id: 2, sigla: 'HT33', nome: 'Holding Total 33', ativo: true },
  { id: 3, sigla: 'SEMSET26', nome: 'Seminário setembro 2026', ativo: true },
  { id: 4, sigla: 'BF26', nome: 'Black Friday 2026', ativo: true },
];
const RESPONSAVEIS = [{ id: 'r1', nome: 'Responsável Exemplo 1' }, { id: 'r2', nome: 'Responsável Exemplo 2' }];

interface PessoaDemo extends Conhecida {
  ref: string; situacao: 'ativa' | 'revisar' | 'mesclada'; aluno: { id: string; turma: string } | null; comprador: boolean; criado_em: string;
}

const dia = (n: number) => new Date(Date.now() - n * 86400000).toISOString();
const hoje = (n = 0) => new Date(Date.now() + n * 86400000).toISOString().slice(0, 10);

let seq = 100;
const novoId = (p: string) => `${p}${++seq}`;

const PESSOAS: PessoaDemo[] = [
  { id: 'p1', ref: 'pe_demo01', nome: 'Ana Exemplo Souza', email: 'ana.exemplo@exemplo.invalid', telefone: '11990000001', documento: '52998224725', situacao: 'ativa', aluno: { id: 'al1', turma: 'T40' }, comprador: true, criado_em: dia(20) },
  { id: 'p2', ref: 'pe_demo02', nome: 'Bruno Exemplo Lima', email: 'bruno.exemplo@exemplo.invalid', telefone: '21990000002', situacao: 'ativa', aluno: null, comprador: false, criado_em: dia(6) },
  { id: 'p3', ref: 'pe_demo03', nome: 'Carla Exemplo Dias', email: 'carla.exemplo@exemplo.invalid', telefone: '31990000003', situacao: 'ativa', aluno: null, comprador: true, criado_em: dia(4) },
  { id: 'p4', ref: 'pe_demo04', nome: 'Diego Exemplo Ramos', email: 'diego.exemplo@exemplo.invalid', telefone: '41990000004', situacao: 'ativa', aluno: null, comprador: false, criado_em: dia(3) },
  { id: 'p5', ref: 'pe_demo05', nome: 'Eva Exemplo Nunes', email: 'eva.exemplo@exemplo.invalid', telefone: '51990000005', situacao: 'ativa', aluno: { id: 'al5', turma: 'T41' }, comprador: true, criado_em: dia(30) },
  { id: 'p6', ref: 'pe_demo06', nome: 'Fabio Exemplo Rocha', email: 'fabio.exemplo@exemplo.invalid', telefone: '61990000006', situacao: 'ativa', aluno: null, comprador: false, criado_em: dia(2) },
  { id: 'p7', ref: 'pe_demo07', nome: 'Bruno Exemplo Lima', email: 'bruno.outro@exemplo.invalid', situacao: 'revisar', aluno: null, comprador: false, criado_em: dia(1) },
];

const ORIGENS: Record<string, Origem[]> = {
  p2: [{ id: 1, quando: dia(6), projeto_id: 1, projeto: 'PB26', pagina_id: 11, pagina: 'patrimoniobrasil.com.br/ak1/', campanha: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', campanha_padrao: true, utm_source: 'metaads', utm_medium: 'CONJUNTO DEMONSTRAÇÃO|000000000000003', utm_campaign: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1|000000000000002', utm_content: 'CRIATIVO DEMONSTRAÇÃO|000000000000001', utm_term: null, de_anuncio: true, fonte: 'formulario' }],
  p4: [{ id: 2, quando: dia(3), projeto_id: 1, projeto: 'PB26', pagina_id: 11, pagina: 'patrimoniobrasil.com.br/ak1/', campanha: null, campanha_padrao: null, utm_source: 'google', utm_medium: 'cpc', utm_campaign: null, utm_content: null, utm_term: null, de_anuncio: true, fonte: 'formulario' }],
  p6: [{ id: 3, quando: dia(2), projeto_id: 2, projeto: 'HT33', pagina_id: null, pagina: null, campanha: 'cf|ht33|vendas|aula ao vivo', campanha_padrao: true, utm_source: 'instagram', utm_medium: null, utm_campaign: null, utm_content: null, utm_term: null, de_anuncio: false, fonte: 'formulario' }],
  p7: [{ id: 4, quando: dia(1), projeto_id: 1, projeto: 'PB26', pagina_id: 11, pagina: 'patrimoniobrasil.com.br/ak1/', campanha: null, campanha_padrao: null, utm_source: 'facebook', utm_medium: null, utm_campaign: null, utm_content: null, utm_term: null, de_anuncio: true, fonte: 'formulario' }],
};

const EVENTOS: Record<string, Evento[]> = {
  p1: [{ id: 1, tipo: 'vinculo', quando: dia(20), projeto: null, fonte: 'sistema', ref_tipo: 'public.thb_alunos', ref_id: 'al1', detalhe: {}, por: null }],
  p2: [{ id: 2, tipo: 'lead', quando: dia(6), projeto: 'PB26', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: {}, por: null },
       { id: 3, tipo: 'mql', quando: dia(5), projeto: 'PB26', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: {}, por: null }],
  p4: [{ id: 4, tipo: 'lead', quando: dia(3), projeto: 'PB26', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: {}, por: null }],
  p6: [{ id: 5, tipo: 'lead', quando: dia(2), projeto: 'HT33', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: {}, por: null }],
  p7: [{ id: 6, tipo: 'lead', quando: dia(1), projeto: 'PB26', fonte: 'formulario', ref_tipo: null, ref_id: null, detalhe: { revisao: 'so_nome' }, por: null }],
};

const COMPRAS: Record<string, Ficha['compras']> = {
  p1: [{ id: 'c1', produto: 'Produto fictício A', status: 'APPROVED', data: dia(40), preco: 100 }],
  p3: [{ id: 'c2', produto: 'Produto fictício B', status: 'CANCELED', data: dia(5), preco: 50 }],
  p5: [{ id: 'c3', produto: 'Produto fictício A', status: 'APPROVED', data: dia(32), preco: 100 }],
};

const neg = (id: string, pipeline: number, etapaId: number, pessoa: PessoaDemo, extra: Partial<Negocio> = {}): Negocio => {
  const et = PIPELINES.flatMap((p) => p.etapas).find((e) => e.id === etapaId)!;
  return {
    id, pipeline_id: pipeline, etapa_id: etapaId, status: statusDaEtapa(et.tipo), pessoa_id: pessoa.id, pessoa: pessoa.nome,
    eh_aluno: !!pessoa.aluno, situacao_pessoa: pessoa.situacao, projeto_id: null, projeto: null, responsavel_id: null, responsavel: null,
    proximo_passo: null, proximo_passo_em: null, entrou_etapa_em: dia(1), criado_em: dia(3), fechado_em: et.tipo === 'aberta' ? null : dia(1),
    motivo_perda: null, externo_tipo: null, ...extra,
  };
};
const P = (id: string) => PESSOAS.find((p) => p.id === id)!;

const NEGOCIOS: Negocio[] = [
  neg('n1', 1, 1, P('p1'), { projeto_id: 2, projeto: 'HT33', responsavel_id: 'r1', responsavel: 'Responsável Exemplo 1', proximo_passo: 'Explicar como entrar na área de membros', proximo_passo_em: hoje(-1) }),
  neg('n2', 1, 2, P('p5'), { projeto_id: 2, projeto: 'HT33', responsavel_id: 'r2', responsavel: 'Responsável Exemplo 2', proximo_passo: 'Confirmar presença no evento', proximo_passo_em: hoje(2) }),
  neg('n3', 2, 5, P('p2'), { projeto_id: 1, projeto: 'PB26', proximo_passo: 'Primeiro contato', proximo_passo_em: hoje() }),
  neg('n4', 2, 7, P('p4'), { projeto_id: 1, projeto: 'PB26', responsavel_id: 'r1', responsavel: 'Responsável Exemplo 1', proximo_passo: 'Retornar a proposta', proximo_passo_em: hoje(1) }),
  neg('n5', 3, 10, P('p3'), { projeto_id: 2, projeto: 'HT33', responsavel_id: 'r2', responsavel: 'Responsável Exemplo 2', proximo_passo: 'Mandar o link do carrinho de novo', proximo_passo_em: hoje(-2) }),
  neg('n6', 4, 15, P('p6'), { projeto_id: 2, projeto: 'HT33', proximo_passo: 'Entender o motivo do cancelamento' }),
  neg('n7', 2, 9, P('p6'), { projeto_id: 3, projeto: 'SEMSET26', motivo_perda: 'Motivo fictício', criado_em: dia(25) }),
];

const HISTORICO: Record<string, { quando: string; acao: string; de: string | null; para: string | null; por: string | null }[]> = {};

const REVISOES: RevisaoPendente[] = [{
  id: 1, motivo: 'so_nome', criado_em: dia(1), detalhe: { casou_por: null, tipos: [] },
  pessoa: { id: 'p7', nome: 'Bruno Exemplo Lima', situacao: 'revisar', eh_aluno: false, turma: null, criado_em: dia(1) },
  candidatos: [{ id: 'p2', nome: 'Bruno Exemplo Lima', eh_aluno: false, turma: null, situacao: 'ativa' }],
}];

const PERMISSOES = { pode_ver: true, pode_editar: true, pode_ver_doc: true, pode_ver_contato: true };

export const demoConfig = (): ConfigCrm => ({ pipelines: PIPELINES, motivos: [], responsaveis: RESPONSAVEIS, projetos: PROJETOS, permissoes: PERMISSOES });

export function demoListar(pipeline: number, projeto: number | null, responsavel: string | null, status: string | null): Negocio[] {
  return NEGOCIOS.filter((n) => n.pipeline_id === pipeline && (!status || n.status === status)
    && (projeto == null || n.projeto_id === projeto) && (responsavel == null || n.responsavel_id === responsavel))
    .map((n) => ({ ...n, pessoa: P(n.pessoa_id)?.nome ?? n.pessoa, situacao_pessoa: P(n.pessoa_id)?.situacao ?? n.situacao_pessoa }));
}

const etapaPorId = (id: number) => PIPELINES.flatMap((p) => p.etapas).find((e) => e.id === id);
const historico = (n: string, acao: string, de: string | null, para: string | null) =>
  (HISTORICO[n] ??= []).unshift({ quando: new Date().toISOString(), acao, de, para, por: 'Você (demonstração)' });

export function demoMover(id: string, etapaId: number, motivoObs: string | null): Resposta {
  const n = NEGOCIOS.find((x) => x.id === id);
  const de = n && etapaPorId(n.etapa_id);
  const para = etapaPorId(etapaId);
  if (!n || !de || !para || !PIPELINES.find((p) => p.id === n.pipeline_id)?.etapas.some((e) => e.id === etapaId)) return { ok: false, msg: 'Etapa não é deste pipeline.' };
  const cod = validarMovimento(de, para, !!motivoObs);
  if (cod) return { ok: false, msg: MSG_MOVIMENTO[cod], codigo: cod };
  n.etapa_id = para.id; n.status = statusDaEtapa(para.tipo); n.entrou_etapa_em = new Date().toISOString();
  n.fechado_em = n.status === 'aberto' ? null : new Date().toISOString();
  n.motivo_perda = n.status === 'perdido' ? motivoObs : null;
  historico(id, de.tipo !== 'aberta' && para.tipo === 'aberta' ? 'reaberto' : 'etapa', de.nome, para.nome);
  return { ok: true, msg: `Movido para ${para.nome}.` };
}

export function demoEditar(id: string, p: { responsavel_id?: string | null; proximo_passo?: string | null; proximo_passo_em?: string | null; projeto_id?: number | null }): Resposta {
  const n = NEGOCIOS.find((x) => x.id === id);
  if (!n) return { ok: false, msg: 'Negócio não encontrado.' };
  if ('responsavel_id' in p) { n.responsavel_id = p.responsavel_id ?? null; n.responsavel = RESPONSAVEIS.find((r) => r.id === p.responsavel_id)?.nome ?? null; }
  if ('proximo_passo' in p) n.proximo_passo = p.proximo_passo || null;
  if ('proximo_passo_em' in p) n.proximo_passo_em = p.proximo_passo_em || null;
  if ('projeto_id' in p) { n.projeto_id = p.projeto_id ?? null; n.projeto = PROJETOS.find((x) => x.id === p.projeto_id)?.sigla ?? null; }
  historico(id, 'proximo_passo', null, n.proximo_passo);
  return { ok: true, msg: 'Salvo.' };
}

export function demoCriar(p: { pipeline_id: number; pessoa_id: string; projeto_id?: number | null; responsavel_id?: string | null; proximo_passo?: string | null; proximo_passo_em?: string | null }): Resposta {
  const pessoa = P(p.pessoa_id);
  const pipe = PIPELINES.find((x) => x.id === p.pipeline_id);
  if (!pessoa || !pipe) return { ok: false, msg: 'Dados inválidos.' };
  if (NEGOCIOS.some((n) => n.pessoa_id === pessoa.id && n.pipeline_id === pipe.id && n.status === 'aberto' && (n.projeto_id ?? 0) === (p.projeto_id ?? 0))) {
    return { ok: false, msg: 'Esta pessoa já tem um negócio aberto neste pipeline e projeto.' };
  }
  const primeira = pipe.etapas.find((e) => e.tipo === 'aberta' && e.ativa)!;
  const id = novoId('n');
  NEGOCIOS.push(neg(id, pipe.id, primeira.id, pessoa, {
    projeto_id: p.projeto_id ?? null, projeto: PROJETOS.find((x) => x.id === p.projeto_id)?.sigla ?? null,
    responsavel_id: p.responsavel_id ?? null, responsavel: RESPONSAVEIS.find((r) => r.id === p.responsavel_id)?.nome ?? null,
    proximo_passo: p.proximo_passo ?? null, proximo_passo_em: p.proximo_passo_em ?? null, criado_em: new Date().toISOString(), entrou_etapa_em: new Date().toISOString(),
  }));
  historico(id, 'criado', null, primeira.nome);
  return { ok: true, msg: 'Negócio criado.', id };
}

export const demoHistorico = (id: string) => HISTORICO[id] ?? [];

const projetosDa = (id: string) => [...new Set((ORIGENS[id] ?? []).map((o) => o.projeto).filter(Boolean) as string[])];

export function demoBuscar(termo: string | null, projeto: number | null): ItemBusca[] {
  const t = (termo ?? '').trim();
  if (t.length < 3 && projeto == null) return [];
  const nome = normalizarNome(t);
  const email = normalizarEmail(t);
  const doc = normalizarDocumento(t);
  const tel = chaveTelefone(normalizarTelefone(t));
  const sigla = PROJETOS.find((x) => x.id === projeto)?.sigla;
  return PESSOAS.filter((p) => p.situacao !== 'mesclada')
    .filter((p) => !t || (nome && (normalizarNome(p.nome) ?? '').includes(nome)) || (email && p.email === email) || (doc && p.documento === doc)
      || (tel && chaveTelefone(normalizarTelefone(p.telefone)) === tel))
    .filter((p) => !sigla || projetosDa(p.id).includes(sigla) || NEGOCIOS.some((n) => n.pessoa_id === p.id && n.projeto_id === projeto))
    .map((p) => ({
      tipo: 'pessoa' as const, id: p.id, ref: p.ref, nome: p.nome, situacao: p.situacao, teste: false, email: p.email ?? null,
      telefone: p.telefone ?? null, eh_aluno: !!p.aluno, eh_comprador: p.comprador, turma: p.aluno?.turma ?? null, projetos: projetosDa(p.id),
      negocios_abertos: NEGOCIOS.filter((n) => n.pessoa_id === p.id && n.status === 'aberto').length, criado_em: p.criado_em,
    }));
}

export function demoFicha(id: string): Ficha | null {
  const p = P(id);
  if (!p) return null;
  return {
    pessoa: { id: p.id, ref: p.ref, nome: p.nome, situacao: p.situacao, teste: false, criado_em: p.criado_em, mesclada_de: null,
      email: p.email ?? null, telefone: p.telefone ?? null, documento: p.documento ?? null },
    aluno: p.aluno ? { id: p.aluno.id, nome: p.nome, turma: p.aluno.turma, cancelado: false } : null,
    comprador_id: p.comprador ? 'comprador-ficticio' : null,
    identificadores: p.aluno ? [] : [
      ...(p.email ? [{ tipo: 'email' as const, origem: 'formulario', criado_em: p.criado_em, valor: p.email }] : []),
      ...(p.telefone ? [{ tipo: 'telefone' as const, origem: 'formulario', criado_em: p.criado_em, valor: p.telefone }] : []),
    ],
    origens: ORIGENS[id] ?? [],
    eventos: [...(EVENTOS[id] ?? [])].sort((a, b) => (a.quando < b.quando ? 1 : -1)),
    compras: COMPRAS[id] ?? [],
    negocios: NEGOCIOS.filter((n) => n.pessoa_id === id).map((n) => {
      const pl = PIPELINES.find((x) => x.id === n.pipeline_id)!;
      const et = etapaPorId(n.etapa_id)!;
      return { id: n.id, pipeline_id: pl.id, pipeline: pl.nome, pipeline_tipo: pl.tipo, etapa_id: et.id, etapa: et.nome, etapa_tipo: et.tipo,
        status: n.status, projeto: n.projeto, projeto_id: n.projeto_id, responsavel_id: n.responsavel_id, responsavel: n.responsavel,
        proximo_passo: n.proximo_passo, proximo_passo_em: n.proximo_passo_em, motivo_perda: n.motivo_perda, criado_em: n.criado_em, fechado_em: n.fechado_em };
    }),
    revisoes: REVISOES.filter((r) => r.pessoa.id === id || r.candidatos.some((c) => c.id === id)).map((r) => ({ id: r.id, motivo: r.motivo, criado_em: r.criado_em })),
    permissoes: { pode_editar: true, pode_ver_doc: true, pode_ver_contato: true },
  };
}

export function demoCadastrar(e: Entrada): Resposta {
  if (!temIdentificador(e)) return { ok: false, msg: 'Informe um e-mail, telefone (com DDD) ou documento válido.' };
  const r = resolverIdentidade(e, PESSOAS.filter((p) => p.situacao !== 'mesclada'));
  if (r.pessoaId) return { ok: true, msg: 'Esta pessoa já existia: o registro foi ligado a ela.', pessoa_id: r.pessoaId, revisao: r.revisao };
  const id = novoId('p');
  PESSOAS.push({ id, ref: `pe_demo${seq}`, nome: e.nome?.trim() || null, email: normalizarEmail(e.email), telefone: normalizarTelefone(e.telefone),
    documento: normalizarDocumento(e.documento), situacao: r.revisao ? 'revisar' : 'ativa', aluno: null, comprador: false, criado_em: new Date().toISOString() });
  (EVENTOS[id] ??= []).push({ id: seq, tipo: 'cadastro', quando: new Date().toISOString(), projeto: null, fonte: 'crm', ref_tipo: null, ref_id: null, detalhe: {}, por: 'Você (demonstração)' });
  if (r.revisao) {
    REVISOES.push({ id: seq, motivo: r.revisao, criado_em: new Date().toISOString(), detalhe: { casou_por: null, tipos: [] },
      pessoa: { id, nome: e.nome ?? null, situacao: 'revisar', eh_aluno: false, turma: null, criado_em: new Date().toISOString() },
      candidatos: r.candidatos.map((c) => ({ id: c, nome: P(c)?.nome ?? null, eh_aluno: !!P(c)?.aluno, turma: P(c)?.aluno?.turma ?? null, situacao: P(c)?.situacao ?? 'ativa' })) });
  }
  return { ok: true, msg: r.revisao ? 'Cadastrado. Pode ser alguém que já existe: ficou para revisão.' : 'Pessoa nova cadastrada.', pessoa_id: id, revisao: r.revisao };
}

export const demoRevisoes = (): RevisaoPendente[] => REVISOES;

export function demoDecidir(id: number, decisao: 'mesma' | 'diferente', alvo: string | null): Resposta {
  const i = REVISOES.findIndex((r) => r.id === id);
  if (i < 0) return { ok: false, msg: 'Revisão não encontrada ou já decidida.' };
  const r = REVISOES[i];
  const p = P(r.pessoa.id);
  if (decisao === 'mesma') {
    if (!alvo || !r.candidatos.some((c) => c.id === alvo)) return { ok: false, msg: 'Escolha uma das pessoas candidatas.' };
    p.situacao = 'mesclada';
    NEGOCIOS.filter((n) => n.pessoa_id === p.id).forEach((n) => { n.pessoa_id = alvo; });
    ORIGENS[alvo] = [...(ORIGENS[alvo] ?? []), ...(ORIGENS[p.id] ?? [])];
    EVENTOS[alvo] = [...(EVENTOS[alvo] ?? []), ...(EVENTOS[p.id] ?? [])];
  } else {
    p.situacao = 'ativa';
  }
  REVISOES.splice(i, 1);
  return { ok: true, msg: decisao === 'mesma' ? 'Pessoas juntadas.' : 'Marcadas como pessoas diferentes.' };
}

/** Mesmo efeito da máscara do banco, para mostrar na demonstração como o operador sem permissão veria. */
export const demoMascarado = (f: Ficha): Ficha => ({
  ...f, pessoa: { ...f.pessoa, email: mascararEmail(f.pessoa.email), telefone: mascararFim(f.pessoa.telefone), documento: mascararFim(f.pessoa.documento) },
});
