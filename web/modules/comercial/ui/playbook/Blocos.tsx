'use client';

// Peças de leitura do playbook: texto com negrito e destaque da busca, tabela que vira cartões no celular
// (nunca rolagem horizontal), regra inegociável, trecho a definir e script com botão de copiar.
import { useEffect, useRef, useState } from 'react';
import { Badge, type Tone } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { segmentar, textoLimpo } from './busca';
import { ROTULO_STATUS, type Bloco, type StatusTrecho } from './conteudo';

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

export function BlocoPlaybook({ bloco, termo }: { bloco: Bloco; termo: string }) {
  switch (bloco.tipo) {
    case 'paragrafo':
      return <p className="text-sm leading-relaxed text-[var(--fg-2)]"><TextoRico texto={bloco.texto} termo={termo} /></p>;
    case 'subtitulo':
      return <h3 className="pt-2 text-sm font-semibold text-[var(--fg)]"><TextoRico texto={bloco.texto} termo={termo} /></h3>;
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
  }
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
