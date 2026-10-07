// Demonstração da catalogação de origem (20261007141044): regras de exemplo (as mesmas da proposta da migration, em
// resumo), listas do AC e a evidência de entrada de cada contato demo. As contas usam as regras puras do domínio.
import {
  mqlDoEvento, resolverProjeto,
  type CamposEvento, type CanalEntrada, type DetalheOrigem, type ListaAc, type OrigemContato, type OrigemDetalhada,
  type PainelCatalogo, type PendenciaCatalogo, type RegraCatalogo,
} from '../domain/catalogacao';
import type { Contato } from '../domain/types';

/** Nomes do cadastro do Marketing (mkt.projetos) que a demonstração conhece. */
export const PROJETOS_DEMO: Record<string, string> = {
  'seminario-conjunto-2026-11': 'Patrimônio Brasil 2026',
  'black-friday-2026-10': 'Black Friday 2026',
};

export const LISTAS_AC_DEMO: ListaAc[] = [
  { id: '403', nome: 'Holding Total' }, { id: '541', nome: 'CURSO NACIONAL DE FORMAÇÃO EM HOLDING FAMILIAR' },
  { id: '586', nome: 'HT 32 - Leads Lançamento Meteórico' }, { id: '603', nome: 'Patrimônio Brasil - Geral' },
  { id: '607', nome: 'Sessão de Viabilidade [SEMSET26]' }, { id: '613', nome: 'Black Friday 2026' },
  { id: '614', nome: 'Clínica Internacional Diamante Dez/26 - Leads Pré-Checkout' },
];

const r = (id: number, campo: RegraCatalogo['campo'], operador: RegraCatalogo['operador'], padrao: string, projeto: string | null,
  extra: Partial<RegraCatalogo> = {}): RegraCatalogo => ({
  id, campo, operador, padrao, projeto, projetoNome: projeto ? PROJETOS_DEMO[projeto] ?? null : null,
  valeDe: null, valeAte: null, prioridade: projeto ? 100 : 200, ativo: true, nota: null, ...extra,
});

export function regrasDemo(): RegraCatalogo[] {
  return [
    r(1, 'ac_lista', 'comeca', 'Patrimônio Brasil', 'seminario-conjunto-2026-11', { nota: 'Listas 603, 609–612' }),
    r(2, 'ac_tag', 'comeca', 'PB ', 'seminario-conjunto-2026-11', { nota: 'PB = Patrimônio Brasil' }),
    r(3, 'ac_lista', 'igual', 'Black Friday 2026', 'black-friday-2026-10'),
    r(4, 'ac_lista', 'contem', 'HT 32', 'imersao-holding-total-2026-09'),
    r(5, 'hotmart_oferta', 'igual', 'jqigl9li', 'imersao-holding-total-2026-09', { nota: 'HT32: ingresso' }),
    r(6, 'hotmart_oferta', 'igual', '3mcmh0eu', 'imersao-holding-total-2026-09', { valeDe: '2026-09-01', valeAte: '2026-09-30', nota: 'Ingresso padrão do HT: só set/26 é HT32' }),
    r(7, 'ac_lista', 'contem', 'SEMSET', 'seminario-elaine-2026-09'),
    r(8, 'funil', 'igual', 'Clint · MQLS', 'seminario-elaine-2026-09', { nota: 'CONFIRMAR' }),
    r(9, 'ac_tag', 'comeca', '[CNHF - AGO/2026]', 'cnhf-2026-08'),
    r(10, 'ac_lista', 'igual', '403', null, { nota: 'Lista geral "Holding Total"' }),
    r(11, 'ac_tag', 'igual', 'PB MQL', 'seminario-conjunto-2026-11', { tipo: 'mql', nota: 'MQL do Patrimônio Brasil (PB NAO MQL não é)' }),
  ];
}

interface EvidenciaDemo { canal: CanalEntrada; em: string; campos: CamposEvento; linha: string | null; detalhe: DetalheOrigem }

// Evidência de entrada de cada contato demo (determinística pelo índice). Sem dado pessoal: só lista/tag/produto/funil.
const MOLDES: ((em: string) => EvidenciaDemo)[] = [
  (em) => ({ canal: 'hotmart', em, linha: 'ht', campos: { hotmart_produto: '1560865', hotmart_oferta: '4vn5e2td' },
    detalhe: { hotmart: { em, produtoId: '1560865', produto: 'Holding Total', ofertaCodigo: '4vn5e2td', classe: 'aprovada', linha: 'ht' } } }),
  () => ({ canal: 'hotmart', em: '2026-09-12T13:00:00.000Z', linha: 'ht', campos: { hotmart_produto: '1560865', hotmart_oferta: 'jqigl9li' },
    detalhe: { hotmart: { em: '2026-09-12T13:00:00.000Z', produtoId: '1560865', produto: 'Holding Total', ofertaCodigo: 'jqigl9li', classe: 'aprovada', linha: 'ht' } } }),
  (em) => ({ canal: 'activecampaign', em, linha: null, campos: { ac_lista: '603' },
    detalhe: { activecampaign: { em, tipo: 'subscribe', lista: '603', listaNome: 'Patrimônio Brasil - Geral' } } }),
  (em) => ({ canal: 'activecampaign', em, linha: null, campos: { ac_tag: 'PB MQL' },
    detalhe: { activecampaign: { em, tipo: 'contact_tag_added', tag: 'PB MQL' } } }),
  (em) => ({ canal: 'clint', em, linha: 'sv', campos: { funil: 'Clint · MQLS' }, detalhe: { clint: { em, funil: 'Clint · MQLS', linha: 'sv' } } }),
  (em) => ({ canal: 'hotmart', em, linha: 'acelera', campos: { hotmart_produto: '8381847', hotmart_oferta: '30gjdp9b' },
    detalhe: { hotmart: { em, produtoId: '8381847', produto: 'Acelera Holding', ofertaCodigo: '30gjdp9b', classe: 'aprovada', linha: 'acelera' } } }),
  (em) => ({ canal: 'activecampaign', em, linha: null, campos: {}, detalhe: { activecampaign: { em, tipo: 'update' } } }),
  (em) => ({ canal: 'activecampaign', em, linha: null, campos: { ac_lista: '613' },
    detalhe: { activecampaign: { em, tipo: 'subscribe', lista: '613', listaNome: 'Black Friday 2026' } } }),
  (em) => ({ canal: 'manual', em, linha: null, campos: {}, detalhe: {} }),
];

export function evidenciaDemo(c: Pick<Contato, 'criadoEm'>, i: number): EvidenciaDemo {
  return MOLDES[i % MOLDES.length](c.criadoEm);
}

export interface EstadoOrigemDemo { evidencia: EvidenciaDemo; manual: string | null }

export function origemDemo(e: EstadoOrigemDemo, regras: RegraCatalogo[]): OrigemDetalhada {
  const res = e.manual
    ? { projeto: e.manual, regraId: null, motivo: 'manual' as const, campo: null, valor: null }
    : resolverProjeto(e.evidencia.campos, regras, { quando: e.evidencia.em, chavesConhecidas: Object.keys(PROJETOS_DEMO), listas: LISTAS_AC_DEMO });
  const regra = regras.find((x) => x.id === res.regraId) ?? null;
  const mql = mqlDoEvento(e.evidencia.campos, regras, { quando: e.evidencia.em, listas: LISTAS_AC_DEMO });
  return {
    mqlDesde: mql ? e.evidencia.em : null, mqlProjeto: mql?.projeto ?? null, mqlProjetoNome: mql?.projeto ? PROJETOS_DEMO[mql.projeto] ?? null : null,
    canal: e.evidencia.canal, entrouEm: e.evidencia.em, projeto: res.projeto, projetoNome: res.projeto ? PROJETOS_DEMO[res.projeto] ?? null : null,
    linha: e.evidencia.linha, motivo: res.motivo, manual: !!e.manual,
    detalhe: { ...e.evidencia.detalhe, ...(res.campo ? { projetoVeioDe: { fonte: e.evidencia.canal, campo: res.campo, valor: res.valor ?? '' } } : {}) },
    regra: regra && regra.id != null ? { id: regra.id, campo: regra.campo, operador: regra.operador, padrao: regra.padrao } : null,
    podeDefinir: true,
  };
}

export function resumoDeOrigem(o: OrigemDetalhada): OrigemContato {
  return { canal: o.canal, entrouEm: o.entrouEm, projeto: o.projeto, projetoNome: o.projetoNome, linha: o.linha, mqlDesde: o.mqlDesde ?? null };
}

/** Painel da tela Configurações › Catalogação a partir das origens calculadas. */
export function painelDemo(origens: OrigemDetalhada[], estados: EstadoOrigemDemo[], regras: RegraCatalogo[], podeEditar: boolean, podeClassificar = podeEditar): PainelCatalogo {
  const porCanal = new Map<CanalEntrada, { total: number; comProjeto: number }>();
  const porLinha = new Map<string, number>();
  const projetos = new Map<string, number>();
  const pend = new Map<string, PendenciaCatalogo>();
  origens.forEach((o, i) => {
    const c = porCanal.get(o.canal) ?? { total: 0, comProjeto: 0 };
    c.total += 1; if (o.projeto) c.comProjeto += 1;
    porCanal.set(o.canal, c);
    if (o.projeto) projetos.set(o.projeto, (projetos.get(o.projeto) ?? 0) + 1);
    else porLinha.set(o.linha ?? '-', (porLinha.get(o.linha ?? '-') ?? 0) + 1);
    if (o.motivo === 'sem_regra') {
      for (const [campo, valor] of Object.entries(estados[i].evidencia.campos)) {
        if (!valor || campo === 'ac_lista_nome' || campo === 'funil_projeto') continue;
        const k = `${campo}|${valor}`;
        const atual = pend.get(k);
        pend.set(k, {
          campo: campo as PendenciaCatalogo['campo'], valor,
          nome: campo === 'ac_lista' ? LISTAS_AC_DEMO.find((l) => l.id === valor)?.nome ?? null
            : campo === 'hotmart_produto' ? (estados[i].evidencia.detalhe.hotmart?.produto ?? null) : null,
          contatos: (atual?.contatos ?? 0) + 1,
        });
      }
    }
  });
  const chaves = new Set([...Object.keys(PROJETOS_DEMO), ...regras.filter((x) => x.projeto).map((x) => x.projeto as string)]);
  return {
    podeEditar,
    podeClassificar,
    regras: regras.map((x) => ({ ...x, projetoNome: x.projeto ? PROJETOS_DEMO[x.projeto] ?? null : null,
      contatos: origens.filter((o, i) => !estados[i].manual && o.regra?.id === x.id).length })),
    listasAc: [...LISTAS_AC_DEMO].sort((a, b) => Number(b.id) - Number(a.id)),
    projetos: [...chaves].sort().map((chave) => ({ chave, nome: PROJETOS_DEMO[chave] ?? null, contatos: projetos.get(chave) ?? 0 })),
    resumo: {
      total: origens.length,
      comProjeto: origens.filter((o) => o.projeto).length,
      mql: origens.filter((o) => o.mqlDesde).length,
      produtoSemProjeto: origens.filter((o) => !o.projeto && o.linha).length,
      semNada: origens.filter((o) => !o.projeto && !o.linha).length,
      motivos: {
        regra_sem_projeto: origens.filter((o) => o.motivo === 'regra_sem_projeto').length,
        sem_regra: origens.filter((o) => o.motivo === 'sem_regra').length,
        sem_dado: origens.filter((o) => o.motivo === 'sem_dado').length,
      },
      porCanal: [...porCanal].map(([canal, v]) => ({ canal, ...v })).sort((a, b) => b.total - a.total),
      semProjetoPorLinha: [...porLinha].map(([linha, total]) => ({ linha, total })).sort((a, b) => b.total - a.total),
    },
    pendencias: [...pend.values()].sort((a, b) => b.contatos - a.contatos || a.valor.localeCompare(b.valor)),
  };
}

