'use client';

// Na vida do projeto (migrations 20261006a e 20261006d): o cadastro (tipo, unidade, lançamento, especialista, períodos,
// contas), as campanhas sugeridas pela conta e sigla, o MODELO DE LANÇAMENTO (aplicar com prévia), o checklist de montagem
// agrupado por momento e com o caminho para resolver cada item, e o gerador de nome de campanha e UTM (com as campanhas
// esperadas do modelo). Leitura e gravação pelas funções public.trafego_* (admin/dev).
import { useEffect, useState } from 'react';
import { Badge, Button, ConfirmDialog, CopyField, EmptyState, FilterSelect, Input, Loading, Modal, ProgressBar, Row } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { linhaUtm, montarNomeCampanha, porMomento, type ListasCadastro, type ProjetoCadastro } from '../domain/cadastro';
import {
  MOMENTOS, ROTULO_AVISO_PREVIA, ROTULO_MOMENTO, contarPrevia, type Esperada, type Momento, type PreviaModelo,
} from '../domain/modelos';
import { ROTULO_TIPO, type AcaoChecklist, type Checklist, type ConfigTrafego, type Conta } from '../domain/tipos';
import {
  ajustarCampanha, apagarEsperada, apagarItemProjeto, aplicarModelo, carregarChecklist, marcarItemProjeto, previasDoProjeto, salvarItemProjeto,
} from '../infrastructure/trafego-data';
import { SEM_DADO, dataBR, reais } from './formato';

type Flash = (msg: string) => void;

const periodo = (a: string | null, b: string | null) => (a || b ? `${dataBR(a)} a ${dataBR(b)}` : SEM_DADO);

/** Resumo do cadastro, o modelo aplicado e as sugestões de campanha. */
export function CadastroResumo({ cad, listas, contas, flash, onMudou, onAplicarModelo }: {
  cad: ProjetoCadastro; listas: ListasCadastro; contas: Conta[]; flash: Flash; onMudou: () => void; onAplicarModelo: () => void;
}) {
  const unidade = listas.unidades.find((u) => u.codigo === cad.unidade);
  const lanc = listas.tipos_lancamento.find((t) => t.codigo === cad.tipo_lancamento);
  const nomesContas = cad.contas.map((id) => contas.find((c) => c.id === id)?.nome ?? `conta ${id}`);

  async function ligar(id: number) {
    const r = await ajustarCampanha({ id, projeto_id: cad.id });
    flash(r.msg);
    if (r.ok) onMudou();
  }

  return (
    <div className="space-y-3">
      <div className="grid gap-x-6 sm:grid-cols-2">
        <Row k="Tipo e unidade" v={cad.tipo ? `${ROTULO_TIPO[cad.tipo]} · ${unidade?.nome ?? 'unidade não marcada'}` : 'Não marcado'} />
        <Row k="Tipo de lançamento" v={lanc?.nome ?? 'Não definido'} />
        <Row k="Especialista" v={cad.especialista_nome ?? 'Não definido'} />
        <Row k="Etiqueta do ClickUp" v={cad.etiqueta_clickup ? <span className="font-mono text-xs">{cad.etiqueta_clickup}</span> : 'Sem etiqueta'} />
        <Row k="Captação" v={periodo(cad.captacao_inicio, cad.captacao_fim)} />
        <Row k="Evento" v={periodo(cad.evento_inicio, cad.evento_fim)} />
        <Row k="Contas de anúncio" v={nomesContas.length ? nomesContas.join(', ') : 'Nenhuma ligada'} />
        <Row k="Modelo de lançamento" v={
          <span className="inline-flex flex-wrap items-center gap-2">
            {cad.modelo ? cad.modelo.nome : 'nenhum aplicado'}
            <Button size="sm" variant="subtle" onClick={onAplicarModelo} disabled={!cad.tipo_lancamento || !cad.unidade}
              title={!cad.tipo_lancamento || !cad.unidade ? 'Marque a unidade e o tipo de lançamento do projeto antes' : undefined}>
              {cad.modelo ? 'Aplicar de novo ou outro' : 'Aplicar modelo'}{cad.modelos_disponiveis ? ` (${cad.modelos_disponiveis})` : ''}
            </Button>
          </span>} />
      </div>
      {cad.sugestoes.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Campanhas sugeridas (conta do projeto, sigla no nome, sem projeto)</div>
          <ul className="mt-1 divide-y divide-[var(--border)]">
            {cad.sugestoes.map((s) => (
              <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 py-1.5">
                <span><span className="font-mono text-xs break-all">{s.nome}</span> <span className="text-xs text-[var(--fg-3)]">· {s.conta}</span></span>
                <Button size="sm" variant="subtle" onClick={() => void ligar(s.id)}>Ligar ao projeto</Button>
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

/** A prévia de um modelo (sem carregar), para testar a renderização. */
export function PreviaVista({ p, objetivoFase }: { p: PreviaModelo; objetivoFase?: (f: string | null) => string }) {
  const n = contarPrevia(p);
  const nomeFase = objetivoFase ?? ((f: string | null) => f ?? 'pelo objetivo');
  return (
    <div className="space-y-3 text-sm">
      {p.modelo.rascunho && <p className="text-xs text-[var(--yellow)]">Rascunho a validar: datas e percentuais de exemplo.</p>}
      {p.avisos.map((a) => <p key={a} className="text-xs text-[var(--fg-3)]">{ROTULO_AVISO_PREVIA[a] ?? a}</p>)}
      <div>
        <div className="text-xs font-semibold text-[var(--fg-2)]">Fases ({n.novas} nova(s), {n.mudam} mudaria(m) só confirmando, {n.iguais} igual(is)) · verba máxima {reais(p.verba_maxima)}</div>
        <table className="mt-1 w-full text-xs">
          <thead><tr className="text-left text-[var(--fg-3)]"><th className="py-1">Fase</th><th>Período</th><th>Verba</th><th>No projeto</th></tr></thead>
          <tbody>
            {p.fases.map((f) => (
              <tr key={f.fase} className="border-t border-[var(--border)]">
                <td className="py-1">{f.nome} <span className="text-[var(--fg-3)]">{f.pct_verba != null ? `${f.pct_verba}%` : ''}</span></td>
                <td>{f.inicio || f.fim ? `${dataBR(f.inicio)} a ${dataBR(f.fim)}` : <span className="text-[var(--fg-3)]">{f.aviso === 'datas_invertidas' ? 'datas invertidas' : 'sem data'}</span>}</td>
                <td className="tabular">{reais(f.verba)}</td>
                <td>{!f.existe ? <Badge tone="success">nova</Badge> : f.muda
                  ? <span className="text-[var(--yellow)]">hoje {reais(f.atual?.verba ?? null)}, {dataBR(f.atual?.inicio ?? null) || 'sem início'} a {dataBR(f.atual?.fim ?? null) || 'sem fim'}</span>
                  : <span className="text-[var(--fg-3)]">igual</span>}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
      {p.campanhas.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Campanhas esperadas ({n.campanhas} nova(s))</div>
          <ul className="mt-1 flex flex-wrap gap-1.5">
            {p.campanhas.map((c, i) => (
              <li key={i} className={`rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs ${c.ja_existe ? 'text-[var(--fg-3)]' : 'text-[var(--fg)]'}`}>
                {c.objetivo}{c.descricao ? ` · ${c.descricao}` : ''}{c.pagina ? ` · ${c.pagina.toUpperCase()}` : ''} <span className="text-[var(--fg-3)]">({nomeFase(c.fase)}{c.ja_existe ? ', já no projeto' : ''})</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      {p.itens.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Checklist ({n.itens} item(ns) novo(s))</div>
          <ul className="mt-1 list-disc pl-5 text-xs">
            {p.itens.map((x, i) => <li key={i} className={x.ja_existe ? 'text-[var(--fg-3)]' : ''}>{x.texto} <span className="text-[var(--fg-3)]">({ROTULO_MOMENTO[x.momento].toLowerCase()}{x.ja_existe ? ', já no projeto' : ''})</span></li>)}
          </ul>
        </div>
      )}
      {(p.metas.meta_cpl != null || p.metas.meta_pct_mql != null) && (
        <p className="text-xs text-[var(--fg-2)]">Metas do modelo: CPL {reais(p.metas.meta_cpl)} · % MQL {p.metas.meta_pct_mql ?? SEM_DADO}. Só preenchem onde o projeto não tem meta (ou confirmando).</p>
      )}
    </div>
  );
}

/** "Aplicar modelo": lista os modelos do tipo + unidade do projeto (padrão primeiro), mostra a prévia e aplica. */
export function ModalAplicarModelo({ projetoId, config, onFechar, onAplicado }: {
  projetoId: number; config: ConfigTrafego; onFechar: () => void; onAplicado: (m: string) => void;
}) {
  const [previas, setPrevias] = useState<PreviaModelo[] | null | undefined>(undefined);
  const [escolhido, setEscolhido] = useState<number | null>(null);
  const [substituir, setSubstituir] = useState(false);
  const [confirmar, setConfirmar] = useState(false);
  const [aplicando, setAplicando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  useEffect(() => {
    let vivo = true;
    previasDoProjeto(projetoId).then((x) => { if (vivo) { setPrevias(x); setEscolhido(x?.[0]?.modelo.id ?? null); } });
    return () => { vivo = false; };
  }, [projetoId]);

  const p = previas?.find((x) => x.modelo.id === escolhido) ?? null;
  const mudam = p ? contarPrevia(p).mudam : 0;
  const fase = (f: string | null) => (f ? config.fases.find((x) => x.codigo === f)?.nome ?? f : 'pelo objetivo');

  async function aplicar() {
    if (!p) return;
    setAplicando(true);
    const r = await aplicarModelo(projetoId, p.modelo.id, substituir);
    setAplicando(false);
    setConfirmar(false);
    if (!r.ok) { setErro(r.msg); return; }
    onAplicado(r.msg);
  }

  return (
    <Modal onClose={onFechar} title="Aplicar modelo de lançamento" width="max-w-3xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" disabled={!p || !p.pode_aplicar || aplicando} onClick={() => (substituir && mudam > 0 ? setConfirmar(true) : void aplicar())}>
        {aplicando ? 'Aplicando…' : 'Aplicar'}
      </Button>
    </>}>
      {previas === undefined ? <Loading /> : previas === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (sem acesso, ou a migration 20261006d ainda não foi aplicada).</p>
      ) : previas.length === 0 ? (
        <EmptyState title="Nenhum modelo ativo para este tipo de lançamento e unidade" hint="Crie ou ative um na aba Modelos de lançamento." />
      ) : (
        <div className="space-y-4">
          <fieldset>
            <legend className="text-xs font-medium text-[var(--fg-2)] mb-1">Modelo</legend>
            <div className="flex flex-col gap-1">
              {previas.map((x) => (
                <label key={x.modelo.id} className="inline-flex items-center gap-2 text-sm text-[var(--fg-2)] cursor-pointer">
                  <input type="radio" name="modelo" checked={escolhido === x.modelo.id} onChange={() => setEscolhido(x.modelo.id)} />
                  {x.modelo.nome}
                  {x.padrao && <Badge tone="accent">padrão</Badge>}
                  {x.modelo.rascunho && <Badge tone="warning">rascunho</Badge>}
                </label>
              ))}
            </div>
          </fieldset>
          {p && <PreviaVista p={p} objetivoFase={fase} />}
          {p && mudam > 0 && (
            <label className="flex items-start gap-2 text-sm text-[var(--fg-2)] cursor-pointer">
              <input type="checkbox" className="mt-1" checked={substituir} onChange={(e) => setSubstituir(e.target.checked)} />
              <span>Substituir também as {mudam} fase(s) que já existem e ficariam diferentes (verba e datas do modelo). Sem marcar, elas ficam como estão.</span>
            </label>
          )}
          <p className="text-xs text-[var(--fg-3)]">Aplicar só acrescenta: nada do projeto é apagado. Campanhas esperadas e itens que já existem não se repetem.</p>
          {erro && <p role="alert" className="text-sm text-[var(--red)]">{erro}</p>}
        </div>
      )}
      {confirmar && p && (
        <ConfirmDialog title="Substituir fases" danger confirmLabel="Substituir e aplicar"
          message={`${mudam} fase(s) do projeto vão receber a verba e as datas do modelo ${p.modelo.nome}. O que foi editado à mão nelas será trocado.`}
          onCancel={() => setConfirmar(false)} onConfirm={() => void aplicar()} />
      )}
    </Modal>
  );
}

const ROTULO_ACAO: Record<AcaoChecklist, string> = {
  projeto: 'Editar projeto', paginas: 'Cadastrar páginas', hotmart: 'Ligar produto', modelo: 'Aplicar modelo', planejamento: 'Editar planejamento',
  fases: 'Ver fases', gerador: 'Gerar nome', campanhas: 'Ver campanhas',
};

/** O checklist em si (sem carregar), agrupado por momento, com o caminho para resolver cada item pendente. */
export function ChecklistVista({ c, onMarcar, onAcao, onNovoItem, onApagarItem }: {
  c: Checklist | null; onMarcar?: (item: number, feito: boolean) => void; onAcao?: (a: AcaoChecklist) => void;
  onNovoItem?: (texto: string, momento: Momento) => void; onApagarItem?: (item: number) => void;
}) {
  const [texto, setTexto] = useState('');
  const [momento, setMomento] = useState<Momento>('antes');
  if (c === null) return <p className="text-sm text-[var(--fg-3)]">Indisponível (sem acesso, ou a migration 20261006a ainda não foi aplicada).</p>;
  const pct = c.total ? Math.round((c.feitos / c.total) * 1000) / 10 : 0;
  const bola = (ok: boolean, aplica: boolean) => (
    <span className={`mt-0.5 inline-grid w-5 h-5 shrink-0 place-items-center rounded-full ${!aplica ? 'bg-[var(--surface-3)] text-[var(--fg-3)]' : ok ? 'bg-[var(--green)] text-black' : 'border border-[var(--border)] text-[var(--fg-3)]'}`}>
      {aplica && ok ? <Icon name="check" size={12} /> : null}
    </span>
  );
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="text-sm font-semibold text-[var(--fg)] tabular">{c.feitos} de {c.total} prontos</div>
        <div className="w-40"><ProgressBar value={pct} tone={c.feitos === c.total ? 'green' : 'accent'} ariaLabel={`${c.feitos} de ${c.total} itens prontos`} /></div>
        {c.modelo ? <span className="text-xs text-[var(--fg-3)]">Modelo: {c.modelo.nome}</span> : <span className="text-xs text-[var(--fg-3)]">Sem modelo aplicado</span>}
      </div>
      <div className="grid gap-4 lg:grid-cols-3">
        {porMomento(c).map(({ momento: m, itens }) => (
          <div key={m}>
            <div className="text-xs font-semibold text-[var(--fg-2)]">{ROTULO_MOMENTO[m]}</div>
            {itens.length === 0 ? <p className="mt-1 text-xs text-[var(--fg-3)]">Nada aqui.</p> : (
              <ul className="mt-1 space-y-1.5">
                {itens.map((i) => (
                  <li key={i.codigo ?? `m${i.id}`} className="flex items-start gap-2 text-sm">
                    {i.codigo ? bola(i.ok, i.aplica) : (
                      <input type="checkbox" className="mt-1" checked={i.ok} disabled={!onMarcar} aria-label={i.texto} onChange={(e) => onMarcar?.(i.id!, e.target.checked)} />
                    )}
                    <div className="min-w-0 flex-1">
                      <span className={i.aplica ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}>
                        {i.texto}{!i.aplica ? ' (não se aplica)' : i.detalhe ? ` · ${i.detalhe}` : ''}
                        {!i.codigo && <span className="text-[11px] text-[var(--fg-3)]"> {i.do_modelo ? '(do modelo)' : '(à mão)'}</span>}
                      </span>
                      {i.codigo && i.aplica && !i.ok && i.acao && onAcao && (
                        <div><Button size="sm" variant="link" onClick={() => onAcao(i.acao!)}>{ROTULO_ACAO[i.acao]} <Icon name="arrow-right" size={12} /></Button></div>
                      )}
                      {!i.codigo && i.ok && <div className="text-[11px] text-[var(--fg-3)]">Marcado por {i.marcado_por ?? 'sem nome'} em {dataBR(i.marcado_em ?? null)}</div>}
                    </div>
                    {!i.codigo && onApagarItem && (
                      <Button size="sm" variant="ghost" aria-label={`Tirar "${i.texto}" do projeto`} onClick={() => onApagarItem(i.id!)}><Icon name="trash" size={12} /></Button>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </div>
        ))}
      </div>
      {c.esperadas && c.esperadas.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Campanhas esperadas</div>
          <ul className="mt-1 flex flex-wrap gap-1.5">
            {c.esperadas.map((e) => (
              <li key={e.id} className="inline-flex items-center gap-1 rounded-[var(--r-sm)] border border-[var(--border)] px-2 py-0.5 text-xs">
                {e.criada ? <Icon name="check" size={12} /> : <Icon name="circle" size={10} />}
                {e.objetivo}{e.descricao ? ` · ${e.descricao}` : ''}{e.pagina ? ` · ${e.pagina.toUpperCase()}` : ''}
              </li>
            ))}
          </ul>
        </div>
      )}
      {onNovoItem && (
        <form className="flex flex-wrap items-end gap-2" onSubmit={(e) => { e.preventDefault(); if (texto.trim()) { onNovoItem(texto.trim(), momento); setTexto(''); } }}>
          <label className="block min-w-[16rem] flex-1"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Item manual novo (só deste projeto)</span>
            <Input value={texto} maxLength={200} onChange={(e) => setTexto(e.target.value)} placeholder="Ex.: pixel conferido na página" />
          </label>
          <FilterSelect value={momento} onChange={(e) => setMomento(e.target.value as Momento)} aria-label="Momento do item">
            {MOMENTOS.map((m) => <option key={m} value={m}>{ROTULO_MOMENTO[m]}</option>)}
          </FilterSelect>
          <Button size="sm" variant="subtle" type="submit" disabled={!texto.trim()}><Icon name="plus" size={12} /> Item</Button>
        </form>
      )}
    </div>
  );
}

export function ChecklistPainel({ projetoId, versao, flash, onMudou, onAcao }: {
  projetoId: number; versao: number; flash: Flash; onMudou: () => void; onAcao?: (a: AcaoChecklist) => void;
}) {
  const [c, setC] = useState<Checklist | null | undefined>(undefined);
  const [n, setN] = useState(0);
  const [apagar, setApagar] = useState<number | null>(null);
  useEffect(() => {
    let vivo = true;
    carregarChecklist(projetoId).then((x) => { if (vivo) setC(x); });
    return () => { vivo = false; };
  }, [projetoId, versao, n]);
  if (c === undefined) return null;
  const feito = (r: { ok: boolean; msg: string }) => { flash(r.msg); if (r.ok) { setN((x) => x + 1); onMudou(); } };
  return (
    <>
      <ChecklistVista c={c} onAcao={onAcao}
        onMarcar={async (item, ok) => feito(await marcarItemProjeto(item, ok))}
        onNovoItem={async (texto, momento) => feito(await salvarItemProjeto({ projeto_id: projetoId, texto, momento }))}
        onApagarItem={(item) => setApagar(item)} />
      {apagar != null && (
        <ConfirmDialog title="Tirar item" danger confirmLabel="Tirar" message="Tirar este item do checklist deste projeto? O modelo não muda."
          onCancel={() => setApagar(null)} onConfirm={async () => { const id = apagar; setApagar(null); feito(await apagarItemProjeto(id)); }} />
      )}
    </>
  );
}

/** Gerador do nome de campanha no padrão e da linha de UTM do Meta, com botão de copiar e as campanhas esperadas do modelo. */
export function GeradorCampanha({ sigla, listas, config, paginas, gestoresProjeto, esperadas = [], flash, onMudou }: {
  sigla: string; listas: ListasCadastro; config: ConfigTrafego; paginas: { codigo: string; nome: string }[]; gestoresProjeto: string[];
  esperadas?: Esperada[]; flash?: Flash; onMudou?: () => void;
}) {
  const [gestor, setGestor] = useState(gestoresProjeto[0] ?? '');
  const [objetivo, setObjetivo] = useState('');
  const [descricao, setDescricao] = useState('');
  const [pagina, setPagina] = useState('');
  const r = montarNomeCampanha({ gestor, sigla, objetivo, descricao, pagina },
    { gestores: config.gestores.map((g) => g.sigla), objetivos: listas.objetivos });
  const utm = listas.utm.meta ?? [];
  const pronto = gestor && objetivo && descricao.trim();
  const usar = (e: Esperada) => { setObjetivo(e.objetivo); setDescricao(e.descricao ?? ''); setPagina(e.pagina && paginas.some((p) => p.codigo === e.pagina) ? e.pagina : ''); };

  return (
    <div className="space-y-3">
      {esperadas.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-[var(--fg-2)]">Campanhas esperadas do modelo · clique para preencher</div>
          <ul className="mt-1 flex flex-wrap gap-1.5">
            {esperadas.map((e) => (
              <li key={e.id} className="inline-flex items-center gap-1">
                <Button size="sm" variant={e.criada ? 'ghost' : 'subtle'} onClick={() => usar(e)}>
                  {e.criada && <Icon name="check" size={12} />}{e.objetivo}{e.descricao ? ` · ${e.descricao}` : ''}{e.pagina ? ` · ${e.pagina.toUpperCase()}` : ''}
                </Button>
                {flash && onMudou && (
                  <Button size="sm" variant="ghost" aria-label={`Tirar a campanha esperada ${e.objetivo}`}
                    onClick={async () => { const x = await apagarEsperada(e.id); flash(x.msg); if (x.ok) onMudou(); }}><Icon name="x" size={12} /></Button>
                )}
              </li>
            ))}
          </ul>
        </div>
      )}
      <div className="grid gap-3 sm:grid-cols-4">
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Gestor</span>
          <FilterSelect value={gestor} onChange={(e) => setGestor(e.target.value)}>
            <option value="">Escolha</option>
            {config.gestores.map((g) => <option key={g.sigla} value={g.sigla}>{g.sigla} · {g.nome}</option>)}
          </FilterSelect>
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Objetivo</span>
          <FilterSelect value={objetivo} onChange={(e) => setObjetivo(e.target.value)}>
            <option value="">Escolha</option>
            {listas.objetivos.map((o) => <option key={o} value={o}>{o}</option>)}
          </FilterSelect>
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Descrição <span className="font-normal text-[var(--fg-3)]">· livre; partes separadas por |</span></span>
          <Input value={descricao} onChange={(e) => setDescricao(e.target.value.toUpperCase())} maxLength={160} placeholder="TEASER | META | PQ | ABO" />
        </label>
        <label className="block"><span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Página (só teste de página)</span>
          <FilterSelect value={pagina} onChange={(e) => setPagina(e.target.value)}>
            <option value="">Nenhuma</option>
            {paginas.map((p) => <option key={p.codigo} value={p.codigo}>{p.codigo.toUpperCase()} · {p.nome}</option>)}
          </FilterSelect>
        </label>
      </div>
      {pronto && r.erros.length > 0 && <p role="alert" className="text-sm text-[var(--red)]">{r.erros.join(' ')}</p>}
      {pronto && r.nome && <CopyField label="Nome da campanha" value={r.nome} />}
      {utm.length > 0 ? (
        <div>
          <CopyField label="Parâmetros de URL (Meta)" value={linhaUtm(utm)} />
          <p className="mt-1 text-xs text-[var(--fg-3)]">
            Colar no campo &quot;Parâmetros de URL&quot; do anúncio. O Meta troca as macros pelo nome e id da campanha, do conjunto e do anúncio e pelo
            posicionamento (padrão do gp-operacoes). O sistema cruza pelo id.
          </p>
        </div>
      ) : <EmptyState title="Sem parâmetros de UTM cadastrados" hint="mkt_trafego.utm_parametros (migration 20261006a)." />}
    </div>
  );
}

/** Progresso do checklist na tabela da Central. */
export function ProgressoMontagem({ feitos, total }: { feitos: number | null | undefined; total: number | null | undefined }) {
  if (feitos == null || !total) return <span className="text-xs text-[var(--fg-3)]">{SEM_DADO}</span>;
  return <Badge tone={feitos === total ? 'success' : 'neutral'}>{feitos}/{total}</Badge>;
}
