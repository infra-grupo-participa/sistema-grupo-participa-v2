// Resumo do dia da Central do Tráfego ("o que está pegando fogo"). Domínio puro.
//
// O banco é quem decide (mkt_trafego.alertas, migration 20261006i); aqui ficam:
//   - textoAlerta: a frase que a tela mostra para cada alerta;
//   - calcularAlertas: as MESMAS regras, para o modo de demonstração e para os testes (alertas.test.ts confere os
//     mesmos números do ensaio da 20261006i). Mudou lá, muda aqui.
// Limiares: tabela mkt_trafego.alerta_regras (chegam por parâmetro; nada de número fixo aqui).
//   acima_verba_diaria  gasto de ontem > verba diária × (1 + limiar%)
//   cpl_acima_meta      CPL > meta de CPL × (1 + limiar%)
//   leads_abaixo_meta   leads < esperado × (1 − limiar%); esperado = meta × dias passados ÷ dias do período (fase de
//                       captação planejada com datas, senão início e fim do projeto), arredondado
//   ritmo_fase          fase em andamento com verba: gasto desde o início fora de esperado × (1 ± limiar%);
//                       esperado = verba × dias passados ÷ dias da fase
//   verba_perto_fim     % da verba ≥ limiar
//   fora_padrao         campanhas fora do padrão com gasto nos últimos `limiar` dias (inclui as sem projeto)
//   sem_fase            campanhas do projeto sem fase com gasto nos últimos `limiar` dias
//   conta_fora_projeto  (20261006j) campanhas com a sigla do projeto no nome gastando nos últimos `limiar` dias numa conta
//                       que não é do projeto; só avalia projeto com conta ligada
//   checklist_incompleto (20261006l) projeto em captação (ontem entre início e fim da captação) com item do checklist de
//                       "antes de subir as campanhas" pendente, a partir de `limiar` dias do início da captação
//   sem_oferta_exclusiva (20261006l, decisão do Victor de 06/10/2026) projeto interno em captação ou com o carrinho aberto
//                       (ontem dentro da captação, do evento ou da fase abertura de carrinho) sem nenhuma oferta
//                       exclusiva ligada: a receita dele é só estimada. A partir de `limiar` dias do início do período
// Período da meta de leads: a fase de captação planejada com datas; senão o período padrão do projeto (20261006j: a
// captação do projeto, senão início e fim), como mkt_trafego.periodo_padrao.

import { arredondar } from './kpis';
import type { Alerta, LinhaResumo, Regra, RegraAlerta } from './tipos';

const DIA_MS = 86400000;
const dia = (ymd: string) => Date.UTC(Number(ymd.slice(0, 4)), Number(ymd.slice(5, 7)) - 1, Number(ymd.slice(8, 10)));
const dias = (de: string, ate: string) => Math.round((dia(ate) - dia(de)) / DIA_MS);

export interface FaseEntrada { fase: string; nome: string; verba: number | null; inicio: string | null; fim: string | null; gastoAteOntem: number }
export interface CampanhaEntrada { fora_padrao: boolean; fase: string | null; ultimoGasto: string | null; conta_id?: number; conta?: string }
export interface ProjetoEntrada {
  linha: Pick<LinhaResumo, 'projeto_id' | 'sigla' | 'nome' | 'investido' | 'verba_maxima' | 'verba_diaria' | 'gasto_ontem' | 'ritmo_ontem'
    | 'pct_verba' | 'leads' | 'meta_leads' | 'cpl' | 'meta_cpl' | 'inicio' | 'fim'>
    & Pick<Partial<LinhaResumo>, 'captacao_inicio' | 'captacao_fim' | 'evento_inicio' | 'evento_fim' | 'tipo'>;
  /** Projeto ativo em mkt.projetos e com status que entra no resumo do dia. */
  entra: boolean;
  fases: FaseEntrada[];
  campanhas: CampanhaEntrada[];
  /** Contas de anúncio do projeto (20261006j). Vazio = a regra conta_fora_projeto não avalia. */
  contasProjeto?: number[];
  /** Campanhas com a sigla do projeto no nome (ligadas a ele ou não), com a conta. */
  campanhasDaSigla?: CampanhaEntrada[];
  /** Itens do checklist de "antes" ainda pendentes (20261006l). */
  pendentesAntes?: string[];
  /** Ofertas exclusivas ligadas ao projeto. Ausente = a regra sem_oferta_exclusiva não avalia. */
  ofertasExclusivas?: number;
}

const ORDEM: RegraAlerta[] = ['acima_verba_diaria', 'cpl_acima_meta', 'leads_abaixo_meta', 'ritmo_fase', 'verba_perto_fim', 'fora_padrao', 'sem_fase',
  'conta_fora_projeto', 'checklist_incompleto', 'sem_oferta_exclusiva'];

export function calcularAlertas(ontem: string, regras: Regra[], projetos: ProjetoEntrada[], semProjeto: CampanhaEntrada[]): Alerta[] {
  const rg = new Map(regras.filter((r) => r.ligada).map((r) => [r.codigo, r]));
  const out: Alerta[] = [];
  const add = (regra: RegraAlerta, p: ProjetoEntrada['linha'] | null, valor: number, referencia: number | null, detalhe: Alerta['detalhe']) => {
    const r = rg.get(regra)!;
    out.push({ regra, nome: r.nome, gravidade: r.gravidade, limiar: r.limiar, unidade: r.unidade, projeto_id: p?.projeto_id ?? null,
      sigla: p?.sigla ?? null, projeto_nome: p?.nome ?? null, valor, referencia, detalhe });
  };
  const recente = (ultimo: string | null, n: number) => ultimo != null && dias(ultimo, ontem) < n;

  for (const { linha: l, entra, fases, campanhas, contasProjeto, campanhasDaSigla, pendentesAntes, ofertasExclusivas } of projetos) {
    if (!entra) continue;
    let r = rg.get('acima_verba_diaria');
    if (r && l.investido != null && l.verba_diaria != null && l.verba_diaria > 0 && l.gasto_ontem != null
        && l.gasto_ontem > l.verba_diaria * (1 + r.limiar / 100)) {
      add('acima_verba_diaria', l, l.gasto_ontem, l.verba_diaria, { pct: l.ritmo_ontem });
    }
    r = rg.get('cpl_acima_meta');
    if (r && l.cpl != null && l.meta_cpl != null && l.meta_cpl > 0 && l.cpl > l.meta_cpl * (1 + r.limiar / 100)) {
      add('cpl_acima_meta', l, l.cpl, l.meta_cpl, { pct: arredondar((l.cpl / l.meta_cpl) * 100, 1) });
    }
    r = rg.get('leads_abaixo_meta');
    if (r && l.leads != null && l.meta_leads != null && l.meta_leads > 0) {
      const cap = fases.find((f) => f.fase === 'captacao' && f.inicio && f.fim);
      const padrao = l.captacao_inicio ? { ini: l.captacao_inicio, fim: l.captacao_fim ?? null } : { ini: l.inicio, fim: l.fim };
      const ini = cap ? cap.inicio! : padrao.ini;
      const fim = cap ? cap.fim! : padrao.fim;
      if (ini && fim && ini <= ontem) {
        const esperado = arredondar(l.meta_leads * Math.min(1, (dias(ini, ontem) + 1) / (dias(ini, fim) + 1)), 0);
        if (esperado > 0 && l.leads < esperado * (1 - r.limiar / 100)) {
          add('leads_abaixo_meta', l, l.leads, esperado, { meta: l.meta_leads, periodo: cap ? 'captacao' : 'projeto', inicio: ini, fim,
            pct: arredondar((l.leads / esperado) * 100, 1) });
        }
      }
    }
    r = rg.get('ritmo_fase');
    if (r && l.investido != null) {
      for (const f of fases) {
        if (f.verba == null || f.verba <= 0 || !f.inicio || !f.fim || f.inicio > ontem || f.fim < ontem) continue;
        const esperado = arredondar((f.verba * (dias(f.inicio, ontem) + 1)) / (dias(f.inicio, f.fim) + 1), 2);
        if (esperado > 0 && (f.gastoAteOntem > esperado * (1 + r.limiar / 100) || f.gastoAteOntem < esperado * (1 - r.limiar / 100))) {
          add('ritmo_fase', l, f.gastoAteOntem, esperado, { fase: f.fase, fase_nome: f.nome, verba: f.verba, inicio: f.inicio, fim: f.fim,
            direcao: f.gastoAteOntem > esperado ? 'acima' : 'abaixo', pct: arredondar((f.gastoAteOntem / esperado) * 100, 1) });
        }
      }
    }
    r = rg.get('verba_perto_fim');
    if (r && l.pct_verba != null && l.pct_verba >= r.limiar) {
      add('verba_perto_fim', l, l.pct_verba, r.limiar, { investido: l.investido ?? undefined, verba_maxima: l.verba_maxima ?? undefined });
    }
    r = rg.get('fora_padrao');
    if (r) {
      const n = campanhas.filter((c) => c.fora_padrao && recente(c.ultimoGasto, r!.limiar)).length;
      if (n > 0) add('fora_padrao', l, n, null, { dias: r.limiar });
    }
    r = rg.get('sem_fase');
    if (r) {
      const n = campanhas.filter((c) => c.fase == null && recente(c.ultimoGasto, r!.limiar)).length;
      if (n > 0) add('sem_fase', l, n, null, { dias: r.limiar });
    }
    r = rg.get('conta_fora_projeto');
    if (r && contasProjeto && contasProjeto.length > 0) {
      const fora = (campanhasDaSigla ?? []).filter((c) => c.conta_id != null && !contasProjeto.includes(c.conta_id) && recente(c.ultimoGasto, r!.limiar));
      if (fora.length > 0) {
        add('conta_fora_projeto', l, fora.length, null, { dias: r.limiar, contas: [...new Set(fora.map((c) => c.conta ?? String(c.conta_id)))].sort() });
      }
    }
    r = rg.get('checklist_incompleto');
    if (r && l.captacao_inicio && l.captacao_inicio <= ontem && (l.captacao_fim ?? ontem) >= ontem && pendentesAntes && pendentesAntes.length > 0) {
      const d = dias(l.captacao_inicio, ontem);
      if (d >= r.limiar) add('checklist_incompleto', l, pendentesAntes.length, null, { dias: d, itens: pendentesAntes });
    }
    r = rg.get('sem_oferta_exclusiva');
    if (r && ofertasExclusivas === 0 && l.tipo !== 'externo') {
      const dentro = (ini: string | null | undefined, fim: string | null | undefined) => !!ini && ini <= ontem && (fim ?? ini) >= ontem;
      const emCaptacao = !!l.captacao_inicio && l.captacao_inicio <= ontem && (l.captacao_fim ?? ontem) >= ontem;
      const carrinho = fases.filter((f) => f.fase === 'abertura_carrinho' && f.inicio && f.fim && f.inicio <= ontem && f.fim >= ontem)
        .map((f) => f.inicio!).sort()[0];
      const evento = dentro(l.evento_inicio, l.evento_fim) ? l.evento_inicio! : undefined;
      const ini = emCaptacao ? l.captacao_inicio! : [evento, carrinho].filter((x): x is string => !!x).sort()[0];
      if (ini) {
        const d = dias(ini, ontem);
        if (d >= r.limiar) add('sem_oferta_exclusiva', l, 0, null, { fase: emCaptacao ? 'captacao' : 'abertura_carrinho', inicio: ini, dias: d });
      }
    }
  }
  const rf = rg.get('fora_padrao');
  if (rf) {
    const n = semProjeto.filter((c) => c.fora_padrao && recente(c.ultimoGasto, rf.limiar)).length;
    if (n > 0) add('fora_padrao', null, n, null, { dias: rf.limiar });
  }
  return out.sort((a, b) => (a.gravidade === b.gravidade ? 0 : a.gravidade === 'alta' ? -1 : 1)
    || ORDEM.indexOf(a.regra) - ORDEM.indexOf(b.regra)
    || (a.sigla ?? '￿').localeCompare(b.sigla ?? '￿'));
}

const brl = (n: number | null | undefined, casas = 0) =>
  n == null ? 'sem dado' : Number(n).toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', minimumFractionDigits: casas, maximumFractionDigits: casas });
const pct = (n: number | null | undefined) => (n == null ? 'sem dado' : `${Number(n).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`);
const int = (n: number | null | undefined) => (n == null ? 'sem dado' : Number(n).toLocaleString('pt-BR'));
const dataBR = (ymd: string | undefined) => (ymd ? ymd.slice(0, 10).split('-').reverse().join('/') : '');

/** A frase do alerta (sem a sigla do projeto, que a tela mostra ao lado). */
export function textoAlerta(a: Alerta): string {
  const d = a.detalhe;
  switch (a.regra) {
    case 'acima_verba_diaria':
      return `Gastou ${brl(a.valor)} ontem; a verba diária é ${brl(a.referencia)} (${pct(d.pct)}).`;
    case 'cpl_acima_meta':
      return `CPL de ${brl(a.valor, 2)}; a meta é ${brl(a.referencia, 2)} (${pct(d.pct)} da meta).`;
    case 'leads_abaixo_meta':
      return `${int(a.valor)} leads; o esperado para ontem era ${int(a.referencia)} (meta ${int(d.meta)} ${d.periodo === 'captacao' ? 'na captação' : 'no projeto'}, ${dataBR(d.inicio)} a ${dataBR(d.fim)}).`;
    case 'ritmo_fase':
      return `${d.fase_nome ?? d.fase}: gastou ${brl(a.valor)} desde ${dataBR(d.inicio)}; pelo planejado seriam ${brl(a.referencia)} (${pct(d.pct)}, ${d.direcao === 'acima' ? 'acima' : 'abaixo'} do ritmo).`;
    case 'verba_perto_fim':
      return `${pct(a.valor)} da verba máxima já investido${a.valor > 100 ? ' (passou da verba)' : ''}.`;
    case 'fora_padrao':
      return `${int(a.valor)} campanha(s) com nome fora do padrão gastando nos últimos ${int(d.dias)} dias${a.projeto_id == null ? ', sem projeto ligado' : ''}.`;
    case 'conta_fora_projeto':
      return `${int(a.valor)} campanha(s) com a sigla do projeto gastando nos últimos ${int(d.dias)} dias em conta que não é do projeto (${(d.contas ?? []).join(', ')}).`;
    case 'checklist_incompleto':
      return `Em captação há ${int(d.dias)} dia(s) com ${int(a.valor)} item(ns) de "antes de subir as campanhas" pendente(s): ${(d.itens ?? []).join('; ')}.`;
    case 'sem_oferta_exclusiva':
      return `${d.fase === 'captacao' ? 'Em captação' : 'Com o carrinho aberto'} há ${int(d.dias)} dia(s) sem oferta exclusiva ligada: a receita do projeto é só estimada. Crie na Hotmart uma oferta só para este projeto e ligue na vida do projeto marcando "oferta exclusiva".`;
    case 'sem_fase':
      return `${int(a.valor)} campanha(s) sem fase gastando nos últimos ${int(d.dias)} dias (marque a fase na campanha).`;
    default:
      return a.nome;
  }
}

/** Regra em linguagem de gente, com o limiar atual (para a legenda do bloco). */
export function textoRegra(r: Regra): string {
  const l = r.unidade === 'dias' ? `${r.limiar} dias` : `${r.limiar}%`;
  return `${r.nome} (limiar ${l}${r.ligada ? '' : ', desligada'})`;
}
