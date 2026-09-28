'use client';

// Sub-aba "Eventos" de Previsão de caixa (#receber?ver=eventos, fatia F3, z67): o evento planejado do bloco 4.
// - Carga: o PAI (FinanceiroClient) busca a lista (fn_fin_eventos_planejados_listar) na 1ª vez que esta sub-aba abre e
//   guarda; os candidatos a evento de referência (fn_fin_funis) só quando o formulário abre, 1×. Este componente não
//   consulta nada sozinho (desmonta a cada troca de sub-aba).
// - Escrita: só com canEdit. A trava real é o banco (gp_pode_operar_financeiro); a validação daqui repete as regras da
//   RPC para poupar uma ida ao banco. Nada se apaga: arquivar com motivo.
// - Mini-curva: tabela com barra por dia (a barra é enfeite de leitura, aria-hidden; o número está em texto ao lado).
// Formulários e curva ficam no fluxo da página (nada `absolute`).
import { useId, useMemo, useState } from 'react';
import { fmtBRLc, fmtData, fmtDataHora } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import {
  candidatosReferencia, somarDiasISO, totalEsperado, validarEvento, validarMotivoArquivar,
  type EventoPlanejado, type FormEvento, type SituacaoEventoPlanejado,
} from '../../domain/eventos-planejados';
import type { Funil } from '../../domain/funis';
import { EVENTOS_RECEBER as T } from './textos';

export type RepoEventos = Pick<FinanceiroRepository, 'salvarEventoPlanejado' | 'arquivarEventoPlanejado'>;

const TH = 'px-2 py-1.5 text-left text-[11px] font-semibold uppercase text-[var(--fg-3)] whitespace-nowrap';
const TD = 'px-2 py-1 align-top';
const BTN = 'rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const BTN_1 = 'rounded-[var(--r-sm)] border border-[var(--accent)] px-2 py-0.5 text-xs font-semibold text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';
const INPUT = 'rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs text-[var(--fg)]';
const N_COLS = 9;

type Aviso = { tipo: 'ok' | 'erro'; msg: string } | null;
type Filtro = 'sem_arquivados' | SituacaoEventoPlanejado;

const fmtTam = (n: number) => n.toLocaleString('pt-BR', { maximumFractionDigits: 2 });
const fmtPct = (f: number | null) => (f == null ? '—' : `${(f * 100).toLocaleString('pt-BR', { minimumFractionDigits: 1, maximumFractionDigits: 1 })}%`);

function formDe(e: EventoPlanejado | null): FormEvento {
  if (!e) {
    return { nome: '', abertura: '', evento_ref_id: '', tamanho_conservador: '0,7', tamanho_base: '1', tamanho_otimista: '1,3',
      pausa_avulso: true, observacao: '' };
  }
  const t = (n: number) => String(n).replace('.', ',');
  return {
    id: e.id, nome: e.nome, abertura: e.abertura, evento_ref_id: String(e.evento_ref_id),
    tamanho_conservador: t(e.tamanho_conservador), tamanho_base: t(e.tamanho_base), tamanho_otimista: t(e.tamanho_otimista),
    pausa_avulso: e.pausa_avulso, observacao: e.observacao ?? '',
  };
}

export function Eventos({
  eventos, erro, candidatos, erroCandidatos, canEdit, hojeISO, repo, onTentarDeNovo, onPedirCandidatos, onAlterado,
  filtroInicial = null,
}: {
  /** NULL = carregando. */
  eventos: EventoPlanejado[] | null;
  erro: string | null;
  /** fn_fin_funis inteiro (o filtro de candidato é daqui). NULL = ainda não pedido ou carregando. */
  candidatos: Funil[] | null;
  erroCandidatos: string | null;
  canEdit: boolean;
  hojeISO: string;
  repo?: RepoEventos;
  onTentarDeNovo?: () => void;
  onPedirCandidatos?: () => void;
  onAlterado?: () => void;
  /** Situação já filtrada ao abrir (link da Visão geral, `&situacao=encerrado`). */
  filtroInicial?: string | null;
}) {
  const podeEditar = canEdit && !!repo;
  const [filtro, setFiltro] = useState<Filtro>(
    filtroInicial === 'ativo' || filtroInicial === 'encerrado' || filtroInicial === 'arquivado' ? filtroInicial : 'sem_arquivados');
  const [form, setForm] = useState<(FormEvento & { erros: string[] }) | null>(null);
  const [arquivando, setArquivando] = useState<{ id: number; motivo: string; erro: string | null } | null>(null);
  const [curvaAberta, setCurvaAberta] = useState<Set<number>>(new Set());
  const [ocupado, setOcupado] = useState(false);
  const [aviso, setAviso] = useState<Aviso>(null);
  const id = useId();

  const visiveis = (eventos ?? []).filter((e) => (filtro === 'sem_arquivados' ? e.situacao !== 'arquivado' : e.situacao === filtro));
  const opcoes = useMemo(() => candidatosReferencia(candidatos ?? [], hojeISO), [candidatos, hojeISO]);

  const abrirForm = (e: EventoPlanejado | null) => {
    setAviso(null);
    setArquivando(null);
    setForm({ ...formDe(e), erros: [] });
    onPedirCandidatos?.();
  };

  const alternarCurva = (k: number) => setCurvaAberta((s) => {
    const n = new Set(s);
    if (n.has(k)) n.delete(k); else n.add(k);
    return n;
  });

  const gravar = async () => {
    if (!form || !repo) return;
    const v = validarEvento(form, hojeISO);
    if (!v.ok) { setForm({ ...form, erros: v.erros }); return; }
    setOcupado(true);
    setAviso(null);
    try {
      const r = await repo.salvarEventoPlanejado(v.entrada);
      if (!r.ok) { setForm({ ...form, erros: [r.msg ?? 'Não foi possível gravar.'] }); return; }
      setForm(null);
      setAviso({ tipo: 'ok', msg: T.gravou });
      onAlterado?.();
    } finally {
      setOcupado(false);
    }
  };

  const arquivar = async () => {
    if (!arquivando || !repo) return;
    const e = validarMotivoArquivar(arquivando.motivo);
    if (e) { setArquivando({ ...arquivando, erro: e }); return; }
    setOcupado(true);
    setAviso(null);
    try {
      const r = await repo.arquivarEventoPlanejado(arquivando.id, arquivando.motivo.trim());
      if (!r.ok) { setArquivando({ ...arquivando, erro: r.msg ?? 'Não foi possível arquivar.' }); return; }
      setArquivando(null);
      setAviso({ tipo: 'ok', msg: T.arquivou });
      onAlterado?.();
    } finally {
      setOcupado(false);
    }
  };

  return (
    <section className="space-y-2" aria-labelledby={`${id}-titulo`}>
      <div className="flex flex-wrap items-center gap-2">
        <h2 id={`${id}-titulo`} className="text-sm font-semibold text-[var(--fg)]">{T.titulo}</h2>
        {eventos && (
          <label className="flex items-center gap-1 text-xs text-[var(--fg-3)]" htmlFor={`${id}-filtro`}>
            {T.filtro}
            <select id={`${id}-filtro`} className={INPUT} value={filtro} onChange={(e) => setFiltro(e.target.value as Filtro)}>
              <option value="sem_arquivados">{T.todosSemArquivados}</option>
              <option value="ativo">{T.situacao.ativo}</option>
              <option value="encerrado">{T.situacao.encerrado}</option>
              <option value="arquivado">{T.situacao.arquivado}</option>
            </select>
          </label>
        )}
        {eventos && podeEditar && !form && (
          <button type="button" className={`${BTN} ml-auto`} disabled={ocupado} onClick={() => abrirForm(null)}>{T.novo}</button>
        )}
      </div>
      <p className="text-xs text-[var(--fg-3)]">{T.explicacao} {T.totalEsperado}: {T.totalEsperadoAjuda}{!canEdit && <> {T.somenteLeitura}</>}</p>
      {aviso && (
        <p role={aviso.tipo === 'erro' ? 'alert' : 'status'}
          className={`text-xs ${aviso.tipo === 'erro' ? 'font-semibold text-[var(--red)]' : 'text-[var(--fg-2)]'}`}>{aviso.msg}</p>
      )}
      {podeEditar && form && form.id == null && (
        <FormularioEvento form={form} opcoes={opcoes} candidatosCarregando={candidatos == null && !erroCandidatos}
          erroCandidatos={erroCandidatos} hojeISO={hojeISO} ocupado={ocupado} onMudar={setForm}
          onGravar={() => void gravar()} onCancelar={() => setForm(null)} refAtual={null} />
      )}

      {erro ? (
        <p role="alert" className="text-xs text-[var(--fg-2)]">
          {erro} {onTentarDeNovo && <button type="button" className={BTN} onClick={onTentarDeNovo}>{T.tentarDeNovo}</button>}
        </p>
      ) : eventos == null ? (
        <p role="status" className="text-xs text-[var(--fg-3)]">{T.carregando}</p>
      ) : (
        <div className="overflow-x-auto rounded-[var(--r-md)] border border-[var(--border)]">
          <table className="w-full border-collapse text-xs">
            <thead className="bg-[var(--surface-2)]">
              <tr>
                <th className={TH}>{T.evento}</th><th className={TH}>{T.vendas}</th><th className={TH}>{T.referencia}</th>
                <th className={`${TH} text-right`}>{T.tamanho}</th>
                <th className={`${TH} text-right`}>{T.totalEsperado}</th>
                <th className={TH}>{T.pausa}</th><th className={TH}>{T.filtro}</th>
                <th className={TH}>{T.quem}</th><th className={TH}>{T.acoes}</th>
              </tr>
            </thead>
            <tbody>
              {visiveis.length === 0 ? (
                <tr><td colSpan={N_COLS} className="px-2 py-2 text-[var(--fg-3)]">{T.vazio}</td></tr>
              ) : visiveis.flatMap((e) => {
                const aberta = curvaAberta.has(e.id);
                const idCurva = `${id}-curva-${e.id}`;
                const editandoEste = form?.id === e.id;
                const arquivandoEste = arquivando?.id === e.id;
                const tb = totalEsperado(e, 'base');
                return [
                  <tr key={e.id} className={`border-t border-[var(--border)] ${e.situacao === 'arquivado' ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]'}`}>
                    <td className={TD}>
                      <span className="font-semibold">{e.nome}</span>
                      {e.observacao && <span className="block max-w-[40ch] text-[11px] text-[var(--fg-3)]">{e.observacao}</span>}
                    </td>
                    <td className={`${TD} tabular whitespace-nowrap`}>{fmtData(e.abertura)} a {fmtData(e.fim_vendas)}</td>
                    <td className={TD}>
                      {e.evento_ref_nome}
                      <span className="block text-[11px] text-[var(--fg-3)]">
                        {fmtData(e.evento_ref_abertura)} a {fmtData(e.evento_ref_venda_ate)} · {e.total_ref == null ? T.semVendaRef : fmtBRLc(e.total_ref)}
                      </span>
                    </td>
                    <td className={`${TD} text-right tabular whitespace-nowrap`}>
                      {fmtTam(e.tamanho_base)}×
                      <span className="block text-[11px] text-[var(--fg-3)]">
                        {T.cenarios(`${fmtTam(e.tamanho_conservador)}×`, `${fmtTam(e.tamanho_base)}×`, `${fmtTam(e.tamanho_otimista)}×`)}
                      </span>
                    </td>
                    <td className={`${TD} text-right tabular whitespace-nowrap`}>
                      {tb == null ? <span className="text-[var(--fg-3)]">{T.semVendaRef}</span> : fmtBRLc(tb)}
                      {tb != null && (
                        <span className="block text-[11px] text-[var(--fg-3)]">
                          {T.cenarios(fmtBRLc(totalEsperado(e, 'conservador')), fmtBRLc(tb), fmtBRLc(totalEsperado(e, 'otimista')))}
                        </span>
                      )}
                    </td>
                    <td className={`${TD} whitespace-nowrap`}>{e.pausa_avulso ? T.sim : T.nao}</td>
                    <td className={`${TD} whitespace-nowrap`}>
                      {T.situacao[e.situacao] ?? e.situacao}
                      {e.situacao === 'arquivado' && e.arquivado_motivo && (
                        <span className="block max-w-[32ch] whitespace-normal text-[11px] text-[var(--fg-3)]">
                          {T.arquivadoPor(e.arquivado_por_nome ?? '—', e.arquivado_motivo)}
                        </span>
                      )}
                    </td>
                    <td className={`${TD} whitespace-nowrap text-[var(--fg-2)]`}>
                      {e.atualizado_por_nome ?? e.criado_por_nome ?? '—'}
                      {(e.atualizado_em ?? e.criado_em) ? ` · ${fmtDataHora(e.atualizado_em ?? e.criado_em)}` : ''}
                    </td>
                    <td className={TD}>
                      <span className="flex flex-wrap gap-1">
                        <button type="button" className={BTN} aria-expanded={aberta} aria-controls={idCurva}
                          aria-label={`${aberta ? T.ocultarCurva : T.verCurva}: ${e.nome}`} onClick={() => alternarCurva(e.id)}>
                          {aberta ? T.ocultarCurva : T.verCurva}
                        </button>
                        {podeEditar && e.situacao !== 'arquivado' && !editandoEste && (
                          <button type="button" className={BTN} disabled={ocupado} aria-label={`${T.editar}: ${e.nome}`} onClick={() => abrirForm(e)}>
                            {T.editar}
                          </button>
                        )}
                        {podeEditar && e.situacao !== 'arquivado' && !arquivandoEste && (
                          <button type="button" className={BTN} disabled={ocupado} aria-label={`${T.arquivar}: ${e.nome}`}
                            onClick={() => { setAviso(null); setForm(null); setArquivando({ id: e.id, motivo: '', erro: null }); }}>
                            {T.arquivar}
                          </button>
                        )}
                      </span>
                    </td>
                  </tr>,
                  aberta ? (
                    <tr key={`${e.id}-curva`} id={idCurva}>
                      <td colSpan={N_COLS} className="px-2 pb-2"><MiniCurva e={e} /></td>
                    </tr>
                  ) : null,
                  podeEditar && editandoEste && form ? (
                    <tr key={`${e.id}-form`} className="bg-[var(--surface-2)]">
                      <td colSpan={N_COLS} className="px-2 py-2">
                        <FormularioEvento form={form} opcoes={opcoes} candidatosCarregando={candidatos == null && !erroCandidatos}
                          erroCandidatos={erroCandidatos} hojeISO={hojeISO} ocupado={ocupado} onMudar={setForm}
                          onGravar={() => void gravar()} onCancelar={() => setForm(null)}
                          refAtual={{ id: e.evento_ref_id, nome: e.evento_ref_nome }} />
                      </td>
                    </tr>
                  ) : null,
                  podeEditar && arquivandoEste && arquivando ? (
                    <tr key={`${e.id}-arq`} className="bg-[var(--surface-2)]">
                      <td colSpan={N_COLS} className="px-2 py-2">
                        <form className="flex flex-wrap items-end gap-3" aria-label={`${T.arquivar}: ${e.nome}`}
                          onSubmit={(ev) => { ev.preventDefault(); void arquivar(); }}>
                          <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${idCurva}-motivo`}>
                            {T.motivo}
                            <input id={`${idCurva}-motivo`} className={`${INPUT} w-80`} value={arquivando.motivo} maxLength={500} autoFocus
                              aria-invalid={!!arquivando.erro} aria-describedby={arquivando.erro ? `${idCurva}-motivo-erro` : undefined}
                              onChange={(ev) => setArquivando({ ...arquivando, motivo: ev.target.value, erro: null })} />
                          </label>
                          <span className="flex gap-2">
                            <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? T.salvando : T.confirmarArquivar}</button>
                            <button type="button" className={BTN} disabled={ocupado} onClick={() => setArquivando(null)}>{T.cancelar}</button>
                          </span>
                          {arquivando.erro && (
                            <p id={`${idCurva}-motivo-erro`} role="alert" className="basis-full text-xs font-semibold text-[var(--red)]">{arquivando.erro}</p>
                          )}
                        </form>
                      </td>
                    </tr>
                  ) : null,
                ];
              })}
            </tbody>
          </table>
        </div>
      )}
    </section>
  );
}

/** Curva da referência em tabela: dia, data no evento planejado, barra (decorativa), participação e valores em texto. */
export function MiniCurva({ e }: { e: EventoPlanejado }) {
  const max = e.curva.reduce((m, p) => Math.max(m, p.participacao ?? 0), 0);
  if (e.curva.length === 0 || max === 0) return <p className="text-[11px] text-[var(--fg-3)]">{T.curvaVazia}</p>;
  return (
    <table className="border-collapse text-[11px]">
      <caption className="pb-1 text-left font-semibold text-[var(--fg-2)]">{T.curvaTitulo(e.evento_ref_nome)}</caption>
      <thead>
        <tr className="text-[var(--fg-3)]">
          <th className="pr-3 text-left font-normal">{T.dia}</th>
          <th className="pr-3 text-left font-normal">{T.diaPlanejado}</th>
          <th className="pr-3 text-left font-normal">{T.participacao}</th>
          <th className="pr-3 text-right font-normal">{T.liquidoRef}</th>
          <th className="text-right font-normal">{T.vendaBase}</th>
        </tr>
      </thead>
      <tbody className="text-[var(--fg-2)]">
        {e.curva.map((p) => (
          <tr key={p.d}>
            <td className="pr-3 tabular">D{p.d}</td>
            <td className="pr-3 tabular">{fmtData(somarDiasISO(e.abertura, p.d))}</td>
            <td className="pr-3">
              <span className="flex items-center gap-2">
                <span aria-hidden="true" className="inline-block h-2 w-32 bg-[var(--surface-3)]">
                  <span className="block h-2 bg-[var(--accent)]" style={{ width: `${Math.round(((p.participacao ?? 0) / max) * 100)}%` }} />
                </span>
                <span className="tabular">{fmtPct(p.participacao)}</span>
              </span>
            </td>
            <td className="pr-3 text-right tabular">{fmtBRLc(p.liquido)}</td>
            <td className="text-right tabular">{fmtBRLc(Math.round(e.tamanho_base * p.liquido * 100) / 100)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function FormularioEvento({ form, opcoes, candidatosCarregando, erroCandidatos, hojeISO, ocupado, onMudar, onGravar, onCancelar, refAtual }: {
  form: FormEvento & { erros: string[] }; opcoes: Funil[]; candidatosCarregando: boolean; erroCandidatos: string | null;
  hojeISO: string; ocupado: boolean; onMudar: (f: (FormEvento & { erros: string[] }) | null) => void;
  onGravar: () => void; onCancelar: () => void;
  /** Na edição: a referência gravada entra na lista mesmo se deixou de ser candidata. */
  refAtual: { id: number; nome: string } | null;
}) {
  const id = useId();
  const idErros = `${id}-erros`;
  const mudar = (p: Partial<FormEvento>) => onMudar({ ...form, ...p, erros: [] });
  const inv = form.erros.length > 0;
  const desc = inv ? idErros : undefined;
  const refFora = refAtual && !opcoes.some((f) => f.evento_id === refAtual.id);
  return (
    <form className="flex flex-wrap items-end gap-3 rounded-[var(--r-md)] border border-[var(--border)] px-2 py-2"
      aria-label={form.id == null ? T.tituloNovo : T.tituloEditar} onSubmit={(e) => { e.preventDefault(); onGravar(); }}>
      <span className="basis-full text-xs font-semibold text-[var(--fg)]">{form.id == null ? T.tituloNovo : T.tituloEditar}</span>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-nome`}>
        {T.nome}
        <input id={`${id}-nome`} className={`${INPUT} w-56`} value={form.nome} maxLength={120} autoFocus
          aria-invalid={inv} aria-describedby={desc} onChange={(e) => mudar({ nome: e.target.value })} />
      </label>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-ab`}>
        {T.abertura}
        <input id={`${id}-ab`} type="date" className={INPUT} value={form.abertura}
          min={somarDiasISO(hojeISO, -31)} max={somarDiasISO(hojeISO, 400)}
          aria-invalid={inv} aria-describedby={desc} onChange={(e) => mudar({ abertura: e.target.value })} />
      </label>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-ref`}>
        {T.eventoRef}
        {erroCandidatos ? (
          <span role="alert" className="text-xs text-[var(--fg-2)]">{T.erroRef}</span>
        ) : candidatosCarregando ? (
          <span role="status" className="text-xs text-[var(--fg-3)]">{T.carregandoRef}</span>
        ) : (
          <select id={`${id}-ref`} className={`${INPUT} max-w-[32ch]`} value={form.evento_ref_id}
            aria-invalid={inv} aria-describedby={`${id}-ref-ajuda${desc ? ` ${desc}` : ''}`}
            onChange={(e) => mudar({ evento_ref_id: e.target.value })}>
            <option value="">{T.selecione}</option>
            {refFora && refAtual && <option value={String(refAtual.id)}>{refAtual.nome}</option>}
            {opcoes.map((f) => (
              <option key={f.evento_id} value={String(f.evento_id)}>
                {f.nome} ({fmtData(f.carrinho_inicio ?? f.inicio)} a {fmtData(f.venda_ate)})
              </option>
            ))}
          </select>
        )}
        <span id={`${id}-ref-ajuda`} className="max-w-[32ch]">{T.eventoRefAjuda}</span>
      </label>
      <fieldset className="flex items-end gap-2">
        <legend className="text-[11px] text-[var(--fg-3)]">{T.tamanho}</legend>
        {([['tamanho_conservador', T.conservador], ['tamanho_base', T.base], ['tamanho_otimista', T.otimista]] as const).map(([k, rot]) => (
          <label key={k} className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-${k}`}>
            {rot}
            <input id={`${id}-${k}`} className={`${INPUT} w-16 text-right tabular`} inputMode="decimal" value={form[k]}
              aria-invalid={inv} aria-describedby={`${id}-tam-ajuda${desc ? ` ${desc}` : ''}`} onChange={(e) => mudar({ [k]: e.target.value })} />
          </label>
        ))}
        <span id={`${id}-tam-ajuda`} className="max-w-[24ch] text-[11px] text-[var(--fg-3)]">{T.tamanhoAjuda}</span>
      </fieldset>
      <label className="flex max-w-[40ch] items-start gap-1.5 text-[11px] text-[var(--fg-2)]" htmlFor={`${id}-pausa`}>
        <input id={`${id}-pausa`} type="checkbox" checked={form.pausa_avulso} aria-describedby={`${id}-pausa-ajuda`}
          onChange={(e) => mudar({ pausa_avulso: e.target.checked })} />
        <span>
          {T.pausaAvulso}
          <span id={`${id}-pausa-ajuda`} className="block text-[var(--fg-3)]">{T.pausaAvulsoAjuda}</span>
        </span>
      </label>
      <label className="flex flex-col gap-0.5 text-[11px] text-[var(--fg-3)]" htmlFor={`${id}-obs`}>
        {T.observacao}
        <input id={`${id}-obs`} className={`${INPUT} w-72`} value={form.observacao} maxLength={500}
          aria-invalid={inv} aria-describedby={desc} onChange={(e) => mudar({ observacao: e.target.value })} />
      </label>
      <span className="flex gap-2">
        <button type="submit" className={BTN_1} disabled={ocupado}>{ocupado ? T.salvando : T.salvar}</button>
        <button type="button" className={BTN} disabled={ocupado} onClick={onCancelar}>{T.cancelar}</button>
      </span>
      {inv && (
        <ul id={idErros} role="alert" className="basis-full text-xs font-semibold text-[var(--red)]">
          {form.erros.map((e) => <li key={e}>{e}</li>)}
        </ul>
      )}
    </form>
  );
}
