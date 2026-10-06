import { describe, expect, it } from 'vitest';
import { motivoErro } from '../../projetos/domain/campanha';
import { comKpis } from '../domain/kpis';
import { somaPct } from '../domain/modelos';
import {
  demoAlertas, demoAplicarModelo, demoAtivarModelo, demoDuplicarModelo, demoMarcarItem, demoModelos, demoPrevias, demoSalvarItem, demoSalvarModelo, demoCadastro, demoChecklist, demoListasCadastro, demoSalvarCadastro, 
  demoAjustarCampanha, demoApagarProduto, demoProdutosVistos, demoReceita, demoSalvarConta, demoCampanhas, demoContas, demoProdutos, demoProjeto, demoResumo, demoSalvarFase, demoSalvarProduto,
} from './demo';

describe('modo de demonstração do Tráfego (dados fictícios)', () => {
  it('projetos: os 4 da semente real + 3 fictícios marcados como Exemplo', () => {
    const r = demoResumo();
    expect(r.map((l) => l.sigla)).toEqual(['PB26', 'HT33', 'SEMSET26', 'BF26', 'DEXA26', 'AEXA26', 'LPEXA26']);
    expect(r.filter((l) => l.tipo === 'externo').every((l) => l.nome.includes('Exemplo'))).toBe(true);
  });
  it('contas e campanhas são fictícias (Conta Exemplo, descrição EXEMPLO)', () => {
    expect(demoContas().every((c) => c.nome.includes('Exemplo'))).toBe(true);
    expect(demoCampanhas(null, false, false).every((c) => /exemplo/i.test(c.nome))).toBe(true);
  });
  it('KPIs do demo seguem o domínio; projeto sem campanha fica sem dado', () => {
    for (const l of demoResumo()) expect(comKpis(l)).toEqual(l);
    const sem = demoResumo().find((l) => l.sigla === 'SEMSET26')!;
    expect([sem.investido, sem.pct_verba, sem.ctr]).toEqual([null, null, null]);
    expect(demoResumo().find((l) => l.sigla === 'PB26')!.investido).toBeGreaterThan(0);
  });
  it('fora do padrão e sem projeto aparecem; fase fora da lista recusada', () => {
    expect(demoCampanhas(null, false, true).length).toBeGreaterThan(0);
    expect(demoCampanhas(null, true, false).map((c) => c.id)).toEqual([7, 8, 12, 15]);
    const bf = demoCampanhas(null, false, false).find((c) => c.id === 13)!;
    expect(demoCampanhas(null, false, true).some((c) => c.id === 13)).toBe(false);
    // ANTECIPAÇÃO entrou na lista (Victor, 06/10/2026): fase antecipação, logo antes da captação
    expect(bf.erros).not.toContain('objetivo_desconhecido');
    expect(bf.objetivo).toBe('ANTECIPAÇÃO');
    expect(bf.fase).toBe('antecipacao');
    expect(motivoErro('objetivo_desconhecido', { ...bf, objetivo: 'XYZ', projeto: bf.projeto_lido })).toBe('Objetivo XYZ não está na lista');
    expect(demoCampanhas(null, false, true).some((c) => c.id === 14)).toBe(false);
    expect(demoAjustarCampanha({ id: 4, fase: 'xyz' }).ok).toBe(false);
    expect(demoSalvarFase({ projeto_id: 1, fase: 'captacao', verba: '1' }).ok).toBe(false);
    expect(demoProjeto(1)!.fases.map((f) => f.fase)).toEqual(['aquecimento', 'captacao', 'lembrete']);
  });
  it('fase pelo objetivo, DISTRIBUIÇÃO em "sem fase", correção à mão prevalece', () => {
    const fase = (id: number) => demoCampanhas(null, false, false).find((c) => c.id === id)!.fase;
    expect([fase(1), fase(2), fase(4), fase(5), fase(9)]).toEqual(['captacao', 'aquecimento', 'captacao', 'remarketing', null]);
    expect(demoProjeto(1)!.campanhas_sem_fase).toBe(1);
    expect(demoAjustarCampanha({ id: 9, fase: 'aquecimento' }).ok).toBe(true);
    expect(fase(9)).toBe('aquecimento');
    expect(demoProjeto(1)!.campanhas_sem_fase).toBe(0);
    demoAjustarCampanha({ id: 9, fase: null });
    expect(fase(9)).toBeNull();
  });
  it('vários gestores por projeto; KPIs com cliques no link e page views', () => {
    const pb = demoResumo().find((l) => l.sigla === 'PB26')!;
    expect(pb.gestores).toEqual(['RS', 'CF']);
    expect(pb.cpc).not.toBeNull();
    expect(pb.connect_rate).not.toBeNull();
    expect(demoResumo().find((l) => l.sigla === 'HT33')!.connect_rate).toBeNull();
  });
  it('receita por nível (decisão de 06/10/2026): PB26 com oferta exclusiva e SCK; o produto inteiro é estimada à parte', () => {
    const pb = demoResumo().find((l) => l.sigla === 'PB26')!;
    // receita do projeto = níveis 1 a 3 (12300 oferta exclusiva + 1990 SCK); a estimada (só produto + período) não soma
    expect([pb.receita, pb.receita_liquida, pb.receita_oferta, pb.receita_sck, pb.receita_estimada]).toEqual([14290, 13590, 12300, 1990, 6150]);
    expect([pb.receita_ofertas_exclusivas, pb.receita_disputa]).toEqual([1, 1]);
    const rec = demoReceita(1)!;
    expect([rec.sem_oferta_exclusiva, rec.disputas_total, rec.sck_chaves]).toEqual([false, 1, ['seminario-conjunto-2026-11', 'pb26']]);
    // uma oferta só pode ser exclusiva de um projeto
    const outra = demoSalvarProduto({ projeto_id: 4, conta: 'academy', produto_id: '0000001', oferta_codigo: 'ex0001', oferta_exclusiva: true, de: '', ate: '', obs: '' });
    expect([outra.ok, outra.msg]).toEqual([false, expect.stringContaining('já é exclusiva de PB26')]);
    expect(demoSalvarProduto({ projeto_id: 4, conta: 'academy', produto_id: '0000001', oferta_codigo: '', oferta_exclusiva: true, de: '', ate: '', obs: '' }).ok).toBe(false);
    expect(demoProdutosVistos()[0].ofertas[0].exclusiva_de).toBe('PB26');
    expect(demoResumo().find((l) => l.sigla === 'HT33')!.receita).toBeNull();
    // sem conta: recusado (auditoria 06/10/2026: o vínculo leva a conta da Hotmart)
    expect(demoSalvarProduto({ projeto_id: 2, produto_id: '0000002', oferta_codigo: '', de: '', ate: '', obs: '' }).ok).toBe(false);
    const r = demoSalvarProduto({ projeto_id: 2, conta: 'escritorio', produto_id: '0000002', oferta_codigo: '', de: '', ate: '', obs: '' });
    expect([r.ok, r.avisos]).toEqual([true, ['sem_periodo', 'sem_oferta_exclusiva']]);
    expect(demoReceita(2)!.sem_oferta_exclusiva).toBe(true);
    // o mesmo id em outra conta: sem venda nela
    expect(demoSalvarProduto({ projeto_id: 2, conta: 'academy', produto_id: '0000002', oferta_codigo: '', de: '', ate: '', obs: '' }).avisos)
      .toEqual(['sem_periodo', 'produto_sem_compras', 'sem_oferta_exclusiva']);
    const ht = demoResumo().find((l) => l.sigla === 'HT33')!;
    expect([ht.receita, ht.receita_vinculos, ht.receita_sem_periodo]).toEqual([null, 2, 2]);
    for (const v of demoProdutos(2)) demoApagarProduto(v.id);
    expect(demoSalvarProduto({ projeto_id: 1, conta: 'academy', produto_id: '0000001', oferta_codigo: '', de: '', ate: '', obs: '' }).ok).toBe(false);
  });
  it('cadastro (20261006j): reais sem unidade nem contas; fictícios com tipo, unidade, lançamento e especialista Exemplo', () => {
    const pb = demoCadastro(1)!;
    expect([pb.tipo, pb.unidade, pb.tipo_lancamento, pb.contas]).toEqual(['interno', null, null, []]);
    const dexa = demoResumo().find((l) => l.sigla === 'DEXA26')!;
    expect([dexa.tipo, dexa.unidade_nome, dexa.tipo_lancamento_nome, dexa.especialista, dexa.receita_aplica]).toEqual(
      ['externo', 'Diamantes', 'Lançamento clássico', 'Especialista Exemplo', false]);
    expect(demoResumo().find((l) => l.sigla === 'AEXA26')!.tipo_lancamento).toBe('palestra');
    const l = demoListasCadastro();
    expect(l.regras.escritorio).toEqual(['lancamento_classico', 'atm']);
    expect(l.especialistas.filter((e) => e.tipo === 'interno').map((e) => e.nome)).toEqual(['Marcio Carvalho de Sá', 'Elaine Montenegro']);
    expect(l.modelos.filter((m) => m.rascunho)).toHaveLength(9);
  });
  it('sugestão pela conta e sigla; alerta de conta de fora', () => {
    expect(demoCadastro(7)!.sugestoes.map((x) => x.id)).toEqual([12]);
    const a = demoAlertas().alertas.find((x) => x.regra === 'conta_fora_projeto')!;
    expect([a.sigla, a.valor, a.detalhe.contas]).toEqual(['LPEXA26', 1, ['Conta Exemplo Diamante']]);
  });
  it('salvar: regra da unidade, Aurum sozinho, especialista externo novo', () => {
    const base = { sigla: 'ZZEX26', nome: 'Teste Exemplo', etiqueta_clickup: '', inicio: '', fim: '', captacao_inicio: '', captacao_fim: '',
      evento_inicio: '', evento_fim: '', ativo: true, especialista_id: null, especialista_nome: '', status: '', gestores: [], contas: [] };
    expect(demoSalvarCadastro({ ...base, tipo: 'interno', unidade: 'escritorio', tipo_lancamento: 'lancamento_pago' }).ok).toBe(false);
    const r = demoSalvarCadastro({ ...base, tipo: 'externo', unidade: 'aurum', tipo_lancamento: '', especialista_nome: 'Pessoa Exemplo Nova' });
    expect([r.ok, r.tipo_lancamento, r.avisos]).toEqual([true, 'palestra', ['especialista_cadastrado']]);
  });
  it('modelos (20261006l): 9 exemplos rascunho; LPEXA26 já com o do lançamento pago aplicado', () => {
    const ms = demoModelos();
    expect(ms.map((m) => m.nome)).toContain('Exemplo: Lançamento pago semanal gravado (LPSG) CSM');
    expect(ms.every((m) => m.rascunho && somaPct(m.fases) === 100)).toBe(true);
    const cad = demoCadastro(7)!;
    expect(cad.modelo?.nome).toBe('Exemplo: Lançamento pago CSM');
    expect(cad.esperadas.map((e) => e.objetivo)).toEqual(['AQUECIMENTO', 'VENDAS', 'LEMBRETE', 'REMARKETING', 'CARRINHO']);
    const cap = demoProjeto(7)!.fases.find((x) => x.fase === 'captacao')!;
    expect([cap.verba, cap.inicio, cap.fim]).toEqual([5400, cad.captacao_inicio, cad.captacao_fim]);
  });
  it('aplicar de novo não duplica; confirmar substitui a fase editada; outra unidade recusada', () => {
    const m = demoModelos().find((x) => x.nome === 'Exemplo: Lançamento pago CSM')!;
    demoSalvarFase({ id: demoProjeto(7)!.fases.find((x) => x.fase === 'captacao')!.id!, projeto_id: 7, fase: 'captacao', verba: '1000', inicio: '', fim: '', obs: '' });
    const p = demoPrevias(7)![0];
    expect(p.fases.find((f) => f.fase === 'captacao')).toMatchObject({ existe: true, muda: true });
    expect(demoAplicarModelo(7, m.id, false)).toMatchObject({ ok: true, criadas: 0, atualizadas: 0, esperadas: 0, itens: 0 });
    expect(demoProjeto(7)!.fases.find((x) => x.fase === 'captacao')!.verba).toBe(1000);
    expect(demoAplicarModelo(7, m.id, true)).toMatchObject({ ok: true, atualizadas: 1 });
    expect(demoProjeto(7)!.fases.find((x) => x.fase === 'captacao')!.verba).toBe(5400);
    const atm = demoModelos().find((x) => x.nome === 'Exemplo: ATM Escritório')!;
    expect(demoAplicarModelo(7, atm.id, false).ok).toBe(false);
  });
  it('salvar, duplicar e inativar modelo', () => {
    const base = demoModelos().find((x) => x.nome === 'Exemplo: ATM CSM')!;
    expect(demoSalvarModelo({ ...base, id: 0, nome: 'Modelo Exemplo LPSG', tipo_lancamento: 'lpsg', unidades: [{ unidade: 'escritorio', padrao: false }] }).ok).toBe(false);
    const r = demoSalvarModelo({ ...base, id: 0, nome: 'Modelo Exemplo ATM', unidades: [{ unidade: 'csm', padrao: true }] });
    expect(r.ok).toBe(true);
    expect(demoModelos().find((x) => x.id === base.id)!.unidades[0].padrao).toBe(false);
    const d = demoDuplicarModelo(r.id!);
    expect(demoModelos().find((x) => x.id === d.id)!.nome).toBe('Modelo Exemplo ATM (cópia)');
    demoAtivarModelo(r.id!, false);
    expect(demoModelos().find((x) => x.id === r.id)!.unidades[0].padrao).toBe(false);
  });
  it('SendFlow: grupo de leads onde há campanha LEADS, grupo de compradores onde há VENDAS (grupo é etapa do funil)', () => {
    const LEADS = 'Automação de ingresso no grupo de leads configurada no SendFlow';
    const COMPRADORES = 'Automação de ingresso no grupo de compradores configurada no SendFlow';
    const ms = demoModelos().filter((m) => m.nome.startsWith('Exemplo: '));
    expect(ms).toHaveLength(9);
    for (const m of ms) {
      const objs = m.campanhas.map((c) => c.objetivo);
      const textos = m.itens.map((i) => i.texto);
      expect(textos.includes(LEADS)).toBe(objs.includes('LEADS'));
      expect(textos.includes(COMPRADORES)).toBe(objs.includes('VENDAS'));
      expect(textos.some((t) => t.includes('grupo do WhatsApp'))).toBe(false);
    }
    expect(ms.find((m) => m.nome === 'Exemplo: Lançamento clássico CSM')!.itens.map((i) => i.texto)).toEqual([LEADS]);
    expect(ms.find((m) => m.nome === 'Exemplo: Lançamento pago CSM')!.itens.map((i) => i.texto)).toEqual([COMPRADORES]);
    expect(ms.find((m) => m.nome === 'Exemplo: ATM CSM')!.itens).toEqual([]);
  });
  it('checklist por momento, item do modelo marcado, item à mão, alerta em captação', () => {
    const c = demoChecklist(7)!;
    expect(c.manuais[0]).toMatchObject({ texto: 'Automação de ingresso no grupo de compradores configurada no SendFlow', ok: true, do_modelo: true, momento: 'antes' });
    expect(c.automaticos.find((i) => i.codigo === 'campanhas_esperadas')!.detalhe).toBe('1 de 5');
    expect(demoResumo().find((l) => l.sigla === 'LPEXA26')!.checklist_feitos).toBe(c.feitos);
    demoMarcarItem(c.manuais[0].id!, false);
    expect(demoChecklist(7)!.feitos).toBe(c.feitos - 1);
    expect(demoSalvarItem({ projeto_id: 7, texto: 'Pixel conferido (exemplo)', momento: 'durante' }).ok).toBe(true);
    expect(demoSalvarItem({ projeto_id: 7, texto: 'pixel conferido (EXEMPLO)', momento: 'antes' }).ok).toBe(false);
    expect(demoChecklist(6)!.automaticos.find((i) => i.codigo === 'hotmart')!.aplica).toBe(false);
    const a = demoAlertas().alertas.find((x) => x.regra === 'checklist_incompleto' && x.sigla === 'LPEXA26')!;
    expect(a.detalhe.itens).toContain('Automação de ingresso no grupo de compradores configurada no SendFlow');
  });
});

describe('contas (20261006k): unidade, principal e inativa', () => {
  it('lista: ativas, principais primeiro; a inativa por último', () => {
    const cs = demoContas();
    expect(cs.slice(0, 2).every((c) => c.principal && c.ativa)).toBe(true);
    expect(cs.at(-1)!.ativa).toBe(false);
  });
  it('unidade precisa combinar com o dono', () => {
    expect(demoSalvarConta({ plataforma: 'meta', conta_externa: '000000000000009', nome: 'Conta Exemplo Nova', dono: 'grupo', unidade: 'aurum' }).ok).toBe(false);
    expect(demoSalvarConta({ plataforma: 'meta', conta_externa: '000000000000009', nome: 'Conta Exemplo Nova', dono: 'grupo', unidade: 'escritorio', principal: true }).ok).toBe(true);
  });
});
