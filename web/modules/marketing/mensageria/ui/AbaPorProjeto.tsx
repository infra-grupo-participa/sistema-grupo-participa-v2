'use client';

// Aba Por projeto: a mesma listagem do log, filtrada pelo servidor (p_projeto = sigla), com totais por canal.
// Só leitura: lançar e corrigir é na aba Disparos.
import { useState } from 'react';
import { FilterSelect, Input, Loading } from '@/shared/ui/components';
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import { fmtNum, periodoPadrao } from '../domain/mensageria';
import { useListaDisparos } from './AbaDisparos';
import { Campo, Erro, FaltaLancar, TabelaDisparos, TabelaPorCanal } from './pecas';

export function AbaPorProjeto({ hoje, projetos, ativo, versao }: { hoje: string; projetos: Projeto[]; ativo: boolean; versao: number }) {
  const [sigla, setSigla] = useState('');
  const [periodo, setPeriodo] = useState(() => periodoPadrao(hoje));
  const filtro = sigla && periodo.de && periodo.ate ? { ...periodo, projeto: sigla, canal: null, ferramenta: null } : null;
  const r = useListaDisparos(filtro, versao, ativo);

  return (
    <div className="space-y-4">
      <p role="note" className="rounded-[var(--r-md)] border border-[var(--border)] px-3 py-2 text-sm text-[var(--fg)]">
        Esta visão vem do log. Não se digita aqui. Para lançar ou corrigir, use a aba Disparos.
      </p>
      <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
        <div className="col-span-2 sm:col-span-2">
          <Campo rotulo="Projeto">
            <FilterSelect value={sigla} onChange={(e) => setSigla(e.target.value)}>
              <option value="">Escolha o projeto</option>
              {projetos.map((p) => <option key={p.id} value={p.sigla}>{p.sigla} · {p.nome}</option>)}
            </FilterSelect>
          </Campo>
        </div>
        <Campo rotulo="De"><Input type="date" value={periodo.de} max={periodo.ate || undefined} onChange={(e) => setPeriodo((p) => ({ ...p, de: e.target.value }))} /></Campo>
        <Campo rotulo="Até"><Input type="date" value={periodo.ate} min={periodo.de || undefined} onChange={(e) => setPeriodo((p) => ({ ...p, ate: e.target.value }))} /></Campo>
      </div>

      {!filtro ? (
        <p className="text-sm text-[var(--fg-2)]">Escolha o projeto para ver os disparos dele.</p>
      ) : r === undefined ? <Loading minHeight={120} /> : r === null ? (
        <Erro msg="Não foi possível carregar os disparos (erro de rede ou sem acesso)." />
      ) : !r.ok ? <Erro msg={r.msg} /> : (
        <>
          <FaltaLancar totais={r.totais} />
          <section aria-label="Totais por canal" className="space-y-2">
            <h2 className="text-sm font-semibold text-[var(--fg)]">Totais por canal <span className="font-normal text-[var(--fg-2)]">· {fmtNum(r.totais.qtd)} disparo(s) no período</span></h2>
            <TabelaPorCanal porCanal={r.por_canal} />
          </section>
          {r.truncado && (
            <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow-border)] px-3 py-2 text-sm text-[var(--fg)]">
              Este período tem mais de {fmtNum(r.limite)} disparos. A tabela mostra os {fmtNum(r.limite)} mais recentes; os totais contam todos. Encurte o período para ver o resto.
            </p>
          )}
          <TabelaDisparos linhas={r.linhas} />
        </>
      )}
    </div>
  );
}
