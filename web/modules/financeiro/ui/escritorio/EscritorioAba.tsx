'use client';

// Aba "Escritório" do Financeiro (#escritorio, 30/09/2026): o setor escritório (Sessão de Viabilidade → Croqui →
// Holding Familiar). Sub-abas no hash (#escritorio?ver=), como o Faturamento: Funil e Contratos da Holding Familiar.
// Contratos depende da z93 no banco: a sonda (1 RPC, cacheada no FinanceiroClient) decide se a sub-aba aparece — função
// ausente = sub-aba escondida e o link `?ver=contratos` cai no Funil. O tablist só aparece com 2+ sub-abas visíveis.
import { useEffect, useRef, useState } from 'react';
import { Loading } from '@/shared/ui/components';
import type { CacheEscritorioFunil } from '../../application/carregar-escritorio-funil';
import type { CacheContratosHF, DisponibilidadeContratos } from '../../application/carregar-contratos-hf';
import { ROTULO_SUBABA_ESCRITORIO, SUBABAS_ESCRITORIO_ATIVAS, type SubAbaEscritorio } from './hash';
import { FunilEscritorio } from './FunilEscritorio';
import { ContratosEscritorio, type RepoContratosEscrita } from './ContratosEscritorio';

/** Sub-abas que aparecem: as ativas, menos Contratos enquanto a z93 não está confirmada no banco. */
export function subAbasVisiveis(disp: DisponibilidadeContratos): SubAbaEscritorio[] {
  return SUBABAS_ESCRITORIO_ATIVAS.filter((s) => s !== 'contratos' || disp === 'sim');
}

export function EscritorioAba({ sub, onSubChange, cacheFunil, cacheContratos, repo, canEdit, canVerDoc, onContratoAlterado }: {
  sub: SubAbaEscritorio; onSubChange: (s: SubAbaEscritorio) => void; cacheFunil: CacheEscritorioFunil;
  cacheContratos: CacheContratosHF; repo: RepoContratosEscrita; canEdit: boolean; canVerDoc: boolean;
  onContratoAlterado?: () => void;
}) {
  const [disp, setDisp] = useState<DisponibilidadeContratos>(() => cacheContratos.disponibilidade());
  useEffect(() => {
    let vivo = true;
    cacheContratos.sondar().then((d) => {
      if (!vivo) return;
      setDisp(d);
      if (d === 'nao') onSubChange('funil'); // link ?ver=contratos sem a z93: o hash volta a #escritorio
    });
    return () => { vivo = false; };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cacheContratos]);

  const visiveis = subAbasVisiveis(disp);
  const efetiva: SubAbaEscritorio = visiveis.includes(sub) ? sub : sub === 'contratos' && disp === 'desconhecida' ? 'contratos' : 'funil';
  const comAbas = visiveis.length > 1;
  return (
    <div className="space-y-4">
      {comAbas && <SubAbasEscritorio abas={visiveis} ativa={efetiva} onSelecionar={onSubChange} />}
      <div role={comAbas ? 'tabpanel' : undefined} id={`escritorio-painel-${efetiva}`}
        aria-labelledby={comAbas ? `escritorio-tab-${efetiva}` : undefined}>
        {efetiva === 'funil' && <FunilEscritorio cache={cacheFunil} />}
        {efetiva === 'contratos' && (disp === 'sim'
          ? <ContratosEscritorio cache={cacheContratos} repo={repo} canEdit={canEdit} canVerDoc={canVerDoc} onAlterado={onContratoAlterado} />
          : <Loading label="Carregando os contratos…" minHeight={240} />)}
      </div>
    </div>
  );
}

/** Mesmo padrão WAI-ARIA do SubAbasFaturamento: seta move o foco e troca a aba, Home/End. */
function SubAbasEscritorio({ abas, ativa, onSelecionar }: {
  abas: readonly SubAbaEscritorio[]; ativa: SubAbaEscritorio; onSelecionar: (s: SubAbaEscritorio) => void;
}) {
  const botoes = useRef<Partial<Record<SubAbaEscritorio, HTMLButtonElement | null>>>({});
  const L = abas;
  const ir = (alvo: SubAbaEscritorio) => { onSelecionar(alvo); botoes.current[alvo]?.focus(); };
  const mover = (dir: 1 | -1) => ir(L[(L.indexOf(ativa) + dir + L.length) % L.length]);
  return (
    <div role="tablist" aria-label="Escritório" className="flex w-fit overflow-hidden rounded-[var(--r-md)] border border-[var(--border)]"
      onKeyDown={(e) => {
        if (e.key === 'ArrowRight') { e.preventDefault(); mover(1); }
        else if (e.key === 'ArrowLeft') { e.preventDefault(); mover(-1); }
        else if (e.key === 'Home') { e.preventDefault(); ir(L[0]); }
        else if (e.key === 'End') { e.preventDefault(); ir(L[L.length - 1]); }
      }}>
      {L.map((s, i) => (
        <button key={s} ref={(el) => { botoes.current[s] = el; }} type="button" role="tab" id={`escritorio-tab-${s}`}
          aria-selected={ativa === s} aria-controls={`escritorio-painel-${s}`} tabIndex={ativa === s ? 0 : -1}
          onClick={() => onSelecionar(s)}
          className={`${i ? 'border-l border-[var(--border)] ' : ''}px-3 py-1.5 text-xs font-semibold ${
            ativa === s ? 'bg-[var(--accent-subtle)] text-[var(--accent)]' : 'text-[var(--fg-3)] hover:bg-[var(--surface-2)]'}`}>
          {ROTULO_SUBABA_ESCRITORIO[s]}
        </button>
      ))}
    </div>
  );
}
