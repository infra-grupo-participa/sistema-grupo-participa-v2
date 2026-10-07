'use client';

// Calendário da empresa na home (/): grade do mês + "Próximos eventos". Fonte: cadastro de projetos do Marketing
// (mkt.projetos) via public.calendario_eventos. Sem tabela: no celular a grade vira pontos e o dia tocado lista
// os eventos embaixo.
import { useEffect, useMemo, useState } from 'react';
import { Badge, Drawer, FilterSelect, Skeleton } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import {
  COR_FASE, FASES, FILTRO_VAZIO, ROTULO_FASE, filtrar, hojeSaoPaulo, mesNaJanela, mesSeguinte, montarGradeMes,
  opcoesFiltro, proximosEventos, rotuloMes, rotuloPeriodo, rotuloQuem, semData,
  type DiaGrade, type EventoCalendario, type Fase, type Filtro, type ItemProximo, type MarcaDia, type PeriodoFase,
} from '../domain/calendario';
import { carregarCalendario, type CargaCalendario } from '../application/carregar-calendario';
import { SupabaseCalendarioRepository } from '../infrastructure/supabase-calendario.repository';
import type { CalendarioRepository } from '../application/ports';

const DIAS_SEMANA = [
  { curto: 'S', longo: 'Seg' }, { curto: 'T', longo: 'Ter' }, { curto: 'Q', longo: 'Qua' }, { curto: 'Q', longo: 'Qui' },
  { curto: 'S', longo: 'Sex' }, { curto: 'S', longo: 'Sáb' }, { curto: 'D', longo: 'Dom' },
];
const MAX_BARRAS = 3;

export function CalendarioEmpresa({ repo: repoProp }: { repo?: CalendarioRepository }) {
  const repo = useMemo(() => repoProp ?? new SupabaseCalendarioRepository(), [repoProp]);
  const hoje = useMemo(() => hojeSaoPaulo(), []);
  const [anoHoje, mesHoje] = hoje.split('-').map(Number);
  const [mes, setMes] = useState({ ano: anoHoje, mes: mesHoje });
  const [carga, setCarga] = useState<CargaCalendario | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [filtro, setFiltro] = useState<Filtro>(FILTRO_VAZIO);
  const [diaSel, setDiaSel] = useState<string | null>(null);
  const [aberto, setAberto] = useState<number | null>(null);

  // Recarrega só quando o mês sai da janela já carregada (mês anterior a +3 meses).
  const precisaCarregar = !carga || !mesNaJanela(mes.ano, mes.mes, carga.janela);
  useEffect(() => {
    if (!precisaCarregar) return;
    let vivo = true;
    carregarCalendario(repo, mes.ano, mes.mes)
      .then((c) => { if (vivo) { setCarga(c); setErro(null); } })
      .catch((e: Error) => { if (vivo) setErro(e.message || 'Não foi possível carregar o calendário.'); });
    return () => { vivo = false; };
  }, [repo, mes.ano, mes.mes, precisaCarregar]);

  const todos = useMemo(() => carga?.eventos ?? [], [carga]);
  const opcoes = useMemo(() => opcoesFiltro(todos), [todos]);
  const visiveis = useMemo(() => filtrar(todos, filtro), [todos, filtro]);
  const grade = useMemo(() => montarGradeMes(mes.ano, mes.mes, visiveis, hoje), [mes, visiveis, hoje]);
  const proximos = useMemo(() => proximosEventos(visiveis, hoje), [visiveis, hoje]);
  const pendentes = useMemo(() => semData(visiveis), [visiveis]);
  const fasesUsadas = useMemo(() => {
    const s = new Set<Fase>(todos.flatMap((e) => e.fases.map((f) => f.fase)));
    return FASES.filter((f) => s.has(f));
  }, [todos]);
  const marcasDiaSel = useMemo(
    () => (diaSel ? grade.flat().find((d) => d.data === diaSel)?.marcas ?? [] : []),
    [grade, diaSel],
  );
  const eventoAberto = aberto != null ? todos.find((e) => e.id === aberto) ?? null : null;

  const irPara = (delta: number) => {
    setMes((m) => mesSeguinte(m.ano, m.mes, delta));
    setDiaSel(null);
  };
  const noMesDeHoje = mes.ano === anoHoje && mes.mes === mesHoje;
  const carregando = precisaCarregar && !erro;

  return (
    <section aria-labelledby="calendario-titulo" className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] shadow-[var(--shadow-sm)] p-4 sm:p-5">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <h2 id="calendario-titulo" className="text-base font-bold text-[var(--fg)] inline-flex items-center gap-2">
            <Icon name="calendar-days" size={18} className="text-[var(--accent)]" /> Calendário
          </h2>
          <p className="mt-0.5 text-sm text-[var(--fg-2)]">Projetos e eventos da empresa, do cadastro do Marketing.</p>
        </div>
        <div className="flex items-center gap-1">
          <button type="button" onClick={() => irPara(-1)} aria-label="Mês anterior"
            className="w-9 h-9 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
            <Icon name="chevron-left" />
          </button>
          <div className="min-w-[9.5rem] text-center text-sm font-semibold text-[var(--fg)] capitalize" aria-live="polite">
            {rotuloMes(mes.ano, mes.mes)}
          </div>
          <button type="button" onClick={() => irPara(1)} aria-label="Próximo mês"
            className="w-9 h-9 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
            <Icon name="chevron-right" />
          </button>
          {!noMesDeHoje && (
            <button type="button" onClick={() => { setMes({ ano: anoHoje, mes: mesHoje }); setDiaSel(null); }}
              className="ml-1 px-2.5 h-9 rounded-[var(--r-md)] border border-[var(--border)] text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]">
              Hoje
            </button>
          )}
        </div>
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-2">
        <label className="sr-only" htmlFor="cal-filtro-tipo">Tipo de lançamento</label>
        <FilterSelect id="cal-filtro-tipo" value={filtro.tipoLancamento}
          onChange={(e) => setFiltro((f) => ({ ...f, tipoLancamento: e.target.value }))}>
          <option value="">Todos os tipos</option>
          {opcoes.tipos.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}
        </FilterSelect>
        <label className="sr-only" htmlFor="cal-filtro-marca">Marca</label>
        <FilterSelect id="cal-filtro-marca" value={filtro.unidade}
          onChange={(e) => setFiltro((f) => ({ ...f, unidade: e.target.value }))}>
          <option value="">Todas as marcas</option>
          {opcoes.unidades.map((o) => <option key={o.valor} value={o.valor}>{o.rotulo}</option>)}
        </FilterSelect>
        {(filtro.tipoLancamento || filtro.unidade) && (
          <button type="button" onClick={() => setFiltro(FILTRO_VAZIO)} className="text-xs font-semibold text-[var(--accent)] hover:underline">
            Limpar filtros
          </button>
        )}
      </div>

      <Legenda fases={fasesUsadas.length ? fasesUsadas : FASES} />

      {erro ? (
        <p role="alert" className="mt-4 rounded-[var(--r-md)] border border-[var(--red-border)] bg-[var(--red-subtle)] px-3 py-2 text-sm text-[var(--fg)]">
          Não foi possível carregar o calendário. {erro}
        </p>
      ) : (
        <div className="mt-4 grid gap-5 lg:grid-cols-[minmax(0,1fr)_18rem]">
          <div className="min-w-0">
            {carregando ? <Skeleton w="100%" h={320} /> : (
              <Grade grade={grade} diaSel={diaSel} onDia={(d) => setDiaSel((s) => (s === d ? null : d))} onEvento={setAberto} />
            )}
            {diaSel && !carregando && (
              <DiaSelecionado data={diaSel} marcas={marcasDiaSel} onEvento={setAberto} onFechar={() => setDiaSel(null)} />
            )}
          </div>
          <div className="min-w-0">
            <h3 className="text-sm font-bold text-[var(--fg)]">Próximos eventos</h3>
            {carregando ? (
              <div className="mt-2 space-y-2"><Skeleton w="100%" h={56} /><Skeleton w="100%" h={56} /></div>
            ) : proximos.length === 0 ? (
              <p className="mt-2 text-sm text-[var(--fg-3)]">Nenhum evento com data à frente{filtro.tipoLancamento || filtro.unidade ? ' neste filtro' : ''}.</p>
            ) : (
              <ul className="mt-2 space-y-2">
                {proximos.map((p) => <li key={p.evento.id}><CartaoProximo item={p} hoje={hoje} onAbrir={() => setAberto(p.evento.id)} /></li>)}
              </ul>
            )}
            {!carregando && pendentes.length > 0 && (
              <div className="mt-4 rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] px-3 py-2">
                <div className="text-xs font-semibold text-[var(--fg-2)]">Sem data no cadastro</div>
                <div className="mt-1 flex flex-wrap gap-1.5">
                  {pendentes.map((e) => (
                    <button key={e.id} type="button" onClick={() => setAberto(e.id)} className="max-w-full">
                      <Badge>{e.nome}</Badge>
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
      )}

      {eventoAberto && <ResumoProjeto evento={eventoAberto} hoje={hoje} onClose={() => setAberto(null)} />}
    </section>
  );
}

function Legenda({ fases }: { fases: Fase[] }) {
  return (
    <ul className="mt-3 flex flex-wrap gap-x-3 gap-y-1.5" aria-label="Legenda das fases">
      {fases.map((f) => (
        <li key={f} className="inline-flex items-center gap-1.5 text-xs text-[var(--fg-2)]">
          <span className="h-2.5 w-2.5 rounded-sm" style={{ background: COR_FASE[f].forte }} aria-hidden />
          {ROTULO_FASE[f]}{f === 'replay' ? ' (interno)' : ''}
        </li>
      ))}
    </ul>
  );
}

function Grade({ grade, diaSel, onDia, onEvento }: {
  grade: DiaGrade[][]; diaSel: string | null; onDia: (d: string) => void; onEvento: (id: number) => void;
}) {
  return (
    <div role="grid" aria-label="Mês" className="rounded-[var(--r-md)] border border-[var(--border)] overflow-hidden">
      <div role="row" className="grid grid-cols-7 bg-[var(--surface-3)] border-b border-[var(--border)]">
        {DIAS_SEMANA.map((d) => (
          <div key={d.longo} role="columnheader" aria-label={d.longo} className="py-1.5 text-center text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">
            <span className="sm:hidden">{d.curto}</span><span className="hidden sm:inline">{d.longo}</span>
          </div>
        ))}
      </div>
      {grade.map((semana) => (
        <div role="row" key={semana[0].data} className="grid grid-cols-7 border-b border-[var(--border-faint)] last:border-b-0">
          {semana.map((dia) => <CelulaDia key={dia.data} dia={dia} selecionado={diaSel === dia.data} onDia={onDia} onEvento={onEvento} />)}
        </div>
      ))}
    </div>
  );
}

function CelulaDia({ dia, selecionado, onDia, onEvento }: {
  dia: DiaGrade; selecionado: boolean; onDia: (d: string) => void; onEvento: (id: number) => void;
}) {
  const extras = dia.marcas.length - MAX_BARRAS;
  const rotulo = `${dia.data.split('-').reverse().join('/')}${dia.marcas.length ? `, ${dia.marcas.length} ${dia.marcas.length === 1 ? 'fase' : 'fases'}` : ''}`;
  return (
    <div
      role="gridcell"
      aria-selected={selecionado}
      className={`relative min-w-0 min-h-[3.25rem] sm:min-h-[5.5rem] border-r border-[var(--border-faint)] last:border-r-0 ${
        dia.doMes ? '' : 'bg-[var(--surface-1)]'
      } ${selecionado ? 'outline outline-2 -outline-offset-2 outline-[var(--accent)]' : ''}`}
    >
      <button
        type="button"
        onClick={() => onDia(dia.data)}
        aria-label={rotulo}
        className="absolute inset-0 w-full h-full hover:bg-[var(--surface-3)] focus-visible:bg-[var(--surface-3)] transition-colors"
      />
      <div className="relative pointer-events-none px-1 pt-1">
        <span className={`inline-grid place-items-center h-5 min-w-5 px-1 rounded-full text-[11px] tabular ${
          dia.hoje ? 'bg-[var(--accent)] text-black font-bold' : dia.doMes ? 'text-[var(--fg-2)]' : 'text-[var(--fg-4)]'
        }`}>{dia.dia}</span>
      </div>
      {/* celular: pontos */}
      {dia.marcas.length > 0 && (
        <div className="relative pointer-events-none flex flex-wrap gap-0.5 px-1 pb-1 sm:hidden" aria-hidden>
          {dia.marcas.slice(0, 4).map((m, i) => (
            <span key={i} className="h-1.5 w-1.5 rounded-full" style={{ background: COR_FASE[m.fase].forte }} />
          ))}
        </div>
      )}
      {/* telas maiores: barras com a sigla no começo da fase */}
      <div className="relative pointer-events-none hidden sm:flex flex-col gap-0.5 pb-1">
        {dia.marcas.slice(0, MAX_BARRAS).map((m, i) => <Barra key={`${m.eventoId}-${m.fase}-${i}`} m={m} onEvento={onEvento} />)}
        {extras > 0 && <span className="pointer-events-none px-1 text-[10px] text-[var(--fg-3)]">+{extras}</span>}
      </div>
    </div>
  );
}

function Barra({ m, onEvento }: { m: MarcaDia; onEvento: (id: number) => void }) {
  const cor = COR_FASE[m.fase];
  return (
    <button
      type="button"
      onClick={() => onEvento(m.eventoId)}
      title={`${m.nome} · ${ROTULO_FASE[m.fase]}${m.interno ? ' (interno)' : ''}`}
      className={`pointer-events-auto h-4 min-w-0 text-left text-[10px] font-semibold leading-4 truncate text-[var(--fg)] ${
        m.comeca ? 'ml-1 rounded-l-[3px] pl-1' : ''} ${m.termina ? 'mr-1 rounded-r-[3px]' : ''} ${m.interno ? 'opacity-70' : ''}`}
      style={{ background: cor.suave, borderLeft: m.comeca ? `3px solid ${cor.forte}` : undefined }}
    >
      {m.comeca ? m.sigla : ' '}
    </button>
  );
}

function DiaSelecionado({ data, marcas, onEvento, onFechar }: {
  data: string; marcas: MarcaDia[]; onEvento: (id: number) => void; onFechar: () => void;
}) {
  return (
    <div className="mt-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-3">
      <div className="flex items-center justify-between gap-2">
        <div className="text-sm font-semibold text-[var(--fg)]">{data.split('-').reverse().join('/')}</div>
        <button type="button" onClick={onFechar} aria-label="Fechar dia" className="w-7 h-7 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:bg-[var(--surface-3)]">
          <Icon name="x" size={14} />
        </button>
      </div>
      {marcas.length === 0 ? (
        <p className="mt-1 text-sm text-[var(--fg-3)]">Nada marcado neste dia.</p>
      ) : (
        <ul className="mt-2 space-y-1.5">
          {marcas.map((m, i) => (
            <li key={i}>
              <button type="button" onClick={() => onEvento(m.eventoId)} className="w-full flex items-center gap-2 text-left rounded-[var(--r-sm)] px-1 py-1 hover:bg-[var(--surface-3)]">
                <span className="h-2.5 w-2.5 shrink-0 rounded-sm" style={{ background: COR_FASE[m.fase].forte }} aria-hidden />
                <span className="min-w-0 flex-1 truncate text-sm text-[var(--fg)]">{m.nome}</span>
                <span className="shrink-0 text-xs text-[var(--fg-3)]">{ROTULO_FASE[m.fase]}{m.interno ? ' · interno' : ''}</span>
              </button>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}

function CartaoProximo({ item, hoje, onAbrir }: { item: ItemProximo; hoje: string; onAbrir: () => void }) {
  const { evento: e, faseAtual, proximaFase, diasAteProxima } = item;
  const ano = Number(hoje.slice(0, 4));
  const quem = rotuloQuem(e);
  return (
    <button type="button" onClick={onAbrir}
      className="w-full text-left rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2.5 hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors">
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-sm font-semibold text-[var(--fg)] truncate">{e.nome}</div>
          <div className="text-xs text-[var(--fg-3)] truncate">{[e.tipoLancamentoNome, quem].filter(Boolean).join(' · ') || e.sigla}</div>
        </div>
        <Icon name="chevron-right" size={14} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
      </div>
      <div className="mt-1.5 space-y-0.5 text-xs">
        {faseAtual && <LinhaFase rotulo="Agora" f={faseAtual} ano={ano} />}
        {proximaFase && (
          <LinhaFase rotulo={diasAteProxima === 1 ? 'Amanhã' : `Em ${diasAteProxima} dias`} f={proximaFase} ano={ano} />
        )}
      </div>
    </button>
  );
}

function LinhaFase({ rotulo, f, ano }: { rotulo: string; f: PeriodoFase; ano: number }) {
  return (
    <div className="flex items-center gap-1.5 min-w-0">
      <span className="h-2 w-2 shrink-0 rounded-sm" style={{ background: COR_FASE[f.fase].forte }} aria-hidden />
      <span className="shrink-0 font-semibold text-[var(--fg-2)]">{rotulo}:</span>
      <span className="truncate text-[var(--fg-2)]">{ROTULO_FASE[f.fase]} {rotuloPeriodo(f.inicio, f.fim, ano)}{f.interno ? ' · interno' : ''}</span>
    </div>
  );
}

function ResumoProjeto({ evento: e, hoje, onClose }: { evento: EventoCalendario; hoje: string; onClose: () => void }) {
  const ano = Number(hoje.slice(0, 4));
  return (
    <Drawer
      onClose={onClose}
      width="max-w-lg"
      title={e.nome}
      subtitle={[e.sigla, e.chave].filter(Boolean).join(' · ')}
      badges={
        <>
          {e.tipoLancamentoNome && <Badge tone="accent">{e.tipoLancamentoNome}</Badge>}
          {e.unidadeNome && <Badge>{e.unidadeNome}</Badge>}
          {e.tipo && <Badge>{e.tipo === 'externo' ? 'Externo' : 'Interno'}</Badge>}
          {e.especialista && <Badge dot>{e.especialista}</Badge>}
        </>
      }
    >
      <h3 className="text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Datas</h3>
      {e.fases.length === 0 ? (
        <p className="mt-2 text-sm text-[var(--fg-2)]">Sem datas no cadastro do Marketing ainda.</p>
      ) : (
        <ul className="mt-2 space-y-2">
          {e.fases.map((f, i) => {
            const agora = f.inicio <= hoje && f.fim >= hoje;
            const passou = f.fim < hoje;
            return (
              <li key={i} className="flex items-center gap-3 rounded-[var(--r-md)] border px-3 py-2"
                style={{ borderColor: COR_FASE[f.fase].borda, background: COR_FASE[f.fase].suave, opacity: passou ? 0.6 : 1 }}>
                <span className="h-3 w-3 shrink-0 rounded-sm" style={{ background: COR_FASE[f.fase].forte }} aria-hidden />
                <span className="min-w-0 flex-1 text-sm font-medium text-[var(--fg)]">
                  {ROTULO_FASE[f.fase]}
                  {f.interno && <span className="ml-1.5 text-xs font-normal text-[var(--fg-3)]">interno</span>}
                </span>
                <span className="shrink-0 text-sm tabular text-[var(--fg-2)]">
                  {rotuloPeriodo(f.inicio, f.fim, ano)}{agora ? ' · agora' : ''}
                </span>
              </li>
            );
          })}
        </ul>
      )}
      {e.links.length > 0 && (
        <>
          <h3 className="mt-5 text-xs font-semibold uppercase tracking-wide text-[var(--fg-3)]">Links</h3>
          <ul className="mt-2 space-y-1">
            {e.links.map((l) => (
              <li key={l.url}>
                <a href={l.url} target="_blank" rel="noopener noreferrer"
                  className="inline-flex max-w-full items-center gap-1.5 text-sm text-[var(--accent)] hover:underline">
                  <span className="truncate">{l.nome}</span>
                  <span className="truncate text-xs text-[var(--fg-3)]">{l.url.replace(/^https:\/\//, '')}</span>
                  <Icon name="arrow-up-right" size={12} className="shrink-0" />
                </a>
              </li>
            ))}
          </ul>
        </>
      )}
    </Drawer>
  );
}
