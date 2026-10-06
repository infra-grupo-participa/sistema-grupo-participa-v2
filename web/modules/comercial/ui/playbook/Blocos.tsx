'use client';

// Peças de leitura do playbook: texto com negrito e destaque da busca, tabela que vira cartões no celular
// (nunca rolagem horizontal), regra inegociável, trecho a definir e script com botão de copiar.
import Link from 'next/link';
import { useEffect, useId, useRef, useState } from 'react';
import { Badge, type Tone } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { acharPalavras, palavrasDaBusca, segmentar, textoLimpo } from './busca';
import { ROTULO_STATUS, type Atalho, type Bloco, type LinkFerramenta, type StatusTrecho } from './conteudo';

/** Texto com **negrito** e o termo da busca destacado. */
export function TextoRico({ texto, termo }: { texto: string; termo: string }) {
  return (
    <>
      {segmentar(texto, termo).map((s, i) => {
        const conteudo = s.destaque
          ? <mark className="rounded-[2px] bg-[var(--yellow-subtle)] text-[var(--fg)] ring-1 ring-[var(--yellow-border)]">{s.texto}</mark>
          : s.texto;
        return s.negrito ? <strong key={i} className="font-semibold text-[var(--fg)]">{conteudo}</strong> : <span key={i}>{conteudo}</span>;
      })}
    </>
  );
}

/**
 * Desenha um bloco. `onLinkInterno` recebe os links "#secao" (atalhos e perguntas) e devolve true se tratou
 * (a central troca de parte e rola); sem ele, o link segue o navegador.
 */
export function BlocoPlaybook({ bloco, termo, onLinkInterno }: { bloco: Bloco; termo: string; onLinkInterno?: (href: string) => boolean }) {
  switch (bloco.tipo) {
    case 'paragrafo':
      return <p className="text-sm leading-relaxed text-[var(--fg-2)]"><TextoRico texto={bloco.texto} termo={termo} /></p>;
    case 'subtitulo':
      return <h4 className="pt-2 text-sm font-semibold text-[var(--fg)]"><TextoRico texto={bloco.texto} termo={termo} /></h4>;
    case 'lista':
      return <Lista bloco={bloco} termo={termo} />;
    case 'tabela':
      return <TabelaPlaybook bloco={bloco} termo={termo} />;
    case 'regra':
      return <Regra bloco={bloco} termo={termo} />;
    case 'alerta':
      return <TrechoAberto status={bloco.status} texto={bloco.texto} quem={bloco.quem} termo={termo} />;
    case 'script':
      return <Script titulo={bloco.titulo} texto={bloco.texto} nota={bloco.nota} termo={termo} />;
    case 'passos':
      return <Passos titulo={bloco.titulo} itens={bloco.itens} termo={termo} />;
    case 'dicas':
      return <Caixa tipo="dicas" titulo={bloco.titulo} itens={bloco.itens} termo={termo} />;
    case 'cuidados':
      return <Caixa tipo="cuidados" titulo={bloco.titulo} itens={bloco.itens} termo={termo} />;
    case 'em_breve':
      return <EmBreve titulo={bloco.titulo} texto={bloco.texto} termo={termo} />;
    case 'pergunta':
      return <Pergunta pergunta={bloco.pergunta} resposta={bloco.resposta} link={bloco.link} termo={termo} />;
    case 'atalhos':
      return <Atalhos itens={bloco.itens} termo={termo} onLinkInterno={onLinkInterno} />;
  }
}

/** Passo a passo: trilha numerada, um passo por linha. */
function Passos({ titulo, itens, termo }: { titulo?: string; itens: string[]; termo: string }) {
  return (
    <div>
      {titulo && <p className="mb-2 text-sm font-semibold text-[var(--fg)]"><TextoRico texto={titulo} termo={termo} /></p>}
      <ol className="space-y-0">
        {itens.map((it, i) => (
          <li key={i} className="relative flex gap-3 pb-2.5 last:pb-0">
            {/* Linha que liga os passos (decorativa). */}
            {i < itens.length - 1 && <span aria-hidden className="absolute left-[11px] top-6 bottom-0 w-px bg-[var(--border)]" />}
            <span aria-hidden className="relative grid h-6 w-6 shrink-0 place-items-center rounded-full border border-[var(--border-strong)] bg-[var(--surface-2)] text-[11px] font-semibold tabular text-[var(--fg)]">{i + 1}</span>
            <span className="min-w-0 pt-0.5 text-sm leading-relaxed text-[var(--fg-2)]"><span className="sr-only">Passo {i + 1}: </span><TextoRico texto={it} termo={termo} /></span>
          </li>
        ))}
      </ol>
    </div>
  );
}

const CAIXA = {
  dicas: { rotulo: 'Dicas', icone: 'star', caixa: 'border-[var(--green-border)] bg-[var(--green-subtle)]', cor: 'text-[var(--green)]' },
  cuidados: { rotulo: 'Erros comuns', icone: 'alert', caixa: 'border-[var(--yellow-border)] bg-[var(--yellow-subtle)]', cor: 'text-[var(--yellow)]' },
} as const;

/** Dicas (verde) ou erros comuns (amarelo): título com ícone e texto, nunca só cor. */
function Caixa({ tipo, titulo, itens, termo }: { tipo: keyof typeof CAIXA; titulo?: string; itens: string[]; termo: string }) {
  const c = CAIXA[tipo];
  return (
    <div className={`rounded-[var(--r-md)] border px-3 py-2.5 ${c.caixa}`}>
      <p className="mb-1.5 flex items-center gap-1.5 text-sm font-semibold text-[var(--fg)]">
        <Icon name={c.icone} size={14} className={`shrink-0 ${c.cor}`} />
        <TextoRico texto={titulo ?? c.rotulo} termo={termo} />
      </p>
      <ul className="space-y-1 text-sm leading-relaxed text-[var(--fg-2)]">
        {itens.map((it, i) => (
          <li key={i} className="flex gap-2">
            <span aria-hidden className="shrink-0 text-[var(--fg-3)]">·</span>
            <span className="min-w-0"><TextoRico texto={it} termo={termo} /></span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/** Função que ainda não existe: selo escrito "Em breve" + o que vai fazer. */
function EmBreve({ titulo, texto, termo }: { titulo: string; texto: string; termo: string }) {
  return (
    <div className="flex gap-3 rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] px-3 py-2.5 text-sm leading-relaxed">
      <Icon name="hourglass" size={15} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
      <div className="min-w-0">
        <p className="flex flex-wrap items-center gap-2 font-semibold text-[var(--fg)]">
          <TextoRico texto={titulo} termo={termo} />
          <Badge tone="info">Em breve</Badge>
        </p>
        <p className="mt-0.5 text-[var(--fg-2)]"><TextoRico texto={texto} termo={termo} /></p>
      </div>
    </div>
  );
}

/** Pergunta frequente em sanfona. Abre sozinha quando a palavra destacada está nela. */
function Pergunta({ pergunta, resposta, link, termo }: { pergunta: string; resposta: string; link?: LinkFerramenta; termo: string }) {
  const palavras = palavrasDaBusca(termo);
  const temTermo = palavras.length > 0 && acharPalavras(`${pergunta} ${resposta}`, palavras).length > 0;
  const [aberta, setAberta] = useState(temTermo);
  const [termoVisto, setTermoVisto] = useState(termo);
  // Novo destaque: reabre a pergunta que tem o termo (ajuste de estado no render, sem efeito).
  if (termo !== termoVisto) {
    setTermoVisto(termo);
    if (temTermo) setAberta(true);
  }
  const id = `pergunta-${useId()}`;
  return (
    <div className="rounded-[var(--r-md)] border border-[var(--border)]">
      <h4 className="m-0">
        <button
          type="button"
          aria-expanded={aberta}
          aria-controls={id}
          onClick={() => setAberta((a) => !a)}
          className="flex w-full items-start justify-between gap-3 rounded-[var(--r-md)] px-3 py-2.5 text-left text-sm font-semibold text-[var(--fg)] transition-colors hover:bg-[var(--surface-2)]"
        >
          <span className="min-w-0"><TextoRico texto={pergunta} termo={termo} /></span>
          <Icon name={aberta ? 'chevron-up' : 'chevron-down'} size={15} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
        </button>
      </h4>
      <div id={id} hidden={!aberta} className="border-t border-[var(--border-faint)] px-3 pb-3 pt-2 text-sm leading-relaxed text-[var(--fg-2)]">
        <p><TextoRico texto={resposta} termo={termo} /></p>
        {link && (
          <Link href={link.href} className="mt-2 inline-flex items-center gap-1.5 text-xs font-medium text-[var(--fg-2)] underline-offset-2 hover:text-[var(--fg)] hover:underline">
            Abrir {link.rotulo} <Icon name="arrow-up-right" size={12} />
          </Link>
        )}
      </div>
    </div>
  );
}

/** Cartões de atalho: tela do sistema (Link) ou seção da ajuda (#id, tratada pela central). */
function Atalhos({ itens, termo, onLinkInterno }: { itens: Atalho[]; termo: string; onLinkInterno?: (href: string) => boolean }) {
  const classe = 'group flex h-full items-start gap-3 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2.5 transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-2)]';
  const miolo = (a: Atalho) => (
    <>
      <span className="grid h-8 w-8 shrink-0 place-items-center rounded-[var(--r-md)] bg-[var(--surface-3)] text-[var(--fg-2)]"><Icon name={a.icone} size={15} /></span>
      <span className="min-w-0 flex-1">
        <span className="block text-sm font-semibold text-[var(--fg)]"><TextoRico texto={a.rotulo} termo={termo} /></span>
        <span className="block text-xs leading-relaxed text-[var(--fg-3)]"><TextoRico texto={a.texto} termo={termo} /></span>
      </span>
      <Icon name={a.href.startsWith('#') ? 'arrow-right' : 'arrow-up-right'} size={13} className="mt-1 shrink-0 text-[var(--fg-3)] transition-transform group-hover:translate-x-0.5" />
    </>
  );
  return (
    <ul className="grid gap-2 sm:grid-cols-2">
      {itens.map((a) => (
        <li key={a.href + a.rotulo} className="min-w-0">
          {a.href.startsWith('#') ? (
            <a href={a.href} className={classe} onClick={(e) => { if (onLinkInterno?.(a.href)) e.preventDefault(); }}>{miolo(a)}</a>
          ) : (
            <Link href={a.href} className={classe}>{miolo(a)}</Link>
          )}
        </li>
      ))}
    </ul>
  );
}

function Lista({ bloco, termo }: { bloco: Extract<Bloco, { tipo: 'lista' }>; termo: string }) {
  const Tag = bloco.numerada ? 'ol' : 'ul';
  return (
    <div>
      {bloco.titulo && <p className="mb-1.5 text-sm font-semibold text-[var(--fg)]"><TextoRico texto={bloco.titulo} termo={termo} /></p>}
      <Tag className="space-y-1.5 text-sm leading-relaxed text-[var(--fg-2)]">
        {bloco.itens.map((it, i) => (
          <li key={i} className="flex gap-2.5">
            <span aria-hidden className="shrink-0 w-5 text-right tabular text-[var(--fg-3)]">{bloco.numerada ? `${i + 1}.` : '·'}</span>
            <span className="min-w-0"><TextoRico texto={it} termo={termo} /></span>
          </li>
        ))}
      </Tag>
    </div>
  );
}

/**
 * Tabela do playbook. Telas largas: tabela com quebra de linha (largura da coluna de texto, sem rolagem).
 * Celular: cada linha vira um cartão com "coluna: valor". Célula vazia não aparece no cartão.
 */
function TabelaPlaybook({ bloco, termo }: { bloco: Extract<Bloco, { tipo: 'tabela' }>; termo: string }) {
  const { colunas, linhas, titulo } = bloco;
  return (
    <div>
      {titulo && <p className="mb-1.5 text-sm font-semibold text-[var(--fg)]"><TextoRico texto={titulo} termo={termo} /></p>}
      <table className="hidden md:table w-full table-auto border-collapse text-sm">
        <thead>
          <tr className="border-b border-[var(--border)]">
            {colunas.map((c, i) => (
              <th key={i} scope="col" className="px-2 py-1.5 text-left align-bottom text-xs font-semibold text-[var(--fg-3)] [overflow-wrap:anywhere]">
                {c ? <TextoRico texto={c} termo={termo} /> : <span className="sr-only">Item</span>}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {linhas.map((l, i) => (
            <tr key={i} className="border-b border-[var(--border-faint)] last:border-b-0">
              {l.map((cel, j) => {
                const Cel = j === 0 ? 'th' : 'td';
                return (
                  <Cel key={j} scope={j === 0 ? 'row' : undefined} className={`px-2 py-2 text-left align-top leading-relaxed [overflow-wrap:anywhere] ${j === 0 ? 'font-medium text-[var(--fg)]' : 'font-normal text-[var(--fg-2)]'}`}>
                    {cel ? <TextoRico texto={cel} termo={termo} /> : <span className="text-[var(--fg-4)]" aria-label="vazio">·</span>}
                  </Cel>
                );
              })}
            </tr>
          ))}
        </tbody>
      </table>
      <ul className="md:hidden space-y-2">
        {linhas.map((l, i) => (
          <li key={i} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] px-3 py-2">
            <p className="text-sm font-medium text-[var(--fg)] [overflow-wrap:anywhere]"><TextoRico texto={l[0]} termo={termo} /></p>
            <dl className="mt-1 space-y-1">
              {l.slice(1).map((cel, j) => cel ? (
                <div key={j} className="text-sm leading-relaxed [overflow-wrap:anywhere]">
                  <dt className="text-[11px] font-semibold text-[var(--fg-3)]"><TextoRico texto={colunas[j + 1] || 'Item'} termo={termo} /></dt>
                  <dd className="text-[var(--fg-2)]"><TextoRico texto={cel} termo={termo} /></dd>
                </div>
              ) : null)}
            </dl>
          </li>
        ))}
      </ul>
    </div>
  );
}

function Regra({ bloco, termo }: { bloco: Extract<Bloco, { tipo: 'regra' }>; termo: string }) {
  return (
    <div className="flex gap-3 rounded-[var(--r-md)] border border-[var(--border-strong)] bg-[var(--surface-2)] px-3 py-2.5">
      {bloco.numero != null ? (
        <span className="grid place-items-center shrink-0 w-6 h-6 rounded-full border border-[var(--border-strong)] text-xs font-semibold tabular text-[var(--fg)]">{bloco.numero}</span>
      ) : (
        <Icon name="lock" size={15} className="shrink-0 mt-0.5 text-[var(--fg-3)]" />
      )}
      <div className="min-w-0 text-sm leading-relaxed">
        <p className="font-semibold text-[var(--fg)]"><TextoRico texto={bloco.titulo} termo={termo} /></p>
        {bloco.texto && <p className="mt-0.5 text-[var(--fg-2)]"><TextoRico texto={bloco.texto} termo={termo} /></p>}
      </div>
    </div>
  );
}

const TOM_STATUS: Record<StatusTrecho, Tone> = {
  em_validacao: 'info', a_definir: 'warning', a_validar: 'warning', a_revisar: 'warning', a_escrever: 'neutral',
};

/** Trecho que ainda não vale como regra: status escrito (não só cor) + quem decide. */
function TrechoAberto({ status, texto, quem, termo }: { status: StatusTrecho; texto: string; quem?: string; termo: string }) {
  return (
    <div className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] px-3 py-2 text-sm leading-relaxed">
      <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
        <Badge tone={TOM_STATUS[status]}>{ROTULO_STATUS[status]}</Badge>
        {quem && <span className="text-xs text-[var(--fg-3)]">Quem decide: <TextoRico texto={quem} termo={termo} /></span>}
      </div>
      <p className="mt-1 text-[var(--fg-2)]"><TextoRico texto={texto} termo={termo} /></p>
    </div>
  );
}

/** Mensagem pronta. Copia o texto limpo (sem marcação); `{Chave}` é o que o vendedor troca. */
function Script({ titulo, texto, nota, termo }: { titulo: string; texto: string; nota?: string; termo: string }) {
  return (
    <figure className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]">
      <figcaption className="flex items-center justify-between gap-2 border-b border-[var(--border-faint)] px-3 py-1.5">
        <span className="inline-flex min-w-0 items-center gap-2 text-xs font-semibold text-[var(--fg-2)]">
          <Icon name="message" size={13} className="shrink-0 text-[var(--fg-3)]" />
          <span className="min-w-0"><TextoRico texto={titulo} termo={termo} /></span>
        </span>
        <BotaoCopiarScript texto={textoLimpo(texto)} titulo={textoLimpo(titulo)} />
      </figcaption>
      <blockquote className="px-3 py-2.5 text-sm leading-relaxed text-[var(--fg)] whitespace-pre-line">
        <TextoRico texto={texto} termo={termo} />
      </blockquote>
      {nota && <p className="px-3 pb-2.5 text-xs leading-relaxed text-[var(--fg-3)]"><TextoRico texto={nota} termo={termo} /></p>}
    </figure>
  );
}

function BotaoCopiarScript({ texto, titulo }: { texto: string; titulo: string }) {
  const [estado, setEstado] = useState<'ocioso' | 'ok' | 'erro'>('ocioso');
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);
  useEffect(() => () => { if (timer.current) clearTimeout(timer.current); }, []);
  const copiar = async () => {
    try {
      await navigator.clipboard.writeText(texto);
      setEstado('ok');
    } catch {
      setEstado('erro');
    }
    if (timer.current) clearTimeout(timer.current);
    timer.current = setTimeout(() => setEstado('ocioso'), 1800);
  };
  const rotulo = estado === 'ok' ? 'Copiado' : estado === 'erro' ? 'Não copiou' : 'Copiar';
  return (
    <button
      type="button"
      onClick={copiar}
      aria-label={estado === 'ocioso' ? `Copiar mensagem: ${titulo}` : rotulo}
      className="inline-flex shrink-0 items-center gap-1.5 rounded-[var(--r-sm)] px-2 min-h-8 text-xs font-medium text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)] transition-colors"
    >
      <Icon name={estado === 'ok' ? 'check' : estado === 'erro' ? 'alert' : 'copy'} size={13} />
      <span aria-live="polite">{rotulo}</span>
    </button>
  );
}
