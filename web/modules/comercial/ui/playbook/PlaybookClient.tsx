'use client';

// Central de ajuda do Comercial: como usar o sistema (módulo a módulo) + o playbook de vendas, num lugar só.
// Busca no topo em todo o conteúdo, uma parte por vez (Comece aqui, Como funciona, Módulos, Playbook, Perguntas,
// Glossário), seções em sanfona com âncora própria (#modulo-funil) e atalho para a tela de cada assunto.
// O texto mora em ajuda-conteudo.ts e conteudo.ts; esta tela só desenha.
import Link from 'next/link';
import { useCallback, useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Badge, Button, FilterSelect, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { FaixaNumeros, PaginaComercial, Vazio } from '../comum';
import { BlocoPlaybook, TextoRico } from './Blocos';
import { buscarSecoes, resumoConteudo, termoValido } from './busca';
import { SECOES, SELO } from './conteudo';
import {
  BUSCAS_SUGERIDAS, CENTRAL, PARTES, PRIMEIRO_DIA, parte as dadosParte, secoesDaParte,
  type ParteKey, type SecaoAjuda,
} from './ajuda-conteudo';

const RESUMO_PLAYBOOK = resumoConteudo(SECOES);
/** Partes que já abrem com todas as seções à mostra (leitura corrida). As outras abrem recolhidas. */
const ABERTAS_DE_INICIO: ParteKey[] = ['comece', 'sistema'];

/** Para onde o endereço (#...) aponta: uma seção, o começo de uma parte, ou nada. */
function lerAncora(hash: string): { parte: ParteKey; secao: string | null } | null {
  const id = decodeURIComponent(hash.replace('#', ''));
  if (!id) return null;
  const p = PARTES.find((x) => x.ancora === id);
  if (p) return { parte: p.key, secao: null };
  const s = CENTRAL.find((x) => x.id === id);
  return s ? { parte: s.parte, secao: s.id } : null;
}

export function PlaybookClient() {
  const [busca, setBusca] = useState('');
  const consulta = termoValido(useDeferredValue(busca));
  const buscando = consulta !== '';
  const [parteAtual, setParteAtual] = useState<ParteKey>('comece');
  const [abertas, setAbertas] = useState<Set<string>>(() => new Set(secoesDaParte('comece').map((s) => s.id)));
  const [ativa, setAtiva] = useState<string | null>(null);
  /** Palavra que segue destacada no texto depois de abrir um resultado da busca. */
  const [destaque, setDestaque] = useState('');

  const achados = useMemo(() => buscarSecoes(CENTRAL, consulta), [consulta]);
  const secoes = secoesDaParte(parteAtual);

  const rolarPara = (id: string, suave = true) => {
    requestAnimationFrame(() => {
      const el = document.getElementById(id);
      el?.scrollIntoView({ behavior: suave ? 'smooth' : 'auto', block: 'start' });
      // Leva o foco junto (teclado e leitor de tela chegam onde o olho chegou).
      el?.focus({ preventScroll: true });
    });
  };

  const abrirParte = useCallback((p: ParteKey, secao: string | null) => {
    setParteAtual(p);
    const todas = secoesDaParte(p).map((s) => s.id);
    setAbertas(new Set(ABERTAS_DE_INICIO.includes(p) ? todas : secao ? [secao] : []));
    setAtiva(secao);
  }, []);

  // Link com #secao ou #parte (de outra tela, do Slack, do voltar do navegador): abre direto lá.
  useEffect(() => {
    const seguir = () => {
      const alvo = lerAncora(window.location.hash);
      if (!alvo) return;
      setBusca('');
      setDestaque('');
      abrirParte(alvo.parte, alvo.secao);
      rolarPara(alvo.secao ?? 'central-conteudo', false);
    };
    seguir();
    window.addEventListener('hashchange', seguir);
    return () => window.removeEventListener('hashchange', seguir);
  }, [abrirParte]);

  // Seção que está na tela marca o item do sumário.
  useEffect(() => {
    if (buscando) return;
    const els = secoes.map((s) => document.getElementById(s.id)).filter((e): e is HTMLElement => !!e);
    const obs = new IntersectionObserver((entradas) => {
      const visivel = entradas.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
      if (visivel) setAtiva(visivel.target.id);
    }, { rootMargin: '-15% 0px -70% 0px' });
    els.forEach((e) => obs.observe(e));
    return () => obs.disconnect();
  }, [secoes, buscando]);

  /** Vai para uma seção (de qualquer parte) e a deixa aberta. */
  const irSecao = (id: string, manterDestaque?: string) => {
    const s = CENTRAL.find((x) => x.id === id);
    if (!s) return;
    if (s.parte !== parteAtual) abrirParte(s.parte, id);
    else setAbertas((a) => (a.has(id) ? a : new Set(a).add(id)));
    setAtiva(id);
    setBusca('');
    setDestaque(manterDestaque ?? '');
    window.history.replaceState(null, '', `#${id}`);
    rolarPara(id);
  };

  /** Vai para o começo de uma parte. */
  const irParte = (p: ParteKey) => {
    abrirParte(p, null);
    setBusca('');
    setDestaque('');
    window.history.replaceState(null, '', `#${dadosParte(p).ancora}`);
    rolarPara('central-conteudo');
  };

  /** Link interno do conteúdo (#id) vira navegação da central; link de tela segue normal. */
  const onLinkInterno = (href: string) => {
    const alvo = lerAncora(href);
    if (!alvo) return false;
    if (alvo.secao) irSecao(alvo.secao); else irParte(alvo.parte);
    return true;
  };

  const alternar = (id: string) => setAbertas((a) => {
    const n = new Set(a);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });
  const todasAbertas = secoes.every((s) => abertas.has(s.id));
  const idxParte = PARTES.findIndex((p) => p.key === parteAtual);
  const proxima = PARTES[idxParte + 1];
  const anterior = PARTES[idxParte - 1];
  const infoParte = dadosParte(parteAtual);

  return (
    <PaginaComercial
      titulo="Central de ajuda"
      subtitulo="Como usar o sistema do Comercial e o playbook de vendas, num lugar só."
    >
      {/* ── Busca ── */}
      <section aria-labelledby="central-busca-titulo" className="mb-5 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] px-4 py-4 sm:px-5">
        <h2 id="central-busca-titulo" className="text-base font-semibold text-[var(--fg)]">Como podemos ajudar?</h2>
        <p className="mt-0.5 mb-3 text-sm text-[var(--fg-3)]">Escreva do seu jeito. A busca olha o sistema, o playbook, as perguntas e o glossário.</p>
        <div role="search" className="flex">
          <SearchInput
            value={busca}
            onChange={(e) => setBusca(e.target.value)}
            onLimpar={() => setBusca('')}
            onKeyDown={(e) => { if (e.key === 'Enter' && achados[0]) irSecao(achados[0].secao.id, consulta); }}
            placeholder="Ex.: como mover um negócio, motivo de perda, disparo, objeção de preço"
            aria-label="Buscar na central de ajuda"
            aria-describedby="central-busca-status"
            className="!min-h-11 !text-base sm:!text-sm"
          />
        </div>
        {!buscando && (
          <div className="mt-3 flex flex-wrap items-center gap-1.5">
            <span className="text-xs text-[var(--fg-3)]">Mais buscados:</span>
            {BUSCAS_SUGERIDAS.map((b) => (
              <button
                key={b}
                type="button"
                onClick={() => setBusca(b)}
                className="inline-flex items-center rounded-[var(--r-pill)] border border-[var(--border)] px-2.5 min-h-7 text-xs text-[var(--fg-2)] transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]"
              >
                {b}
              </button>
            ))}
          </div>
        )}
        <p id="central-busca-status" className="sr-only" aria-live="polite">
          {buscando ? `${achados.length} ${achados.length === 1 ? 'resultado' : 'resultados'} para ${consulta}` : ''}
        </p>
      </section>

      {buscando ? (
        <ResultadosBusca consulta={consulta} achados={achados} onAbrir={(id) => irSecao(id, consulta)} onLimpar={() => setBusca('')} onSugestao={setBusca} />
      ) : (
        <>
          <PortaDeEntrada parteAtual={parteAtual} onParte={irParte} onSecao={(id) => irSecao(id)} />

          <div className="lg:grid lg:grid-cols-[230px_minmax(0,1fr)] lg:gap-8">
            <Sumario parteAtual={parteAtual} ativa={ativa} onParte={irParte} onSecao={(id) => irSecao(id)} />

            <div id="central-conteudo" tabIndex={-1} className="min-w-0 max-w-[78ch] scroll-mt-4 outline-none">
              {/* Celular: o sumário vira um seletor fixo no topo. */}
              <div className="lg:hidden sticky top-0 z-10 -mx-1 mb-3 bg-[var(--surface-0)] px-1 py-2">
                <label className="block">
                  <span className="sr-only">Ir para</span>
                  <FilterSelect
                    value={ativa ?? `parte:${parteAtual}`}
                    onChange={(e) => {
                      const v = e.target.value;
                      if (v.startsWith('parte:')) irParte(v.slice(6) as ParteKey); else irSecao(v);
                    }}
                    className="w-full"
                  >
                    {PARTES.map((p) => (
                      <optgroup key={p.key} label={p.titulo}>
                        <option value={`parte:${p.key}`}>{p.titulo}: início</option>
                        {secoesDaParte(p.key).map((s) => <option key={s.id} value={s.id}>{s.titulo}</option>)}
                      </optgroup>
                    ))}
                  </FilterSelect>
                </label>
              </div>

              <header className="mb-3">
                <p className="text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">Parte {idxParte + 1} de {PARTES.length}</p>
                <h2 className="mt-0.5 flex items-center gap-2 text-lg font-bold text-[var(--fg)]">
                  <Icon name={infoParte.icone} size={18} className="shrink-0 text-[var(--fg-3)]" />
                  {infoParte.titulo}
                </h2>
                <p className="mt-0.5 text-sm text-[var(--fg-2)]">{infoParte.descricao}</p>
              </header>

              {parteAtual === 'playbook' && (
                <div className="mb-4 space-y-2">
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[var(--fg-3)]">
                    <Badge tone="info">{SELO.versao} · {SELO.validacao}</Badge>
                    <span>{SELO.fonte}</span>
                  </div>
                  <p className="text-xs text-[var(--fg-3)]">{SELO.data}</p>
                  <FaixaNumeros
                    discreta
                    rotulo="O playbook em números"
                    itens={[
                      { rotulo: 'Seções', valor: RESUMO_PLAYBOOK.secoes - 1, info: { nome: 'Seções do playbook', oQueE: 'Quantas seções o playbook de vendas tem nesta parte. O glossário do playbook mora na parte "Glossário".', comoConta: 'Contado do próprio conteúdo do playbook.', paraQue: 'Ter noção do tamanho; use o sumário ou a busca para ir direto ao assunto.' } },
                      { rotulo: 'Scripts prontos', valor: RESUMO_PLAYBOOK.scripts, info: { nome: 'Scripts prontos', oQueE: 'Mensagens prontas para copiar: abordagem, qualificação, objeções, recuperação e acompanhamento de MQL.', comoConta: 'Cada bloco de mensagem com botão "Copiar" conta um.', paraQue: 'Falar com o lead nas palavras aprovadas, trocando só o que está entre chaves.' } },
                      { rotulo: 'Trechos a definir', valor: RESUMO_PLAYBOOK.pendencias, info: { nome: 'Trechos a definir', oQueE: 'Trechos marcados como a definir, a validar, a revisar ou a escrever. Enquanto estão assim, a regra ainda não vale.', comoConta: 'Cada marcação no texto conta uma (o selo "em validação" não entra).', paraQue: 'Saber o que ainda depende de decisão antes de tratar como regra.' } },
                      { rotulo: 'Pontos em aberto', valor: RESUMO_PLAYBOOK.emAberto, info: { nome: 'Pontos em aberto', oQueE: 'Decisões pendentes do Comercial, cada uma com quem decide.', comoConta: 'Linhas da tabela da seção "O que ainda está em aberto".', paraQue: 'Cobrar a decisão de quem decide.', meta: 'Zero, à medida que o Jonathan valida o playbook.' } },
                    ]}
                  />
                </div>
              )}

              {destaque && (
                <div className="mb-3 flex flex-wrap items-center gap-2 text-xs text-[var(--fg-3)]">
                  <span>Destacando <mark className="rounded-[2px] bg-[var(--yellow-subtle)] px-1 text-[var(--fg)] ring-1 ring-[var(--yellow-border)]">{destaque}</mark> no texto.</span>
                  <button type="button" onClick={() => setDestaque('')} className="underline hover:text-[var(--fg)]">Tirar destaque</button>
                </div>
              )}

              <div className="mb-3 flex justify-end">
                <Button size="sm" variant="ghost" onClick={() => setAbertas(todasAbertas ? new Set() : new Set(secoes.map((s) => s.id)))}>
                  <Icon name={todasAbertas ? 'chevron-up' : 'chevron-down'} size={14} /> {todasAbertas ? 'Recolher tudo' : 'Abrir tudo'}
                </Button>
              </div>

              <div className="space-y-3">
                {secoes.map((s, i) => {
                  const sub = s.subgrupo && s.subgrupo !== secoes[i - 1]?.subgrupo ? s.subgrupo : null;
                  return (
                    <div key={s.id}>
                      {sub && <p className="mb-2 mt-5 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)] first:mt-0">{sub}</p>}
                      <SecaoAjudaView secao={s} termo={destaque} aberta={abertas.has(s.id)} onAlternar={() => alternar(s.id)} onLinkInterno={onLinkInterno} />
                    </div>
                  );
                })}
              </div>

              <nav aria-label="Navegar entre as partes" className="mt-6 grid gap-2 sm:grid-cols-2">
                {anterior ? (
                  <button type="button" onClick={() => irParte(anterior.key)} className="rounded-[var(--r-lg)] border border-[var(--border)] px-4 py-3 text-left transition-colors hover:bg-[var(--surface-2)]">
                    <span className="flex items-center gap-1 text-xs text-[var(--fg-3)]"><Icon name="arrow-left" size={12} /> Parte anterior</span>
                    <span className="block text-sm font-semibold text-[var(--fg)]">{anterior.titulo}</span>
                  </button>
                ) : <span className="hidden sm:block" />}
                {proxima && (
                  <button type="button" onClick={() => irParte(proxima.key)} className="rounded-[var(--r-lg)] border border-[var(--border)] px-4 py-3 text-right transition-colors hover:bg-[var(--surface-2)]">
                    <span className="flex items-center justify-end gap-1 text-xs text-[var(--fg-3)]">Próxima parte <Icon name="arrow-right" size={12} /></span>
                    <span className="block text-sm font-semibold text-[var(--fg)]">{proxima.titulo}</span>
                  </button>
                )}
              </nav>
            </div>
          </div>
        </>
      )}
    </PaginaComercial>
  );
}

/** Cartões das seis partes + os dois guias de primeiro dia. */
function PortaDeEntrada({ parteAtual, onParte, onSecao }: {
  parteAtual: ParteKey; onParte: (p: ParteKey) => void; onSecao: (id: string) => void;
}) {
  return (
    <div className="mb-6 space-y-3">
      <div className="grid gap-2 sm:grid-cols-2">
        {PRIMEIRO_DIA.map((g) => (
          <button
            key={g.id}
            type="button"
            onClick={() => onSecao(g.id)}
            className="group flex items-start gap-3 rounded-[var(--r-lg)] border border-[var(--border-accent)] bg-[var(--accent-subtle)] px-4 py-3 text-left transition-colors hover:bg-[var(--surface-3)]"
          >
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[var(--surface-1)] text-[var(--fg)]"><Icon name={g.icone} size={17} /></span>
            <span className="min-w-0">
              <span className="block text-sm font-semibold text-[var(--fg)]">{g.titulo}</span>
              <span className="block text-xs leading-relaxed text-[var(--fg-2)]">{g.texto}</span>
            </span>
            <Icon name="arrow-right" size={14} className="ml-auto mt-1 shrink-0 text-[var(--fg-3)] transition-transform group-hover:translate-x-0.5" />
          </button>
        ))}
      </div>
      <nav aria-label="Partes da central de ajuda">
        <ul className="grid gap-2 grid-cols-2 md:grid-cols-3">
          {PARTES.map((p) => {
            const sel = p.key === parteAtual;
            return (
              <li key={p.key} className="min-w-0">
                <button
                  type="button"
                  onClick={() => onParte(p.key)}
                  aria-current={sel ? 'true' : undefined}
                  className={`flex h-full w-full items-start gap-2.5 rounded-[var(--r-lg)] border px-3 py-2.5 text-left transition-colors ${
                    sel ? 'border-[var(--border-accent)] bg-[var(--surface-3)]' : 'border-[var(--border)] bg-[var(--surface-1)] hover:bg-[var(--surface-2)]'
                  }`}
                >
                  <Icon name={p.icone} size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
                  <span className="min-w-0">
                    <span className="block text-sm font-semibold leading-snug text-[var(--fg)]">{p.titulo}</span>
                    <span className="hidden sm:block text-xs leading-snug text-[var(--fg-3)]">{p.chamada}</span>
                    <span className="block text-[11px] tabular text-[var(--fg-3)] sm:hidden">{secoesDaParte(p.key).length} tópicos</span>
                  </span>
                </button>
              </li>
            );
          })}
        </ul>
      </nav>
    </div>
  );
}

/** Sumário lateral fixo (telas largas): as seis partes; a parte aberta mostra os tópicos. */
function Sumario({ parteAtual, ativa, onParte, onSecao }: {
  parteAtual: ParteKey; ativa: string | null; onParte: (p: ParteKey) => void; onSecao: (id: string) => void;
}) {
  return (
    <nav aria-label="Sumário da central de ajuda" className="hidden lg:block sticky top-0 self-start max-h-[calc(100dvh-var(--header-height)-48px)] overflow-y-auto pr-1">
      <ul className="space-y-1">
        {PARTES.map((p) => {
          const aberta = p.key === parteAtual;
          const lista = secoesDaParte(p.key);
          return (
            <li key={p.key}>
              <a
                href={`#${p.ancora}`}
                onClick={(e) => { e.preventDefault(); onParte(p.key); }}
                aria-current={aberta && !ativa ? 'location' : undefined}
                className={`flex items-center gap-2 rounded-[var(--r-sm)] px-2 py-1.5 text-[13px] transition-colors ${
                  aberta ? 'font-semibold text-[var(--fg)]' : 'text-[var(--fg-2)] hover:bg-[var(--surface-2)] hover:text-[var(--fg)]'
                }`}
              >
                <Icon name={p.icone} size={14} className="shrink-0 text-[var(--fg-3)]" />
                <span className="min-w-0 flex-1">{p.titulo}</span>
                <span className="shrink-0 text-[11px] font-normal tabular text-[var(--fg-3)]">{lista.length}</span>
              </a>
              {aberta && (
                <ul className="mb-2 ml-3">
                  {lista.map((s, i) => {
                    const sel = s.id === ativa;
                    const sub = s.subgrupo && s.subgrupo !== lista[i - 1]?.subgrupo ? s.subgrupo : null;
                    return (
                      <li key={s.id}>
                        {sub && <p className="mt-2 mb-0.5 px-2 text-[10px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{sub}</p>}
                        <a
                          href={`#${s.id}`}
                          aria-current={sel ? 'location' : undefined}
                          onClick={(e) => { e.preventDefault(); onSecao(s.id); }}
                          className={`flex items-center gap-1.5 border-l-2 px-2 py-1 text-[13px] leading-snug transition-colors ${
                            sel ? 'border-[var(--accent)] font-medium text-[var(--fg)]' : 'border-[var(--border-faint)] text-[var(--fg-2)] hover:text-[var(--fg)]'
                          }`}
                        >
                          <span className="min-w-0">{s.titulo}</span>
                          {s.emBreve && <span className="shrink-0 text-[10px] text-[var(--fg-3)]">em breve</span>}
                        </a>
                      </li>
                    );
                  })}
                </ul>
              )}
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function ResultadosBusca({ consulta, achados, onAbrir, onLimpar, onSugestao }: {
  consulta: string;
  achados: ReturnType<typeof buscarSecoes<SecaoAjuda>>;
  onAbrir: (id: string) => void;
  onLimpar: () => void;
  onSugestao: (b: string) => void;
}) {
  if (achados.length === 0) {
    return (
      <div>
        <Vazio
          icone="search"
          titulo="Nada encontrado"
          hint={`Nenhum assunto fala de "${consulta}". Tente uma palavra só, ou um dos assuntos abaixo.`}
          acao={<Button size="sm" variant="ghost" onClick={onLimpar}><Icon name="x" size={14} /> Limpar busca</Button>}
        />
        <div className="-mt-6 flex flex-wrap justify-center gap-1.5">
          {BUSCAS_SUGERIDAS.map((b) => (
            <button key={b} type="button" onClick={() => onSugestao(b)} className="rounded-[var(--r-pill)] border border-[var(--border)] px-2.5 min-h-7 text-xs text-[var(--fg-2)] hover:bg-[var(--surface-3)]">{b}</button>
          ))}
        </div>
      </div>
    );
  }
  return (
    <section aria-labelledby="central-resultados" className="max-w-[90ch]">
      <h2 id="central-resultados" className="mb-3 text-sm text-[var(--fg-2)]">
        <span className="font-semibold text-[var(--fg)]">{achados.length} {achados.length === 1 ? 'assunto' : 'assuntos'}</span> sobre &quot;{consulta}&quot;. Os mais certeiros primeiro.
      </h2>
      <ol className="space-y-2">
        {achados.map(({ secao: s, trecho }) => {
          const p = dadosParte(s.parte);
          return (
            <li key={s.id}>
              <button
                type="button"
                onClick={() => onAbrir(s.id)}
                className="group block w-full rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] px-4 py-3 text-left transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-2)]"
              >
                <span className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-[var(--fg-3)]">
                  <Icon name={p.icone} size={12} />
                  <span>{p.titulo}{s.subgrupo ? ` · ${s.subgrupo}` : ''}</span>
                  {s.emBreve && <Badge>em breve</Badge>}
                </span>
                <span className="mt-0.5 flex items-center gap-2 text-sm font-semibold text-[var(--fg)]">
                  <span className="min-w-0"><TextoRico texto={s.titulo} termo={consulta} /></span>
                  <Icon name="arrow-right" size={13} className="shrink-0 text-[var(--fg-3)] transition-transform group-hover:translate-x-0.5" />
                </span>
                {trecho && <span className="mt-1 block text-sm leading-relaxed text-[var(--fg-2)]"><TextoRico texto={trecho} termo={consulta} /></span>}
              </button>
            </li>
          );
        })}
      </ol>
    </section>
  );
}

function SecaoAjudaView({ secao, termo, aberta, onAlternar, onLinkInterno }: {
  secao: SecaoAjuda; termo: string; aberta: boolean; onAlternar: () => void; onLinkInterno: (href: string) => boolean;
}) {
  const idCorpo = `${secao.id}-corpo`;
  const idTitulo = `${secao.id}-titulo`;
  return (
    <section id={secao.id} tabIndex={-1} aria-labelledby={idTitulo} className="scroll-mt-16 lg:scroll-mt-4 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] outline-none">
      {/* Sanfona: o título é o h3 e o botão fica dentro dele (heading dentro de botão é HTML inválido). */}
      <h3 className="m-0">
        <button
          id={idTitulo}
          type="button"
          onClick={onAlternar}
          aria-expanded={aberta}
          aria-controls={idCorpo}
          className="flex w-full items-start gap-3 rounded-[var(--r-lg)] px-4 py-3 text-left transition-colors hover:bg-[var(--surface-2)]"
        >
          {secao.icone && (
            <span className="mt-0.5 grid h-8 w-8 shrink-0 place-items-center rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] text-[var(--fg-2)]">
              <Icon name={secao.icone} size={15} />
            </span>
          )}
          <span className="min-w-0 flex-1">
            <span className="flex flex-wrap items-center gap-2 text-base font-semibold leading-snug text-[var(--fg)]">
              <TextoRico texto={secao.titulo} termo={termo} />
              {secao.emBreve && <Badge>em breve</Badge>}
            </span>
            {secao.resumo && <span className="mt-0.5 block text-xs font-normal leading-relaxed text-[var(--fg-3)]"><TextoRico texto={secao.resumo} termo={termo} /></span>}
          </span>
          <Icon name={aberta ? 'chevron-up' : 'chevron-down'} size={16} className="mt-1 shrink-0 text-[var(--fg-3)]" />
        </button>
      </h3>
      <div id={idCorpo} hidden={!aberta} className="space-y-3 border-t border-[var(--border-faint)] px-4 pb-4 pt-3">
        {aberta && (
          <>
            {secao.ferramentas && secao.ferramentas.length > 0 && (
              <div className="flex flex-wrap items-center gap-2">
                <span className="text-xs text-[var(--fg-3)]">Abrir no sistema:</span>
                {secao.ferramentas.map((f) => (
                  <Link
                    key={f.href}
                    href={f.href}
                    className="inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border border-[var(--border)] px-2.5 min-h-8 text-xs text-[var(--fg-2)] transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]"
                  >
                    {f.rotulo} <Icon name="arrow-up-right" size={12} />
                  </Link>
                ))}
              </div>
            )}
            {secao.blocos.map((b, i) => <BlocoPlaybook key={i} bloco={b} termo={termo} onLinkInterno={onLinkInterno} />)}
          </>
        )}
      </div>
    </section>
  );
}

