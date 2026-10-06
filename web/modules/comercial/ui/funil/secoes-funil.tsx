'use client';

// Seções do funil, usadas pelo editor por abas (funil existente) e pelo assistente passo a passo (funil novo):
// Geral (nome, ícone, agrupador, produto, entrada), Etapas, Campanhas e Distribuição.
// O estado mora em quem usa; aqui só desenha e devolve mudanças.
import { useRef, useState } from 'react';
import { Badge, Button, FilterSelect, Input, MultiSelect, Toggle } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ORIGENS_HOTMART, PRODUTOS, ROTULO_CAMPO, ROTULO_ORIGEM } from '../../domain/catalogo';
import {
  AJUDA_PAPEL, COR_ETAPA, CORES_ETAPA, ROTULO_PAPEL, etapasPadrao, fmtMinutos, podeRemoverEtapa,
  type ProblemaFunil,
} from '../../domain/funis';
import { chaveProjeto } from '../../domain/modelos';
import type {
  Agrupador, CampoKey, Campanha, CanalCampanha, CorEtapa, EtapaFunil, EtapaKey, Funil, Negocio, ProdutoKey, Vendedor,
} from '../../domain/types';
import { Aviso } from '../comum';
import { ICONES_FUNIL, integracoesDoFunil } from './assistente';

export const CANAIS: { value: CanalCampanha; label: string; dica: string }[] = [
  { value: 'utm', label: 'UTM / anúncio', dica: 'utm_campaign = chave-do-projeto' },
  { value: 'formulario', label: 'Formulário', dica: 'Qual formulário ou pesquisa' },
  { value: 'disparo', label: 'Disparo', dica: 'Código da ficha de disparo (ex.: HM-REC-*)' },
  { value: 'hotmart', label: 'Evento Hotmart', dica: 'Qual evento do checkout' },
  { value: 'webhook', label: 'Webhook', dica: 'Página ou sistema que envia' },
  { value: 'manual', label: 'Manual / lista', dica: 'De onde vem a lista' },
];

const PAPEIS = Object.keys(ROTULO_PAPEL) as EtapaKey[];

/** Nome da cor em português (leitor de tela e title). */
const ROTULO_COR: Record<CorEtapa, string> = {
  info: 'Azul', cyan: 'Ciano', purple: 'Roxo', accent: 'Âmbar', yellow: 'Amarelo', green: 'Verde', red: 'Vermelho', neutral: 'Cinza',
};

const CAMPOS: CampoKey[] = ['perfil_profissional', 'atua_com_holding', 'produto_interesse', 'objecao_principal', 'forma_pagamento'];

/** Campos de validação de cada seção (avisos no topo e contagem nas abas). */
export const CAMPOS_GERAL = ['nome', 'agrupador', 'eventos'];

let seqLocal = 0;
export const idLocal = (p: string) => `${p}-tmp-${Date.now().toString(36)}-${++seqLocal}`;

export function funilVazio(agrupador: Agrupador | undefined): Funil {
  return {
    id: '', nome: '', icone: 'kanban', projeto: null, agrupadorId: agrupador?.id ?? '', produto: agrupador?.produto ?? 'hm', tipo: 'manual',
    eventosHotmart: [], etapas: etapasPadrao(idLocal('e')), campanhas: [], distribuicao: null, ativo: true, criadoEm: '',
  };
}

/** Etapas abertas (expandidas) no editor de etapas. */
export function useEtapasAbertas() {
  const [abertas, setAbertas] = useState<Set<string>>(() => new Set());
  const alternar = (id: string, abrir?: boolean) => setAbertas((s) => {
    const n = new Set(s);
    if (abrir ?? !n.has(id)) n.add(id); else n.delete(id);
    return n;
  });
  return { abertas, alternar };
}

/** Põe o foco no campo do problema (depois que a seção certa estiver na tela); abre a etapa citada ("Nome": …). */
export function focarProblema(p: ProblemaFunil, f: Funil, abrirEtapa: (id: string) => void) {
  let alvo = `funil-${p.campo}`;
  if (p.campo === 'etapas') {
    const citada = /^"(.+?)"/.exec(p.msg)?.[1];
    const etapa = f.etapas.find((e) => e.nome === citada) ?? f.etapas.find((e) => !e.nome.trim());
    if (etapa) { abrirEtapa(etapa.id); alvo = `etapa-nome-${etapa.id}`; } else alvo = '';
  }
  if (alvo) setTimeout(() => document.getElementById(alvo)?.focus(), 50);
}

export function CampoFunil({ rotulo, dica, className = '', htmlFor, grupo, children }: {
  rotulo: string; dica?: string; className?: string; htmlFor?: string; grupo?: boolean; children: React.ReactNode;
}) {
  // Grupo de botões não vai dentro de <label> (o clique no rótulo acionaria o primeiro botão).
  const Raiz = grupo ? 'div' : 'label';
  return (
    <Raiz className={`block ${className}`} {...(!grupo && htmlFor ? { htmlFor } : {})}>
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">{rotulo}</span>
      {children}
      {dica && <span className="block mt-1 text-[11px] text-[var(--fg-3)]">{dica}</span>}
    </Raiz>
  );
}

/** Problemas que impedem salvar, no topo da seção, cada um com atalho para o campo. */
export function ProblemasDaSecao({ problemas, irPara, verbo = 'salvar' }: { problemas: ProblemaFunil[]; irPara: (p: ProblemaFunil) => void; verbo?: string }) {
  if (!problemas.length) return null;
  return (
    <Aviso tom="warning">
      <div className="font-medium text-[var(--fg)]">{problemas.length === 1 ? `Falta 1 coisa para ${verbo}` : `Faltam ${problemas.length} coisas para ${verbo}`}</div>
      <ul className="mt-1 space-y-0.5">
        {problemas.map((p) => (
          <li key={p.msg} className="flex flex-wrap items-baseline gap-x-2 text-xs">
            <span>{p.msg}</span>
            <button type="button" onClick={() => irPara(p)} className="font-medium text-[var(--fg)] underline underline-offset-2 hover:no-underline">Ir para</button>
          </li>
        ))}
      </ul>
    </Aviso>
  );
}

// ── Geral ──

export function SecaoGeral({ f, set, agrupadores, novoAgrupador, setNovoAgrupador, problemas, irPara, projeto, autoFoco = true }: {
  f: Funil;
  set: (p: Partial<Funil>) => void;
  agrupadores: Agrupador[];
  novoAgrupador: string | null;
  setNovoAgrupador: (v: string | null) => void;
  /** Problemas desta seção (vazio enquanto não for hora de mostrar). */
  problemas: ProblemaFunil[];
  irPara: (p: ProblemaFunil) => void;
  /** Campo opcional "Chave do projeto" (assistente): vira utm_campaign nas campanhas. */
  projeto?: { valor: string; onChange: (v: string) => void };
  autoFoco?: boolean;
}) {
  const chave = projeto ? chaveProjeto(projeto.valor) : '';
  return (
    <div className="space-y-4 max-w-3xl">
      <ProblemasDaSecao problemas={problemas} irPara={irPara} />
      <div className="grid gap-4 md:grid-cols-2">
        <CampoFunil rotulo="Nome do funil" htmlFor="funil-nome">
          <Input id="funil-nome" autoFocus={autoFoco} value={f.nome} placeholder="Ex.: Venda ativa, Recuperação Imersão, Sessão de Viabilidade" onChange={(e) => set({ nome: e.target.value })} />
        </CampoFunil>
        <CampoFunil rotulo="Agrupador" dica="A pasta onde o funil aparece (normalmente o produto).">
          {novoAgrupador === null ? (
            <div className="flex gap-2">
              <FilterSelect id="funil-agrupador" aria-label="Agrupador" value={f.agrupadorId} onChange={(e) => set({ agrupadorId: e.target.value })} className="flex-1">
                <option value="">Escolha…</option>
                {agrupadores.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}
              </FilterSelect>
              <Button size="sm" variant="ghost" onClick={() => { setNovoAgrupador(''); set({ agrupadorId: 'novo' }); }}><Icon name="plus" size={13} /> Novo</Button>
            </div>
          ) : (
            <div className="flex gap-2">
              <Input id="funil-agrupador" aria-label="Nome do agrupador novo" autoFocus value={novoAgrupador} placeholder="Nome do agrupador novo" onChange={(e) => setNovoAgrupador(e.target.value)} />
              <Button size="sm" variant="ghost" onClick={() => { setNovoAgrupador(null); set({ agrupadorId: '' }); }}>Cancelar</Button>
            </div>
          )}
        </CampoFunil>
        <CampoFunil rotulo="Produto" dica="Valor do negócio e regras de supressão (já comprou) vêm do produto.">
          <FilterSelect value={f.produto} onChange={(e) => set({ produto: e.target.value as ProdutoKey })}>
            {PRODUTOS.map((p) => <option key={p.key} value={p.key}>{p.nome} · escada {p.escada}</option>)}
          </FilterSelect>
        </CampoFunil>
        {projeto && (
          <CampoFunil rotulo="Chave do projeto (opcional)" htmlFor="funil-projeto"
            dica={chave ? `Vira utm_campaign = ${chave} nas campanhas.` : 'A mesma chave do ClickUp, do Drive e do utm_campaign (ex.: ht34-meteorico-out26).'}>
            <Input id="funil-projeto" value={projeto.valor} placeholder="Ex.: HT34 meteórico out26" onChange={(e) => projeto.onChange(e.target.value)} />
          </CampoFunil>
        )}
        <CampoFunil rotulo="Como o negócio entra" grupo className={projeto ? 'md:col-span-2' : ''}>
          <div role="radiogroup" aria-label="Como o negócio entra" className="grid grid-cols-2 gap-2">
            {([['manual', 'Manual', 'O comercial cria ou recebe por campanha (Venda ativa).'], ['hotmart', 'Automático Hotmart', 'Nasce sozinho de eventos do checkout.']] as const).map(([k, l, d]) => (
              <button key={k} type="button" role="radio" aria-checked={f.tipo === k} onClick={() => set({ tipo: k })}
                onKeyDown={(e) => { if (['ArrowLeft', 'ArrowRight', 'ArrowUp', 'ArrowDown'].includes(e.key)) { e.preventDefault(); set({ tipo: k === 'manual' ? 'hotmart' : 'manual' }); (e.currentTarget.parentElement?.querySelector(`[aria-checked="false"]`) as HTMLElement | null)?.focus(); } }}
                tabIndex={f.tipo === k ? 0 : -1}
                className={`text-left rounded-[var(--r-md)] border px-3 py-2 transition-colors ${f.tipo === k ? 'border-[var(--border-accent)] bg-[var(--surface-4)]' : 'border-[var(--border)] hover:bg-[var(--surface-3)]'}`}>
                <div className={`text-sm text-[var(--fg)] ${f.tipo === k ? 'font-semibold' : 'font-medium'}`}>{l}</div>
                <div className="text-[11px] text-[var(--fg-3)] leading-snug">{d}</div>
              </button>
            ))}
          </div>
        </CampoFunil>
        {f.tipo === 'hotmart' && (
          <CampoFunil rotulo="Eventos da Hotmart que criam negócio aqui" className="md:col-span-2" grupo>
            <div id="funil-eventos" tabIndex={-1} className="flex flex-wrap gap-2">
              {ORIGENS_HOTMART.map((o) => {
                const on = f.eventosHotmart.includes(o);
                return (
                  <button key={o} type="button" aria-pressed={on} onClick={() => set({ eventosHotmart: on ? f.eventosHotmart.filter((x) => x !== o) : [...f.eventosHotmart, o] })}
                    className={`inline-flex items-center gap-1.5 min-h-8 rounded-[var(--r-pill)] border px-3 text-xs transition-colors ${on ? 'border-[var(--border-accent)] bg-[var(--surface-4)] text-[var(--fg)] font-semibold' : 'border-[var(--border)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]'}`}>
                    {on && <Icon name="check" size={12} />}{ROTULO_ORIGEM[o]}
                  </button>
                );
              })}
            </div>
          </CampoFunil>
        )}
        <CampoFunil rotulo="Ícone" grupo className="md:col-span-2" dica="Aparece na lista de funis e no título do funil.">
          <SeletorIcone valor={f.icone} onChange={(icone) => set({ icone })} />
        </CampoFunil>
      </div>
    </div>
  );
}

/** Ícone do funil: radiogroup em grade, setas navegam; alvo de 36px. */
export function SeletorIcone({ valor, onChange }: { valor: string; onChange: (nome: string) => void }) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const atual = Math.max(0, ICONES_FUNIL.findIndex((i) => i.nome === valor));
  const onKeyDown = (ev: React.KeyboardEvent, i: number) => {
    const d = ev.key === 'ArrowRight' || ev.key === 'ArrowDown' ? 1 : ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? -1 : 0;
    if (!d) return;
    ev.preventDefault();
    const j = (i + d + ICONES_FUNIL.length) % ICONES_FUNIL.length;
    refs.current[j]?.focus();
    onChange(ICONES_FUNIL[j].nome);
  };
  return (
    <div role="radiogroup" aria-label="Ícone do funil" className="grid grid-cols-6 sm:grid-cols-12 gap-1 max-w-xl">
      {ICONES_FUNIL.map((ic, i) => {
        const sel = i === atual;
        return (
          <button
            key={ic.nome}
            ref={(el) => { refs.current[i] = el; }}
            type="button"
            role="radio"
            aria-checked={sel}
            aria-label={ic.rotulo}
            title={ic.rotulo}
            tabIndex={sel ? 0 : -1}
            onClick={() => onChange(ic.nome)}
            onKeyDown={(ev) => onKeyDown(ev, i)}
            className={`grid place-items-center h-9 rounded-[var(--r-md)] border transition-colors ${sel ? 'border-[var(--border-accent)] bg-[var(--surface-4)] text-[var(--fg)]' : 'border-transparent text-[var(--fg-3)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]'}`}
          >
            <Icon name={ic.nome} size={16} />
          </button>
        );
      })}
    </div>
  );
}

// ── Etapas ──

export function SecaoEtapas({ f, set, negociosDoFunil, abertas, alternarEtapa, problemas, irPara }: {
  f: Funil;
  set: (p: Partial<Funil>) => void;
  negociosDoFunil: Negocio[];
  abertas: Set<string>;
  alternarEtapa: (id: string, abrir?: boolean) => void;
  problemas: ProblemaFunil[];
  irPara: (p: ProblemaFunil) => void;
}) {
  const [arrastando, setArrastando] = useState<number | null>(null);
  const setEtapa = (id: string, p: Partial<EtapaFunil>) => set({ etapas: f.etapas.map((e) => (e.id === id ? { ...e, ...p } : e)) });
  const moverEtapa = (i: number, d: -1 | 1) => {
    const j = i + d;
    if (j < 0 || j >= f.etapas.length) return;
    const es = [...f.etapas];
    [es[i], es[j]] = [es[j], es[i]];
    set({ etapas: es });
  };
  const reordenar = (de: number, para: number) => {
    setArrastando(null);
    if (de === para) return;
    const es = [...f.etapas];
    const [x] = es.splice(de, 1);
    es.splice(para, 0, x);
    set({ etapas: es });
  };
  const addEtapa = () => {
    const nova: EtapaFunil = { id: idLocal('e'), nome: 'Nova etapa', papel: 'qualificar', cor: 'neutral', slaAtencaoMin: null, slaCriticoMin: null, camposObrigatorios: [], criterio: '' };
    const iGanho = f.etapas.findIndex((e) => e.papel === 'fechado');
    const es = [...f.etapas];
    es.splice(iGanho >= 0 ? iGanho : es.length, 0, nova);
    set({ etapas: es });
    alternarEtapa(nova.id, true);
    setTimeout(() => {
      const el = document.getElementById(`etapa-nome-${nova.id}`) as HTMLInputElement | null;
      el?.focus();
      el?.select();
    }, 50);
  };

  return (
    <div className="space-y-4">
      <ProblemasDaSecao problemas={problemas} irPara={irPara} />
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-xs text-[var(--fg-3)] max-w-xl">
          O <strong className="font-semibold text-[var(--fg-2)]">papel</strong> de cada etapa liga as regras da casa: negociação fica fora de disparo em massa, ganho só com pagamento aprovado.
        </p>
        <div className="flex gap-2">
          <Button size="sm" variant="ghost" onClick={() => set({ etapas: etapasPadrao(idLocal('e')) })} disabled={negociosDoFunil.some((n) => n.status === 'aberto')} title="Só em funil sem negócio aberto">Usar etapas do playbook</Button>
          <Button size="sm" variant="subtle" onClick={addEtapa}><Icon name="plus" size={14} /> Adicionar etapa</Button>
        </div>
      </div>
      <ol className="rounded-[var(--r-lg)] border border-[var(--border)] divide-y divide-[var(--border-faint)] bg-[var(--surface-1)]">
        {f.etapas.map((e, i) => (
          <LinhaEtapa
            key={e.id}
            e={e}
            i={i}
            total={f.etapas.length}
            aberta={abertas.has(e.id)}
            emUso={negociosDoFunil.filter((n) => n.etapaId === e.id && n.status === 'aberto').length}
            removivel={podeRemoverEtapa(e.id, negociosDoFunil) && f.etapas.length > 2}
            arrastando={arrastando}
            onArrastar={setArrastando}
            onSoltar={(de) => reordenar(de, i)}
            onAlternar={() => alternarEtapa(e.id)}
            onMover={(d) => moverEtapa(i, d)}
            onMudar={(p) => setEtapa(e.id, p)}
            onRemover={() => set({ etapas: f.etapas.filter((x) => x.id !== e.id) })}
          />
        ))}
      </ol>
    </div>
  );
}

const BOTAO_ICONE = 'grid place-items-center w-8 h-8 rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-30 disabled:hover:bg-transparent disabled:cursor-not-allowed';

/** Etapa em linha compacta (ordem, cor, nome, papel, alertas); expande para editar o resto. */
function LinhaEtapa({ e, i, total, aberta, emUso, removivel, arrastando, onArrastar, onSoltar, onAlternar, onMover, onMudar, onRemover }: {
  e: EtapaFunil; i: number; total: number; aberta: boolean; emUso: number; removivel: boolean;
  arrastando: number | null; onArrastar: (i: number | null) => void; onSoltar: (de: number) => void;
  onAlternar: () => void; onMover: (d: -1 | 1) => void; onMudar: (p: Partial<EtapaFunil>) => void; onRemover: () => void;
}) {
  const [sobre, setSobre] = useState(false);
  const painel = `etapa-painel-${e.id}`;
  const sla = e.slaAtencaoMin != null && e.slaCriticoMin != null ? `${fmtMinutos(e.slaAtencaoMin)} / ${fmtMinutos(e.slaCriticoMin)}` : 'sem alerta';
  return (
    <li
      draggable={!aberta}
      onDragStart={(ev) => { ev.dataTransfer.effectAllowed = 'move'; onArrastar(i); }}
      onDragEnd={() => { onArrastar(null); setSobre(false); }}
      onDragOver={(ev) => { if (arrastando != null) { ev.preventDefault(); setSobre(true); } }}
      onDragLeave={() => setSobre(false)}
      onDrop={(ev) => { ev.preventDefault(); setSobre(false); if (arrastando != null) onSoltar(arrastando); }}
      className={`transition-colors ${sobre ? 'bg-[var(--accent-subtle)]' : aberta ? 'bg-[var(--surface-2)]' : ''} ${arrastando === i ? 'opacity-50' : ''}`}
    >
      <div className="flex items-center gap-1 px-2 py-1.5">
        <div className="flex items-center">
          <button type="button" aria-label={`Subir ${e.nome || 'etapa'}`} disabled={i === 0} onClick={() => onMover(-1)} className={BOTAO_ICONE}><Icon name="chevron-up" size={16} /></button>
          <button type="button" aria-label={`Descer ${e.nome || 'etapa'}`} disabled={i === total - 1} onClick={() => onMover(1)} className={BOTAO_ICONE}><Icon name="chevron-down" size={16} /></button>
        </div>
        <button type="button" aria-expanded={aberta} aria-controls={painel} onClick={onAlternar}
          className="flex-1 min-w-0 flex items-center gap-3 min-h-8 rounded-[var(--r-md)] px-2 text-left hover:bg-[var(--surface-3)] md:cursor-grab">
          <span className="w-5 text-right text-xs tabular text-[var(--fg-3)]">{i + 1}</span>
          <span aria-hidden className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: COR_ETAPA[e.cor] }} />
          <span className={`flex-1 min-w-0 truncate text-sm font-medium ${e.nome.trim() ? 'text-[var(--fg)]' : 'text-[var(--fg-3)] italic'}`}>{e.nome.trim() || 'Sem nome'}</span>
          <span className="hidden sm:block w-40 truncate text-xs text-[var(--fg-2)]">{ROTULO_PAPEL[e.papel]}</span>
          <span className="hidden md:block w-28 truncate text-xs tabular text-[var(--fg-3)]" title="Alerta de atenção / crítico">{sla}</span>
          {emUso > 0 && <span className="hidden sm:block text-xs tabular text-[var(--fg-3)]">{emUso} {emUso === 1 ? 'aberto' : 'abertos'}</span>}
          <Icon name={aberta ? 'chevron-up' : 'chevron-down'} size={16} className="shrink-0 text-[var(--fg-3)]" />
        </button>
        <button type="button" disabled={!removivel} onClick={onRemover}
          aria-label={`Remover ${e.nome || 'etapa'}`}
          title={removivel ? 'Remover etapa' : 'Mova os negócios abertos antes de remover'}
          className={`${BOTAO_ICONE} hover:!text-[var(--red)] hover:bg-[var(--red-subtle)]`}>
          <Icon name="trash" size={16} />
        </button>
      </div>

      {aberta && (
        <div id={painel} className="px-3 pb-4 pt-1 sm:pl-[88px] grid gap-3 sm:grid-cols-2">
          <CampoFunil rotulo="Nome">
            <Input id={`etapa-nome-${e.id}`} value={e.nome} onChange={(ev) => onMudar({ nome: ev.target.value })} />
          </CampoFunil>
          <CampoFunil rotulo="Papel no playbook" dica={AJUDA_PAPEL[e.papel]}>
            <FilterSelect value={e.papel} onChange={(ev) => onMudar({ papel: ev.target.value as EtapaKey })}>
              {PAPEIS.map((p) => <option key={p} value={p}>{ROTULO_PAPEL[p]}</option>)}
            </FilterSelect>
          </CampoFunil>
          <CampoFunil rotulo="Critério para passar" className="sm:col-span-2">
            <Input value={e.criterio} placeholder="O que precisa acontecer para ir à próxima etapa" onChange={(ev) => onMudar({ criterio: ev.target.value })} />
          </CampoFunil>
          <CampoFunil rotulo="Campos obrigatórios para entrar" grupo>
            <MultiSelect
              values={e.camposObrigatorios}
              onChange={(v) => onMudar({ camposObrigatorios: v as CampoKey[] })}
              placeholder="Nenhum"
              options={CAMPOS.map((c) => ({ value: c, label: ROTULO_CAMPO[c] }))}
            />
          </CampoFunil>
          <CampoFunil rotulo="Alerta de tempo na etapa" grupo dica="Vazio nos dois = etapa sem alerta.">
            <div className="flex flex-wrap items-center gap-3">
              <Duracao rotulo="Atenção" valor={e.slaAtencaoMin} onChange={(v) => onMudar({ slaAtencaoMin: v })} />
              <Duracao rotulo="Crítico" valor={e.slaCriticoMin} onChange={(v) => onMudar({ slaCriticoMin: v })} />
            </div>
          </CampoFunil>
          <CampoFunil rotulo="Cor" grupo className="sm:col-span-2">
            <SeletorCor valor={e.cor} onChange={(cor) => onMudar({ cor })} />
          </CampoFunil>
        </div>
      )}
    </li>
  );
}

/** Cor da etapa: radiogroup com setas e nomes em português; alvo de 32px. */
function SeletorCor({ valor, onChange }: { valor: CorEtapa; onChange: (c: CorEtapa) => void }) {
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  const onKeyDown = (ev: React.KeyboardEvent, i: number) => {
    const d = ev.key === 'ArrowRight' || ev.key === 'ArrowDown' ? 1 : ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? -1 : 0;
    if (!d) return;
    ev.preventDefault();
    const j = (i + d + CORES_ETAPA.length) % CORES_ETAPA.length;
    refs.current[j]?.focus();
    onChange(CORES_ETAPA[j]);
  };
  return (
    <div role="radiogroup" aria-label="Cor da etapa" className="flex flex-wrap items-center gap-0.5">
      {CORES_ETAPA.map((c, i) => (
        <button
          key={c}
          ref={(el) => { refs.current[i] = el; }}
          type="button"
          role="radio"
          aria-checked={valor === c}
          aria-label={ROTULO_COR[c]}
          title={ROTULO_COR[c]}
          tabIndex={valor === c ? 0 : -1}
          onClick={() => onChange(c)}
          onKeyDown={(ev) => onKeyDown(ev, i)}
          className="grid place-items-center w-8 h-8 rounded-full hover:bg-[var(--surface-3)]"
        >
          <span className={`w-5 h-5 rounded-full border-2 ${valor === c ? 'border-[var(--fg)]' : 'border-transparent'}`} style={{ background: COR_ETAPA[c] }} />
        </button>
      ))}
    </div>
  );
}

/** Alerta de tempo: número + unidade (min, h, dias). Vazio = sem alerta. */
function Duracao({ rotulo, valor, onChange }: { rotulo: string; valor: number | null; onChange: (min: number | null) => void }) {
  const unidadeDe = (m: number | null) => (m == null ? 'h' : m % 1440 === 0 && m >= 1440 ? 'd' : m % 60 === 0 && m >= 60 ? 'h' : 'm');
  const [unidade, setUnidade] = useState<'m' | 'h' | 'd'>(unidadeDe(valor));
  const fator = unidade === 'd' ? 1440 : unidade === 'h' ? 60 : 1;
  return (
    <span className="inline-flex items-center gap-1 text-xs text-[var(--fg-3)]">
      {rotulo}
      <Input type="number" min={0} className="!w-16 !py-1 text-right" aria-label={`Alerta de ${rotulo.toLowerCase()}`}
        value={valor == null ? '' : Math.round(valor / fator)}
        onChange={(e) => onChange(e.target.value === '' ? null : Math.max(0, Number(e.target.value)) * fator)} />
      <FilterSelect value={unidade} aria-label={`Unidade do alerta de ${rotulo.toLowerCase()}`} className="!py-1 !pr-7 !text-xs" onChange={(e) => {
        const u = e.target.value as 'm' | 'h' | 'd';
        const novoFator = u === 'd' ? 1440 : u === 'h' ? 60 : 1;
        setUnidade(u);
        if (valor != null) onChange(Math.round(valor / fator) * novoFator);
      }}>
        <option value="m">min</option>
        <option value="h">h</option>
        <option value="d">dias</option>
      </FilterSelect>
    </span>
  );
}

// ── Campanhas ──

export function SecaoCampanhas({ f, set, integracoes = false }: {
  f: Funil;
  set: (p: Partial<Funil>) => void;
  /** Mostra o checklist mínimo de integrações (assistente). */
  integracoes?: boolean;
}) {
  const setCampanha = (id: string, p: Partial<Campanha>) => set({ campanhas: f.campanhas.map((c) => (c.id === id ? { ...c, ...p } : c)) });
  return (
    <div className="space-y-5">
      <div className="space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-xs text-[var(--fg-3)] max-w-xl">
            Portas de entrada do funil: o lead que chega por elas vira negócio aqui, já com a origem preenchida.
          </p>
          <Button size="sm" variant="subtle" onClick={() => set({ campanhas: [...f.campanhas, { id: idLocal('cp'), nome: '', canal: 'utm', regra: f.projeto ? `utm_campaign = ${f.projeto}` : '', ativa: true, criadoEm: '' }] })}>
            <Icon name="plus" size={14} /> Nova campanha
          </Button>
        </div>
        {f.campanhas.length === 0 && (
          <div className="rounded-[var(--r-lg)] border border-dashed border-[var(--border)] py-8 text-center text-sm text-[var(--fg-3)]">
            Nenhuma campanha. Sem campanha, o negócio só entra criado à mão.
          </div>
        )}
        {f.campanhas.map((c) => (
          <div key={c.id} className="grid gap-2 items-center rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)] p-3 md:grid-cols-[1fr_170px_1.3fr_auto_auto]">
            <Input value={c.nome} placeholder="Nome (ex.: HT33 Meteórico)" aria-label="Nome da campanha" onChange={(e) => setCampanha(c.id, { nome: e.target.value })} />
            <FilterSelect value={c.canal} aria-label="Canal" onChange={(e) => setCampanha(c.id, { canal: e.target.value as CanalCampanha })}>
              {CANAIS.map((x) => <option key={x.value} value={x.value}>{x.label}</option>)}
            </FilterSelect>
            <Input value={c.regra} placeholder={CANAIS.find((x) => x.value === c.canal)?.dica} aria-label="Regra de entrada" onChange={(e) => setCampanha(c.id, { regra: e.target.value })} />
            <Toggle checked={c.ativa} onChange={(v) => setCampanha(c.id, { ativa: v })} label={c.ativa ? 'Ativa' : 'Pausada'} />
            <button type="button" aria-label="Remover campanha" onClick={() => set({ campanhas: f.campanhas.filter((x) => x.id !== c.id) })} className="grid place-items-center w-8 h-8 rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--red)] hover:bg-[var(--red-subtle)]">
              <Icon name="trash" size={15} />
            </button>
          </div>
        ))}
      </div>

      {integracoes && (
        <section aria-labelledby="funil-integracoes" className="space-y-2">
          <h3 id="funil-integracoes" className="text-sm font-semibold text-[var(--fg)]">Integrações mínimas</h3>
          <p className="text-xs text-[var(--fg-3)] max-w-xl">O que precisa estar ligado para o funil andar sozinho. A conexão é feita pelo time de sistemas depois de criar.</p>
          <ul className="rounded-[var(--r-lg)] border border-[var(--border)] divide-y divide-[var(--border-faint)]">
            {integracoesDoFunil(f).map((i) => (
              <li key={i.id} className="flex items-start justify-between gap-3 px-3 py-2.5">
                <div className="min-w-0">
                  <div className="text-sm font-medium text-[var(--fg)]">{i.nome}</div>
                  <div className="text-xs text-[var(--fg-3)] leading-snug">{i.explicacao}</div>
                </div>
                <span className="shrink-0"><Badge tone="warning">A conectar</Badge></span>
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  );
}

// ── Distribuição ──

export function SecaoDistribuicao({ f, set, vendedores, problemas, irPara }: {
  f: Funil;
  set: (p: Partial<Funil>) => void;
  vendedores: Vendedor[];
  problemas: ProblemaFunil[];
  irPara: (p: ProblemaFunil) => void;
}) {
  return (
    <div className="space-y-4 max-w-2xl">
      <ProblemasDaSecao problemas={problemas} irPara={irPara} />
      <Toggle
        checked={f.distribuicao !== null}
        onChange={(v) => set({ distribuicao: v ? vendedores.filter((x) => x.ativo).map((x) => ({ vendedorId: x.id, percentual: x.percentual })) : null })}
        label="Distribuição própria deste funil"
      />
      <p className="text-sm text-[var(--fg-2)]">
        {f.distribuicao === null
          ? 'Usa a distribuição geral do Comercial (Configurações). Contato com dono mantém o dono em qualquer funil.'
          : 'Lead sem dono que entra neste funil vai pelo percentual abaixo. Contato com dono continua com o dono.'}
      </p>
      {f.distribuicao !== null && (
        <div className="rounded-[var(--r-lg)] border border-[var(--border)] divide-y divide-[var(--border-faint)]">
          {vendedores.filter((v) => v.ativo).map((v) => {
            const atual = f.distribuicao!.find((d) => d.vendedorId === v.id)?.percentual ?? 0;
            return (
              <div key={v.id} className="flex items-center justify-between gap-3 px-3 py-2">
                <span className="text-sm text-[var(--fg)]">{v.nome} <span className="text-[11px] text-[var(--fg-3)]">· {v.papel}</span></span>
                <span className="flex items-center gap-1">
                  <Input type="number" min={0} max={100} value={atual} className="!w-20 text-right" aria-label={`Percentual de ${v.nome}`}
                    onChange={(e) => {
                      const p = Math.max(0, Math.min(100, Number(e.target.value) || 0));
                      const resto = f.distribuicao!.filter((d) => d.vendedorId !== v.id);
                      set({ distribuicao: [...resto, { vendedorId: v.id, percentual: p }] });
                    }} />
                  <span className="text-sm text-[var(--fg-3)]">%</span>
                </span>
              </div>
            );
          })}
          <div className="flex items-center justify-between px-3 py-2 text-sm">
            <span className="text-[var(--fg-3)]">Soma</span>
            {(() => {
              const soma = f.distribuicao!.reduce((s, d) => s + d.percentual, 0);
              return <span id="funil-distribuicao" tabIndex={-1} className={`font-semibold tabular ${soma === 100 ? 'text-[var(--fg)]' : 'text-[var(--red)]'}`}>{soma}%{soma === 100 ? '' : ' (precisa somar 100%)'}</span>;
            })()}
          </div>
        </div>
      )}
    </div>
  );
}
