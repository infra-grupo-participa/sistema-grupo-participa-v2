'use client';

// Bloco C: evolução rumo à Black. Pergunta: "a audiência cresce de uma live para a outra até a venda?".
// Um ponto por live (o pico), uma linha por tipo; abaixo, a conta que sustenta cada leitura: pico ÷ pico da anterior do
// mesmo tipo (soma sobre soma não se aplica aqui: é uma live contra outra, numerador e denominador visíveis).
import { SectionCard } from '@/shared/ui/components';
import { picoContraAnterior, pontosDeEvolucao, ROTULO_TIPO_LIVE, type Live } from '../../domain/lives';
import { GraficoEvolucao } from '../graficos-lives';
import { COR_TIPO, dataCurta, numeroDe, pctDe } from './formatos';

export function EvolucaoLives({ lives, onAbrir }: { lives: Live[]; onAbrir: (videoId: string) => void }) {
  const pontos = pontosDeEvolucao(lives);
  const medidas = pontos.filter((p) => p.pico !== null);
  const comparaveis = lives.filter((l) => picoContraAnterior(lives, l)).sort((a, b) => Date.parse(a.dataPrevista) - Date.parse(b.dataPrevista));
  const temAmostra = lives.some((l) => l.pico !== null && !l.temStudio);
  return (
    <SectionCard title="Evolução rumo à Black" subtitle="Pico de espectadores simultâneos em cada live. Cada tipo é comparado só com ele mesmo.">
      {medidas.length === 0 ? (
        <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">Nenhuma live tem pico medido ainda. Importe o CSV do Studio de uma live realizada para começar.</p>
      ) : (
        <div className="space-y-4">
          <GraficoEvolucao pontos={pontos} lives={lives} onAbrir={onAbrir} rotulo="Pico de espectadores por live, na ordem do calendário" />
          <div className="flex flex-wrap gap-x-4 gap-y-1 text-xs text-[var(--fg-2)]">
            {(['consultoria', 'produto', 'black'] as const).map((t) => (
              <span key={t} className="inline-flex items-center gap-1.5"><span aria-hidden className="h-2.5 w-2.5 rounded-full" style={{ background: COR_TIPO[t] }} />{ROTULO_TIPO_LIVE[t]}</span>
            ))}
            {temAmostra && <span className="inline-flex items-center gap-1.5"><span aria-hidden className="h-2.5 w-2.5 rounded-full border-2 border-[var(--fg-3)]" />círculo vazado: pico amostrado pela API, sem o CSV do Studio</span>}
          </div>
          {comparaveis.length > 0 && (
            <div className="overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]">
              <table className="w-full table-fixed text-left text-sm">
                <caption className="sr-only">Pico de cada live contra o pico da anterior do mesmo tipo</caption>
                <thead className="bg-[var(--surface-3)] text-xs uppercase tracking-wide text-[var(--fg-2)]">
                  <tr><th scope="col" className="w-[34%] px-3 py-2 font-semibold">Live</th><th scope="col" className="px-3 py-2 text-right font-semibold">Pico</th><th scope="col" className="px-3 py-2 text-right font-semibold">Anterior</th><th scope="col" className="w-[26%] px-3 py-2 text-right font-semibold">Pico ÷ anterior</th></tr>
                </thead>
                <tbody>
                  {comparaveis.map((l) => {
                    const c = picoContraAnterior(lives, l)!;
                    return (
                      <tr key={l.videoId} className="border-t border-[var(--border)]">
                        <th scope="row" className="px-3 py-2 font-medium text-[var(--fg)]"><span aria-hidden className="mr-1.5 inline-block h-2 w-2 rounded-full" style={{ background: COR_TIPO[l.tipo] }} />{ROTULO_TIPO_LIVE[l.tipo]} {dataCurta(l.dataPrevista)}</th>
                        <td className="tabular px-3 py-2 text-right text-[var(--fg)]">{numeroDe(c.num)}</td>
                        <td className="tabular px-3 py-2 text-right text-[var(--fg-2)]" title={`${ROTULO_TIPO_LIVE[c.contra.tipo]} ${dataCurta(c.contra.dataPrevista)}`}>{numeroDe(c.den)} <span className="text-[11px] text-[var(--fg-3)]">({dataCurta(c.contra.dataPrevista)})</span></td>
                        <td className="tabular px-3 py-2 text-right font-semibold" style={{ color: c.razao >= 1 ? 'var(--green)' : 'var(--yellow)' }}>{pctDe(c.razao)}</td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            </div>
          )}
          <p className="text-xs text-[var(--fg-3)]">100% ou mais: a live segurou pelo menos o pico da anterior do mesmo tipo. A live da Black entra no gráfico quando tiver pico.</p>
        </div>
      )}
    </SectionCard>
  );
}
