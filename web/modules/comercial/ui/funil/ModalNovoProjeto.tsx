'use client';

// "Comecei um novo projeto": o gestor escolhe o tipo, dá o nome e cria de uma vez os funis certos, com a chave
// do projeto (a mesma do ClickUp, do Drive e do utm_campaign) nas campanhas. Mostra antes o que vai ser criado.
import { useMemo, useState } from 'react';
import { Button, FilterSelect, Input, Modal } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { PRODUTOS } from '../../domain/catalogo';
import { chaveProjeto, funisDoProjeto, MODELOS_FUNIL, MODELOS_PROJETO } from '../../domain/modelos';
import type { Agrupador, ProdutoKey, TipoProjeto } from '../../domain/types';
import { Campo } from '../comum';
import { avisarMudanca, repo } from '../repositorio';
import { cadeiaEtapas } from './assistente';

const AGRUPADOR_PREVIA: Agrupador = { id: 'previa', nome: '', produto: null, ordem: 0 };

export function ModalNovoProjeto({ agrupadores, agrupadorInicial, onClose, onCriado }: {
  agrupadores: Agrupador[];
  agrupadorInicial: Agrupador | undefined;
  onClose: () => void;
  onCriado: (funilIds: string[], msg: string) => void;
}) {
  const [tipo, setTipo] = useState<TipoProjeto>(MODELOS_PROJETO[0].tipo);
  const [nome, setNome] = useState('');
  const [agrupadorId, setAgrupadorId] = useState(agrupadorInicial?.id ?? '');
  const [novoAgrupador, setNovoAgrupador] = useState<string | null>(null);
  const [produto, setProduto] = useState<ProdutoKey>(agrupadorInicial?.produto ?? 'ht');
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  const modelo = MODELOS_PROJETO.find((m) => m.tipo === tipo)!;
  const chave = chaveProjeto(nome);
  const previa = useMemo(() => funisDoProjeto(tipo, nome.trim() || 'Projeto', AGRUPADOR_PREVIA, produto), [tipo, nome, produto]);
  const faltando = !nome.trim() ? 'Dê um nome ao projeto.'
    : !chave ? 'O nome precisa ter letras ou números para virar chave.'
      : novoAgrupador !== null ? (!novoAgrupador.trim() ? 'Dê um nome ao agrupador novo.' : null)
        : !agrupadorId ? 'Escolha o agrupador.' : null;

  const escolherAgrupador = (id: string) => {
    setAgrupadorId(id);
    const a = agrupadores.find((x) => x.id === id);
    if (a?.produto) setProduto(a.produto);
  };

  const criar = async () => {
    if (faltando) return;
    setSalvando(true);
    setErro(null);
    let ag = agrupadorId;
    if (novoAgrupador !== null) {
      const r = await repo.criarAgrupador(novoAgrupador.trim(), produto);
      if (!r.ok || !r.agrupadorId) { setErro(r.msg ?? 'Não foi possível criar o agrupador.'); setSalvando(false); return; }
      ag = r.agrupadorId;
      setAgrupadorId(ag);
      setNovoAgrupador(null);
      avisarMudanca();
    }
    const r = await repo.criarProjeto(tipo, nome.trim(), ag, produto);
    setSalvando(false);
    if (!r.ok || !r.funilIds?.length) { setErro(r.msg ?? 'Não foi possível criar o projeto.'); return; }
    avisarMudanca();
    onCriado(r.funilIds, r.msg ?? `${r.funilIds.length} funis criados.`);
  };

  const onKeyDownTipo = (ev: React.KeyboardEvent, i: number) => {
    const d = ev.key === 'ArrowRight' || ev.key === 'ArrowDown' ? 1 : ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? -1 : 0;
    if (!d) return;
    ev.preventDefault();
    const j = (i + d + MODELOS_PROJETO.length) % MODELOS_PROJETO.length;
    setTipo(MODELOS_PROJETO[j].tipo);
    (ev.currentTarget.parentElement?.children[j] as HTMLElement | undefined)?.focus();
  };

  return (
    <Modal
      onClose={onClose}
      width="max-w-4xl"
      title="Comecei um novo projeto"
      footer={<>
        <span className="flex-1 min-w-0 self-center text-xs">
          {erro ? <span role="alert" className="text-[var(--red)]">{erro}</span> : faltando ? <span className="text-[var(--fg-3)]">{faltando}</span> : null}
        </span>
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!!faltando || salvando} onClick={criar}>
          {previa.length === 1 ? 'Criar 1 funil' : `Criar ${previa.length} funis`}
        </Button>
      </>}
    >
      <div className="space-y-5">
        <section aria-labelledby="projeto-tipo" className="space-y-2">
          <h3 id="projeto-tipo" className="text-sm font-semibold text-[var(--fg)]">Tipo de projeto</h3>
          <div role="radiogroup" aria-labelledby="projeto-tipo" className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            {MODELOS_PROJETO.map((m, i) => {
              const sel = m.tipo === tipo;
              const nomesFunis = m.funis.map((id) => MODELOS_FUNIL.find((x) => x.id === id)?.nome ?? id).join(', ');
              return (
                <button key={m.tipo} type="button" role="radio" aria-checked={sel} tabIndex={sel ? 0 : -1}
                  onClick={() => setTipo(m.tipo)} onKeyDown={(ev) => onKeyDownTipo(ev, i)}
                  className={`text-left rounded-[var(--r-lg)] border p-3 transition-colors ${sel ? 'border-[var(--border-accent)] bg-[var(--surface-4)]' : 'border-[var(--border)] bg-[var(--surface-1)] hover:bg-[var(--surface-3)]'}`}>
                  <div className="flex items-center gap-2">
                    <Icon name={m.icone} size={16} className={sel ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'} />
                    <span className={`min-w-0 truncate text-sm text-[var(--fg)] ${sel ? 'font-semibold' : 'font-medium'}`}>{m.nome}</span>
                  </div>
                  <p className="mt-1 text-xs text-[var(--fg-2)] leading-snug">{m.descricao}</p>
                  <p className="mt-1.5 text-[11px] text-[var(--fg-3)] leading-snug">Cria: {nomesFunis}</p>
                </button>
              );
            })}
          </div>
        </section>

        <div className="grid gap-4 md:grid-cols-3">
          <Campo rotulo="Nome do projeto" dica={chave ? <>Chave: <code className="text-[var(--fg-2)]">{chave}</code> · vira utm_campaign nas campanhas</> : 'Ex.: HT34 meteórico out26'}>
            <Input autoFocus value={nome} placeholder="Ex.: HT34 meteórico out26" onChange={(e) => setNome(e.target.value)} />
          </Campo>
          {novoAgrupador === null ? (
            <Campo rotulo="Agrupador" dica="A pasta onde os funis aparecem.">
              <div className="flex gap-2">
                <FilterSelect value={agrupadorId} onChange={(e) => escolherAgrupador(e.target.value)} className="flex-1 min-w-0">
                  <option value="">Escolha…</option>
                  {agrupadores.map((a) => <option key={a.id} value={a.id}>{a.nome}</option>)}
                </FilterSelect>
                <Button size="sm" variant="ghost" onClick={() => setNovoAgrupador('')}><Icon name="plus" size={13} /> Novo</Button>
              </div>
            </Campo>
          ) : (
            <Campo rotulo="Agrupador novo">
              <div className="flex gap-2">
                <Input autoFocus value={novoAgrupador} placeholder="Nome do agrupador" onChange={(e) => setNovoAgrupador(e.target.value)} />
                <Button size="sm" variant="ghost" onClick={() => setNovoAgrupador(null)}>Cancelar</Button>
              </div>
            </Campo>
          )}
          <Campo rotulo="Produto">
            <FilterSelect value={produto} onChange={(e) => setProduto(e.target.value as ProdutoKey)}>
              {PRODUTOS.map((p) => <option key={p.key} value={p.key}>{p.nome} · escada {p.escada}</option>)}
            </FilterSelect>
          </Campo>
        </div>

        <section aria-labelledby="projeto-previa" className="space-y-2">
          <h3 id="projeto-previa" className="text-sm font-semibold text-[var(--fg)]">O que vai ser criado</h3>
          <ul className="rounded-[var(--r-lg)] border border-[var(--border)] divide-y divide-[var(--border-faint)]">
            {previa.map((f) => (
              <li key={f.etapas[0]?.id ?? f.nome} className="flex items-start gap-3 px-3 py-2.5">
                <Icon name={f.icone} size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
                <div className="min-w-0 flex-1">
                  <div className="text-sm font-medium text-[var(--fg)] break-words">{f.nome}</div>
                  <div className="text-xs text-[var(--fg-3)] leading-snug">{cadeiaEtapas(f.etapas)}</div>
                  {f.campanhas.length > 0 && (
                    <div className="mt-0.5 text-[11px] text-[var(--fg-3)] break-words">Entrada: {f.campanhas.map((c) => c.regra).join(' · ')}</div>
                  )}
                </div>
                {f.tipo === 'hotmart' && <span className="shrink-0 text-[11px] text-[var(--fg-3)]">Automático</span>}
              </li>
            ))}
          </ul>
        </section>

        <section aria-labelledby="projeto-checklist" className="space-y-2">
          <h3 id="projeto-checklist" className="text-sm font-semibold text-[var(--fg)]">Checklist do projeto</h3>
          <ul className="space-y-1.5">
            {modelo.checklist.map((item) => (
              <li key={item} className="flex items-start gap-2 text-sm text-[var(--fg-2)]">
                <Icon name="circle" size={14} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
                <span>{item}</span>
              </li>
            ))}
          </ul>
          <p className="text-[11px] text-[var(--fg-3)]">Combine cada item com o time antes de abrir a captação.</p>
        </section>
      </div>
    </Modal>
  );
}
