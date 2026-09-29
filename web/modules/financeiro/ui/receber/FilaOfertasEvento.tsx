'use client';

// "Ofertas a confirmar" (z82), no topo da aba Previsão de caixa (#receber). O banco liga sozinho cada oferta da Hotmart a
// um evento; o que ele não liga com certeza fica aqui para alguém do Financeiro decidir (quem vê o Financeiro decide —
// decisão do Marcio; a guarda é gp_pode_ver_financeiro nas duas RPCs).
// - Carga: 1 chamada (fn_fin_fila_ofertas) ao montar = ao abrir a aba (a aba desmonta a cada troca); troca de sub-aba não
//   remonta este bloco. Depois de cada decisão, 1 recarga. Sem polling. N = 0 → o bloco some.
// - "Outro evento…" e "Criar evento" reusam a lista de eventos que o pai já busca para a sub-aba Eventos (fn_fin_funis,
//   1× por página, só quando um dos dois é aberto). Nenhuma RPC nova.
// - Botões desabilitados durante a chamada; erro da RPC em linguagem simples (tradução no repositório).
// Formulários ficam no fluxo da página (nada `absolute`).
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import {
  formDaProposta, novoEventoDoForm, rotuloOferta, validarNovoEvento,
  type DecisaoOferta, type FormNovoEvento, type OfertaFila,
} from '../../domain/fila-ofertas';
import type { Funil } from '../../domain/funis';

export type RepoFilaOfertas = Pick<FinanceiroRepository, 'carregarFilaOfertas' | 'decidirOferta'>;

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 align-top';
const BTN = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const BTN_1 = 'rounded-[var(--r-sm)] border border-[var(--accent)] px-2 py-0.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const INPUT = 'rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]';
const N_COLS = 6;

export const FILA_OFERTAS = {
  titulo: (n: number) => `Ofertas a confirmar (${n})`,
  explicacao: 'Vendas que o sistema não conseguiu ligar a um evento com certeza. Diga a que evento cada oferta pertence.',
  erroCarga: 'Não foi possível carregar as ofertas a confirmar.',
  tentarDeNovo: 'Tentar de novo',
  confirmarEm: (evento: string) => `Confirmar em ${evento}`,
  semSugestao: 'sem sugestão',
  outro: 'Outro evento…',
  criar: 'Criar evento',
  rejeitar: 'Não é de evento',
  rejeitarPergunta: 'Estas vendas não são de nenhum evento?',
  sim: 'Sim, não é de evento',
  cancelar: 'Cancelar',
  escolhaEvento: 'Evento',
  ligar: 'Ligar a este evento',
  carregandoEventos: 'Carregando os eventos…',
  erroEventos: 'Não foi possível carregar a lista de eventos. Feche e abra de novo.',
  criarELigar: 'Criar evento e ligar',
  gravando: 'Gravando…',
} as const;

type Aviso = { tipo: 'ok' | 'erro'; msg: string } | null;
type Painel = { codigo: string; tipo: 'outro'; eventoId: string }
  | { codigo: string; tipo: 'criar'; form: FormNovoEvento; erros: string[] }
  | { codigo: string; tipo: 'rejeitar' }
  | null;

const periodo = (o: OfertaFila) => (o.primeira_venda === o.ultima_venda
  ? fmtData(o.primeira_venda) : `${fmtData(o.primeira_venda)} a ${fmtData(o.ultima_venda)}`);

export function FilaOfertasEvento({ repo, inicial, candidatos, erroCandidatos, onPedirCandidatos, onEventoCriado }: {
  repo: RepoFilaOfertas;
  /** Teste de render: a lista já pronta, nenhuma chamada. */
  inicial?: OfertaFila[];
  /** Eventos existentes (fn_fin_funis, do pai). NULL = ainda não pedido ou carregando. */
  candidatos: Funil[] | null;
  erroCandidatos: string | null;
  onPedirCandidatos?: () => void;
  /** Um evento novo foi criado: o pai descarta a lista de eventos guardada (a próxima abertura busca de novo). */
  onEventoCriado?: () => void;
}) {
  const [itens, setItens] = useState<OfertaFila[] | null>(inicial ?? null);
  const [erro, setErro] = useState<string | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [aviso, setAviso] = useState<Aviso>(null);
  const [painel, setPainel] = useState<Painel>(null);

  // setState só no retorno da chamada (nunca síncrono no corpo do efeito).
  const buscar = () => repo.carregarFilaOfertas().then(
    (l) => { setItens(l); setErro(null); },
    (e: unknown) => setErro(e instanceof Error && e.message ? e.message : FILA_OFERTAS.erroCarga),
  );
  useEffect(() => {
    if (inicial == null) void buscar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const eventos = useMemo(
    () => (candidatos ?? []).slice().sort((a, b) => (b.inicio ?? '').localeCompare(a.inicio ?? '') || a.nome.localeCompare(b.nome)),
    [candidatos],
  );
  const categorias = useMemo(() => [...new Set((candidatos ?? []).map((f) => f.categoria).filter(Boolean))].sort(), [candidatos]);

  const decidir = async (o: OfertaFila, d: DecisaoOferta) => {
    setOcupado(true);
    setAviso(null);
    try {
      const r = await repo.decidirOferta(o.oferta_codigo, d);
      if (r.ok) {
        setPainel(null);
        setAviso({ tipo: 'ok', msg: `${rotuloOferta(o)}: ${r.msg ?? 'decisão gravada.'}` });
        if (d.tipo === 'criar') onEventoCriado?.();
      } else {
        setAviso({ tipo: 'erro', msg: r.msg ?? 'Não foi possível gravar a decisão.' });
      }
      if (r.ok || r.recarregar) await buscar();
    } catch {
      setAviso({ tipo: 'erro', msg: 'Não foi possível gravar a decisão (erro de rede). Tente de novo.' });
    } finally {
      setOcupado(false);
    }
  };

  const abrir = (p: NonNullable<Painel>) => {
    setAviso(null);
    if (p.tipo !== 'rejeitar') onPedirCandidatos?.();
    setPainel((a) => (a && a.codigo === p.codigo && a.tipo === p.tipo ? null : p));
  };

  if (erro) {
    return (
      <p role="alert" className="text-xs text-[var(--fg-2)]">
        {erro}{' '}
        <button type="button" className={BTN} onClick={() => { setErro(null); void buscar(); }}>{FILA_OFERTAS.tentarDeNovo}</button>
      </p>
    );
  }
  // Carregando (null) ou vazia: nada na tela. Um aviso de sucesso da última decisão fica até a próxima ação.
  if (!itens || itens.length === 0) {
    return aviso?.tipo === 'ok' ? <p role="status" className="text-xs text-[var(--fg-2)]">{aviso.msg}</p> : null;
  }

  return (
    <section aria-labelledby="fila-ofertas-titulo" className="space-y-1.5 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2">
      <h2 id="fila-ofertas-titulo" className="text-sm font-semibold text-[var(--fg)]">{FILA_OFERTAS.titulo(itens.length)}</h2>
      <p className="text-xs text-[var(--fg-3)]">{FILA_OFERTAS.explicacao}</p>
      {aviso && (
        <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
          className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>
          {aviso.msg}
        </p>
      )}
      <div className="overflow-x-auto">
        <table className="w-full text-xs">
          <thead>
            <tr className="border-b border-[var(--border)]">
              <th className={TH}>Oferta</th>
              <th className={TH}>Produto</th>
              <th className={`${TH} text-right`}>Vendas</th>
              <th className={TH}>Período das vendas</th>
              <th className={TH}>Evento sugerido</th>
              <th className={TH}>Decisão</th>
            </tr>
          </thead>
          <tbody>
            {itens.map((o) => {
              const aberto = painel?.codigo === o.oferta_codigo ? painel : null;
              return (
                <LinhaOferta key={o.oferta_codigo} o={o} painel={aberto} ocupado={ocupado}
                  eventos={eventos} categorias={categorias} carregandoEventos={candidatos == null && !erroCandidatos}
                  erroEventos={erroCandidatos}
                  onConfirmarSugestao={() => { if (o.sugestao_evento_id != null) void decidir(o, { tipo: 'confirmar', eventoId: o.sugestao_evento_id }); }}
                  onAbrirOutro={() => abrir({ codigo: o.oferta_codigo, tipo: 'outro', eventoId: o.sugestao_evento_id == null ? '' : String(o.sugestao_evento_id) })}
                  onAbrirCriar={() => abrir({ codigo: o.oferta_codigo, tipo: 'criar', form: formDaProposta(o), erros: [] })}
                  onAbrirRejeitar={() => abrir({ codigo: o.oferta_codigo, tipo: 'rejeitar' })}
                  onPainel={setPainel}
                  onFechar={() => setPainel(null)}
                  onDecidir={(d) => void decidir(o, d)} />
              );
            })}
          </tbody>
        </table>
      </div>
    </section>
  );
}

function LinhaOferta({
  o, painel, ocupado, eventos, categorias, carregandoEventos, erroEventos,
  onConfirmarSugestao, onAbrirOutro, onAbrirCriar, onAbrirRejeitar, onPainel, onFechar, onDecidir,
}: {
  o: OfertaFila;
  painel: Painel;
  ocupado: boolean;
  eventos: Funil[];
  categorias: string[];
  carregandoEventos: boolean;
  erroEventos: string | null;
  onConfirmarSugestao: () => void;
  onAbrirOutro: () => void;
  onAbrirCriar: () => void;
  onAbrirRejeitar: () => void;
  onPainel: (p: Painel) => void;
  onFechar: () => void;
  onDecidir: (d: DecisaoOferta) => void;
}) {
  const nome = rotuloOferta(o);
  const idLista = `fila-ofertas-cat-${o.oferta_codigo}`;
  return (
    <>
      <tr className="border-b border-[var(--border)]">
        <td className={`${TD} font-semibold text-[var(--fg)]`}>{nome}</td>
        <td className={`${TD} text-[var(--fg-2)]`}>{o.produto_nome ?? '—'}</td>
        <td className={`${TD} text-right tabular-nums`}>{o.n_vendas.toLocaleString('pt-BR')}</td>
        <td className={`${TD} whitespace-nowrap tabular-nums text-[var(--fg-2)]`}>{periodo(o)}</td>
        <td className={TD}>{o.sugestao_evento ?? <span className="text-[var(--fg-3)]">{FILA_OFERTAS.semSugestao}</span>}</td>
        <td className={TD}>
          <div className="flex flex-wrap gap-1">
            {o.sugestao_evento_id != null && (
              <button type="button" className={BTN_1} disabled={ocupado} onClick={onConfirmarSugestao}>
                {FILA_OFERTAS.confirmarEm(o.sugestao_evento ?? `evento ${o.sugestao_evento_id}`)}
              </button>
            )}
            <button type="button" className={BTN} disabled={ocupado} aria-expanded={painel?.tipo === 'outro'} onClick={onAbrirOutro}>
              {FILA_OFERTAS.outro}
            </button>
            <button type="button" className={BTN} disabled={ocupado} aria-expanded={painel?.tipo === 'criar'} onClick={onAbrirCriar}>
              {FILA_OFERTAS.criar}
            </button>
            <button type="button" className={BTN} disabled={ocupado} aria-expanded={painel?.tipo === 'rejeitar'} onClick={onAbrirRejeitar}>
              {FILA_OFERTAS.rejeitar}
            </button>
          </div>
        </td>
      </tr>

      {painel?.tipo === 'outro' && (
        <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
          <td colSpan={N_COLS} className={TD}>
            {erroEventos ? <p role="alert" className="text-xs text-[var(--fg-2)]">{FILA_OFERTAS.erroEventos}</p>
              : carregandoEventos ? <p role="status" className="text-xs text-[var(--fg-3)]">{FILA_OFERTAS.carregandoEventos}</p>
              : (
                <form className="flex flex-wrap items-center gap-2" onSubmit={(e) => {
                  e.preventDefault();
                  if (painel.eventoId) onDecidir({ tipo: 'confirmar', eventoId: Number(painel.eventoId) });
                }}>
                  <label className="flex items-center gap-1 text-xs text-[var(--fg-3)]">
                    {FILA_OFERTAS.escolhaEvento}
                    <select className={INPUT} value={painel.eventoId} disabled={ocupado}
                      onChange={(e) => onPainel({ ...painel, eventoId: e.target.value })}>
                      <option value="">—</option>
                      {eventos.map((ev) => (
                        <option key={ev.evento_id} value={String(ev.evento_id)}>{`${ev.nome} · ${fmtData(ev.inicio)}`}</option>
                      ))}
                    </select>
                  </label>
                  <button type="submit" className={BTN_1} disabled={ocupado || !painel.eventoId}>
                    {ocupado ? FILA_OFERTAS.gravando : FILA_OFERTAS.ligar}
                  </button>
                  <button type="button" className={BTN} disabled={ocupado} onClick={onFechar}>{FILA_OFERTAS.cancelar}</button>
                </form>
              )}
          </td>
        </tr>
      )}

      {painel?.tipo === 'criar' && (
        <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
          <td colSpan={N_COLS} className={TD}>
            <form className="space-y-1.5" noValidate onSubmit={(e) => {
              e.preventDefault();
              const erros = validarNovoEvento(painel.form);
              if (erros.length) { onPainel({ ...painel, erros }); return; }
              onDecidir({ tipo: 'criar', evento: novoEventoDoForm(painel.form) });
            }}>
              <div className="flex flex-wrap items-end gap-2">
                <Campo rotulo="Nome do evento">
                  <input className={`${INPUT} w-72`} value={painel.form.nome} maxLength={200} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, nome: e.target.value } })} />
                </Campo>
                <Campo rotulo="Tipo de evento">
                  <input className={`${INPUT} w-40`} value={painel.form.categoria} list={idLista} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, categoria: e.target.value } })} />
                  <datalist id={idLista}>{categorias.map((c) => <option key={c} value={c} />)}</datalist>
                </Campo>
                <Campo rotulo="Data do evento">
                  <input type="date" className={INPUT} value={painel.form.inicio} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, inicio: e.target.value } })} />
                </Campo>
                <Campo rotulo="Último dia (se mais de um)">
                  <input type="date" className={INPUT} value={painel.form.fim} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, fim: e.target.value } })} />
                </Campo>
                <Campo rotulo="Vendas abrem em">
                  <input type="date" className={INPUT} value={painel.form.carrinho_inicio} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, carrinho_inicio: e.target.value } })} />
                </Campo>
                <Campo rotulo="Vendas até">
                  <input type="date" className={INPUT} value={painel.form.venda_ate} disabled={ocupado}
                    onChange={(e) => onPainel({ ...painel, form: { ...painel.form, venda_ate: e.target.value } })} />
                </Campo>
              </div>
              {painel.erros.length > 0 && (
                <ul role="alert" className="list-disc pl-4 text-xs text-[var(--red)]">
                  {painel.erros.map((m) => <li key={m}>{m}</li>)}
                </ul>
              )}
              <div className="flex gap-1">
                <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? FILA_OFERTAS.gravando : FILA_OFERTAS.criarELigar}</button>
                <button type="button" className={BTN} disabled={ocupado} onClick={onFechar}>{FILA_OFERTAS.cancelar}</button>
              </div>
            </form>
          </td>
        </tr>
      )}

      {painel?.tipo === 'rejeitar' && (
        <tr className="border-b border-[var(--border)] bg-[var(--surface-2)]">
          <td colSpan={N_COLS} className={TD}>
            <div className="flex flex-wrap items-center gap-2 text-xs">
              <span className="text-[var(--fg-2)]">{FILA_OFERTAS.rejeitarPergunta}</span>
              <button type="button" className={BTN_1} disabled={ocupado} onClick={() => onDecidir({ tipo: 'rejeitar' })}>
                {ocupado ? FILA_OFERTAS.gravando : FILA_OFERTAS.sim}
              </button>
              <button type="button" className={BTN} disabled={ocupado} onClick={onFechar}>{FILA_OFERTAS.cancelar}</button>
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

function Campo({ rotulo, children }: { rotulo: string; children: ReactNode }) {
  return (
    <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]">
      {rotulo}
      {children}
    </label>
  );
}
