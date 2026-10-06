import { describe, expect, it } from 'vitest';
import { comKpis } from '../domain/kpis';
import {
  demoAlertas, demoAplicarPacote, demoCadastro, demoChecklist, demoListasCadastro, demoMarcarChecklist, demoSalvarCadastro, demoSalvarPacote,
  demoAjustarCampanha, demoApagarProduto, demoCampanhas, demoContas, demoProdutos, demoProjeto, demoResumo, demoSalvarFase, demoSalvarProduto,
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
    expect(demoCampanhas(null, true, false).map((c) => c.id)).toEqual([7, 8, 12]);
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
  it('receita (fase 2): PB26 com o produto Exemplo ligado; sem vínculo = sem dado; vínculo sem período não soma', () => {
    expect(demoResumo().find((l) => l.sigla === 'PB26')!.receita).toBe(18450);
    expect(demoResumo().find((l) => l.sigla === 'HT33')!.receita).toBeNull();
    const r = demoSalvarProduto({ projeto_id: 2, produto_id: '0000002', oferta_codigo: '', de: '', ate: '', obs: '' });
    expect([r.ok, r.avisos]).toEqual([true, ['sem_periodo']]);
    const ht = demoResumo().find((l) => l.sigla === 'HT33')!;
    expect([ht.receita, ht.receita_vinculos, ht.receita_sem_periodo]).toEqual([null, 1, 1]);
    demoApagarProduto(demoProdutos(2)[0].id);
    expect(demoSalvarProduto({ projeto_id: 1, produto_id: '0000001', oferta_codigo: '', de: '', ate: '', obs: '' }).ok).toBe(false);
  });
  it('cadastro (20261006a): reais sem unidade nem contas; fictícios com tipo, unidade, lançamento e especialista Exemplo', () => {
    const pb = demoCadastro(1)!;
    expect([pb.tipo, pb.unidade, pb.tipo_lancamento, pb.contas]).toEqual(['interno', null, null, []]);
    const dexa = demoResumo().find((l) => l.sigla === 'DEXA26')!;
    expect([dexa.tipo, dexa.unidade_nome, dexa.tipo_lancamento_nome, dexa.especialista, dexa.receita_aplica]).toEqual(
      ['externo', 'Diamantes', 'Lançamento clássico', 'Especialista Exemplo', false]);
    expect(demoResumo().find((l) => l.sigla === 'AEXA26')!.tipo_lancamento).toBe('palestra');
    const l = demoListasCadastro();
    expect(l.regras.escritorio).toEqual(['lancamento_classico', 'lpsg', 'atm']);
    expect(l.especialistas.filter((e) => e.tipo === 'interno').map((e) => e.nome)).toEqual(['Marcio Carvalho de Sá', 'Elaine Montenegro']);
    expect(l.pacotes).toEqual([]);
  });
  it('sugestão pela conta e sigla; alerta de conta de fora', () => {
    expect(demoCadastro(7)!.sugestoes.map((x) => x.id)).toEqual([12]);
    const a = demoAlertas().alertas.find((x) => x.regra === 'conta_fora_projeto')!;
    expect([a.sigla, a.valor, a.detalhe.contas]).toEqual(['LPEXA26', 1, ['Conta Exemplo Diamante']]);
  });
  it('salvar: regra da unidade, Aurum sozinho, especialista externo novo', () => {
    const base = { sigla: 'ZZEX26', nome: 'Teste Exemplo', linha: 'Exemplo', etiqueta_clickup: '', inicio: '', fim: '', captacao_inicio: '', captacao_fim: '',
      evento_inicio: '', evento_fim: '', ativo: true, especialista_id: null, especialista_nome: '', status: '', gestores: [], contas: [] };
    expect(demoSalvarCadastro({ ...base, tipo: 'interno', unidade: 'escritorio', tipo_lancamento: 'lancamento_pago' }).ok).toBe(false);
    const r = demoSalvarCadastro({ ...base, tipo: 'externo', unidade: 'aurum', tipo_lancamento: '', especialista_nome: 'Pessoa Exemplo Nova' });
    expect([r.ok, r.tipo_lancamento, r.avisos]).toEqual([true, 'palestra', ['especialista_cadastrado']]);
  });
  it('pacote vazio; aplicar cria a captação com o período de captação', () => {
    expect(demoAplicarPacote(7).ok).toBe(false);
    demoSalvarPacote({ tipo_lancamento: 'lancamento_pago', fase: 'captacao', ordem: '1', objetivos: ['VENDAS'], pct_verba: '50', dias: '', obs: '' });
    expect(demoAplicarPacote(7).ok).toBe(true);
    const f = demoProjeto(7)!.fases.find((x) => x.fase === 'captacao')!;
    expect([f.verba, f.inicio]).toEqual([4500, demoCadastro(7)!.captacao_inicio]);
  });
  it('checklist: automáticos + manual marcado por alguém; progresso no resumo', () => {
    const c = demoChecklist(7)!;
    expect(c.manuais[0]).toMatchObject({ texto: 'Automação de ingresso no grupo do WhatsApp configurada no SendFlow', ok: true });
    expect(demoResumo().find((l) => l.sigla === 'LPEXA26')!.checklist_feitos).toBe(c.feitos);
    demoMarcarChecklist(7, 1, false);
    expect(demoChecklist(7)!.feitos).toBe(c.feitos - 1);
    expect(demoChecklist(6)!.automaticos.find((i) => i.codigo === 'hotmart')!.aplica).toBe(false);
  });
});
