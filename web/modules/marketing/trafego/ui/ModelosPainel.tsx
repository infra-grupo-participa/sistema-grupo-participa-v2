'use client';

// Aba "Modelos de lançamento" da Central do Tráfego (migration 20261006l; substitui "Pacotes e checklist"). Cada modelo:
// nome, tipo de lançamento, unidades (com o padrão), fases com datas relativas e % da verba, campanhas esperadas, itens
// do checklist por momento e metas padrão. Os "Exemplo: …" são rascunhos com números genéricos, para editar e validar.
import { useEffect, useMemo, useState } from 'react';
import { Badge, Button, DataTable, EmptyState, FilterSelect, Input, Loading, Modal, SectionCard, Td, Th, Thead, Toggle, Tr } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_AVISO_CADASTRO, type ListasCadastro } from '../domain/cadastro';
import {
  MODELO_VAZIO, MOMENTOS, ROTULO_MOMENTO, ROTULO_REF, somaPct, textoRelativo, validarModelo,
  type Modelo, type ModeloFase, type Momento, type RefData,
} from '../domain/modelos';
import type { ConfigTrafego, Resposta } from '../domain/tipos';
import { ativarModelo, duplicarModelo, listarModelos, salvarModelo } from '../infrastructure/trafego-data';
import { CampoNumero } from './CampoNumero';

type Flash = (msg: string) => void;
const msg = (r: Resposta) => [r.msg, ...(r.avisos ?? []).map((a) => ROTULO_AVISO_CADASTRO[a] ?? a)].join(' ');
const REFS = Object.keys(ROTULO_REF) as RefData[];

function Rotulo({ children }: { children: React.ReactNode }) {
  return <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{children}</span>;
}

function Bloco({ titulo, dica, acao, children }: { titulo: string; dica?: string; acao?: React.ReactNode; children: React.ReactNode }) {
  return (
    <fieldset className="rounded-[var(--r-md)] border border-[var(--border)] p-3">
      <legend className="px-1 text-xs font-semibold text-[var(--fg-2)]">{titulo}</legend>
      <div className="mb-2 flex flex-wrap items-center justify-between gap-2">
        {dica && <p className="text-xs text-[var(--fg-3)]">{dica}</p>}
        {acao}
      </div>
      {children}
    </fieldset>
  );
}

export function ModalModelo({ inicial, listas, config, onFechar, onSalvo }: {
  inicial: Modelo; listas: ListasCadastro; config: ConfigTrafego; onFechar: () => void; onSalvo: (m: string) => void;
}) {
  const [m, setM] = useState<Modelo>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = <K extends keyof Modelo>(k: K, v: Modelo[K]) => setM((x) => ({ ...x, [k]: v }));
  const unidadesValidas = listas.unidades.filter((u) => (listas.regras[u.codigo] ?? []).includes(m.tipo_lancamento));
  const nomeFase = (f: string) => config.fases.find((x) => x.codigo === f)?.nome ?? f;
  const setFase = (i: number, v: Partial<ModeloFase>) => set('fases', m.fases.map((f, j) => (j === i ? { ...f, ...v } : f)));
  const mover = <T,>(xs: T[], i: number, d: number) => { const y = [...xs]; const [a] = y.splice(i, 1); y.splice(i + d, 0, a); return y; };
  const soma = somaPct(m.fases);

  async function salvar() {
    const e = validarModelo(m, listas.regras, listas.objetivos);
    if (e) { setErro(e); return; }
    setSalvando(true);
    const r = await salvarModelo(m);
    setSalvando(false);
    if (!r.ok) { setErro(r.msg); return; }
    onSalvo(msg(r));
  }

  return (
    <Modal onClose={onFechar} title={m.id ? `Editar modelo: ${inicial.nome}` : 'Novo modelo de lançamento'} width="max-w-5xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      <div className="space-y-4">
        {m.rascunho && (
          <p className="rounded-[var(--r-md)] border border-[var(--yellow)] bg-[var(--surface-3)] px-3 py-2 text-xs text-[var(--fg)]">
            <b>Rascunho a validar.</b> Fases, datas e percentuais deste modelo são de exemplo, não são decisão de ninguém. Ajuste e desligue &quot;Rascunho&quot; quando estiver valendo.
          </p>
        )}
        <div className="grid gap-3 sm:grid-cols-3">
          <label className="block sm:col-span-2"><Rotulo>Nome</Rotulo>
            <Input value={m.nome} onChange={(e) => set('nome', e.target.value)} maxLength={80} placeholder="LPSG padrão CSM" autoFocus={!m.id} />
          </label>
          <label className="block"><Rotulo>Tipo de lançamento</Rotulo>
            <FilterSelect value={m.tipo_lancamento} onChange={(e) => setM((x) => ({ ...x, tipo_lancamento: e.target.value,
              unidades: x.unidades.filter((u) => (listas.regras[u.unidade] ?? []).includes(e.target.value)) }))}>
              <option value="">Escolha</option>
              {listas.tipos_lancamento.map((t) => <option key={t.codigo} value={t.codigo}>{t.nome}</option>)}
            </FilterSelect>
          </label>
        </div>
        <div className="flex flex-wrap items-start gap-6">
          <fieldset>
            <legend className="text-xs font-medium text-[var(--fg-2)] mb-1">Unidades <span className="font-normal text-[var(--fg-3)]">· só as que têm este tipo</span></legend>
            {!m.tipo_lancamento ? <p className="text-xs text-[var(--fg-3)]">Escolha o tipo antes.</p> : (
              <div className="flex flex-col gap-1">
                {unidadesValidas.map((u) => {
                  const marcada = m.unidades.find((x) => x.unidade === u.codigo);
                  return (
                    <div key={u.codigo} className="flex items-center gap-3 text-sm text-[var(--fg-2)]">
                      <label className="inline-flex items-center gap-1.5 cursor-pointer">
                        <input type="checkbox" checked={!!marcada} onChange={() => set('unidades', marcada
                          ? m.unidades.filter((x) => x.unidade !== u.codigo) : [...m.unidades, { unidade: u.codigo, padrao: false }])} />
                        {u.nome}
                      </label>
                      {marcada && (
                        <label className="inline-flex items-center gap-1.5 text-xs cursor-pointer" title="O modelo sugerido primeiro para este tipo nesta unidade (tira o padrão de outro modelo)">
                          <input type="checkbox" checked={marcada.padrao} onChange={() => set('unidades', m.unidades.map((x) => (x.unidade === u.codigo ? { ...x, padrao: !x.padrao } : x)))} />
                          padrão
                        </label>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </fieldset>
          <div className="flex flex-col gap-2 pt-5">
            <Toggle checked={m.ativo} onChange={(v) => set('ativo', v)} label="Ativo" />
            <Toggle checked={m.rascunho} onChange={(v) => set('rascunho', v)} label="Rascunho a validar" />
          </div>
          <label className="block w-36"><Rotulo>Meta de CPL (R$)</Rotulo>
            <CampoNumero valor={m.meta_cpl} onValor={(n) => set('meta_cpl', n)} placeholder="opcional" />
          </label>
          <label className="block w-36"><Rotulo>Meta de % MQL</Rotulo>
            <CampoNumero valor={m.meta_pct_mql} onValor={(n) => set('meta_pct_mql', n)} placeholder="opcional" />
          </label>
        </div>

        <Bloco titulo="Fases" dica={`Datas relativas às do projeto (dias negativos = antes). Soma: ${soma.toLocaleString('pt-BR')}% da verba máxima${soma > 100 ? ' (passou de 100)' : ''}.`}
          acao={<Button size="sm" variant="subtle" onClick={() => set('fases', [...m.fases, { fase: '', ordem: m.fases.length + 1, inicio_ref: 'captacao_inicio', inicio_dias: 0, fim_ref: 'captacao_fim', fim_dias: 0, pct_verba: null, obs: null }])}>
            <Icon name="plus" size={12} /> Fase</Button>}>
          {m.fases.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Nenhuma fase.</p> : (
            <div className="space-y-2">
              {m.fases.map((f, i) => (
                <div key={i} className="grid items-end gap-2 sm:grid-cols-[1.2fr_1.6fr_1.6fr_0.6fr_auto]">
                  <label className="block"><Rotulo>Fase</Rotulo>
                    <FilterSelect value={f.fase} onChange={(e) => setFase(i, { fase: e.target.value })}>
                      <option value="">Escolha</option>
                      {config.fases.map((x) => <option key={x.codigo} value={x.codigo}>{x.nome}</option>)}
                    </FilterSelect>
                  </label>
                  {(['inicio', 'fim'] as const).map((k) => (
                    <div key={k}>
                      <Rotulo>{k === 'inicio' ? 'Início' : 'Fim'} <span className="font-normal text-[var(--fg-3)]">· {textoRelativo(f[`${k}_ref`], f[`${k}_dias`])}</span></Rotulo>
                      <div className="flex gap-1">
                        <CampoNumero className="w-16" inteiro aria-label={`Dias do ${k === 'inicio' ? 'início' : 'fim'} (negativo = antes)`} valor={f[`${k}_dias`]}
                          onValor={(n) => setFase(i, { [`${k}_dias`]: n ?? 0 } as Partial<ModeloFase>)} />
                        <FilterSelect value={f[`${k}_ref`] ?? ''} aria-label={`Referência do ${k}`}
                          onChange={(e) => setFase(i, { [`${k}_ref`]: (e.target.value || null) as RefData | null } as Partial<ModeloFase>)}>
                          <option value="">sem data</option>
                          {REFS.map((r) => <option key={r} value={r}>{ROTULO_REF[r]}</option>)}
                        </FilterSelect>
                      </div>
                    </div>
                  ))}
                  <label className="block"><Rotulo>% verba</Rotulo>
                    <CampoNumero valor={f.pct_verba} onValor={(n) => setFase(i, { pct_verba: n })} />
                  </label>
                  <div className="flex gap-1 pb-1">
                    <Button size="sm" variant="ghost" aria-label={`Subir a fase ${nomeFase(f.fase)}`} disabled={i === 0} onClick={() => set('fases', mover(m.fases, i, -1))}><Icon name="arrow-up" size={12} /></Button>
                    <Button size="sm" variant="ghost" aria-label={`Descer a fase ${nomeFase(f.fase)}`} disabled={i === m.fases.length - 1} onClick={() => set('fases', mover(m.fases, i, 1))}><Icon name="arrow-down" size={12} /></Button>
                    <Button size="sm" variant="danger" aria-label={`Tirar a fase ${nomeFase(f.fase)}`} onClick={() => set('fases', m.fases.filter((_, j) => j !== i))}><Icon name="trash" size={12} /></Button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </Bloco>

        <Bloco titulo="Campanhas esperadas" dica="O gerador de nome oferece cada uma; o checklist confere se foi criada (pelo objetivo e, se tiver, pela página)."
          acao={<Button size="sm" variant="subtle" onClick={() => set('campanhas', [...m.campanhas, { objetivo: '', fase: null, descricao: null, pagina: null }])}>
            <Icon name="plus" size={12} /> Campanha</Button>}>
          {m.campanhas.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Nenhuma campanha esperada.</p> : (
            <div className="space-y-2">
              {m.campanhas.map((c, i) => {
                const setC = (v: Partial<typeof c>) => set('campanhas', m.campanhas.map((x, j) => (j === i ? { ...x, ...v } : x)));
                return (
                  <div key={i} className="grid items-end gap-2 sm:grid-cols-[1fr_1fr_2fr_0.7fr_auto]">
                    <label className="block"><Rotulo>Objetivo</Rotulo>
                      <FilterSelect value={c.objetivo} onChange={(e) => setC({ objetivo: e.target.value })}>
                        <option value="">Escolha</option>
                        {listas.objetivos.map((o) => <option key={o} value={o}>{o}</option>)}
                      </FilterSelect>
                    </label>
                    <label className="block"><Rotulo>Fase</Rotulo>
                      <FilterSelect value={c.fase ?? ''} onChange={(e) => setC({ fase: e.target.value || null })}>
                        <option value="">Pelo objetivo</option>
                        {config.fases.map((x) => <option key={x.codigo} value={x.codigo}>{x.nome}</option>)}
                      </FilterSelect>
                    </label>
                    <label className="block"><Rotulo>Descrição sugerida <span className="font-normal text-[var(--fg-3)]">· opcional, partes com |</span></Rotulo>
                      <Input value={c.descricao ?? ''} maxLength={120} onChange={(e) => setC({ descricao: e.target.value.toUpperCase() || null })} placeholder="TEASER | META" />
                    </label>
                    <label className="block"><Rotulo>Página</Rotulo>
                      <Input value={c.pagina ?? ''} maxLength={7} onChange={(e) => setC({ pagina: e.target.value.toLowerCase() || null })} placeholder="ak1" />
                    </label>
                    <Button size="sm" variant="danger" aria-label="Tirar a campanha esperada" className="mb-1" onClick={() => set('campanhas', m.campanhas.filter((_, j) => j !== i))}><Icon name="trash" size={12} /></Button>
                  </div>
                );
              })}
            </div>
          )}
        </Bloco>

        <Bloco titulo="Checklist manual" dica="O que o sistema não confere sozinho. O momento organiza o checklist do projeto (o de antes avisa no resumo do dia durante a captação)."
          acao={<Button size="sm" variant="subtle" onClick={() => set('itens', [...m.itens, { texto: '', momento: 'antes' }])}><Icon name="plus" size={12} /> Item</Button>}>
          {m.itens.length === 0 ? <p className="text-xs text-[var(--fg-3)]">Nenhum item manual.</p> : (
            <div className="space-y-2">
              {m.itens.map((x, i) => (
                <div key={i} className="grid items-end gap-2 sm:grid-cols-[3fr_1.2fr_auto]">
                  <label className="block"><Rotulo>Item</Rotulo>
                    <Input value={x.texto} maxLength={200} onChange={(e) => set('itens', m.itens.map((y, j) => (j === i ? { ...y, texto: e.target.value } : y)))} />
                  </label>
                  <label className="block"><Rotulo>Momento</Rotulo>
                    <FilterSelect value={x.momento} onChange={(e) => set('itens', m.itens.map((y, j) => (j === i ? { ...y, momento: e.target.value as Momento } : y)))}>
                      {MOMENTOS.map((mo) => <option key={mo} value={mo}>{ROTULO_MOMENTO[mo]}</option>)}
                    </FilterSelect>
                  </label>
                  <Button size="sm" variant="danger" aria-label="Tirar o item" className="mb-1" onClick={() => set('itens', m.itens.filter((_, j) => j !== i))}><Icon name="trash" size={12} /></Button>
                </div>
              ))}
            </div>
          )}
        </Bloco>

        <label className="block"><Rotulo>Observação</Rotulo>
          <Input value={m.obs ?? ''} maxLength={1000} onChange={(e) => set('obs', e.target.value || null)} />
        </label>
      </div>
      {erro && <p role="alert" className="mt-3 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

/** A tabela (sem carregar), para testar a renderização. */
export function TabelaModelos({ modelos, listas, config, onEditar, onDuplicar, onAtivar }: {
  modelos: Modelo[]; listas: ListasCadastro; config: ConfigTrafego;
  onEditar: (m: Modelo) => void; onDuplicar: (m: Modelo) => void; onAtivar: (m: Modelo) => void;
}) {
  const unidade = (c: string) => listas.unidades.find((u) => u.codigo === c)?.nome ?? c;
  const fase = (c: string) => config.fases.find((x) => x.codigo === c)?.nome ?? c;
  if (modelos.length === 0) return <EmptyState title="Nenhum modelo neste filtro" hint="Crie um modelo novo ou mude o filtro." />;
  return (
    <DataTable minWidth={980}>
      <Thead><Th>Modelo</Th><Th>Tipo</Th><Th>Unidades</Th><Th>Fases (% da verba)</Th><Th>Campanhas</Th><Th>Checklist</Th><Th>{''}</Th></Thead>
      <tbody>
        {modelos.map((m) => (
          <Tr key={m.id}>
            <Td>
              <div className="font-medium text-[var(--fg)]">{m.nome}</div>
              <div className="mt-0.5 flex flex-wrap gap-1">
                {m.rascunho && <Badge tone="warning">Rascunho a validar</Badge>}
                {!m.ativo && <Badge>Inativo</Badge>}
              </div>
            </Td>
            <Td>{m.tipo_lancamento_nome ?? listas.tipos_lancamento.find((t) => t.codigo === m.tipo_lancamento)?.nome ?? m.tipo_lancamento}</Td>
            <Td>{m.unidades.map((u) => <span key={u.unidade} className="mr-2 whitespace-nowrap">{unidade(u.unidade)}{u.padrao && <b className="text-[var(--accent)]" title="Padrão desta combinação"> ★</b>}</span>)}</Td>
            <Td className="text-xs">{m.fases.length ? m.fases.map((f) => `${fase(f.fase)} ${f.pct_verba ?? '?'}%`).join(' · ') : 'nenhuma'}</Td>
            <Td className="tabular">{m.campanhas.length}</Td>
            <Td className="tabular">{m.itens.length}</Td>
            <Td>
              <div className="flex justify-end gap-1">
                <Button size="sm" variant="subtle" onClick={() => onEditar(m)}><Icon name="pencil" size={12} /> Editar</Button>
                <Button size="sm" variant="ghost" onClick={() => onDuplicar(m)}><Icon name="copy" size={12} /> Duplicar</Button>
                <Button size="sm" variant="ghost" onClick={() => onAtivar(m)}>{m.ativo ? 'Inativar' : 'Ativar'}</Button>
              </div>
            </Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}

export function ModelosPainel({ listas, config, versao, flash, onMudou }: {
  listas: ListasCadastro | null; config: ConfigTrafego; versao: number; flash: Flash; onMudou: () => void;
}) {
  const [modelos, setModelos] = useState<Modelo[] | null | undefined>(undefined);
  const [tipo, setTipo] = useState('');
  const [unidade, setUnidade] = useState('');
  const [inativos, setInativos] = useState(false);
  const [editar, setEditar] = useState<Modelo | null>(null);

  useEffect(() => {
    let vivo = true;
    listarModelos().then((x) => { if (vivo) setModelos(x); });
    return () => { vivo = false; };
  }, [versao]);

  const visiveis = useMemo(() => (modelos ?? []).filter((m) => (inativos || m.ativo) && (!tipo || m.tipo_lancamento === tipo)
    && (!unidade || m.unidades.some((u) => u.unidade === unidade))), [modelos, tipo, unidade, inativos]);

  if (!listas) return <SectionCard title="Modelos de lançamento"><p className="text-sm text-[var(--fg-3)]">Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p></SectionCard>;
  const feito = (r: Resposta) => { flash(msg(r)); if (r.ok) onMudou(); };

  return (
    <SectionCard
      title="Modelos de lançamento"
      subtitle="Fases, datas, verba, campanhas esperadas e checklist de cada tipo de lançamento. No projeto, &quot;Aplicar modelo&quot; preenche o planejamento a partir daqui."
      right={<div className="flex flex-wrap items-center gap-2">
        <FilterSelect value={tipo} onChange={(e) => setTipo(e.target.value)} aria-label="Tipo de lançamento">
          <option value="">Todos os tipos</option>
          {listas.tipos_lancamento.map((t) => <option key={t.codigo} value={t.codigo}>{t.nome}</option>)}
        </FilterSelect>
        <FilterSelect value={unidade} onChange={(e) => setUnidade(e.target.value)} aria-label="Unidade">
          <option value="">Todas as unidades</option>
          {listas.unidades.map((u) => <option key={u.codigo} value={u.codigo}>{u.nome}</option>)}
        </FilterSelect>
        <Toggle checked={inativos} onChange={setInativos} label="Inativos" />
        <Button size="sm" onClick={() => setEditar(MODELO_VAZIO(tipo))}><Icon name="plus" size={14} /> Novo modelo</Button>
      </div>}
    >
      {modelos === undefined ? <Loading /> : modelos === null ? (
        <p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.</p>
      ) : (
        <>
          {modelos.some((m) => m.rascunho) && (
            <p className="mb-3 rounded-[var(--r-md)] border border-[var(--yellow)] bg-[var(--surface-3)] px-3 py-2 text-xs text-[var(--fg)]">
              Os modelos <b>&quot;Exemplo: …&quot;</b> são rascunhos para editar: as fases são da lista que já existe, mas as datas e os percentuais são
              genéricos, de exemplo, não decisão de ninguém. Valide, ajuste e desligue &quot;Rascunho&quot;.
            </p>
          )}
          <TabelaModelos modelos={visiveis} listas={listas} config={config} onEditar={(m) => setEditar(structuredClone(m))}
            onDuplicar={async (m) => feito(await duplicarModelo(m.id))} onAtivar={async (m) => feito(await ativarModelo(m.id, !m.ativo))} />
        </>
      )}
      {editar && <ModalModelo inicial={editar} listas={listas} config={config} onFechar={() => setEditar(null)}
        onSalvo={(t) => { setEditar(null); flash(t); onMudou(); }} />}
    </SectionCard>
  );
}
