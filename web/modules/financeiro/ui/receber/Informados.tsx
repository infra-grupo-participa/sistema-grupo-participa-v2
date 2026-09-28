'use client';

// Recebimentos informados (bloco 5, 28/09/2026): renovações Diamante/Aurum negociadas fora, que o financeiro digitava
// numa planilha. Sub-seção da aba Contas a Receber, como Recorrências.
// - Carga: UMA chamada (fn_fin_informados_listar) quando a sub-seção abre; recarrega só depois de gravar.
// - Escrita (criar/editar, baixa manual, desfazer, arquivar, colar da planilha): só com canEdit (quem opera o
//   financeiro). A trava real é o banco: gp_pode_operar_financeiro() em cada RPC.
// - Identificadores chegam MASCARADOS sem gp_pode_ver_cpf(); a máscara nunca volta ao banco (ver entradaDoFormulario).
// - O texto colado nunca é logado; a prévia mostra os identificadores mascarados localmente.
// Formulário e confirmações ficam no fluxo da página (nada `absolute`).
import { useEffect, useMemo, useState, type ReactNode } from 'react';
import { Badge } from '@/shared/ui/components';
import { fmtBRLc, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import {
  casarResultado, COLUNAS_PLANILHA, entradaDoFormulario, formDeInformado, identificadorOculto, lerColagem, mascararLocal,
  ordenarInformados, previaGravavel, SITUACOES_INFORMADO, TIPOS_INFORMADO,
  type Colagem, type FormInformado, type Informado, type ResultadoLinhaImportacao,
} from '../../domain/recebimentos-informados';
import {
  ACOES_INFORMADO, CAMPOS_INFORMADO, COLAR_PLANILHA, SECAO_INFORMADOS, SITUACAO_INFORMADO, TIPO_INFORMADO,
} from './textos';

export type RepoInformados = Pick<FinanceiroRepository,
  'loadInformados' | 'salvarInformado' | 'baixarInformado' | 'arquivarInformado' | 'importarInformados'>;

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 align-top';
const BTN = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const BTN_1 = 'rounded-[var(--r-sm)] border border-[var(--accent)] px-2 py-0.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const INPUT = 'w-full rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]';

export const rotuloSituacaoInformado = (s: string) => SITUACAO_INFORMADO[s] ?? s; // fora do contrato: cru, não disfarça
export const rotuloTipoInformado = (t: string | null) => (t ? TIPO_INFORMADO[t] ?? t : '—');

const hojeISO = () => new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo' }).format(new Date());

type Aviso = { tipo: 'ok' | 'erro'; msg: string } | null;
type AcaoLinha = { id: string; tipo: 'baixar' | 'arquivar'; valor: string } | null;
type Form = { original: Informado | null; valores: FormInformado; erros: string[] } | null;

export function Informados({ repo, canEdit, canVerDoc, onAlterado, inicial = null, autoAbrir = false }: {
  repo: RepoInformados;
  canEdit: boolean;
  canVerDoc: boolean;
  /** Depois de gravar: a grade (bloco 5) muda — o pai recarrega fn_fin_receber_semanal. */
  onAlterado?: () => void;
  /** Só para teste de render: lista já carregada, sub-seção aberta. */
  inicial?: Informado[] | null;
  /** A sub-seção agora é uma sub-aba própria (Previsão de caixa): abrir a aba já carrega, sem exigir um segundo
   * clique no acordeão interno. Padrão continua fechado (compatível com quem usa Informados fora da sub-aba). */
  autoAbrir?: boolean;
}) {
  const [aberto, setAberto] = useState(inicial != null || autoAbrir);
  const [lista, setLista] = useState<Informado[] | null>(inicial ? ordenarInformados(inicial) : null);
  const [erro, setErro] = useState<string | null>(null);
  const [carregando, setCarregando] = useState(false);
  const [filtro, setFiltro] = useState<string | null>(null);
  const [aviso, setAviso] = useState<Aviso>(null);
  const [ocupado, setOcupado] = useState(false);
  const [form, setForm] = useState<Form>(null);
  const [acao, setAcao] = useState<AcaoLinha>(null);
  const [colando, setColando] = useState(false);

  const carregar = async () => {
    setCarregando(true);
    try {
      setLista(ordenarInformados(await repo.loadInformados()));
      setErro(null);
    } catch {
      setErro(SECAO_INFORMADOS.erroCarregamento);
    } finally {
      setCarregando(false);
    }
  };

  const alternar = () => {
    const abrir = !aberto;
    setAberto(abrir);
    if (abrir && lista == null && !carregando) void carregar();
  };

  // autoAbrir (sub-aba própria): carrega uma vez, ao montar já aberto — sem depender do clique no acordeão.
  // `inicial` (teste de render) já entra com a lista pronta, então esta condição não dispara chamada nenhuma.
  useEffect(() => {
    if (autoAbrir && lista == null && !carregando) void carregar();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** Escrita que deu certo: recarrega a lista (1 chamada) e avisa o pai (grade). */
  const depoisDeGravar = async (msg: string) => {
    setAviso({ tipo: 'ok', msg });
    await carregar();
    onAlterado?.();
  };

  const executar = async (f: () => Promise<{ ok: boolean; msg?: string }>, aoConcluir?: () => void) => {
    setOcupado(true);
    setAviso(null);
    try {
      const r = await f();
      if (!r.ok) { setAviso({ tipo: 'erro', msg: r.msg ?? 'Não foi possível concluir.' }); return; }
      aoConcluir?.();
      await depoisDeGravar(r.msg ?? 'Feito.');
    } finally {
      setOcupado(false);
    }
  };

  const salvarForm = () => {
    if (!form) return;
    const { entrada, erros } = entradaDoFormulario(form.valores, form.original, canVerDoc);
    if (!entrada) { setForm({ ...form, erros }); return; }
    void executar(() => repo.salvarInformado(entrada), () => setForm(null));
  };

  const confirmarAcao = () => {
    if (!acao) return;
    if (acao.tipo === 'baixar') {
      if (!acao.valor) return;
      void executar(() => repo.baixarInformado(acao.id, acao.valor), () => setAcao(null));
    } else {
      if (acao.valor.trim().length < 3) return;
      void executar(() => repo.arquivarInformado(acao.id, acao.valor.trim()), () => setAcao(null));
    }
  };

  const resumo = useMemo(() => {
    const r = new Map<string, { n: number; cents: number }>();
    for (const i of lista ?? []) {
      const x = r.get(i.situacao) ?? { n: 0, cents: 0 };
      x.n += 1; x.cents += Math.round(i.valor * 100);
      r.set(i.situacao, x);
    }
    return r;
  }, [lista]);

  const todos = lista ?? [];
  const ativos = todos.filter((i) => i.situacao !== 'arquivado');
  const visiveis = filtro ? todos.filter((i) => i.situacao === filtro) : ativos;
  const conhecidas = SITUACOES_INFORMADO as readonly string[];
  const extras = [...resumo.keys()].filter((s) => !conhecidas.includes(s)); // situação fora do contrato: aparece, não some
  const botoes: { k: string | null; l: string; n: number; v: number | null }[] = [
    { k: null, l: SECAO_INFORMADOS.todosAtivos, n: ativos.length, v: ativos.reduce((s, i) => s + Math.round(i.valor * 100), 0) / 100 },
    ...[...conhecidas, ...extras].map((s) => ({ k: s, l: rotuloSituacaoInformado(s), n: resumo.get(s)?.n ?? 0, v: (resumo.get(s)?.cents ?? 0) / 100 })),
  ];
  const nCols = canEdit ? 12 : 11;

  return (
    <section className="space-y-2" aria-labelledby="informados-titulo">
      <div className="flex flex-wrap items-center gap-2">
        <h2 id="informados-titulo" className="text-sm font-semibold text-[var(--fg)]">
          <button type="button" onClick={alternar} aria-expanded={aberto} aria-controls="informados-corpo" className="hover:text-[var(--accent)]">
            {aberto ? '▾' : '▸'} {SECAO_INFORMADOS.titulo}
          </button>
        </h2>
        {aberto && lista && botoes.map((b) => (
          <button key={b.k ?? 'ativos'} type="button" aria-pressed={filtro === b.k} onClick={() => setFiltro(b.k)}
            className={`rounded-[var(--r-sm)] border px-2 py-0.5 text-xs ${filtro === b.k ? 'border-[var(--accent)] font-semibold text-[var(--fg)]' : 'border-[var(--border)] text-[var(--fg-2)]'}`}>
            {b.l} <span className="tabular">{b.n}</span>{b.v != null && b.n > 0 ? <span className="tabular"> · {fmtBRLc(b.v)}</span> : null}
          </button>
        ))}
        {aberto && lista && canEdit && (
          <span className="ml-auto flex gap-2">
            <button type="button" className={BTN} disabled={ocupado}
              onClick={() => { setAcao(null); setForm({ original: null, valores: formDeInformado(null, canVerDoc), erros: [] }); }}>
              {SECAO_INFORMADOS.novo}
            </button>
            <button type="button" className={BTN} aria-expanded={colando} onClick={() => setColando((c) => !c)}>{SECAO_INFORMADOS.colar}</button>
          </span>
        )}
      </div>

      {aberto && (
        <div id="informados-corpo" className="space-y-2">
          <p className="text-xs text-[var(--fg-3)]">
            {SECAO_INFORMADOS.explicacao}{!canEdit && <> {SECAO_INFORMADOS.somenteLeitura}</>}
          </p>
          {aviso && (
            <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
              className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{aviso.msg}</p>
          )}
          {erro ? (
            <p role="alert" className="text-xs text-[var(--fg-2)]">
              {erro} <button type="button" className={BTN} onClick={() => void carregar()}>{SECAO_INFORMADOS.tentarDeNovo}</button>
            </p>
          ) : lista == null ? (
            <p className="text-xs text-[var(--fg-3)]">{SECAO_INFORMADOS.carregando}</p>
          ) : (
            <>
              {canEdit && colando && (
                <ColarDaPlanilha repo={repo} canVerDoc={canVerDoc} onGravado={(n) => { setColando(false); void depoisDeGravar(COLAR_PLANILHA.gravou(n)); }} />
              )}
              {canEdit && form && (
                <FormularioInformado form={form} canVerDoc={canVerDoc} ocupado={ocupado}
                  onMudar={(valores) => setForm({ ...form, valores })} onSalvar={salvarForm} onCancelar={() => setForm(null)} />
              )}
              <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
                <table className="w-full border-collapse text-xs">
                  <thead className="bg-[var(--surface-2)]">
                    <tr>
                      <th className={TH}>{CAMPOS_INFORMADO.dataPrevista}</th><th className={TH}>{CAMPOS_INFORMADO.cliente}</th>
                      <th className={TH}>{CAMPOS_INFORMADO.tipo}</th><th className={`${TH} text-right`}>{CAMPOS_INFORMADO.valor}</th>
                      <th className={TH}>{CAMPOS_INFORMADO.viaHotmart}</th><th className={TH}>{CAMPOS_INFORMADO.produtos}</th>
                      <th className={TH}>{CAMPOS_INFORMADO.identificador1}</th><th className={TH}>{CAMPOS_INFORMADO.identificador2}</th>
                      <th className={TH}>{CAMPOS_INFORMADO.acordoDesde}</th><th className={`${TH} text-right`}>{CAMPOS_INFORMADO.recebidoAcumulado}</th>
                      <th className={TH}>{CAMPOS_INFORMADO.situacao}</th>
                      {canEdit && <th className={TH}>{CAMPOS_INFORMADO.acoes}</th>}
                    </tr>
                  </thead>
                  <tbody>
                    {visiveis.length === 0 ? (
                      <tr><td colSpan={nCols} className="px-2 py-2 text-[var(--fg-3)]">{SECAO_INFORMADOS.vazio}</td></tr>
                    ) : visiveis.map((i) => [
                      <tr key={i.id} className="border-t border-[var(--border-faint)] text-[var(--fg)]">
                        <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(i.data_prevista)}</td>
                        <td className={TD}>{i.cliente}</td>
                        <td className={`${TD} whitespace-nowrap text-[var(--fg-2)]`}>{rotuloTipoInformado(i.tipo)}</td>
                        <td className={`${TD} text-right tabular whitespace-nowrap`}>{fmtBRLc(i.valor)}</td>
                        <td className={TD}>{i.via_hotmart ? CAMPOS_INFORMADO.sim : CAMPOS_INFORMADO.nao}</td>
                        <td className={`${TD} text-[var(--fg-2)]`}>{i.produtos.join('; ') || '—'}</td>
                        <td className={`${TD} font-mono text-[11px] text-[var(--fg-2)]`}>{i.identificador1 ?? '—'}</td>
                        <td className={`${TD} font-mono text-[11px] text-[var(--fg-2)]`}>{i.identificador2 ?? '—'}</td>
                        <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(i.acordo_desde)}</td>
                        <td className={`${TD} text-right tabular whitespace-nowrap text-[var(--fg-2)]`}>
                          {i.via_hotmart && (i.recebido_hotmart != null || i.acumulado_acordo != null)
                            ? `${fmtBRLc(i.recebido_hotmart)} / ${fmtBRLc(i.acumulado_acordo)}` : '—'}
                        </td>
                        <td className={`${TD} whitespace-nowrap`}>
                          {/* Cor só no que pede ação: em atraso — cobrar. O texto diz a situação; a cor não é o único sinal. */}
                          {i.situacao === 'em_atraso_cobrar' ? <Badge tone="warning">{rotuloSituacaoInformado(i.situacao)}</Badge> : rotuloSituacaoInformado(i.situacao)}
                          {i.baixa_manual_em && <span className="text-[var(--fg-3)]"> · {fmtData(i.baixa_manual_em)}</span>}
                          {i.situacao === 'arquivado' && i.motivo_arquivo && (
                            <span className="block whitespace-normal text-[var(--fg-3)]">{ACOES_INFORMADO.arquivadoPor(i.motivo_arquivo)}</span>
                          )}
                        </td>
                        {canEdit && (
                          <td className={`${TD} whitespace-nowrap`}>
                            {i.situacao !== 'arquivado' && (
                              <span className="flex gap-1">
                                <button type="button" className={BTN} disabled={ocupado}
                                  onClick={() => { setAcao(null); setForm({ original: i, valores: formDeInformado(i, canVerDoc), erros: [] }); }}>
                                  {ACOES_INFORMADO.editar}
                                </button>
                                {i.baixa_manual_em ? (
                                  <button type="button" className={BTN} disabled={ocupado}
                                    onClick={() => void executar(() => repo.baixarInformado(i.id, null))}>{ACOES_INFORMADO.desfazerBaixa}</button>
                                ) : (
                                  <button type="button" className={BTN} disabled={ocupado} aria-expanded={acao?.id === i.id && acao.tipo === 'baixar'}
                                    onClick={() => setAcao({ id: i.id, tipo: 'baixar', valor: hojeISO() })}>{ACOES_INFORMADO.baixar}</button>
                                )}
                                <button type="button" className={BTN} disabled={ocupado} aria-expanded={acao?.id === i.id && acao.tipo === 'arquivar'}
                                  onClick={() => setAcao({ id: i.id, tipo: 'arquivar', valor: '' })}>{ACOES_INFORMADO.arquivar}</button>
                              </span>
                            )}
                          </td>
                        )}
                      </tr>,
                      canEdit && acao?.id === i.id ? (
                        <tr key={`${i.id}-acao`} className="bg-[var(--surface-2)]">
                          <td colSpan={nCols} className="px-2 py-1.5">
                            <span className="flex flex-wrap items-center gap-2 text-xs">
                              <label className="flex items-center gap-2 text-[var(--fg-2)]">
                                {acao.tipo === 'baixar' ? ACOES_INFORMADO.dataDaBaixa : ACOES_INFORMADO.motivo}
                                {acao.tipo === 'baixar' ? (
                                  <input type="date" className={`${INPUT} w-auto`} value={acao.valor} max={hojeISO()}
                                    onChange={(e) => setAcao({ ...acao, valor: e.target.value })} />
                                ) : (
                                  <input type="text" className={`${INPUT} w-72`} value={acao.valor} maxLength={500}
                                    onChange={(e) => setAcao({ ...acao, valor: e.target.value })} />
                                )}
                              </label>
                              <button type="button" className={BTN_1} onClick={confirmarAcao}
                                disabled={ocupado || (acao.tipo === 'baixar' ? !acao.valor : acao.valor.trim().length < 3)}>
                                {acao.tipo === 'baixar' ? ACOES_INFORMADO.confirmarBaixa : ACOES_INFORMADO.confirmarArquivar}
                              </button>
                              <button type="button" className={BTN} onClick={() => setAcao(null)}>{ACOES_INFORMADO.cancelar}</button>
                            </span>
                          </td>
                        </tr>
                      ) : null,
                    ])}
                  </tbody>
                </table>
              </div>
            </>
          )}
        </div>
      )}
    </section>
  );
}

export function FormularioInformado({ form, canVerDoc, ocupado, onMudar, onSalvar, onCancelar }: {
  form: NonNullable<Form>; canVerDoc: boolean; ocupado: boolean;
  onMudar: (v: FormInformado) => void; onSalvar: () => void; onCancelar: () => void;
}) {
  const v = form.valores;
  const set = <K extends keyof FormInformado>(k: K, x: FormInformado[K]) => onMudar({ ...v, [k]: x });
  const campo = (rotulo: string, filho: ReactNode, ajuda?: string) => (
    <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]">
      <span>{rotulo}{ajuda && <span className="text-[var(--fg-4)]"> · {ajuda}</span>}</span>{filho}
    </label>
  );
  const ident = (k: 'identificador1' | 'identificador2') => {
    const orig = form.original?.[k] ?? null;
    const oculto = form.original != null && identificadorOculto(orig, canVerDoc);
    // Sem gp_pode_ver_cpf() o banco recusa criar/trocar/apagar identificador (P0001): campo desabilitado, mostra só a
    // máscara do atual; entradaDoFormulario não manda as chaves.
    return (
      <input type="text" className={INPUT} value={canVerDoc ? v[k] : ''} autoComplete="off" spellCheck={false}
        disabled={!canVerDoc}
        placeholder={!canVerDoc ? orig ?? '' : oculto && orig ? CAMPOS_INFORMADO.identificadorMantido(orig) : ''}
        onChange={(e) => set(k, e.target.value)} />
    );
  };
  return (
    <form className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] p-2"
      onSubmit={(e) => { e.preventDefault(); onSalvar(); }}
      aria-label={form.original ? ACOES_INFORMADO.tituloEditar : ACOES_INFORMADO.tituloNovo}>
      <p className="text-xs font-semibold text-[var(--fg)]">{form.original ? ACOES_INFORMADO.tituloEditar : ACOES_INFORMADO.tituloNovo}</p>
      <div className="grid grid-cols-2 gap-2 md:grid-cols-5">
        {campo(CAMPOS_INFORMADO.dataPrevista, <input type="date" className={INPUT} value={v.data_prevista} onChange={(e) => set('data_prevista', e.target.value)} />)}
        {campo(CAMPOS_INFORMADO.cliente, <input type="text" className={INPUT} value={v.cliente} onChange={(e) => set('cliente', e.target.value)} />)}
        {campo(CAMPOS_INFORMADO.tipo, (
          <select className={INPUT} value={v.tipo} onChange={(e) => set('tipo', e.target.value)}>
            <option value="">{CAMPOS_INFORMADO.selecione}</option>
            {TIPOS_INFORMADO.map((t) => <option key={t} value={t}>{rotuloTipoInformado(t)}</option>)}
          </select>
        ))}
        {campo(CAMPOS_INFORMADO.valor, <input type="text" inputMode="decimal" className={`${INPUT} text-right tabular`} value={v.valor} onChange={(e) => set('valor', e.target.value)} />)}
        {campo(CAMPOS_INFORMADO.viaHotmart, (
          <select className={INPUT} value={v.via_hotmart} onChange={(e) => set('via_hotmart', e.target.value as FormInformado['via_hotmart'])}>
            <option value="">{CAMPOS_INFORMADO.selecione}</option>
            <option value="S">{CAMPOS_INFORMADO.sim}</option>
            <option value="N">{CAMPOS_INFORMADO.nao}</option>
          </select>
        ))}
        {campo(CAMPOS_INFORMADO.produtos, <input type="text" className={INPUT} value={v.produtos} onChange={(e) => set('produtos', e.target.value)} />, CAMPOS_INFORMADO.produtosAjuda)}
        {campo(CAMPOS_INFORMADO.identificador1, ident('identificador1'),
          canVerDoc ? CAMPOS_INFORMADO.identificadorAjuda : CAMPOS_INFORMADO.identificadorSemPermissao)}
        {campo(CAMPOS_INFORMADO.identificador2, ident('identificador2'), canVerDoc ? undefined : CAMPOS_INFORMADO.identificadorSemPermissao)}
        {campo(CAMPOS_INFORMADO.acordoDesde, <input type="date" className={INPUT} value={v.acordo_desde} onChange={(e) => set('acordo_desde', e.target.value)} />)}
      </div>
      {form.erros.length > 0 && (
        <ul role="alert" className="list-disc pl-5 text-xs text-[var(--red)]">{form.erros.map((e) => <li key={e}>{e}</li>)}</ul>
      )}
      <div className="flex gap-2">
        <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? ACOES_INFORMADO.salvando : ACOES_INFORMADO.salvar}</button>
        <button type="button" className={BTN} onClick={onCancelar}>{ACOES_INFORMADO.cancelar}</button>
      </div>
    </form>
  );
}

/** Colar da planilha: lê o TSV (puro), confere no banco com p_simular=true (prévia) e só então grava (p_simular=false). */
export function ColarDaPlanilha({ repo, canVerDoc, onGravado, inicial }: {
  repo: Pick<RepoInformados, 'importarInformados'>;
  /** gp_pode_ver_cpf(): sem ele, linha com identificador é erro local e nenhuma entrada leva identificador1/2. */
  canVerDoc: boolean;
  onGravado: (n: number) => void;
  /** Só para teste de render: colagem e conferência já feitas. */
  inicial?: { colagem: Colagem; previa: (ResultadoLinhaImportacao | null)[] | null };
}) {
  const [texto, setTexto] = useState('');
  const [colagem, setColagem] = useState<Colagem | null>(inicial?.colagem ?? null);
  const [previa, setPrevia] = useState<(ResultadoLinhaImportacao | null)[] | null>(inicial?.previa ?? null);
  const [ocupado, setOcupado] = useState<'conferindo' | 'gravando' | null>(null);
  const [msg, setMsg] = useState<string | null>(null);

  const comErroLocal = colagem ? colagem.linhas.filter((l) => l.erros.length > 0).length : 0;
  const comErroBanco = previa ? previa.filter((r) => !r?.ok).length : 0;
  const gravavel = !!colagem && previaGravavel(colagem.linhas, previa);

  const conferir = async () => {
    const c = lerColagem(texto, { podeVerDoc: canVerDoc });
    setColagem(c); setPrevia(null); setMsg(null);
    if (c.erroGeral || c.linhas.some((l) => l.erros.length > 0)) return; // erro de formato: nada vai ao banco
    setOcupado('conferindo');
    try {
      const r = await repo.importarInformados(c.linhas.map((l) => l.entrada), true);
      if (!r.ok && r.linhas.length === 0) { setMsg(r.msg ?? null); return; }
      setPrevia(casarResultado(c.linhas.length, r.linhas));
    } finally {
      setOcupado(null);
    }
  };

  const gravar = async () => {
    if (!colagem || !gravavel) return;
    setOcupado('gravando'); setMsg(null);
    try {
      // Grava EXATAMENTE as linhas conferidas (mudar o texto invalida a prévia).
      const r = await repo.importarInformados(colagem.linhas.map((l) => l.entrada), false);
      if (!r.ok && r.linhas.length === 0) { setMsg(r.msg ?? null); return; }
      const casado = casarResultado(colagem.linhas.length, r.linhas);
      if (casado.every((x) => x?.ok === true)) {
        setTexto(''); setColagem(null); setPrevia(null);
        onGravado(colagem.linhas.length);
        return;
      }
      setPrevia(casado);
      setMsg(COLAR_PLANILHA.naoGravou);
    } finally {
      setOcupado(null);
    }
  };

  return (
    <section className="space-y-2 rounded-[var(--r-md)] border border-[var(--border)] p-2" aria-labelledby="colar-titulo">
      <p id="colar-titulo" className="text-xs font-semibold text-[var(--fg)]">{COLAR_PLANILHA.titulo}</p>
      <p className="text-xs text-[var(--fg-3)]">{COLAR_PLANILHA.instrucao} {COLUNAS_PLANILHA.join(' · ')}. {COLAR_PLANILHA.tudoOuNada}</p>
      {!canVerDoc && <p className="text-xs text-[var(--fg-2)]">{COLAR_PLANILHA.identificadoresSemPermissao}</p>}
      <textarea aria-label={COLAR_PLANILHA.rotuloTexto} rows={6} value={texto} spellCheck={false} autoComplete="off"
        className={`${INPUT} font-mono`}
        onChange={(e) => { setTexto(e.target.value); setColagem(null); setPrevia(null); setMsg(null); }} />
      <div className="flex flex-wrap items-center gap-2">
        <button type="button" className={BTN} disabled={!texto.trim() || ocupado != null} onClick={() => void conferir()}>
          {ocupado === 'conferindo' ? COLAR_PLANILHA.conferindo : COLAR_PLANILHA.conferir}
        </button>
        <button type="button" className={BTN_1} disabled={!gravavel || ocupado != null} onClick={() => void gravar()}>
          {ocupado === 'gravando' ? COLAR_PLANILHA.gravando : COLAR_PLANILHA.gravar(colagem?.linhas.length ?? 0)}
        </button>
        <button type="button" className={BTN} disabled={ocupado != null}
          onClick={() => { setTexto(''); setColagem(null); setPrevia(null); setMsg(null); }}>{COLAR_PLANILHA.limpar}</button>
        {colagem && !colagem.erroGeral && (
          <span className="text-xs text-[var(--fg-2)]">
            {COLAR_PLANILHA.resumo(colagem.linhas.length, previa ? comErroBanco : comErroLocal)}
            {colagem.cabecalhoIgnorado && <> · {COLAR_PLANILHA.cabecalhoIgnorado}</>}
          </span>
        )}
      </div>
      {colagem?.erroGeral && <p role="alert" className="text-xs font-semibold text-[var(--red)]">{colagem.erroGeral}</p>}
      {comErroLocal > 0 && <p role="alert" className="text-xs font-semibold text-[var(--red)]">{COLAR_PLANILHA.corrijaNaPlanilha}</p>}
      {msg && <p role="alert" className="text-xs font-semibold text-[var(--red)]">{msg}</p>}
      {colagem && colagem.linhas.length > 0 && (
        <div className="max-h-[480px] overflow-auto rounded-[var(--r-md)] border border-[var(--border)]">
          <table className="w-full border-collapse text-xs">
            <thead className="bg-[var(--surface-2)]">
              <tr>
                <th className={TH}>{COLAR_PLANILHA.linha}</th><th className={TH}>{CAMPOS_INFORMADO.dataPrevista}</th>
                <th className={TH}>{CAMPOS_INFORMADO.cliente}</th><th className={TH}>{CAMPOS_INFORMADO.tipo}</th>
                <th className={`${TH} text-right`}>{CAMPOS_INFORMADO.valor}</th><th className={TH}>{CAMPOS_INFORMADO.viaHotmart}</th>
                <th className={TH}>{CAMPOS_INFORMADO.produtos}</th><th className={TH}>{COLAR_PLANILHA.identificadores}</th>
                <th className={TH}>{CAMPOS_INFORMADO.acordoDesde}</th><th className={TH}>{CAMPOS_INFORMADO.baixaManual}</th>
                <th className={TH}>{COLAR_PLANILHA.resultado}</th>
              </tr>
            </thead>
            <tbody>
              {colagem.linhas.map((l, i) => {
                const e = l.entrada;
                const r = previa?.[i] ?? null;
                const erros = [...l.erros, ...(r && !r.ok && r.erro ? [r.erro] : [])];
                const semResposta = previa != null && r == null;
                return (
                  <tr key={l.n} className={`border-t border-[var(--border-faint)] ${erros.length || semResposta ? 'text-[var(--fg)]' : 'text-[var(--fg-2)]'}`}>
                    <td className={`${TD} tabular`}>{l.n}</td>
                    <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(e.data_prevista)}</td>
                    <td className={TD}>{e.cliente || '—'}</td>
                    <td className={`${TD} whitespace-nowrap`}>{rotuloTipoInformado(e.tipo)}</td>
                    <td className={`${TD} text-right tabular whitespace-nowrap`}>{fmtBRLc(e.valor)}</td>
                    <td className={TD}>{e.via_hotmart == null ? '—' : e.via_hotmart ? CAMPOS_INFORMADO.sim : CAMPOS_INFORMADO.nao}</td>
                    <td className={TD}>{e.produtos.join('; ') || '—'}</td>
                    <td className={`${TD} font-mono text-[11px]`}>
                      {[e.identificador1, e.identificador2].filter(Boolean).map(mascararLocal).join(' · ') || '—'}
                    </td>
                    <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(e.acordo_desde)}</td>
                    <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(e.baixa_manual_em)}</td>
                    <td className={TD}>
                      {erros.length > 0 ? (
                        <ul className="font-semibold text-[var(--red)]">{erros.map((x) => <li key={x}>{x}</li>)}</ul>
                      ) : semResposta ? <span className="font-semibold text-[var(--red)]">{COLAR_PLANILHA.semConferencia}</span>
                        : r?.ok ? COLAR_PLANILHA.ok : '—'}
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}
