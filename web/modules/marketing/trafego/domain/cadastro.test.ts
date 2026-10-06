import { describe, expect, it } from 'vitest';
import {
  PROJETO_FORM_VAZIO, ajustarForm, etiquetaSemAnoMes, lancamentoAutomatico, lancamentosDaUnidade, linhaUtm, montarChecklist, montarNomeCampanha, porMomento,
  nomeTemSigla, periodoProjeto, periodoReceita, validarCadastro, type ListasCadastro,
} from './cadastro';

// As listas são as sementes da migration 20261006j (unidades, tipos e regras, especialistas internos, UTM do Meta).
const L: ListasCadastro = {
  unidades: [
    { codigo: 'csm', tipo: 'interno', nome: 'CSM', descricao: null }, { codigo: 'escritorio', tipo: 'interno', nome: 'Escritório', descricao: null },
    { codigo: 'aurum', tipo: 'externo', nome: 'Aurum', descricao: null }, { codigo: 'diamantes', tipo: 'externo', nome: 'Diamantes', descricao: null },
  ],
  tipos_lancamento: [
    { codigo: 'lancamento_classico', nome: 'Lançamento clássico' }, { codigo: 'lancamento_pago', nome: 'Lançamento pago' },
    { codigo: 'lpsg', nome: 'Lançamento pago semanal gravado (LPSG)' }, { codigo: 'atm', nome: 'ATM' }, { codigo: 'palestra', nome: 'Palestra' },
  ],
  regras: { csm: ['lancamento_classico', 'lancamento_pago', 'lpsg', 'atm'], escritorio: ['lancamento_classico', 'atm'], aurum: ['palestra'], diamantes: ['lancamento_classico', 'lancamento_pago'] },
  especialistas: [{ id: 1, nome: 'Marcio Carvalho de Sá', tipo: 'interno', unidade: null }, { id: 9, nome: 'Especialista Exemplo', tipo: 'externo', unidade: 'aurum' }],
  objetivos: ['ANTECIPAÇÃO', 'AQUECIMENTO', 'CARRINHO', 'DISTRIBUIÇÃO', 'LEADS', 'LEMBRETE', 'REMARKETING', 'VENDAS'],
  utm: { meta: [
    { parametro: 'utm_source', valor: 'metaads' }, { parametro: 'utm_campaign', valor: '{{campaign.name}}|{{campaign.id}}' },
    { parametro: 'utm_medium', valor: '{{adset.name}}|{{adset.id}}' }, { parametro: 'utm_content', valor: '{{ad.name}}|{{ad.id}}' },
    { parametro: 'utm_term', valor: '{{placement}}' },
  ] },
  modelos: [], etiquetas_clickup: [],
};
const F = { ...PROJETO_FORM_VAZIO, sigla: 'zz28', nome: 'Exemplo' };

describe('cadastro do projeto (as regras do banco na tela)', () => {
  it('tipo de lançamento por unidade; pago e LPSG só na CSM; Aurum fixo em palestra', () => {
    expect(lancamentosDaUnidade(L, 'escritorio').map((t) => t.codigo)).toEqual(['lancamento_classico', 'atm']);
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'escritorio', tipo_lancamento: 'lpsg' })).toMatch(/não vale/);
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'csm', tipo_lancamento: 'lpsg' })).toBeNull();
    expect(lancamentoAutomatico(L, 'aurum')).toBe('palestra');
    expect(lancamentoAutomatico(L, 'diamantes')).toBeNull();
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'escritorio', tipo_lancamento: 'lancamento_pago' })).toMatch(/não vale/);
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'csm', tipo_lancamento: 'lancamento_pago' })).toBeNull();
    expect(validarCadastro(L, { ...F, tipo: 'externo', unidade: 'diamantes', tipo_lancamento: 'palestra' })).toMatch(/não vale/);
  });
  it('unidade do tipo, especialista do tipo, interno só da lista', () => {
    expect(validarCadastro(L, { ...F, tipo: 'externo', unidade: 'csm' })).toMatch(/Aurum ou Diamantes/);
    expect(validarCadastro(L, { ...F, tipo: '' })).toMatch(/interno ou externo/);
    expect(validarCadastro(L, { ...F, tipo: 'externo', unidade: 'aurum', especialista_id: 1 })).toMatch(/Especialista/);
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'csm', especialista_nome: 'Novo' })).toMatch(/da lista/);
  });
  it('ajustar: trocar unidade limpa o lançamento que não vale e preenche o automático', () => {
    const a = ajustarForm(L, { ...F, tipo: 'interno', unidade: 'csm', tipo_lancamento: 'lancamento_pago' });
    expect(ajustarForm(L, { ...a, unidade: 'escritorio' }).tipo_lancamento).toBe('');
    expect(ajustarForm(L, { ...F, tipo: 'externo', unidade: 'aurum' }).tipo_lancamento).toBe('palestra');
    expect(ajustarForm(L, { ...F, tipo: 'interno', unidade: 'aurum' }).unidade).toBe('');
  });
  it('períodos: os dois completos ou vazios; o projeto vai do começo mais cedo ao fim mais tarde', () => {
    const p = { ...F, tipo: 'interno' as const, unidade: 'csm' };
    expect(validarCadastro(L, { ...p, captacao_inicio: '2026-11-01' })).toMatch(/início e fim/);
    expect(validarCadastro(L, { ...p, evento_inicio: '2026-11-10', evento_fim: '2026-11-01' })).toMatch(/Evento/);
    expect(periodoProjeto({ ...p, captacao_inicio: '2026-11-01', captacao_fim: '2026-11-20', evento_inicio: '2026-11-25', evento_fim: '2026-11-27' }))
      .toEqual({ inicio: '2026-11-01', fim: '2026-11-27' });
    expect(periodoProjeto({ ...p, inicio: '2026-03-01', fim: '2026-03-31' })).toEqual({ inicio: '2026-03-01', fim: '2026-03-31' });
  });
  it('período da receita (provisório): do início da captação ao fim do evento; os números do ensaio', () => {
    expect(periodoReceita({ inicio: '2026-11-01', fim: '2026-11-27', captacao_inicio: '2026-11-01', captacao_fim: '2026-11-20', evento_inicio: '2026-11-25', evento_fim: '2026-11-27' }))
      .toEqual({ inicio: '2026-11-01', fim: '2026-11-27' });
    expect(periodoReceita({ inicio: '2026-03-01', fim: '2026-03-31', captacao_inicio: null, captacao_fim: null, evento_inicio: null, evento_fim: null }))
      .toEqual({ inicio: '2026-03-01', fim: '2026-03-31' });
    expect(periodoReceita({ inicio: '2026-11-01', fim: '2026-11-20', captacao_inicio: '2026-11-01', captacao_fim: '2026-11-20', evento_inicio: null, evento_fim: null }))
      .toEqual({ inicio: '2026-11-01', fim: '2026-11-20' });
  });
  it('etiqueta: formato da chave; edição com data sem -aaaa-mm só avisa', () => {
    expect(validarCadastro(L, { ...F, tipo: 'interno', unidade: 'csm', etiqueta_clickup: 'Etiqueta Errada' })).toMatch(/chave/);
    expect(etiquetaSemAnoMes('sem-set-2026', '2026-09-30')).toBe(true);
    expect(etiquetaSemAnoMes('black-friday-2026-10', '2026-11-30')).toBe(false);
    expect(etiquetaSemAnoMes('holding-masters', '')).toBe(false);
  });
});

describe('gerador de nome de campanha e UTM', () => {
  const listas = { gestores: ['CF', 'RS', 'EF'], objetivos: L.objetivos };
  it('monta o nome no padrão, com e sem página', () => {
    expect(montarNomeCampanha({ gestor: 'RS', sigla: 'PB26', objetivo: 'LEADS', descricao: 'teste de escritórios', pagina: 'ak1' }, listas))
      .toEqual({ nome: 'RS | PB26 | LEADS | TESTE DE ESCRITÓRIOS | AK1', erros: [] });
    expect(montarNomeCampanha({ gestor: 'CF', sigla: 'PB26', objetivo: 'DISTRIBUIÇÃO', descricao: 'Vídeo', pagina: '' }, listas).nome)
      .toBe('CF | PB26 | DISTRIBUIÇÃO | VÍDEO');
  });
  it('descrição livre com várias partes (revisão de 06/10/2026)', () => {
    const l = listas;
    expect(montarNomeCampanha({ gestor: 'CF', sigla: 'BF26', objetivo: 'ANTECIPAÇÃO', descricao: 'teaser | meta |pq| abo | thruplay', pagina: '' }, l).nome)
      .toBe('CF | BF26 | ANTECIPAÇÃO | TEASER | META | PQ | ABO | THRUPLAY');
    expect(montarNomeCampanha({ gestor: 'RS', sigla: 'PB26', objetivo: 'LEADS', descricao: 'teaser | meta', pagina: 'ak1' }, listas).nome)
      .toBe('RS | PB26 | LEADS | TEASER | META | AK1');
  });
  it('recusa parte vazia, última parte com cara de página sem página escolhida, e campo faltando', () => {
    expect(montarNomeCampanha({ gestor: 'RS', sigla: 'PB26', objetivo: 'LEADS', descricao: 'A || B', pagina: '' }, listas).erros[0]).toMatch(/parte vazia/);
    expect(montarNomeCampanha({ gestor: 'RS', sigla: 'PB26', objetivo: 'LEADS', descricao: 'TESTE | AK1', pagina: '' }, listas).erros[0]).toMatch(/código de página/);
    expect(montarNomeCampanha({ gestor: '', sigla: 'PB26', objetivo: 'LEADS', descricao: 'X', pagina: '' }, listas).nome).toBeNull();
  });
  it('linha de UTM do Meta com as macros oficiais, na ordem da tabela', () => {
    expect(linhaUtm(L.utm.meta)).toBe('utm_source=metaads&utm_campaign={{campaign.name}}|{{campaign.id}}&utm_medium={{adset.name}}|{{adset.id}}&utm_content={{ad.name}}|{{ad.id}}&utm_term={{placement}}');
  });
  it('sigla no nome como palavra inteira (a mesma regra das sugestões do banco)', () => {
    expect(nomeTemSigla('zr28 ensaio fora do padrão', 'ZR28')).toBe(true);
    expect(nomeTemSigla('outra zr280 ensaio', 'ZR28')).toBe(false);
    expect(nomeTemSigla('RS | ZR28 | LEADS | X', 'ZR28')).toBe(true);
  });
});

describe('checklist de montagem (a mesma regra de mkt_trafego.checklist da 20261006l)', () => {
  const base = { tipo: 'interno' as const, contas: 2, campanhas: 3, foraPadrao: 1, semFase: 1, produtosHotmart: 0, paginas: 0,
    etiqueta: null, verbaMaxima: null, fases: 0, metas: [null, null, null], modelo: null, esperadas: [],
    encontradas: [], status: null, eventoFim: null, hoje: '2026-10-06' };
  const itens = [{ id: 1, texto: 'Automação de ingresso no grupo de leads configurada no SendFlow', momento: 'antes' as const, feito_em: null, feito_por: null, do_modelo: true }];
  it('sem modelo nem esperadas: 2 de 12 (contas e campanhas); cada item com momento e ação', () => {
    const c = montarChecklist(base, itens);
    expect([c.feitos, c.total]).toEqual([2, 12]);
    expect(c.automaticos.find((i) => i.codigo === 'modelo')).toMatchObject({ momento: 'antes', acao: 'modelo', ok: false });
    expect(porMomento(c).map((g) => g.itens.length)).toEqual([9, 4, 1]);
    expect(c.pendentes_antes).toContain('Automação de ingresso no grupo de leads configurada no SendFlow');
  });
  it('externo sem campanha: Hotmart, fora do padrão e fase não se aplicam', () => {
    const c = montarChecklist({ ...base, tipo: 'externo', campanhas: 0, foraPadrao: 0, semFase: 0 }, itens);
    expect(c.total).toBe(9);
  });
  it('campanhas esperadas × encontradas e encerramento depois do evento', () => {
    const esperadas = [{ id: 1, objetivo: 'LEADS', fase: 'captacao', descricao: null, pagina: null }, { id: 2, objetivo: 'LEADS', fase: 'captacao', descricao: null, pagina: 'ak1' },
      { id: 3, objetivo: 'LEMBRETE', fase: 'lembrete', descricao: null, pagina: null }];
    const c = montarChecklist({ ...base, modelo: 'Modelo Exemplo', esperadas, encontradas: [{ objetivo: 'LEADS', pagina: null }, { objetivo: 'LEADS', pagina: 'ak1' }],
      eventoFim: '2026-10-01', status: 'ativo' }, [{ ...itens[0], feito_em: '2026-10-05T10:00:00Z', feito_por: 'Pessoa Exemplo' }]);
    expect(c.automaticos.find((i) => i.codigo === 'campanhas_esperadas')!.detalhe).toBe('2 de 3');
    expect(c.esperadas!.map((e) => e.criada)).toEqual([true, true, false]);
    expect(c.automaticos.find((i) => i.codigo === 'encerrado')).toMatchObject({ aplica: true, ok: false });
    expect(c.manuais[0].marcado_por).toBe('Pessoa Exemplo');
  });
});
