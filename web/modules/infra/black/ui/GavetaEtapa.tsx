'use client';

// Gaveta da etapa da Jornada: Etapa (todas as métricas do nó) · Criativos (os anúncios da etapa; no C1, métricas
// de distribuição) · Perfil (quem entrou por ela). Clicar no criativo leva à aba Criativos e troca a gaveta.
import { useId, useMemo, useState } from 'react';
import { Tabs, idsAba } from '@/shared/ui/components';
import { painel } from '../domain/criativos';
import { NO, recortarNo } from '../domain/jornada';
import type { AlvoGaveta, DadosTela } from './contexto';
import { dadosJornada } from './jornada-dados';
import { Farol, Numero, Taxa } from './pecas';
import { PerfilLeads } from './perfil/PerfilLeads';

type Sub = 'etapa' | 'criativos' | 'perfil';
const SUBS: { k: Sub; l: string }[] = [{ k: 'etapa', l: 'Etapa' }, { k: 'criativos', l: 'Criativos' }, { k: 'perfil', l: 'Perfil' }];

export function GavetaEtapa({ d, id, onTrocar }: { d: DadosTela; id: string; onTrocar: (a: AlvoGaveta) => void }) {
  const base = `gaveta-${useId().replace(/:/g, '')}`;
  const [sub, setSub] = useState<Sub>('etapa');
  const n = NO.get(id);
  const jornada = useMemo(() => dadosJornada(d), [d]);
  const rec = useMemo(() => (n ? recortarNo(n, jornada.dias, n.funis.length === 0 ? d.linhas : jornada.linhas, d.idx) : null), [n, jornada, d.linhas, d.idx]);
  const itens = useMemo(() => (rec && rec.dias.length
    ? painel('anuncio', {}, rec.dias, rec.linhas, d.idx, d.config.reguaCpl, (p) => d.paginas.get(p)?.rotulo ?? p)
    : []), [rec, d.idx, d.config.reguaCpl, d.paginas]);
  if (!n || !rec) return <p className="text-sm text-[var(--fg-3)]">Etapa não encontrada.</p>;
  const metricas = jornada.metricas[id] ?? [];
  const distribuicao = Boolean(n.recorte?.distribuicao);

  const abrirCriativo = (anuncio: string) => {
    d.irPara({ aba: 'criativos', criativos: { anuncio } });
    onTrocar({ tipo: 'criativo', id: anuncio });
  };

  return (
    <div className="space-y-3">
      {n.kicker && <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--accent)]">{n.kicker}</p>}
      {n.sub.length > 0 && <p className="text-xs text-[var(--fg-3)]">{n.sub.join(' · ')}</p>}
      <Tabs tabs={SUBS} active={sub} onChange={(k) => setSub(k as Sub)} idBase={base} label="Detalhe da etapa" />

      <div role="tabpanel" id={idsAba(base, 'etapa').panel} aria-labelledby={idsAba(base, 'etapa').tab} hidden={sub !== 'etapa'}>
        {sub === 'etapa' && (
          <div className="atm-historico-panel-enter">
            {n.semFonte && <p className="mb-2 rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-3 text-sm text-[var(--fg-3)]">Sem dado: {n.semFonte}</p>}
            {metricas.length === 0 && !n.semFonte && <p className="text-sm text-[var(--fg-3)]">{n.recorte ? 'Sem dado no período.' : 'Etapa de passagem, sem métrica própria.'}</p>}
            <dl className="divide-y divide-[var(--border-faint)]">
              {metricas.map((m) => (
                <div key={m.rotulo} className="flex items-baseline justify-between gap-3 py-2 text-sm">
                  <dt className="text-[var(--fg-2)]" title={m.nota}>{m.rotulo}{m.nota ? ' *' : ''}</dt>
                  <dd className="text-right text-[var(--fg)]">
                    {m.formato === 'pct' && m.taxa ? <Taxa taxa={m.taxa} /> : <Numero valor={m.valor} formato={m.formato} falta={m.nota} animado={false} />}
                  </dd>
                </div>
              ))}
            </dl>
            {metricas.some((m) => m.nota) && <p className="mt-2 text-[11px] text-[var(--fg-3)]">* Passe o mouse para ver a nota da métrica.</p>}
          </div>
        )}
      </div>

      <div role="tabpanel" id={idsAba(base, 'criativos').panel} aria-labelledby={idsAba(base, 'criativos').tab} hidden={sub !== 'criativos'}>
        {sub === 'criativos' && (
          itens.length === 0
            ? <p className="text-sm text-[var(--fg-3)]">{n.recorte ? 'Sem criativo veiculado nesta etapa no período.' : 'Não se aplica a esta etapa (sem anúncio).'}</p>
            : (
              <ul className="atm-historico-panel-enter space-y-2">
                {itens.map((it) => {
                  const r = it.resumo;
                  const total = it.anuncios.length === 1 ? d.totaisPeriodo.find((t) => t.nivel === 'anuncio' && t.id === it.id) : undefined; // alcance e frequência não somam entre anúncios
                  return (
                    <li key={it.id}>
                      <button type="button" onClick={() => abrirCriativo(it.id)}
                        className="atm-historico-interativo w-full rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-left hover:border-[var(--border-accent)]">
                        <span className="flex items-start gap-2">
                          {!distribuicao && <Farol farol={r.farol} className="mt-1" />}
                          <span className="min-w-0 flex-1 break-words text-sm font-semibold text-[var(--fg)]">{it.nome}</span>
                        </span>
                        <span className="mt-1.5 grid grid-cols-2 gap-x-3 gap-y-1 text-xs sm:grid-cols-3">
                          {distribuicao ? (
                            <>
                              <Par r="Impressões"><Numero valor={r.impressoes} formato="int" animado={false} /></Par>
                              <Par r="Alcance"><Numero valor={total?.alcance ?? null} formato="int" falta="alcance do período" animado={false} /></Par>
                              <Par r="CPM"><Numero valor={r.cpm} formato="brl" animado={false} /></Par>
                              <Par r="Frequência"><Numero valor={total?.frequencia ?? null} formato="dec" falta="frequência do período" animado={false} /></Par>
                              <Par r="Vídeo 75%"><Taxa taxa={r.video75} /></Par>
                              <Par r="Custo por visualização"><Numero valor={r.custoVisualizacao} formato="brl" falta="ThruPlay" animado={false} /></Par>
                            </>
                          ) : (
                            <>
                              <Par r="Investimento"><Numero valor={r.gasto} formato="brl" animado={false} /></Par>
                              <Par r="CTR"><Taxa taxa={r.ctr} /></Par>
                              <Par r="Leads pagos"><Numero valor={r.leadsPagos} formato="int" animado={false} /></Par>
                              <Par r="CPL"><Numero valor={r.cpl} formato="brl" animado={false} /></Par>
                              <Par r="Connect rate"><Taxa taxa={r.connect} /></Par>
                              <Par r="Impressões"><Numero valor={r.impressoes} formato="int" animado={false} /></Par>
                            </>
                          )}
                        </span>
                      </button>
                    </li>
                  );
                })}
              </ul>
            )
        )}
      </div>

      <div role="tabpanel" id={idsAba(base, 'perfil').panel} aria-labelledby={idsAba(base, 'perfil').tab} hidden={sub !== 'perfil'}>
        {sub === 'perfil' && (n.recorte?.linha
          ? <PerfilLeads d={d} linhas={rec.linhas} />
          : <p className="text-sm text-[var(--fg-3)]">Não se aplica a esta etapa: ela não gera cadastro.</p>)}
      </div>
    </div>
  );
}

function Par({ r, children }: { r: string; children: React.ReactNode }) {
  return <span className="flex min-w-0 flex-col"><span className="truncate text-[10px] uppercase tracking-wide text-[var(--fg-3)]">{r}</span><span className="text-[var(--fg)]">{children}</span></span>;
}
