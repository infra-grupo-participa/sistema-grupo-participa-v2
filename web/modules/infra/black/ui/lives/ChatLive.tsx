'use client';

// Chat da live e comentários do vídeo. Clicar num minuto da curva filtra o chat para aquele minuto.
// O texto aparece exatamente como veio da fonte (React escapa; nada entra como HTML). Sem nome de autor: é decisão do desenho.
import { useMemo, useState } from 'react';
import { SectionCard, SearchInput } from '@/shared/ui/components';
import { filtrarChat, filtrarComentarios, minutoDe, type ComentarioLive, type MensagemChat } from '../../domain/lives';
import { Chip } from '../pecas';
import { dataHoraTexto, numeroDe, posicaoTexto } from './formatos';

/** Quantas linhas a tela desenha por vez; "Mostrar mais" libera o resto. */
const PAGINA = 100;

function Vazio({ children }: { children: React.ReactNode }) {
  return <p className="rounded-[var(--r-md)] border border-dashed border-[var(--border-strong)] p-4 text-sm text-[var(--fg-3)]">{children}</p>;
}

export function ChatLive({ chat, minuto, onLimparMinuto, guardado }: {
  chat: MensagemChat[]; minuto: number | null; onLimparMinuto: () => void; guardado: number | null;
}) {
  const [busca, setBusca] = useState('');
  const [limite, setLimite] = useState(PAGINA);
  const lista = useMemo(() => [...filtrarChat(chat, minuto, busca)].sort((a, b) => (a.seg ?? Infinity) - (b.seg ?? Infinity)), [chat, minuto, busca]);
  const visiveis = lista.slice(0, limite);
  const filtrando = minuto !== null || busca.trim() !== '';
  // O banco guarda também as mensagens de antes de a live começar (seg < 0): contam no "guardadas", não no chat do Studio.
  const antes = chat.filter((m) => m.seg !== null && m.seg < 0).length;

  return (
    <SectionCard title="Chat ao vivo"
      subtitle={minuto === null ? 'Clique num minuto da curva para ver só as mensagens daquele minuto.' : `Mensagens do minuto ${minuto}.`}
      right={<span className="tabular shrink-0 text-xs text-[var(--fg-3)]" title="Mensagens guardadas no banco, inclusive as de antes de a live começar. O chat do CSV do Studio é outra contagem.">{guardado === null ? 'Sem dado' : `${numeroDe(guardado)} guardadas${antes > 0 ? ` · ${numeroDe(antes)} antes do início` : ''}`}</span>}>
      <div className="mb-3 flex flex-wrap items-center gap-2">
        <div className="min-w-0 flex-1 basis-56">
          <SearchInput value={busca} onChange={(e) => { setBusca(e.target.value); setLimite(PAGINA); }} onLimpar={() => setBusca('')} placeholder="Buscar no chat" aria-label="Buscar no chat" />
        </div>
        {minuto !== null && <Chip ativo onClick={onLimparMinuto} title="Voltar a mostrar todos os minutos">{`Minuto ${minuto} ✕`}</Chip>}
      </div>
      {chat.length === 0 ? (
        <Vazio>{guardado ? 'As mensagens guardadas ainda não chegaram a esta tela.' : 'Esta live não tem mensagens de chat guardadas.'}</Vazio>
      ) : lista.length === 0 ? (
        <Vazio>Nenhuma mensagem {filtrando ? 'com esse filtro' : ''}.</Vazio>
      ) : (
        <>
          <p className="mb-2 text-xs text-[var(--fg-3)]" aria-live="polite">{filtrando ? `${lista.length} de ${chat.length} mensagens` : `${chat.length} mensagens`}</p>
          <ol className="max-h-[28rem] divide-y divide-[var(--border)] overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]" aria-label="Mensagens do chat">
            {visiveis.map((m, i) => (
              <li key={`${m.seg ?? 'x'}-${i}`} className="flex min-w-0 gap-3 px-3 py-2 text-sm">
                <span className="tabular w-14 shrink-0 text-xs text-[var(--fg-3)]" title={m.seg === null ? undefined : m.seg < 0 ? 'antes de a live começar' : `minuto ${minutoDe(m.seg)}`}>{m.seg === null ? 'Sem dado' : posicaoTexto(m.seg)}</span>
                <span className="min-w-0 break-words"><span className="text-[var(--fg)]">{m.texto}</span></span>
              </li>
            ))}
          </ol>
          {lista.length > visiveis.length && (
            <button type="button" onClick={() => setLimite((l) => l + PAGINA)} className="mt-2 min-h-11 w-full rounded-[var(--r-md)] border border-[var(--border)] text-sm font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
              Mostrar mais ({lista.length - visiveis.length} restantes)
            </button>
          )}
        </>
      )}
    </SectionCard>
  );
}

export function ComentariosLive({ comentarios, total }: { comentarios: ComentarioLive[]; total: number | null }) {
  const [busca, setBusca] = useState('');
  const [limite, setLimite] = useState(PAGINA);
  const lista = useMemo(() => filtrarComentarios(comentarios, busca), [comentarios, busca]);
  const visiveis = lista.slice(0, limite);
  return (
    <SectionCard title="Comentários do vídeo" subtitle="Os comentários públicos do vídeo no YouTube, como estão na fonte."
      right={<span className="tabular shrink-0 text-xs text-[var(--fg-3)]" title="Comentários do vídeo segundo a API do YouTube">{total === null ? 'Sem dado' : `${numeroDe(total)} na API`}</span>}>
      <div className="mb-3"><SearchInput value={busca} onChange={(e) => { setBusca(e.target.value); setLimite(PAGINA); }} onLimpar={() => setBusca('')} placeholder="Buscar nos comentários" aria-label="Buscar nos comentários" /></div>
      {comentarios.length === 0 ? <Vazio>Nenhum comentário guardado para este vídeo.</Vazio>
        : lista.length === 0 ? <Vazio>Nenhum comentário com esse filtro.</Vazio>
        : (
          <>
            <ul className="max-h-[28rem] divide-y divide-[var(--border)] overflow-y-auto rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)]" aria-label="Comentários do vídeo">
              {visiveis.map((c, i) => (
                <li key={`${c.publicadoEm ?? 'x'}-${i}`} className="min-w-0 px-3 py-2 text-sm">
                  <div className="flex flex-wrap items-baseline gap-x-2 text-xs text-[var(--fg-3)]">
                    <span>{c.publicadoEm ? dataHoraTexto(c.publicadoEm) : 'Sem data'}</span>
                    {c.curtidas !== null && <span>{numeroDe(c.curtidas)} curtidas</span>}
                    {c.respostas !== null && c.respostas > 0 && <span>{numeroDe(c.respostas)} respostas</span>}
                  </div>
                  <p className="mt-0.5 break-words text-[var(--fg-2)]">{c.texto}</p>
                </li>
              ))}
            </ul>
            {lista.length > visiveis.length && (
              <button type="button" onClick={() => setLimite((l) => l + PAGINA)} className="mt-2 min-h-11 w-full rounded-[var(--r-md)] border border-[var(--border)] text-sm font-semibold text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
                Mostrar mais ({lista.length - visiveis.length} restantes)
              </button>
            )}
          </>
        )}
    </SectionCard>
  );
}
