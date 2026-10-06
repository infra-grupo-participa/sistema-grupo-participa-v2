'use client';

// Assistente para criar funil, passo a passo: ponto de partida (em branco ou modelo) → geral → etapas →
// campanhas e integrações → distribuição → revisão com boas práticas. Cada passo só avança sem pendência
// (validarFunil); a revisão mostra o que ainda vale melhorar, sem travar. Só o gestor chega aqui.
import { useMemo, useState } from 'react';
import { Button, Drawer } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { PRODUTOS, ROTULO_ORIGEM } from '../../domain/catalogo';
import { validarFunil, type ProblemaFunil } from '../../domain/funis';
import { chaveProjeto, MODELOS_FUNIL } from '../../domain/modelos';
import type { Agrupador, Funil, ModeloFunil, Vendedor } from '../../domain/types';
import { avisarMudanca, repo } from '../repositorio';
import {
  aplicarPartida, boasPraticas, cadeiaEtapas, capaDoModelo, PASSOS, problemasDoPasso, trocarChave, type BoaPratica,
} from './assistente';
import {
  CAMPOS_GERAL, funilVazio, focarProblema, idLocal, ProblemasDaSecao, SecaoCampanhas, SecaoDistribuicao, SecaoEtapas,
  SecaoGeral, useEtapasAbertas,
} from './secoes-funil';

const PASSO_DO_CAMPO: Record<string, number> = { nome: 1, agrupador: 1, eventos: 1, etapas: 2, distribuicao: 4 };

export function AssistenteFunil({ agrupadores, agrupadorInicial, vendedores, onClose, onCriado }: {
  agrupadores: Agrupador[];
  agrupadorInicial: Agrupador | undefined;
  vendedores: Vendedor[];
  onClose: () => void;
  onCriado: (funilId: string, msg: string) => void;
}) {
  const [f, setF] = useState<Funil>(() => funilVazio(agrupadorInicial));
  const [passo, setPasso] = useState(0);
  const [visitado, setVisitado] = useState(0);
  /** Modelo escolhido ('' = em branco). */
  const [modeloId, setModeloId] = useState('');
  const [projetoTexto, setProjetoTexto] = useState('');
  /** Último ponto de partida aplicado às etapas/campanhas (ao sair do passo Geral). */
  const [aplicado, setAplicado] = useState<{ modeloId: string; chave: string | null } | null>(null);
  const [novoAgrupador, setNovoAgrupador] = useState<string | null>(null);
  const [tentou, setTentou] = useState(false);
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const { abertas, alternar } = useEtapasAbertas();

  const set = (p: Partial<Funil>) => setF((x) => ({ ...x, ...p }));
  const modelo = MODELOS_FUNIL.find((m) => m.id === modeloId) ?? null;
  const problemas = useMemo(() => {
    const p = validarFunil(f, vendedores);
    if (novoAgrupador !== null && !novoAgrupador.trim()) p.push({ campo: 'agrupador', msg: 'Dê um nome ao agrupador novo.' });
    return p;
  }, [f, vendedores, novoAgrupador]);
  const doPasso = (i: number) => problemasDoPasso(PASSOS[i].k, problemas);
  const atual = PASSOS[passo].k;
  const visiveis = tentou ? doPasso(passo) : [];

  const escolherModelo = (id: string) => {
    const novo = MODELOS_FUNIL.find((m) => m.id === id) ?? null;
    setF((x) => capaDoModelo(x, novo, modelo?.nome ?? ''));
    setModeloId(id);
  };

  /** Ao passar do Geral: aplica o modelo (se mudou) ou só a chave nova nas campanhas. */
  const prepararEtapas = (x: Funil): Funil => {
    const chave = chaveProjeto(projetoTexto) || null;
    if (!aplicado || aplicado.modeloId !== modeloId) {
      setAplicado({ modeloId, chave });
      return aplicarPartida(x, modelo, chave, idLocal('p'));
    }
    if (aplicado.chave !== chave) {
      setAplicado({ modeloId, chave });
      return trocarChave(x, aplicado.chave, chave, modelo, idLocal('p'));
    }
    return x;
  };

  const irParaProblema = (p: ProblemaFunil) => {
    const destino = PASSO_DO_CAMPO[p.campo] ?? 1;
    if (destino < passo) setPasso(destino);
    setTentou(true);
    focarProblema(p, f, (id) => alternar(id, true));
  };

  /** Vai para o passo `i`. Para frente, para no primeiro passo com pendência. */
  const irPara = (i: number) => {
    if (i <= passo) { setPasso(i); setTentou(false); return; }
    for (let j = passo; j < i; j++) {
      const pj = doPasso(j);
      if (pj.length) {
        setPasso(j);
        setTentou(true);
        focarProblema(pj[0], f, (id) => alternar(id, true));
        return;
      }
    }
    if (passo <= 1 && i > 1) setF(prepararEtapas(f));
    setPasso(i);
    setVisitado((v) => Math.max(v, i));
    setTentou(false);
  };

  const criar = async () => {
    if (problemas.length) { irParaProblema(problemas[0]); return; }
    setSalvando(true);
    setErro(null);
    let agrupadorId = f.agrupadorId;
    if (novoAgrupador !== null) {
      const r = await repo.criarAgrupador(novoAgrupador, f.produto);
      if (!r.ok || !r.agrupadorId) { setErro(r.msg ?? 'Não foi possível criar o agrupador.'); setSalvando(false); return; }
      agrupadorId = r.agrupadorId;
      setNovoAgrupador(null);
      set({ agrupadorId });
    }
    const r = await repo.salvarFunil({ ...f, agrupadorId });
    setSalvando(false);
    if (!r.ok || !r.funilId) { setErro(r.msg ?? 'Não foi possível criar o funil.'); return; }
    avisarMudanca();
    onCriado(r.funilId, r.msg ?? 'Funil criado.');
  };

  const ultimo = passo === PASSOS.length - 1;
  const nomeAgrupador = novoAgrupador !== null ? `${novoAgrupador.trim() || 'sem nome'} (novo)` : agrupadores.find((a) => a.id === f.agrupadorId)?.nome ?? '—';

  return (
    <Drawer
      onClose={onClose}
      width="max-w-5xl"
      title="Novo funil"
      subtitle={`Passo ${passo + 1} de ${PASSOS.length} · ${PASSOS[passo].rotulo}`}
      footer={<>
        {passo > 0 && <Button size="sm" variant="ghost" onClick={() => irPara(passo - 1)}><Icon name="arrow-left" size={14} /> Voltar</Button>}
        <span className="flex-1 min-w-0 text-xs">
          {erro ? <span role="alert" className="text-[var(--red)]">{erro}</span> : null}
        </span>
        <Button size="sm" variant="ghost" onClick={onClose}>Cancelar</Button>
        {ultimo ? (
          <Button size="sm" disabled={salvando || problemas.length > 0} onClick={criar}>Criar funil</Button>
        ) : (
          <Button size="sm" onClick={() => irPara(passo + 1)}>Avançar <Icon name="arrow-right" size={14} /></Button>
        )}
      </>}
    >
      <BarraPassos passo={passo} visitado={visitado} onIr={irPara} />

      {atual === 'partida' && <PassoPartida modeloId={modeloId} onEscolher={escolherModelo} />}

      {atual === 'geral' && (
        <SecaoGeral f={f} set={set} agrupadores={agrupadores} novoAgrupador={novoAgrupador} setNovoAgrupador={setNovoAgrupador}
          problemas={visiveis.filter((p) => CAMPOS_GERAL.includes(p.campo))} irPara={irParaProblema}
          projeto={{ valor: projetoTexto, onChange: setProjetoTexto }} />
      )}
      {atual === 'etapas' && (
        <SecaoEtapas f={f} set={set} negociosDoFunil={[]} abertas={abertas} alternarEtapa={alternar}
          problemas={visiveis} irPara={irParaProblema} />
      )}
      {atual === 'campanhas' && <SecaoCampanhas f={f} set={set} integracoes />}
      {atual === 'distribuicao' && (
        <SecaoDistribuicao f={f} set={set} vendedores={vendedores} problemas={visiveis} irPara={irParaProblema} />
      )}
      {atual === 'revisao' && (
        <div className="space-y-5 max-w-3xl">
          <ProblemasDaSecao problemas={problemas} irPara={irParaProblema} verbo="criar" />
          <Resumo f={f} agrupador={nomeAgrupador} vendedores={vendedores} />
          <ListaBoasPraticas praticas={boasPraticas(f, vendedores)} />
        </div>
      )}
    </Drawer>
  );
}

/** Barra de progresso dos passos: número, nome e linha preenchida até o passo atual. */
function BarraPassos({ passo, visitado, onIr }: { passo: number; visitado: number; onIr: (i: number) => void }) {
  return (
    <nav aria-label="Passos do assistente" className="mb-5">
      <div className="h-1 rounded-full bg-[var(--surface-3)] overflow-hidden" aria-hidden>
        <div className="h-full bg-[var(--accent)] transition-[width]" style={{ width: `${((passo + 1) / PASSOS.length) * 100}%` }} />
      </div>
      <ol className="mt-2 grid grid-cols-6 gap-1">
        {PASSOS.map((p, i) => {
          const pode = i <= visitado;
          const atual = i === passo;
          return (
            <li key={p.k} className="min-w-0">
              <button
                type="button"
                disabled={!pode}
                aria-current={atual ? 'step' : undefined}
                onClick={() => onIr(i)}
                className={`w-full flex items-center gap-1.5 min-h-8 rounded-[var(--r-sm)] px-1 text-left text-xs transition-colors disabled:cursor-default ${atual ? 'text-[var(--fg)] font-semibold' : pode ? 'text-[var(--fg-2)] hover:text-[var(--fg)]' : 'text-[var(--fg-3)]'}`}
              >
                <span className={`grid place-items-center w-5 h-5 shrink-0 rounded-full text-[11px] tabular border ${atual ? 'border-[var(--border-accent)] bg-[var(--surface-4)]' : i < passo ? 'border-[var(--border)] bg-[var(--surface-3)]' : 'border-[var(--border)]'}`}>
                  {i < passo ? <Icon name="check" size={11} /> : i + 1}
                </span>
                <span className={`truncate ${atual ? '' : 'hidden md:inline'}`}>{p.rotulo}</span>
              </button>
            </li>
          );
        })}
      </ol>
    </nav>
  );
}

/** Passo 1: em branco ou um modelo pronto, com descrição e prévia das etapas. */
function PassoPartida({ modeloId, onEscolher }: { modeloId: string; onEscolher: (id: string) => void }) {
  const opcoes: { id: string; nome: string; icone: string; descricao: string; etapas: string; hotmart: boolean }[] = [
    { id: '', nome: 'Em branco', icone: 'plus', descricao: 'Começa com as 6 etapas do playbook e você ajusta.', etapas: 'Etapas do playbook', hotmart: false },
    ...MODELOS_FUNIL.map((m: ModeloFunil) => ({ id: m.id, nome: m.nome, icone: m.icone, descricao: m.descricao, etapas: cadeiaEtapas(m.etapas), hotmart: m.tipo === 'hotmart' })),
  ];
  const onKeyDown = (ev: React.KeyboardEvent, i: number) => {
    const d = ev.key === 'ArrowRight' || ev.key === 'ArrowDown' ? 1 : ev.key === 'ArrowLeft' || ev.key === 'ArrowUp' ? -1 : 0;
    if (!d) return;
    ev.preventDefault();
    const j = (i + d + opcoes.length) % opcoes.length;
    onEscolher(opcoes[j].id);
    (ev.currentTarget.parentElement?.children[j] as HTMLElement | undefined)?.focus();
  };
  return (
    <div className="space-y-3">
      <p className="text-sm text-[var(--fg-2)]">Comece de um modelo da casa ou em branco. Tudo pode ser ajustado nos próximos passos.</p>
      <div role="radiogroup" aria-label="Ponto de partida" className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
        {opcoes.map((o, i) => {
          const sel = o.id === modeloId;
          return (
            <button
              key={o.id || 'branco'}
              type="button"
              role="radio"
              aria-checked={sel}
              tabIndex={sel ? 0 : -1}
              onClick={() => onEscolher(o.id)}
              onKeyDown={(ev) => onKeyDown(ev, i)}
              className={`text-left rounded-[var(--r-lg)] border p-3 transition-colors ${sel ? 'border-[var(--border-accent)] bg-[var(--surface-4)]' : 'border-[var(--border)] bg-[var(--surface-2)] hover:bg-[var(--surface-3)]'}`}
            >
              <div className="flex items-center gap-2">
                <Icon name={o.icone} size={16} className={sel ? 'text-[var(--fg)]' : 'text-[var(--fg-3)]'} />
                <span className={`flex-1 min-w-0 truncate text-sm text-[var(--fg)] ${sel ? 'font-semibold' : 'font-medium'}`}>{o.nome}</span>
                {o.hotmart && <span className="shrink-0 text-[11px] text-[var(--fg-3)]">Automático</span>}
              </div>
              <p className="mt-1 text-xs text-[var(--fg-2)] leading-snug">{o.descricao}</p>
              <p className="mt-1.5 text-[11px] text-[var(--fg-3)] leading-snug line-clamp-2" title={o.etapas}>{o.etapas}</p>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/** Resumo do funil na revisão: o que foi escolhido em cada passo, em linhas de texto. */
function Resumo({ f, agrupador, vendedores }: { f: Funil; agrupador: string; vendedores: Vendedor[] }) {
  const produto = PRODUTOS.find((p) => p.key === f.produto)?.nome ?? f.produto;
  const entrada = f.tipo === 'hotmart'
    ? `Automático Hotmart · ${f.eventosHotmart.map((o) => ROTULO_ORIGEM[o]).join(', ') || 'sem evento'}`
    : 'Manual';
  const campanhas = f.campanhas.length ? f.campanhas.map((c) => `${c.nome || 'sem nome'}${c.ativa ? '' : ' (pausada)'}`).join(', ') : 'Nenhuma';
  const nomeV = (id: string) => vendedores.find((v) => v.id === id)?.nome ?? id;
  const distribuicao = f.distribuicao ? f.distribuicao.filter((d) => d.percentual > 0).map((d) => `${nomeV(d.vendedorId)} ${d.percentual}%`).join(', ') : 'Geral do Comercial';
  const linhas: [string, string][] = [
    ['Agrupador', agrupador],
    ['Produto', produto],
    ['Entrada', entrada],
    ['Chave do projeto', f.projeto ?? '—'],
    [`Etapas (${f.etapas.length})`, cadeiaEtapas(f.etapas)],
    [`Campanhas (${f.campanhas.length})`, campanhas],
    ['Distribuição', distribuicao],
  ];
  return (
    <section aria-labelledby="revisao-resumo" className="rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-2)]">
      <h3 id="revisao-resumo" className="flex items-center gap-2 px-3 py-2.5 border-b border-[var(--border-faint)] text-sm font-semibold text-[var(--fg)]">
        <Icon name={f.icone} size={16} />
        <span className="truncate">{f.nome || 'Sem nome'}</span>
      </h3>
      <dl className="divide-y divide-[var(--border-faint)]">
        {linhas.map(([k, v]) => (
          <div key={k} className="grid gap-0.5 px-3 py-2 sm:grid-cols-[160px_1fr] sm:gap-3">
            <dt className="text-xs text-[var(--fg-3)]">{k}</dt>
            <dd className="text-sm text-[var(--fg)] break-words">{v}</dd>
          </div>
        ))}
      </dl>
    </section>
  );
}

const MARCA: Record<BoaPratica['situacao'], { icone: string; cor: string; rotulo: string }> = {
  ok: { icone: 'check-circle', cor: 'var(--green)', rotulo: 'Feito' },
  pendente: { icone: 'circle', cor: 'var(--yellow)', rotulo: 'Pendente' },
  nao_se_aplica: { icone: 'circle', cor: 'var(--fg-3)', rotulo: 'Não se aplica' },
};

/** Boas práticas calculadas do funil: verde quando feito, pendente com o que falta. Não trava a criação. */
function ListaBoasPraticas({ praticas }: { praticas: BoaPratica[] }) {
  const validas = praticas.filter((p) => p.situacao !== 'nao_se_aplica');
  const feitas = validas.filter((p) => p.situacao === 'ok').length;
  return (
    <section aria-labelledby="revisao-praticas" className="space-y-2">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h3 id="revisao-praticas" className="text-sm font-semibold text-[var(--fg)]">Boas práticas</h3>
        <span className="text-xs tabular text-[var(--fg-3)]">{feitas} de {validas.length} feitas</span>
      </div>
      <ul className="rounded-[var(--r-lg)] border border-[var(--border)] divide-y divide-[var(--border-faint)]">
        {praticas.map((p) => {
          const m = MARCA[p.situacao];
          return (
            <li key={p.id} className="flex items-start gap-3 px-3 py-2.5">
              <span className="mt-0.5 shrink-0" style={{ color: m.cor }}><Icon name={m.icone} size={16} /></span>
              <div className="min-w-0 flex-1">
                <div className="text-sm font-medium text-[var(--fg)]">{p.titulo}<span className="sr-only">: {m.rotulo}</span></div>
                <div className="text-xs text-[var(--fg-3)] leading-snug">{p.detalhe}</div>
              </div>
              <span className="shrink-0 text-[11px] text-[var(--fg-3)]" aria-hidden>{m.rotulo}</span>
            </li>
          );
        })}
      </ul>
      <p className="text-[11px] text-[var(--fg-3)]">Pendência aqui não impede criar: é o que costuma dar problema depois.</p>
    </section>
  );
}
