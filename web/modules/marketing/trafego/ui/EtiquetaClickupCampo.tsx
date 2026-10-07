'use client';

// Campo da etiqueta do ClickUp com busca (revisão do Victor, 06/10/2026): a pessoa digita "seminario" e aparecem as
// etiquetas do ClickUp que contêm isso (sem acento e sem diferença de maiúscula), por public.trafego_clickup_etiquetas_buscar
// (fonte: o que o painel de KPIs já grava + o espelho do ClickUp do Tráfego). Etiqueta fora da lista continua aceita,
// com o aviso "não encontrada no ClickUp".
import { useEffect, useId, useRef, useState } from 'react';
import { Input } from '@/shared/ui/components';
import { etiquetaEncontrada, type EtiquetaClickup } from '../domain/etiquetas';
import { buscarEtiquetasClickup } from '../infrastructure/trafego-data';

export function EtiquetaClickupCampo({ valor, onMudar }: { valor: string; onMudar: (v: string) => void }) {
  const id = useId();
  const [achadas, setAchadas] = useState<EtiquetaClickup[] | null>(null);
  const [aberto, setAberto] = useState(false);
  const [ativo, setAtivo] = useState(-1);
  const [indisponivel, setIndisponivel] = useState(false);
  const fechar = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    let vivo = true;
    const t = setTimeout(() => {
      buscarEtiquetasClickup(valor).then((r) => {
        if (!vivo) return;
        setIndisponivel(r === null);
        setAchadas(r ? r.etiquetas : null);
        setAtivo(-1);
      });
    }, 250);
    return () => { vivo = false; clearTimeout(t); };
  }, [valor]);

  const escolher = (e: string) => { onMudar(e); setAberto(false); };
  const lista = achadas ?? [];
  const naoAchou = !indisponivel && achadas !== null && !etiquetaEncontrada(achadas, valor);

  return (
    <div className="relative">
      <Input
        role="combobox" aria-expanded={aberto && lista.length > 0} aria-controls={`${id}-lista`} aria-autocomplete="list"
        aria-activedescendant={ativo >= 0 ? `${id}-${ativo}` : undefined}
        value={valor} maxLength={80} placeholder="digite para buscar (ex.: seminario)"
        onChange={(e) => { onMudar(e.target.value.toLowerCase()); setAberto(true); }}
        onFocus={() => setAberto(true)}
        onBlur={() => { fechar.current = setTimeout(() => setAberto(false), 150); }}
        onKeyDown={(e) => {
          if (e.key === 'ArrowDown') { e.preventDefault(); setAberto(true); setAtivo((i) => Math.min(i + 1, lista.length - 1)); }
          else if (e.key === 'ArrowUp') { e.preventDefault(); setAtivo((i) => Math.max(i - 1, 0)); }
          else if (e.key === 'Enter' && aberto && ativo >= 0 && lista[ativo]) { e.preventDefault(); escolher(lista[ativo].etiqueta); }
          else if (e.key === 'Escape' && aberto && lista.length > 0) { e.stopPropagation(); setAberto(false); } // só fecha a lista, não o cadastro
        }}
      />
      {aberto && lista.length > 0 && (
        <ul id={`${id}-lista`} role="listbox"
          className="gp-pop-in absolute z-20 mt-1 max-h-56 w-full overflow-auto overscroll-contain rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] py-1 shadow-[var(--highlight-surface),var(--shadow-lg)]">
          {lista.map((e, i) => (
            <li key={e.etiqueta} id={`${id}-${i}`} role="option" aria-selected={i === ativo}
              onMouseDown={(ev) => { ev.preventDefault(); if (fechar.current) clearTimeout(fechar.current); escolher(e.etiqueta); }}
              className={`cursor-pointer px-3 py-1.5 font-mono text-xs ${i === ativo ? 'bg-[var(--surface-3)] text-[var(--fg)]' : 'text-[var(--fg-2)]'} hover:bg-[var(--surface-3)]`}>
              {e.etiqueta}
              <span className="ml-2 font-sans text-[10px] text-[var(--fg-3)]">{e.fontes.map((f) => (f === 'kpi' ? 'painel de KPIs' : 'ClickUp do Tráfego')).join(' · ')}</span>
            </li>
          ))}
        </ul>
      )}
      {naoAchou && <span className="mt-1 block text-[11px] text-[var(--yellow)]">Não encontrada no ClickUp. Confira se está escrita igual à etiqueta de lá (pode salvar assim mesmo).</span>}
      {indisponivel && <span className="mt-1 block text-[11px] text-[var(--fg-3)]">Busca de etiquetas indisponível agora. Digite a etiqueta exata.</span>}
    </div>
  );
}
