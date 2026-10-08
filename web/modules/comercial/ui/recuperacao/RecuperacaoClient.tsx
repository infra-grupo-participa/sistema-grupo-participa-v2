'use client';

// Filas de recuperação pós-lançamento (substitui a "Sala de Guerra" da planilha).
// Regras à vista: sem oferta vigente não se aborda; C e D só depois de A e B zeradas; ordem do playbook.
import { useMemo, useRef, useState } from 'react';
import { Button, FilterSelect, SearchInput, Toast, Toolbar, useFlash } from '@/shared/ui/components';
import { fmtData, fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  produto as produtoDe, ROTULO_SINAL, ROTULO_STATUS_FILA, STATUS_FILA_CAMINHO, STATUS_FILA_SAIDA,
} from '../../domain/catalogo';
import { faixaLiberada, fmtTelefone } from '../../domain/regras';
import type { Contato, FaixaScore, FilaRecuperacao, ItemFila, SinalRecuperacao, StatusFila } from '../../domain/types';
import { Aviso, EsqueletoLista, EstadoErro, FaixaNumeros, PaginaComercial, Pessoa, Segmentado, Vazio, useEquipe } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { ContatoDrawer } from '../contatos/ContatoDrawer';
import { avisarMudanca, repo, useContatosPorIds, useDados } from '../repositorio';
import { INFO_FILA } from './indicadores';
import { FAIXAS, numerosFila } from './numeros-fila';
import { encerrado, GRUPOS_ORDEM, grupoPrioridade, ordenarFila, pendentesAB } from './ordem-fila';
import { ScriptAbordagem } from './ScriptAbordagem';

type FiltroStatus = StatusFila | 'todos' | 'em_trabalho';
const TRAVA_CD = 'Travada: ninguém toca em C e D antes de A e B estarem zeradas.';

/** `embutido`: dentro da tela Estratégias (aba "Filas de recuperação"), sem o cabeçalho de página próprio. */
export function RecuperacaoClient({ embutido = false }: { embutido?: boolean } = {}) {
  const { sessao, vendedores, nomeDe, gestor, verTudo, leitor } = useEquipe();
  const { dados: filas, erro: erroFilas, recarregar: recFilas } = useDados(() => repo.filas());
  // Só os contatos dos itens das filas (não a base inteira).
  const { dados: contatos, erro: erroContatos, recarregar: recContatos } = useContatosPorIds(filas?.flatMap((f) => f.itens.map((i) => i.contatoId)));
  const { toast, flash } = useFlash();

  const [filaId, setFilaId] = useState<string | null>(null);
  const [faixa, setFaixa] = useState<FaixaScore | 'todas'>('todas');
  const [status, setStatus] = useState<FiltroStatus>('todos');
  // null = padrão do papel: vendedor abre na própria carteira, gestor vê todos.
  const [resp, setResp] = useState<string | null>(null);
  const [sinal, setSinal] = useState<SinalRecuperacao | 'todos'>('todos');
  const [busca, setBusca] = useState('');
  const [script, setScript] = useState(false);
  const [selecionado, setSelecionado] = useState<string | null>(null);
  const [contatoAberto, setContatoAberto] = useState<string | null>(null);
  const [filtrosAbertos, setFiltrosAbertos] = useState(false);
  const painelRef = useRef<HTMLDivElement>(null);

  const fila: FilaRecuperacao | null = filas?.find((f) => f.id === filaId) ?? filas?.[0] ?? null;
  const contatoPorId = useMemo(() => new Map((contatos ?? []).map((c) => [c.id, c])), [contatos]);
  const respPadrao = verTudo ? 'todos' : 'meus';
  const respEfetivo = resp ?? respPadrao;

  const itens = useMemo(() => fila?.itens ?? [], [fila]);
  const pendAB = pendentesAB(itens);
  const semOferta = !!fila && !fila.ofertaVigente;

  const visiveis = useMemo(() => {
    const q = busca.trim().toLowerCase();
    const filtrados = itens.filter((i) => {
      if (faixa !== 'todas' && i.faixa !== faixa) return false;
      if (status === 'em_trabalho' && encerrado(i.status)) return false;
      if (status !== 'todos' && status !== 'em_trabalho' && i.status !== status) return false;
      if (respEfetivo === 'meus' && i.responsavelId !== sessao?.vendedorId) return false;
      if (respEfetivo !== 'todos' && respEfetivo !== 'meus' && i.responsavelId !== respEfetivo) return false;
      if (sinal !== 'todos' && !i.sinais.includes(sinal)) return false;
      if (q) {
        const c = contatoPorId.get(i.contatoId);
        if (!`${c?.nome} ${c?.email} ${c?.telefone}`.toLowerCase().includes(q)) return false;
      }
      return true;
    });
    return ordenarFila(filtrados);
  }, [itens, faixa, status, respEfetivo, sinal, busca, sessao, contatoPorId]);

  const numeros = useMemo(() => numerosFila(itens), [itens]);

  // Filtros secundários (fora a faixa e a busca), para o contador do botão "Filtros" no celular.
  const nFiltros = (respEfetivo !== respPadrao ? 1 : 0) + (status !== 'todos' ? 1 : 0) + (sinal !== 'todos' ? 1 : 0);
  const algumFiltro = nFiltros > 0 || faixa !== 'todas' || !!busca.trim();

  function limparFiltros() {
    setFaixa('todas'); setStatus('todos'); setResp(null); setSinal('todos'); setBusca('');
  }

  async function mudarStatus(it: ItemFila, novo: StatusFila) {
    if (!fila || novo === it.status) return;
    const r = await repo.atualizarItemFila(fila.id, it.id, novo);
    if (!r.ok) { flash(r.msg ?? 'Não foi possível salvar.'); return; }
    flash(`Status: ${ROTULO_STATUS_FILA[novo]}`);
    avisarMudanca();
  }

  function abrirScript(id: string) {
    setSelecionado(id);
    setScript(true);
    // No celular e em telas médias o painel fica abaixo da lista: leva até ele.
    requestAnimationFrame(() => painelRef.current?.scrollIntoView({ block: 'nearest', behavior: 'smooth' }));
  }

  const itemSel = selecionado ? itens.find((i) => i.id === selecionado) : undefined;
  const leadSel = itemSel ? { id: itemSel.id, nome: contatoPorId.get(itemSel.contatoId)?.nome ?? '{Nome}', sinais: itemSel.sinais } : null;
  const eu = vendedores.find((v) => v.id === sessao?.vendedorId);
  const evento = fila ? fila.nome.split(' · ')[0] : '';
  const erro = erroFilas ?? erroContatos;

  const linhas = visiveis.map((it) => {
    const c = contatoPorId.get(it.contatoId);
    const liberado = faixaLiberada(it.faixa, pendAB);
    const podeEditar = gestor || it.responsavelId === sessao?.vendedorId;
    const travaMotivo = semOferta
      ? 'Sem oferta definida: a área não aborda.'
      : !liberado
        ? `Faixa ${it.faixa} ${TRAVA_CD.toLowerCase()}`
        : !podeEditar
          ? (leitor ? 'Acesso só de leitura.' : 'Só o responsável da carteira (ou o gestor) muda o status.')
          : null;
    return { it, c, liberado, travaMotivo };
  });

  const botaoScript = (
    <Button size="sm" variant={script ? 'subtle' : 'ghost'} aria-pressed={script} onClick={() => setScript((s) => !s)}>
      <Icon name="message" size={14} /> Script de abordagem
    </Button>
  );
  const corpo = (
    <>
      {erro && (!filas || !contatos) ? (
        <EstadoErro mensagem={erro} onTentar={() => { recFilas(); recContatos(); }} />
      ) : !filas || !contatos ? (
        <CarregandoFila />
      ) : !fila ? (
        <Vazio titulo="Nenhuma fila de recuperação" icone="inbox" hint="A fila é montada pelo Fechamento quando o carrinho de um lançamento fecha." />
      ) : (
        <div className="space-y-4">
          {/* Fila + oferta vigente numa linha: o que se oferece hoje fica à vista sem empurrar a lista. */}
          <div className="flex flex-wrap items-center gap-x-4 gap-y-2">
            <label className="inline-flex min-w-0 items-center gap-2 text-xs text-[var(--fg-3)]">
              <span>Fila</span>
              <FilterSelect value={fila.id} onChange={(e) => { setFilaId(e.target.value); setSelecionado(null); }} className="min-w-0 max-w-full sm:min-w-[260px]">
                {filas.map((f) => <option key={f.id} value={f.id}>{f.nome} · {produtoDe(f.produto).nome} · {fmtData(f.criadaEm)}</option>)}
              </FilterSelect>
            </label>
            <span className="text-xs text-[var(--fg-3)]">{produtoDe(fila.produto).nome} · montada em {fmtData(fila.criadaEm)}</span>
            {fila.ofertaVigente && (
              <span className="inline-flex min-w-0 items-center gap-2 text-sm" title="O preço só sai quando a pessoa pergunta, e na hora. Sem prazo, vaga ou lote inventado.">
                <Icon name="target" size={14} className="shrink-0 text-[var(--fg-3)]" />
                <span className="text-xs text-[var(--fg-3)]">Oferta vigente</span>
                <span className="font-medium text-[var(--fg)] truncate">{fila.ofertaVigente}</span>
              </span>
            )}
          </div>

          {semOferta && (
            <Aviso tom="danger" icone="lock" titulo="Sem oferta definida, a área não aborda.">
              Não se inventa prazo, vaga nem lote. O Fechamento define a oferta do dia antes de qualquer contato; até lá, os status ficam travados.
            </Aviso>
          )}

          <FaixaNumeros
            itens={[
              { rotulo: 'Na fila', valor: numeros.total, info: INFO_FILA.naFila },
              { rotulo: 'Em trabalho', valor: numeros.emTrabalho, info: INFO_FILA.emTrabalho },
              { rotulo: 'Ganhos', valor: numeros.ganhos, info: INFO_FILA.ganhos },
              { rotulo: 'Recuperação', valor: `${numeros.taxa.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`, info: INFO_FILA.taxa },
              {
                rotulo: 'Sem retorno',
                valor: numeros.semRetorno,
                alerta: numeros.semRetorno > 0,
                info: INFO_FILA.semRetorno,
                ativo: sinal === 'respondeu_sem_retorno',
                onClick: () => setSinal((s) => (s === 'respondeu_sem_retorno' ? 'todos' : 'respondeu_sem_retorno')),
              },
            ]}
          />

          <div className="space-y-2">
            <div className="flex flex-wrap items-center gap-2">
              <span className="inline-flex max-w-full items-center gap-1">
                <Segmentado
                  rotulo="Faixa"
                  valor={faixa}
                  onChange={setFaixa}
                  className="min-w-0 max-w-full overflow-x-auto"
                  opcoes={[
                    { valor: 'todas', rotulo: <>Todas <span className="tabular text-[var(--fg-3)]">{numeros.total}</span></> },
                    ...FAIXAS.map((f) => {
                      const travada = !faixaLiberada(f, pendAB);
                      const { total, aAbordar } = numeros.porFaixa[f];
                      return {
                        valor: f,
                        title: travada
                          ? `Faixa ${f}: ${total} na fila, ${aAbordar} a abordar. ${TRAVA_CD} Ainda há ${pendAB} de A e B em "A abordar".`
                          : `Faixa ${f}: ${total} na fila, ${aAbordar} a abordar.${f === 'A' || f === 'B' ? ' Prioridade: zerar antes de C e D.' : ''}`,
                        rotulo: (
                          <>
                            {f} <span className="tabular text-[var(--fg-3)]">{total}</span>
                            {travada && <><Icon name="lock" size={12} className="text-[var(--fg-3)]" /><span className="sr-only">, travada</span></>}
                          </>
                        ),
                      };
                    }),
                  ]}
                />
                <InfoIndicador texto={INFO_FILA.faixas} />
              </span>
              <div className="min-w-0 flex-1 basis-full sm:basis-60">
                <SearchInput placeholder="Buscar por nome, e-mail ou telefone" value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} />
              </div>
              <Button
                size="sm"
                variant="ghost"
                className="md:hidden min-h-8"
                aria-expanded={filtrosAbertos}
                aria-controls="recuperacao-filtros"
                onClick={() => setFiltrosAbertos((v) => !v)}
              >
                <Icon name="sliders" size={13} /> Filtros{nFiltros ? <span className="tabular"> · {nFiltros}</span> : null}
              </Button>
            </div>
            <div id="recuperacao-filtros" className={filtrosAbertos ? 'block' : 'hidden md:block'}>
              <Toolbar>
                <FilterSelect value={respEfetivo} onChange={(e) => setResp(e.target.value)} aria-label="Responsável">
                  <option value="meus">Minha carteira</option>
                  <option value="todos">Todos os responsáveis</option>
                  {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
                </FilterSelect>
                <FilterSelect value={status} onChange={(e) => setStatus(e.target.value as FiltroStatus)} aria-label="Status">
                  <option value="todos">Todos os status</option>
                  <option value="em_trabalho">Em trabalho (não encerrados)</option>
                  {[...STATUS_FILA_CAMINHO, ...STATUS_FILA_SAIDA].map((s) => <option key={s} value={s}>{ROTULO_STATUS_FILA[s]}</option>)}
                </FilterSelect>
                <FilterSelect value={sinal} onChange={(e) => setSinal(e.target.value as SinalRecuperacao | 'todos')} aria-label="Sinal">
                  <option value="todos">Todos os sinais</option>
                  {(Object.keys(ROTULO_SINAL) as SinalRecuperacao[]).map((s) => <option key={s} value={s}>{ROTULO_SINAL[s]}</option>)}
                </FilterSelect>
                {algumFiltro && <Button size="sm" variant="ghost" onClick={limparFiltros}>Limpar filtros</Button>}
              </Toolbar>
            </div>
          </div>

          <div className={script ? 'grid gap-4 xl:grid-cols-[minmax(0,1fr)_380px] items-start' : ''}>
            <div className="min-w-0">
              {!visiveis.length ? (
                <Vazio
                  titulo="Ninguém nesta visão"
                  hint={respEfetivo === 'meus' ? 'Sua carteira está vazia com estes filtros.' : 'Nenhuma pessoa bate com estes filtros.'}
                  acao={respEfetivo === 'meus' && !algumFiltro
                    ? <Button size="sm" variant="ghost" onClick={() => setResp('todos')}>Ver todos os responsáveis</Button>
                    : algumFiltro ? <Button size="sm" variant="ghost" onClick={limparFiltros}>Limpar filtros</Button> : undefined}
                />
              ) : (
                <ListaFila>
                  {linhas.map(({ it, c, liberado, travaMotivo }) => (
                    <ItemFilaLinha
                      key={it.id}
                      it={it}
                      c={c}
                      liberado={liberado}
                      travaMotivo={travaMotivo}
                      nomeDe={nomeDe}
                      ativo={it.id === selecionado}
                      onContato={() => setContatoAberto(it.contatoId)}
                      onScript={() => abrirScript(it.id)}
                      onStatus={(s) => mudarStatus(it, s)}
                    />
                  ))}
                </ListaFila>
              )}
              <p className="mt-2 text-[11px] leading-relaxed text-[var(--fg-3)]">
                Ordem: {GRUPOS_ORDEM.map((g) => `${g.n}) ${g.rotulo}`).join(' · ')}. Dentro de cada grupo, score maior primeiro. Encerrados no fim.
                {fila.ofertaVigente && ' O preço só sai quando a pessoa pergunta, e na hora; sem prazo, vaga ou lote inventado.'}
              </p>
            </div>
            {script && (
              <div ref={painelRef} className="xl:sticky xl:top-4 mt-4 xl:mt-0 scroll-mt-4">
                <ScriptAbordagem
                  lead={leadSel}
                  vendedor={eu?.nome ?? '{Vendedor}'}
                  evento={evento}
                  ofertaVigente={fila.ofertaVigente}
                  onFechar={() => setScript(false)}
                />
              </div>
            )}
          </div>
        </div>
      )}
      {contatoAberto && <ContatoDrawer contatoId={contatoAberto} onClose={() => setContatoAberto(null)} onAbrirContato={setContatoAberto} />}
      <Toast>{toast}</Toast>
    </>
  );

  if (embutido) {
    return (
      <div className="min-w-0 space-y-3">
        <div className="flex flex-wrap items-center justify-between gap-2">
          <p className="text-sm text-[var(--fg-3)]">Filas pós-lançamento, na ordem do playbook: quem respondeu sem retorno vem primeiro.</p>
          {botaoScript}
        </div>
        {corpo}
      </div>
    );
  }
  return (
    <PaginaComercial
      titulo="Filas de recuperação"
      subtitulo="Filas pós-lançamento, na ordem do playbook: quem respondeu sem retorno vem primeiro."
      acoes={botaoScript}
    >
      {corpo}
    </PaginaComercial>
  );
}

function CarregandoFila() {
  return (
    <div className="space-y-4" aria-busy="true" aria-label="Carregando a fila">
      <div className="h-10 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] animate-pulse" />
      <EsqueletoLista linhas={8} />
    </div>
  );
}

interface PropsLinha {
  it: ItemFila; c: Contato | undefined; liberado: boolean; travaMotivo: string | null;
  nomeDe: (id: string | null) => string; ativo: boolean;
  onContato: () => void; onScript: () => void; onStatus: (s: StatusFila) => void;
}

/** Nome da pessoa como botão (abre a ficha do contato); cadeado único quando a faixa está travada. */
function NomePessoa({ it, c, liberado, onContato }: Pick<PropsLinha, 'it' | 'c' | 'liberado' | 'onContato'>) {
  const nome = c?.nome ?? '—';
  return (
    <div className="flex items-center gap-2 min-w-0">
      <button
        type="button"
        onClick={onContato}
        aria-label={`Abrir ficha de ${nome}`}
        className="min-w-0 rounded-[var(--r-sm)] text-left focus-visible:outline-2 focus-visible:outline-[var(--accent)]"
      >
        <Pessoa nome={nome} sub={fmtTelefone(c?.telefone)} size={28} />
      </button>
      {!liberado && (
        <span title={`Faixa ${it.faixa} ${TRAVA_CD.toLowerCase()}`} className="shrink-0 text-[var(--fg-3)]">
          <Icon name="lock" size={13} />
          <span className="sr-only">Travado</span>
        </span>
      )}
    </div>
  );
}

function Sinais({ sinais }: { sinais: SinalRecuperacao[] }) {
  if (!sinais.length) return <span className="text-xs text-[var(--fg-3)]">—</span>;
  return (
    <span className="text-xs leading-relaxed text-[var(--fg-2)]">
      {sinais.map((s, i) => (
        <span key={s}>
          {i > 0 && ' · '}
          <span className={s === 'respondeu_sem_retorno' ? 'font-medium text-[var(--red)]' : undefined}>{ROTULO_SINAL[s]}</span>
        </span>
      ))}
    </span>
  );
}

function FaixaScoreTexto({ it }: { it: ItemFila }) {
  return (
    <span className="whitespace-nowrap text-sm" title={`Faixa ${it.faixa}, score ${it.score} de 100`}>
      <span className="font-semibold text-[var(--fg)]">{it.faixa}</span>
      <span className="ml-1.5 tabular text-[var(--fg-2)]">{it.score}</span>
    </span>
  );
}

/** Select do status; "Alterado por…" e o motivo da trava vão no title (sem badge duplicado). */
function SelectStatus({ it, c, travaMotivo, nomeDe, onStatus }: Pick<PropsLinha, 'it' | 'c' | 'travaMotivo' | 'nomeDe' | 'onStatus'>) {
  const alterado = it.alteradoEm ? `Alterado por ${nomeDe(it.alteradoPor)} em ${fmtDataHora(it.alteradoEm)}` : 'Sem alteração';
  return (
    <span title={travaMotivo ? `${travaMotivo} ${alterado}.` : `${alterado}.`} className="block">
      <FilterSelect
        value={it.status}
        disabled={!!travaMotivo}
        onChange={(e) => onStatus(e.target.value as StatusFila)}
        aria-label={`Status de ${c?.nome ?? 'pessoa'}`}
        className="!py-1 !text-xs w-full min-w-0"
      >
        <optgroup label="Caminho">
          {STATUS_FILA_CAMINHO.map((s) => <option key={s} value={s}>{ROTULO_STATUS_FILA[s]}</option>)}
        </optgroup>
        <optgroup label="Saídas">
          {STATUS_FILA_SAIDA.map((s) => <option key={s} value={s}>{ROTULO_STATUS_FILA[s]}</option>)}
        </optgroup>
      </FilterSelect>
    </span>
  );
}

function BotaoScript({ c, ativo, onScript }: Pick<PropsLinha, 'c' | 'ativo' | 'onScript'>) {
  return (
    <Button size="sm" variant={ativo ? 'subtle' : 'ghost'} onClick={onScript} aria-label={`Script para ${c?.nome ?? 'esta pessoa'}`}>
      <Icon name="message" size={13} /> Script
    </Button>
  );
}

// Lista sem tabela: em contêiner largo (≥ 768px) vira linha de 6 colunas que sempre cabem (nada de rolagem
// lateral); abaixo disso, cartão empilhado. Medido pelo contêiner, não pela tela: o script aberto ao lado estreita a lista.
const COLUNAS = 'grid-cols-[minmax(0,1.6fr)_76px_minmax(0,1.6fr)_minmax(0,1fr)_minmax(150px,180px)_auto]';

function ListaFila({ children }: { children: React.ReactNode }) {
  return (
    <div className="@container">
      <div aria-hidden className={`hidden @3xl:grid ${COLUNAS} items-center gap-x-3 px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]`}>
        <span>Pessoa</span>
        <span>Faixa · score</span>
        <span>Sinais</span>
        <span>Responsável</span>
        <span>Status</span>
        <span />
      </div>
      <ul className="space-y-2 @3xl:space-y-0 @3xl:divide-y @3xl:divide-[var(--border-faint)] @3xl:rounded-[var(--r-md)] @3xl:border @3xl:border-[var(--border)] @3xl:bg-[var(--surface-2)]">
        {children}
      </ul>
    </div>
  );
}

function ItemFilaLinha(p: PropsLinha) {
  const { it, liberado, nomeDe, ativo } = p;
  const fechado = encerrado(it.status);
  const grupo = GRUPOS_ORDEM[grupoPrioridade(it.sinais) - 1]?.rotulo;
  const apagado = !liberado || fechado ? 'opacity-70' : '';
  return (
    <li className={apagado}>
      {/* Contêiner largo: linha. */}
      <div className={`hidden @3xl:grid ${COLUNAS} items-center gap-x-3 px-3 py-2 ${ativo ? 'bg-[var(--accent-subtle)]' : ''}`}>
        <span title={grupo ? `Grupo da ordem: ${grupo}` : undefined} className="min-w-0"><NomePessoa {...p} /></span>
        <FaixaScoreTexto it={it} />
        <span className="min-w-0"><Sinais sinais={it.sinais} /></span>
        <span className="min-w-0 truncate text-sm text-[var(--fg-2)]">{nomeDe(it.responsavelId)}</span>
        <SelectStatus {...p} />
        <span className="justify-self-end"><BotaoScript {...p} /></span>
      </div>
      {/* Contêiner estreito: cartão. */}
      <div className={`@3xl:hidden rounded-[var(--r-md)] border p-3 ${ativo ? 'border-[var(--accent-border)] bg-[var(--accent-subtle)]' : 'border-[var(--border)] bg-[var(--surface-2)]'}`}>
        <div className="flex items-start justify-between gap-3">
          <NomePessoa {...p} />
          <FaixaScoreTexto it={it} />
        </div>
        <div className="mt-2"><Sinais sinais={it.sinais} /></div>
        <div className="mt-1 text-xs text-[var(--fg-3)]">{nomeDe(it.responsavelId)}</div>
        <div className="mt-3 flex items-center gap-2">
          <div className="min-w-0 flex-1"><SelectStatus {...p} /></div>
          <BotaoScript {...p} />
        </div>
      </div>
    </li>
  );
}
