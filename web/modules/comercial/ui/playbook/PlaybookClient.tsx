'use client';

// Playbook do Comercial dentro do sistema: sumário fixo (menu no celular), busca com destaque, seções
// recolhíveis, scripts com cópia rápida e atalho para a tela onde cada regra vira ferramenta.
// O texto mora em conteudo.ts (fonte: gp-operacoes); esta tela só desenha.
import Link from 'next/link';
import { useDeferredValue, useEffect, useMemo, useState } from 'react';
import { Badge, Button, FilterSelect, SearchInput } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { FaixaNumeros, PaginaComercial, Vazio } from '../comum';
import { BlocoPlaybook, TextoRico } from './Blocos';
import { resultadosBusca, resumoConteudo, termoValido } from './busca';
import { GRUPOS, SECOES, SELO, type Secao } from './conteudo';

const RESUMO = resumoConteudo(SECOES);

export function PlaybookClient() {
  const [busca, setBusca] = useState('');
  const termo = termoValido(useDeferredValue(busca));
  const [recolhidas, setRecolhidas] = useState<Set<string>>(() => new Set());
  const [ativa, setAtiva] = useState<string>(SECOES[0].id);

  const achados = useMemo(() => resultadosBusca(SECOES, termo), [termo]);
  const buscando = termo !== '';
  const visiveis = buscando ? SECOES.filter((s) => achados.has(s.id)) : SECOES;
  const totalAchados = [...achados.values()].reduce((a, b) => a + b, 0);

  // Link com #secao (vindo de outra tela ou do Slack): leva direto à seção.
  useEffect(() => {
    const id = decodeURIComponent(window.location.hash.replace('#', ''));
    if (id && SECOES.some((s) => s.id === id)) document.getElementById(id)?.scrollIntoView({ block: 'start' });
  }, []);

  // Seção que está na tela marca o item do sumário.
  useEffect(() => {
    const els = SECOES.map((s) => document.getElementById(s.id)).filter((e): e is HTMLElement => !!e);
    const obs = new IntersectionObserver((entradas) => {
      const visivel = entradas.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
      if (visivel) setAtiva(visivel.target.id);
    }, { rootMargin: '-15% 0px -70% 0px' });
    els.forEach((e) => obs.observe(e));
    return () => obs.disconnect();
  }, [termo]);

  const ir = (id: string) => {
    setRecolhidas((r) => { if (!r.has(id)) return r; const n = new Set(r); n.delete(id); return n; });
    setAtiva(id);
    window.history.replaceState(null, '', `#${id}`);
    requestAnimationFrame(() => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' }));
  };

  const alternar = (id: string) => setRecolhidas((r) => {
    const n = new Set(r);
    if (n.has(id)) n.delete(id); else n.add(id);
    return n;
  });
  const todasRecolhidas = recolhidas.size === SECOES.length;

  return (
    <PaginaComercial
      titulo="Playbook do Comercial"
      subtitulo="O que o comercial faz, quem faz e quais regras não se discutem."
      meta={(
        <FaixaNumeros
          rotulo="O playbook em números"
          itens={[
            { rotulo: 'Seções', valor: RESUMO.secoes, info: { nome: 'Seções', oQueE: 'Quantas seções o playbook tem nesta tela, das regras do departamento aos processos das três áreas.', comoConta: 'Contado do próprio conteúdo do playbook.', paraQue: 'Ter noção do tamanho; use o sumário ou a busca para ir direto ao assunto.' } },
            { rotulo: 'Scripts prontos', valor: RESUMO.scripts, info: { nome: 'Scripts prontos', oQueE: 'Mensagens prontas para copiar: abordagem, qualificação, objeções, recuperação e acompanhamento de MQL.', comoConta: 'Cada bloco de mensagem com botão "Copiar" conta um.', paraQue: 'Falar com o lead nas palavras aprovadas, trocando só o que está entre chaves.' } },
            { rotulo: 'Trechos a definir', valor: RESUMO.pendencias, info: { nome: 'Trechos a definir', oQueE: 'Trechos marcados como a definir, a validar, a revisar ou a escrever. Enquanto estão assim, a regra ainda não vale.', comoConta: 'Cada marcação no texto conta uma (o selo "em validação" não entra).', paraQue: 'Saber o que ainda depende de decisão antes de tratar como regra.' } },
            { rotulo: 'Pontos em aberto', valor: RESUMO.emAberto, info: { nome: 'Pontos em aberto', oQueE: 'Decisões pendentes do Comercial, cada uma com quem decide.', comoConta: 'Linhas da tabela da seção "O que ainda está em aberto".', paraQue: 'Cobrar a decisão de quem decide.', meta: 'Zero, à medida que o Jonathan valida o playbook.' } },
          ]}
        />
      )}
    >
      <div className="lg:grid lg:grid-cols-[220px_minmax(0,1fr)] lg:gap-8">
        <Sumario ativa={ativa} achados={achados} buscando={buscando} onIr={ir} />

        <div className="min-w-0 max-w-[75ch]">
          {/* Celular: o sumário vira menu fixo no topo. */}
          <div className="lg:hidden sticky top-0 z-10 -mx-1 mb-3 bg-[var(--surface-0)] px-1 py-2">
            <label className="block">
              <span className="sr-only">Ir para a seção</span>
              <FilterSelect value={ativa} onChange={(e) => ir(e.target.value)} className="w-full">
                {GRUPOS.map((g) => (
                  <optgroup key={g.key} label={g.titulo}>
                    {SECOES.filter((s) => s.grupo === g.key).map((s) => (
                      <option key={s.id} value={s.id} disabled={buscando && !achados.has(s.id)}>
                        {s.titulo}{buscando && achados.has(s.id) ? ` (${achados.get(s.id)})` : ''}
                      </option>
                    ))}
                  </optgroup>
                ))}
              </FilterSelect>
            </label>
          </div>

          <div className="mb-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[var(--fg-3)]">
            <Badge tone="info">{SELO.versao} · {SELO.validacao}</Badge>
            <span>{SELO.fonte}</span>
          </div>

          <div className="mb-2 flex flex-wrap items-center gap-2">
            <SearchInput
              value={busca}
              onChange={(e) => setBusca(e.target.value)}
              onLimpar={() => setBusca('')}
              placeholder="Buscar no playbook (ex.: supressões, objeção, 15 min)"
              aria-label="Buscar no playbook"
            />
            {!buscando && (
              <Button size="sm" variant="ghost" onClick={() => setRecolhidas(todasRecolhidas ? new Set() : new Set(SECOES.map((s) => s.id)))}>
                <Icon name={todasRecolhidas ? 'chevron-down' : 'chevron-up'} size={14} /> {todasRecolhidas ? 'Abrir tudo' : 'Recolher tudo'}
              </Button>
            )}
          </div>
          <p className="mb-4 min-h-4 text-xs text-[var(--fg-3)]" aria-live="polite">
            {buscando
              ? (visiveis.length ? `"${termo}" aparece ${totalAchados} ${totalAchados === 1 ? 'vez' : 'vezes'} em ${visiveis.length} ${visiveis.length === 1 ? 'seção' : 'seções'}.` : '')
              : SELO.data}
          </p>

          {buscando && visiveis.length === 0 ? (
            <Vazio
              icone="search"
              titulo="Nada encontrado no playbook"
              hint={`Nenhuma seção fala de "${termo}". Tente outra palavra.`}
              acao={<Button size="sm" variant="ghost" onClick={() => setBusca('')}><Icon name="x" size={14} /> Limpar busca</Button>}
            />
          ) : (
            <div className="space-y-3">
              {visiveis.map((s) => (
                <SecaoPlaybook
                  key={s.id}
                  secao={s}
                  termo={termo}
                  aberta={buscando || !recolhidas.has(s.id)}
                  onAlternar={buscando ? undefined : () => alternar(s.id)}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </PaginaComercial>
  );
}

/** Sumário lateral fixo (telas largas), em grupos. Seleção em âmbar; na busca, mostra onde o termo aparece. */
function Sumario({ ativa, achados, buscando, onIr }: {
  ativa: string; achados: Map<string, number>; buscando: boolean; onIr: (id: string) => void;
}) {
  return (
    <nav aria-label="Sumário do playbook" className="hidden lg:block sticky top-0 self-start max-h-[calc(100dvh-var(--header-height)-48px)] overflow-y-auto pr-1">
      {GRUPOS.map((g) => (
        <div key={g.key} className="mb-3">
          <p className="mb-1 px-2 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]">{g.titulo}</p>
          <ul>
            {SECOES.filter((s) => s.grupo === g.key).map((s) => {
              const sel = s.id === ativa;
              const n = achados.get(s.id);
              const apagada = buscando && !n;
              return (
                <li key={s.id}>
                  <a
                    href={`#${s.id}`}
                    aria-current={sel ? 'location' : undefined}
                    onClick={(e) => { e.preventDefault(); if (!apagada) onIr(s.id); }}
                    aria-disabled={apagada || undefined}
                    className={`flex items-center justify-between gap-2 border-l-2 px-2 py-1 text-[13px] leading-snug transition-colors ${
                      sel ? 'border-[var(--accent)] text-[var(--fg)] font-medium' : 'border-transparent text-[var(--fg-2)] hover:text-[var(--fg)]'
                    } ${apagada ? 'opacity-40 pointer-events-none' : ''}`}
                  >
                    <span className="min-w-0">{s.titulo}</span>
                    {n != null && <span className="shrink-0 text-[11px] tabular text-[var(--fg-3)]">{n}</span>}
                  </a>
                </li>
              );
            })}
          </ul>
        </div>
      ))}
    </nav>
  );
}

function SecaoPlaybook({ secao, termo, aberta, onAlternar }: {
  secao: Secao; termo: string; aberta: boolean; onAlternar?: () => void;
}) {
  const idCorpo = `${secao.id}-corpo`;
  const idTitulo = `${secao.id}-titulo`;
  const cabecalho = (
    <>
      <span className="min-w-0">
        <span className="block text-base font-semibold leading-snug text-[var(--fg)]"><TextoRico texto={secao.titulo} termo={termo} /></span>
        {secao.resumo && <span className="mt-0.5 block text-xs font-normal leading-relaxed text-[var(--fg-3)]"><TextoRico texto={secao.resumo} termo={termo} /></span>}
      </span>
      {onAlternar && <Icon name={aberta ? 'chevron-up' : 'chevron-down'} size={16} className="shrink-0 mt-1 text-[var(--fg-3)]" />}
    </>
  );
  return (
    <section id={secao.id} aria-labelledby={idTitulo} className="scroll-mt-16 lg:scroll-mt-4 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)]">
      {/* Padrão de sanfona: o título é o h2 e o botão fica dentro dele (heading dentro de botão é HTML inválido). */}
      <h2 className="m-0">
        {onAlternar ? (
          <button
            id={idTitulo}
            type="button"
            onClick={onAlternar}
            aria-expanded={aberta}
            aria-controls={idCorpo}
            className="flex w-full items-start justify-between gap-3 rounded-[var(--r-lg)] px-4 py-3 text-left hover:bg-[var(--surface-2)] transition-colors"
          >
            {cabecalho}
          </button>
        ) : (
          <span id={idTitulo} className="flex items-start justify-between gap-3 px-4 py-3">{cabecalho}</span>
        )}
      </h2>
      {aberta && (
        <div id={idCorpo} className="space-y-3 border-t border-[var(--border-faint)] px-4 pb-4 pt-3">
          {secao.ferramentas && secao.ferramentas.length > 0 && (
            <div className="flex flex-wrap items-center gap-2">
              <span className="text-xs text-[var(--fg-3)]">No sistema:</span>
              {secao.ferramentas.map((f) => (
                <Link
                  key={f.href}
                  href={f.href}
                  className="inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border border-[var(--border)] px-2.5 min-h-7 text-xs text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors"
                >
                  {f.rotulo} <Icon name="arrow-right" size={12} />
                </Link>
              ))}
            </div>
          )}
          {secao.blocos.map((b, i) => <BlocoPlaybook key={i} bloco={b} termo={termo} />)}
        </div>
      )}
    </section>
  );
}
