// Resumo do dia da Central do Tráfego ("o que está pegando fogo"). Domínio puro.
//
// O banco é quem decide (mkt_trafego.alertas, migration 20261005r); aqui ficam:
//   - textoAlerta: a frase que a tela mostra para cada alerta;
//   - calcularAlertas: as MESMAS regras, para o modo de demonstração e para os testes (alertas.test.ts confere os
//     mesmos números do ensaio da 20261005r). Mudou lá, muda aqui.
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

import { arredondar } from './kpis';
import type { Alerta, LinhaResumo, Regra, RegraAlerta } from './tipos';

const DIA_MS = 86400000;
const dia = (ymd: string) => Date.UTC(Number(ymd.slice(0, 4)), Number(ymd.slice(5, 7)) - 1, Number(ymd.slice(8, 10)));
const dias = (de: string, ate: string) => Math.round((dia(ate) - dia(de)) / DIA_MS);

export interface FaseEntrada { fase: string; nome: string; verba: number | null; inicio: string | null; fim: string | null; gastoAteOntem: number }
export interface CampanhaEntrada { fora_padrao: boolean; fase: string | null; ultimoGasto: string | null }
export interface ProjetoEntrada {
  linha: Pick<LinhaResumo, 'projeto_id' | 'sigla' | 'nome' | 'investido' | 'verba_maxima' | 'verba_diaria' | 'gasto_ontem' | 'ritmo_ontem'
    | 'pct_verba' | 'leads' | 'meta_leads' | 'cpl' | 'meta_cpl' | 'inicio' | 'fim'>;
  /** Projeto ativo em mkt.projetos e com status que entra no resumo do dia. */
  entra: boolean;
  fases: FaseEntrada[];
  campanhas: CampanhaEntrada[];
}

const ORDEM: RegraAlerta[] = ['acima_verba_diaria', 'cpl_acima_meta', 'leads_abaixo_meta', 'ritmo_fase', 'verba_perto_fim', 'fora_padrao', 'sem_fase'];

export function calcularAlertas(ontem: string, regras: Regra[], projetos: ProjetoEntrada[], semProjeto: CampanhaEntrada[]): Alerta[] {
  const rg = new Map(regras.filter((r) => r.ligada).map((r) => [r.codigo, r]));
  const out: Alerta[] = [];
  const add = (regra: RegraAlerta, p: ProjetoEntrada['linha'] | null, valor: number, referencia: number | null, detalhe: Alerta['detalhe']) => {
    const r = rg.get(regra)!;
    out.push({ regra, nome: r.nome, gravidade: r.gravidade, limiar: r.limiar, unidade: r.unidade, projeto_id: p?.projeto_id ?? null,
      sigla: p?.sigla ?? null, projeto_nome: p?.nome ?? null, valor, referencia, detalhe });
  };
  const recente = (ultimo: string | null, n: number) => ultimo != null && dias(ultimo, ontem) < n;

  for (const { linha: l, entra, fases, campanhas } of projetos) {
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
      const ini = cap ? cap.inicio! : l.inicio;
      const fim = cap ? cap.fim! : l.fim;
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
