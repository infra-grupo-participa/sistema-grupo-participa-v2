'use client';

import { ehPago, linhasCaptacao } from '../domain/metricas';
import { ingressoGrupoGeral, leadsDoTrafego, leadsPessoas } from '../domain/numeros';
import type { GrupoResumoBlack, LinhaPerfil } from '../domain/tipos';
import type { IndiceTrafego } from '../domain/metricas';
import { taxa } from '../domain/metricas';
import { Taxa, inteiro } from './pecas';

/** Exibe os totais de leads e de ingresso calculáveis pelo perfil, sem inferir em qual grupo cada pessoa entrou. */
export function ResumoLeads({ linhas, idx, grupo, compacto = false, semDado = false }: {
  linhas: LinhaPerfil[]; idx: IndiceTrafego; grupo?: GrupoResumoBlack | null; compacto?: boolean; semDado?: boolean;
}) {
  const trafego = linhasCaptacao(linhas, idx).filter(ehPago);
  const total = semDado ? null : leadsPessoas(linhas).valor;
  const pagosTrafego = semDado ? null : leadsDoTrafego(linhas, idx).valor;
  const ingressoGeral = semDado ? { valor: null, num: null, den: null, recorte: 'sem fonte', nota: null } : ingressoGrupoGeral(linhas, grupo);
  const ingressoTrafego = semDado ? { valor: null, num: null, den: null, recorte: 'sem fonte', nota: null } : ingressoGrupoGeral(trafego);
  const itens = [
    { rotulo: 'Leads totais', valor: total === null ? 'Sem dado' : inteiro(total) },
    { rotulo: 'Do tráfego C2/C3', valor: pagosTrafego === null ? 'Sem dado' : inteiro(pagosTrafego) },
    { rotulo: 'Ingresso no grupo geral', taxa: ingressoGeral },
    { rotulo: 'Ingresso no grupo do tráfego', taxa: ingressoTrafego },
  ];
  const detalheSegmento = ([
    ['advogado', 'Advogados', 'Denominador: leads do segmento advogado + estudante de Direito.'],
    ['contador', 'Contadores', 'Denominador: leads do segmento contador.'],
    ['outros', 'Outros', 'Denominador: leads do segmento outros.'],
  ] as const).map(([segmento, nome, dica]) => {
    const grupos = grupo?.grupos.filter((g) => g.segmento === segmento) ?? [];
    const g = grupos.length === 1 ? grupos[0] : null;
    const resumo = semDado || !g ? null : taxa(g.leadsNoGrupo ?? null, g.leadsDoSegmento ?? null,
      grupos.length > 1 ? 'Há mais de um grupo neste segmento; a fonte precisa fornecer união por pessoa.' : null);
    return { nome, resumo, dica };
  });
  const sobreposicoes = semDado ? null : grupo?.leadsEmMaisDeUmGrupo ?? null;

  return (
    <div className="space-y-2" aria-label="Resumo de leads e ingresso no grupo">
      <div className={`grid gap-2 ${compacto ? 'grid-cols-2' : 'grid-cols-2 lg:grid-cols-4'}`}>
        {itens.map((item) => (
          <div key={item.rotulo} title={item.rotulo === 'Ingresso no grupo geral' ? 'números únicos que entraram no grupo ÷ leads únicos' : undefined} className="min-w-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-2">
            <div className="text-[11px] leading-snug text-[var(--fg-3)]">{item.rotulo}</div>
            <div className="mt-1 text-sm font-semibold text-[var(--fg)]">
              {item.taxa ? <><Taxa taxa={item.taxa} />{` · ${inteiro(item.taxa.num)} / ${inteiro(item.taxa.den)}`}</> : item.valor}
            </div>
          </div>
        ))}
      </div>
      <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] px-3 py-2 text-xs text-[var(--fg-2)]">
        <strong className="font-semibold text-[var(--fg)]">Ingresso por grupo</strong>
        <ul className="mt-1 grid gap-x-4 gap-y-1 sm:grid-cols-3">
          {detalheSegmento.map(({ nome, resumo, dica }) => (
            <li key={nome} title={dica}>
              {nome}: <span className="font-semibold">{resumo ? <><Taxa taxa={resumo} />{` · ${inteiro(resumo.num)} / ${inteiro(resumo.den)}`}</> : 'Sem dado'}</span>
            </li>
          ))}
        </ul>
        <p className="mt-1 text-[11px] text-[var(--fg-3)]">
          {sobreposicoes === null ? 'Sem dado de sobreposição entre grupos.' : `${inteiro(sobreposicoes)} pessoas em mais de um grupo`}
        </p>
      </div>
    </div>
  );
}
