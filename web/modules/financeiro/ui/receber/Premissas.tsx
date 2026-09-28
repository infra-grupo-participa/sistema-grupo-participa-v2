'use client';

// Sub-aba "Premissas" de Previsão de caixa (#receber?ver=premissas, fatia F2, z66): com que números a previsão é feita,
// desde quando e quem mudou; mais os feriados bancários (dia útil de caixa).
// - Carga: o PAI (FinanceiroClient) faz 1 chamada de premissas + 1 de feriados na 1ª vez que esta sub-aba abre e
//   guarda o resultado; trocar de sub-aba e voltar não consulta. Depois de gravar, o pai rebusca só a lista que mudou
//   e a grade (a previsão depende das premissas e dos feriados).
// - Escrita: só com canEdit. A trava real é o banco (gp_pode_operar_financeiro em cada RPC); a validação daqui só
//   poupa uma ida ao banco com as mesmas regras (faixa, inteiro, vigência de hoje a hoje+366).
// - Percentual é fração no banco (0,05) e % na tela (5).
// Formulários ficam no fluxo da página (nada `absolute`).
import { useId, useMemo, useState } from 'react';
import { fmtData, fmtDataHora } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import type { CenarioReceber } from '../../domain/contas-receber';
import {
  agruparPremissas, anosDosFeriados, formatarFaixa, formatarPremissa, paraExibicao, somarDias, validarFeriado,
  validarPremissa, VIGENCIA_MAX_DIAS,
  type CenarioPremissa, type FeriadoBancario, type PremissaTela, type VigenciaPremissa,
} from '../../domain/premissas-receber';
import { CENARIO_RECEBER, FERIADOS_RECEBER, PREMISSAS_RECEBER } from './textos';

export type RepoPremissas = Pick<FinanceiroRepository, 'salvarPremissaReceber' | 'salvarFeriado'>;

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 align-top';
const BTN = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const BTN_1 = 'rounded-[var(--r-sm)] border border-[var(--accent)] px-2 py-0.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const INPUT = 'rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]';

const rotuloCenario = (c: CenarioReceber) => CENARIO_RECEBER[c] ?? c;
const unidadeCurta = (u: string) => (u === 'percentual' ? '%' : u === 'dias' ? 'dias' : '');

type Aviso = { tipo: 'ok' | 'erro'; msg: string } | null;

export function Premissas({
  premissas, feriados, erroPremissas, erroFeriados, canEdit, hojeISO, repo, onTentarDeNovo, onPremissaGravada, onFeriadoGravado,
}: {
  /** NULL = carregando (ou ainda não pedido). */
  premissas: VigenciaPremissa[] | null;
  feriados: FeriadoBancario[] | null;
  erroPremissas: string | null;
  erroFeriados: string | null;
  canEdit: boolean;
  hojeISO: string;
  repo?: RepoPremissas;
  onTentarDeNovo?: () => void;
  /** Gravou: o pai rebusca a lista de premissas e a grade. */
  onPremissaGravada?: () => void;
  onFeriadoGravado?: () => void;
}) {
  const grupos = useMemo(() => (premissas ? agruparPremissas(premissas) : []), [premissas]);
  return (
    <div className="space-y-4">
      <section className="space-y-2" aria-labelledby="premissas-titulo">
        <h2 id="premissas-titulo" className="text-sm font-semibold text-[var(--fg)]">{PREMISSAS_RECEBER.titulo}</h2>
        <p className="text-xs text-[var(--fg-3)]">
          {PREMISSAS_RECEBER.explicacao}{!canEdit && <> {PREMISSAS_RECEBER.somenteLeitura}</>}
        </p>
        {erroPremissas ? (
          <p role="alert" className="text-xs text-[var(--fg-2)]">
            {erroPremissas} {onTentarDeNovo && <button type="button" className={BTN} onClick={onTentarDeNovo}>{PREMISSAS_RECEBER.tentarDeNovo}</button>}
          </p>
        ) : premissas == null ? (
          <p className="text-xs text-[var(--fg-3)]">{PREMISSAS_RECEBER.carregando}</p>
        ) : grupos.length === 0 ? (
          <p className="text-xs text-[var(--fg-3)]">{PREMISSAS_RECEBER.vazio}</p>
        ) : (
          <TabelaPremissas grupos={grupos} canEdit={canEdit && !!repo} hojeISO={hojeISO} repo={repo} onGravada={onPremissaGravada} />
        )}
      </section>

      <Feriados feriados={feriados} erro={erroFeriados} canEdit={canEdit && !!repo} repo={repo} hojeISO={hojeISO}
        onTentarDeNovo={onTentarDeNovo} onGravado={onFeriadoGravado} />
    </div>
  );
}

type Edicao = { chave: string; cenario: CenarioReceber; valor: string; vigenteDe: string; erros: string[] } | null;

function TabelaPremissas({ grupos, canEdit, hojeISO, repo, onGravada }: {
  grupos: ReturnType<typeof agruparPremissas>; canEdit: boolean; hojeISO: string; repo?: RepoPremissas; onGravada?: () => void;
}) {
  const [historico, setHistorico] = useState<Set<string>>(new Set());
  const [edicao, setEdicao] = useState<Edicao>(null);
  const [ocupado, setOcupado] = useState(false);
  const [aviso, setAviso] = useState<Aviso>(null);
  const nCols = canEdit ? 7 : 6;

  const alternarHistorico = (k: string) => setHistorico((h) => {
    const n = new Set(h);
    if (n.has(k)) n.delete(k); else n.add(k);
    return n;
  });

  const abrirEdicao = (p: PremissaTela, c: CenarioPremissa) => {
    const atual = c.vigente ?? p.cenarios.find((x) => x.cenario === 'base')?.vigente ?? null;
    setAviso(null);
    setEdicao({
      chave: p.chave_base, cenario: c.cenario, vigenteDe: hojeISO, erros: [],
      valor: atual ? String(paraExibicao(atual.valor, p.unidade)).replace('.', ',') : '',
    });
  };

  const gravar = async (p: PremissaTela) => {
    if (!edicao || !repo) return;
    const v = validarPremissa(p, edicao.valor, edicao.vigenteDe, hojeISO);
    if (!v.ok) { setEdicao({ ...edicao, erros: v.erros }); return; }
    setOcupado(true);
    setAviso(null);
    try {
      const r = await repo.salvarPremissaReceber(p.chave_base, v.valor, edicao.vigenteDe, edicao.cenario);
      if (!r.ok) { setAviso({ tipo: 'erro', msg: r.msg ?? 'Não foi possível gravar.' }); return; }
      setEdicao(null);
      setAviso({ tipo: 'ok', msg: PREMISSAS_RECEBER.gravou });
      onGravada?.();
    } finally {
      setOcupado(false);
    }
  };

  return (
    <div className="space-y-2">
      {aviso && (
        <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
          className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{aviso.msg}</p>
      )}
      <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
        <table className="w-full border-collapse text-xs">
          <thead className="bg-[var(--surface-2)]">
            <tr>
              <th className={TH}>{PREMISSAS_RECEBER.premissa}</th><th className={TH}>{PREMISSAS_RECEBER.cenario}</th>
              <th className={`${TH} text-right`}>{PREMISSAS_RECEBER.valor}</th><th className={TH}>{PREMISSAS_RECEBER.desde}</th>
              <th className={TH}>{PREMISSAS_RECEBER.quem}</th><th className={TH}>{PREMISSAS_RECEBER.faixa}</th>
              {canEdit && <th className={TH}>{PREMISSAS_RECEBER.acoes}</th>}
            </tr>
          </thead>
          {grupos.map((g) => (
            <tbody key={g.grupo}>
              <tr className="border-t border-[var(--border)] bg-[var(--surface-2)]">
                <th scope="colgroup" colSpan={nCols} className="px-2 py-1 text-left text-[11px] font-semibold uppercase text-[var(--fg-2)]">{g.grupo}</th>
              </tr>
              {g.premissas.map((p) => p.cenarios.map((c, i) => {
                const k = `${p.chave_base}@${c.cenario}`;
                const base = p.cenarios.find((x) => x.cenario === 'base')?.vigente ?? null;
                const hist = [...c.futuras, ...(c.vigente ? [c.vigente] : []), ...c.anteriores];
                const aberto = historico.has(k);
                const editando = edicao?.chave === p.chave_base && edicao.cenario === c.cenario;
                const idHist = `premissa-hist-${k.replace(/[^a-z0-9_-]/gi, '_')}`;
                return [
                  <tr key={k} className={`${i === 0 ? 'border-t border-[var(--border)]' : 'border-t border-[var(--border-faint)]'} text-[var(--fg)]`}>
                    <td className={TD}>
                      {i === 0 ? (
                        <>
                          <span className="font-semibold">{p.rotulo}</span>
                          <span className="block max-w-[46ch] text-[11px] text-[var(--fg-3)]">{p.ajuda}</span>
                        </>
                      ) : null}
                    </td>
                    <td className={`${TD} whitespace-nowrap`}>{rotuloCenario(c.cenario)}</td>
                    <td className={`${TD} text-right tabular whitespace-nowrap`}>
                      {c.vigente ? formatarPremissa(c.vigente.valor, p.unidade)
                        : c.usaBase ? <span className="text-[var(--fg-3)]">{PREMISSAS_RECEBER.usaBase(base ? formatarPremissa(base.valor, p.unidade) : '—')}</span>
                          : <span className="text-[var(--fg-3)]">{PREMISSAS_RECEBER.semVigente}</span>}
                      {c.futuras[0] && (
                        <span className="block text-[11px] text-[var(--fg-3)]">
                          {PREMISSAS_RECEBER.proxima(formatarPremissa(c.futuras[0].valor, p.unidade), fmtData(c.futuras[0].vigente_de))}
                        </span>
                      )}
                    </td>
                    <td className={`${TD} tabular whitespace-nowrap`}>{c.vigente ? fmtData(c.vigente.vigente_de) : '—'}</td>
                    <td className={`${TD} whitespace-nowrap text-[var(--fg-2)]`}>
                      {c.vigente ? (c.vigente.criado_por_nome ?? PREMISSAS_RECEBER.sistema) : '—'}
                      {hist.length > 0 && (
                        <button type="button" className="ml-2 underline decoration-dotted underline-offset-2 hover:text-[var(--accent)]"
                          aria-expanded={aberto} aria-controls={idHist} onClick={() => alternarHistorico(k)}>
                          {aberto ? PREMISSAS_RECEBER.ocultarHistorico : PREMISSAS_RECEBER.historico(hist.length)}
                        </button>
                      )}
                    </td>
                    <td className={`${TD} whitespace-nowrap text-[var(--fg-3)]`}>{formatarFaixa(p)}</td>
                    {canEdit && (
                      <td className={TD}>
                        {!editando && (
                          <button type="button" className={BTN} disabled={ocupado} onClick={() => abrirEdicao(p, c)}
                            aria-label={`${PREMISSAS_RECEBER.alterar}: ${p.rotulo} (${rotuloCenario(c.cenario)})`}>
                            {PREMISSAS_RECEBER.alterar}
                          </button>
                        )}
                      </td>
                    )}
                  </tr>,
                  aberto ? (
                    <tr key={`${k}-hist`} id={idHist} className="text-[var(--fg-2)]">
                      <td className={TD} />
                      <td colSpan={nCols - 1} className="px-2 pb-2">
                        <table className="border-collapse text-[11px]">
                          <tbody>
                            {hist.map((h) => (
                              <tr key={`${h.chave}-${h.vigente_de}`}>
                                <td className="pr-3 tabular">{fmtData(h.vigente_de)}</td>
                                <td className="pr-3 tabular text-right">{formatarPremissa(h.valor, p.unidade)}</td>
                                <td className="pr-3">{PREMISSAS_RECEBER.situacaoVigencia[h.situacao] ?? h.situacao}</td>
                                <td className="pr-3">{h.criado_por_nome ?? PREMISSAS_RECEBER.sistema}{h.criado_em ? ` · ${fmtDataHora(h.criado_em)}` : ''}</td>
                                <td className="text-[var(--fg-3)]">{h.fonte ?? ''}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </td>
                    </tr>
                  ) : null,
                  editando && edicao ? (
                    <tr key={`${k}-edit`} className="bg-[var(--surface-2)]">
                      <td className={TD} />
                      <td colSpan={nCols - 1} className="px-2 py-2">
                        <FormPremissa p={p} edicao={edicao} hojeISO={hojeISO} ocupado={ocupado}
                          onMudar={setEdicao} onGravar={() => void gravar(p)} onCancelar={() => setEdicao(null)} />
                      </td>
                    </tr>
                  ) : null,
                ];
              }))}
            </tbody>
          ))}
        </table>
      </div>
    </div>
  );
}

function FormPremissa({ p, edicao, hojeISO, ocupado, onMudar, onGravar, onCancelar }: {
  p: PremissaTela; edicao: NonNullable<Edicao>; hojeISO: string; ocupado: boolean;
  onMudar: (e: Edicao) => void; onGravar: () => void; onCancelar: () => void;
}) {
  const id = useId();
  const idErros = `${id}-erros`;
  return (
    <form className="flex flex-wrap items-end gap-3" onSubmit={(e) => { e.preventDefault(); onGravar(); }}
      aria-label={`${PREMISSAS_RECEBER.alterar}: ${p.rotulo} (${rotuloCenario(edicao.cenario)})`}>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-valor`}>
        {PREMISSAS_RECEBER.novoValor(unidadeCurta(p.unidade))}
        {p.unidade === 'liga_desliga' ? (
          <select id={`${id}-valor`} className={INPUT} value={edicao.valor} autoFocus
            aria-invalid={edicao.erros.length > 0} aria-describedby={edicao.erros.length ? idErros : undefined}
            onChange={(e) => onMudar({ ...edicao, valor: e.target.value, erros: [] })}>
            <option value="1">{PREMISSAS_RECEBER.ligado}</option>
            <option value="0">{PREMISSAS_RECEBER.desligado}</option>
          </select>
        ) : (
          <input id={`${id}-valor`} className={`${INPUT} w-28 text-right tabular`} inputMode="decimal" value={edicao.valor} autoFocus
            aria-invalid={edicao.erros.length > 0} aria-describedby={edicao.erros.length ? idErros : undefined}
            onChange={(e) => onMudar({ ...edicao, valor: e.target.value, erros: [] })} />
        )}
      </label>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-vig`}>
        {PREMISSAS_RECEBER.vigenteDe}
        <input id={`${id}-vig`} type="date" className={INPUT} value={edicao.vigenteDe}
          min={hojeISO} max={somarDias(hojeISO, VIGENCIA_MAX_DIAS)}
          onChange={(e) => onMudar({ ...edicao, vigenteDe: e.target.value, erros: [] })} />
      </label>
      <span className="text-[11px] text-[var(--fg-3)]">{PREMISSAS_RECEBER.faixa}: {formatarFaixa(p)}</span>
      <span className="flex gap-2">
        <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? PREMISSAS_RECEBER.salvando : PREMISSAS_RECEBER.salvar}</button>
        <button type="button" className={BTN} disabled={ocupado} onClick={onCancelar}>{PREMISSAS_RECEBER.cancelar}</button>
      </span>
      {edicao.erros.length > 0 && (
        <ul id={idErros} role="alert" className="basis-full text-xs font-semibold text-[var(--red)]">
          {edicao.erros.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}
    </form>
  );
}

function Feriados({ feriados, erro, canEdit, repo, hojeISO, onTentarDeNovo, onGravado }: {
  feriados: FeriadoBancario[] | null; erro: string | null; canEdit: boolean; repo?: RepoPremissas; hojeISO: string;
  onTentarDeNovo?: () => void; onGravado?: () => void;
}) {
  const anoHoje = Number(hojeISO.slice(0, 4));
  const [ano, setAno] = useState<number | null>(anoHoje);
  const [form, setForm] = useState<{ dia: string; nome: string; erros: string[] } | null>(null);
  const [ocupado, setOcupado] = useState(false);
  const [aviso, setAviso] = useState<Aviso>(null);
  const id = useId();

  const anos = useMemo(() => {
    const a = anosDosFeriados(feriados ?? []);
    return a.includes(anoHoje) ? a : [...a, anoHoje].sort((x, y) => x - y);
  }, [feriados, anoHoje]);
  const visiveis = (feriados ?? []).filter((f) => ano == null || f.dia.startsWith(String(ano)));

  const executar = async (dia: string, nome: string, ativo: boolean, msgOk: string, aoConcluir?: () => void) => {
    if (!repo) return;
    setOcupado(true);
    setAviso(null);
    try {
      const r = await repo.salvarFeriado(dia, nome, ativo);
      if (!r.ok) { setAviso({ tipo: 'erro', msg: r.msg ?? 'Não foi possível gravar.' }); return; }
      aoConcluir?.();
      setAviso({ tipo: 'ok', msg: msgOk });
      onGravado?.();
    } finally {
      setOcupado(false);
    }
  };

  const gravarNovo = () => {
    if (!form) return;
    const erros = validarFeriado(form.dia, form.nome);
    if (erros.length) { setForm({ ...form, erros }); return; }
    void executar(form.dia, form.nome.trim(), true, FERIADOS_RECEBER.gravou, () => setForm(null));
  };

  return (
    <section className="space-y-2" aria-labelledby="feriados-titulo">
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="feriados-titulo" className="text-sm font-semibold text-[var(--fg)]">{FERIADOS_RECEBER.titulo}</h2>
        {feriados && (
          <label className="flex items-center gap-1 text-xs text-[var(--fg-3)]" htmlFor={`${id}-ano`}>
            {FERIADOS_RECEBER.ano}
            <select id={`${id}-ano`} className={INPUT} value={ano ?? ''} onChange={(e) => setAno(e.target.value ? Number(e.target.value) : null)}>
              <option value="">{FERIADOS_RECEBER.todos}</option>
              {anos.map((a) => <option key={a} value={a}>{a}</option>)}
            </select>
          </label>
        )}
        {feriados && canEdit && !form && (
          <button type="button" className={`${BTN} ml-auto`} disabled={ocupado}
            onClick={() => { setAviso(null); setForm({ dia: '', nome: '', erros: [] }); }}>
            {FERIADOS_RECEBER.adicionar}
          </button>
        )}
      </div>
      <p className="text-xs text-[var(--fg-3)]">{FERIADOS_RECEBER.explicacao}</p>
      {aviso && (
        <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
          className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{aviso.msg}</p>
      )}
      {canEdit && form && (
        <form className="flex flex-wrap items-end gap-3 rounded-[var(--r-md)] border border-[var(--border)] px-2 py-2"
          aria-label={FERIADOS_RECEBER.adicionar} onSubmit={(e) => { e.preventDefault(); gravarNovo(); }}>
          <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-dia`}>
            {FERIADOS_RECEBER.dia}
            <input id={`${id}-dia`} type="date" className={INPUT} value={form.dia} min="2015-01-01" max="2036-12-31" autoFocus
              aria-invalid={form.erros.length > 0} onChange={(e) => setForm({ ...form, dia: e.target.value, erros: [] })} />
          </label>
          <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-nome`}>
            {FERIADOS_RECEBER.nome}
            <input id={`${id}-nome`} className={`${INPUT} w-64`} value={form.nome} maxLength={120}
              aria-invalid={form.erros.length > 0} onChange={(e) => setForm({ ...form, nome: e.target.value, erros: [] })} />
          </label>
          <span className="flex gap-2">
            <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? PREMISSAS_RECEBER.salvando : FERIADOS_RECEBER.gravar}</button>
            <button type="button" className={BTN} disabled={ocupado} onClick={() => setForm(null)}>{PREMISSAS_RECEBER.cancelar}</button>
          </span>
          {form.erros.length > 0 && (
            <ul role="alert" className="basis-full text-xs font-semibold text-[var(--red)]">{form.erros.map((e) => <li key={e}>{e}</li>)}</ul>
          )}
        </form>
      )}
      {erro ? (
        <p role="alert" className="text-xs text-[var(--fg-2)]">
          {erro} {onTentarDeNovo && <button type="button" className={BTN} onClick={onTentarDeNovo}>{PREMISSAS_RECEBER.tentarDeNovo}</button>}
        </p>
      ) : feriados == null ? (
        <p className="text-xs text-[var(--fg-3)]">{FERIADOS_RECEBER.carregando}</p>
      ) : (
        <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
          <table className="w-full border-collapse text-xs">
            <thead className="bg-[var(--surface-2)]">
              <tr>
                <th className={TH}>{FERIADOS_RECEBER.dia}</th><th className={TH}>{FERIADOS_RECEBER.nome}</th>
                <th className={TH}>{FERIADOS_RECEBER.situacao}</th><th className={TH}>{FERIADOS_RECEBER.fonte}</th>
                <th className={TH}>{FERIADOS_RECEBER.quem}</th>
                {canEdit && <th className={TH}>{FERIADOS_RECEBER.acoes}</th>}
              </tr>
            </thead>
            <tbody>
              {visiveis.length === 0 ? (
                <tr><td colSpan={canEdit ? 6 : 5} className="px-2 py-2 text-[var(--fg-3)]">{FERIADOS_RECEBER.vazio}</td></tr>
              ) : visiveis.map((f) => (
                <tr key={f.dia} className={`border-t border-[var(--border-faint)] ${f.ativo ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}>
                  <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(f.dia)}</td>
                  <td className={TD}>{f.nome}</td>
                  <td className={`${TD} whitespace-nowrap`}>{f.ativo ? FERIADOS_RECEBER.ativo : FERIADOS_RECEBER.inativo}</td>
                  <td className={`${TD} text-[var(--fg-3)]`}>{f.fonte ?? '—'}</td>
                  <td className={`${TD} whitespace-nowrap text-[var(--fg-2)]`}>
                    {f.atualizado_por_nome ?? '—'}{f.atualizado_em ? ` · ${fmtDataHora(f.atualizado_em)}` : ''}
                  </td>
                  {canEdit && (
                    <td className={TD}>
                      <button type="button" className={BTN} disabled={ocupado}
                        aria-label={`${f.ativo ? FERIADOS_RECEBER.desligar : FERIADOS_RECEBER.religar}: ${f.nome} (${fmtData(f.dia)})`}
                        onClick={() => void executar(f.dia, f.nome, !f.ativo, f.ativo ? FERIADOS_RECEBER.desligou : FERIADOS_RECEBER.gravou)}>
                        {f.ativo ? FERIADOS_RECEBER.desligar : FERIADOS_RECEBER.religar}
                      </button>
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
