'use client';

// Seletor de funil: um botão que abre a lista de agrupadores (colapsáveis) com os funis, a contagem de
// abertos e o ponto de prazo crítico. Substitui a coluna fixa à esquerda (devolve 256px ao kanban) e
// serve igual no celular. Cada funil mostra o ícone escolhido; funis de um mesmo projeto ficam juntos sob a
// chave do projeto. "Novo funil" (assistente) fica no rodapé, só para o gestor.
import { useCallback, useRef, useState } from 'react';
import { Icon } from '@/shared/ui/icons';
import { situacaoSla } from '../../domain/regras';
import type { Agrupador, Funil, Negocio } from '../../domain/types';
import { agruparPorProjeto, iconeDoFunil } from './assistente';
import { Popover } from './pecas';

export function SeletorFunil({ funis, agrupadores, negocios, atualId, agora, gestor, onEscolher, onNovoFunil }: {
  funis: Funil[];
  agrupadores: Agrupador[];
  negocios: Negocio[];
  atualId: string | null;
  agora: Date;
  gestor: boolean;
  onEscolher: (funilId: string) => void;
  onNovoFunil: () => void;
}) {
  const [aberto, setAberto] = useState(false);
  const [fechados, setFechados] = useState<Record<string, boolean>>({});
  const botao = useRef<HTMLButtonElement>(null);
  const fechar = useCallback(() => setAberto(false), []);
  const atual = funis.find((f) => f.id === atualId);

  const contagem = (funilId: string) => {
    const abertos = negocios.filter((x) => x.funilId === funilId && x.status === 'aberto');
    return { abertos: abertos.length, criticos: abertos.filter((x) => situacaoSla(x, agora) === 'critico').length };
  };
  // Críticos em OUTROS funis: o ponto no botão avisa sem precisar abrir.
  const criticosFora = funis.filter((f) => f.id !== atualId).reduce((s, f) => s + contagem(f.id).criticos, 0);

  const escolher = (id: string) => {
    setAberto(false);
    botao.current?.focus();
    onEscolher(id);
  };

  return (
    <>
      <button
        ref={botao}
        type="button"
        aria-haspopup="dialog"
        aria-expanded={aberto}
        aria-label={`Trocar de funil. Atual: ${atual?.nome ?? 'nenhum'}${criticosFora ? `. ${criticosFora} no prazo crítico em outros funis` : ''}`}
        onClick={() => setAberto((v) => !v)}
        className="relative inline-flex items-center gap-2 min-h-8 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]"
      >
        <Icon name="kanban" size={14} />
        <span>Trocar funil</span>
        <Icon name="chevron-down" size={14} className="text-[var(--fg-3)]" />
        {criticosFora > 0 && <span aria-hidden className="absolute -top-1 -right-1 w-2 h-2 rounded-full bg-[var(--red)] ring-2 ring-[var(--surface-0)]" />}
      </button>

      <Popover ancora={botao} aberto={aberto} onFechar={fechar} rotulo="Funis" largura={300}>
        <nav aria-label="Funis">
          {agrupadores.map((a) => {
            const fs = funis.filter((f) => f.agrupadorId === a.id);
            if (!fs.length) return null;
            const fechado = !!fechados[a.id];
            return (
              <div key={a.id} className="py-0.5">
                <button
                  type="button"
                  aria-expanded={!fechado}
                  onClick={() => setFechados((x) => ({ ...x, [a.id]: !fechado }))}
                  className="w-full flex items-center justify-between gap-2 min-h-8 px-2 rounded-[var(--r-sm)] text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)] hover:text-[var(--fg-2)]"
                >
                  <span className="truncate">{a.nome}</span>
                  <Icon name={fechado ? 'chevron-right' : 'chevron-down'} size={14} />
                </button>
                {!fechado && agruparPorProjeto(fs).map((g) => (
                  <div key={g.projeto ?? '_soltos'} role="group" aria-label={g.projeto ? `Projeto ${g.projeto}` : undefined}>
                    {g.projeto && (
                      <div className="flex items-center gap-1.5 pl-3 pr-2 pt-1.5 pb-0.5 text-[11px] text-[var(--fg-3)]" title="Chave do projeto (utm_campaign)">
                        <Icon name="tags" size={12} className="shrink-0" />
                        <span className="truncate">{g.projeto}</span>
                      </div>
                    )}
                    {g.funis.map((f) => {
                      const { abertos, criticos } = contagem(f.id);
                      const ativo = f.id === atualId;
                      return (
                        <button
                          key={f.id}
                          type="button"
                          onClick={() => escolher(f.id)}
                          aria-current={ativo ? 'page' : undefined}
                          title={f.nome}
                          className={`w-full flex items-center gap-2 min-h-8 ${g.projeto ? 'pl-5' : 'pl-3'} pr-2 rounded-[var(--r-sm)] text-left text-sm transition-colors ${ativo ? 'bg-[var(--surface-4)] text-[var(--fg)] font-semibold' : 'text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]'}`}
                        >
                          <Icon name={iconeDoFunil(f)} size={14} className="shrink-0 text-[var(--fg-3)]" />
                          <span className="flex-1 truncate">{g.projeto ? semPrefixoProjeto(f.nome) : f.nome}</span>
                          {criticos > 0 && (
                            <span className="inline-flex items-center gap-1 text-[11px] font-medium text-[var(--red)]" title={`${criticos} no prazo crítico`}>
                              <span aria-hidden className="w-1.5 h-1.5 rounded-full bg-[var(--red)]" />
                              {criticos}<span className="sr-only"> no prazo crítico</span>
                            </span>
                          )}
                          <span className="w-6 text-right text-xs tabular text-[var(--fg-3)]">{abertos}<span className="sr-only"> abertos</span></span>
                        </button>
                      );
                    })}
                  </div>
                ))}
              </div>
            );
          })}
          {gestor && (
            <div className="mt-1 pt-1 border-t border-[var(--border)]">
              <button type="button" onClick={() => { setAberto(false); onNovoFunil(); }}
                className="w-full flex items-center gap-2 min-h-8 px-2 rounded-[var(--r-sm)] text-sm text-[var(--fg-2)] hover:bg-[var(--surface-3)] hover:text-[var(--fg)]">
                <Icon name="plus" size={14} /> Novo funil
              </button>
            </div>
          )}
        </nav>
      </Popover>
    </>
  );
}

/** Dentro do grupo do projeto, o nome já diz o projeto: "HT34 · Venda ativa" vira "Venda ativa". */
function semPrefixoProjeto(nome: string): string {
  const i = nome.indexOf(' · ');
  return i > 0 ? nome.slice(i + 3) : nome;
}
