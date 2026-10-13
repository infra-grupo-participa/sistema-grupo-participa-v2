'use client';

// Perfil dos leads de qualquer recorte (geral, funil, etapa, isca, conjunto). Um só, usado no modal de Leads e
// na gaveta da Jornada. Sub-abas Resumo · Leads · Evolução; clicar num valor filtra o resto (filtro cruzado),
// região e estado encadeados. Conta CADASTROS; pessoas únicas aparecem à parte.
import { useId, useMemo, useState } from 'react';
import { Tabs, idsAba } from '@/shared/ui/components';
import { JANELAS_GRUPO, ingressoGrupo, pessoasUnicas } from '../../domain/metricas';
import {
  DIMENSOES_PERFIL, SEM_VALOR, alternarPerfil, aplicarPerfil, contarPor, evolucaoPorDia, porUf, trilhaPerfil,
  type DimensaoId, type FiltroPerfil,
} from '../../domain/perfil';
import type { LinhaPerfil } from '../../domain/tipos';
import type { DadosTela } from '../contexto';
import { Taxa, inteiro } from '../pecas';
import { BarrasClicaveis, LIMITE_ROSCA, RoscaClicavel } from './RoscaClicavel';
import { MapaBrasilBolhas } from './MapaBrasilBolhas';
import { TabelaLeads } from './TabelaLeads';

type SubAba = 'resumo' | 'leads' | 'evolucao';
const SUBABAS: { k: SubAba; l: string }[] = [{ k: 'resumo', l: 'Resumo' }, { k: 'leads', l: 'Leads' }, { k: 'evolucao', l: 'Evolução' }];
const dataCurta = (iso: string) => `${iso.slice(8, 10)}/${iso.slice(5, 7)}`;

export function PerfilLeads({ d, linhas, ocultar = [] }: { d: DadosTela; linhas: LinhaPerfil[]; ocultar?: DimensaoId[] }) {
  const base = useId().replace(/:/g, '');
  const [sub, setSub] = useState<SubAba>('resumo');
  const [filtro, setFiltro] = useState<FiltroPerfil>([]);
  const ctx = useMemo(() => ({ paginas: d.paginas }), [d.paginas]);
  const filtradas = useMemo(() => aplicarPerfil(linhas, filtro), [linhas, filtro]);
  const trilha = useMemo(() => trilhaPerfil(linhas, filtro, ctx), [linhas, filtro, ctx]);
  const alternar = (dim: DimensaoId, valor: string) => setFiltro((f) => alternarPerfil(f, { dim, valor }));
  const escolhido = (dim: DimensaoId) => filtro.find((f) => f.dim === dim)?.valor ?? null;

  const dimensoes = useMemo(() => DIMENSOES_PERFIL.filter((dim) => dim.id !== 'uf' && !ocultar.includes(dim.id)).map((dim) => ({
    dim, itens: contarPor(linhas, dim.id, filtro, ctx),
  })).filter(({ itens }) => itens.some((c) => c.valor !== SEM_VALOR)), [linhas, filtro, ctx, ocultar]);
  const mapa = useMemo(() => porUf(aplicarPerfil(linhas, filtro, 'uf')), [linhas, filtro]);
  const evolucao = useMemo(() => evolucaoPorDia(filtradas, d.diasPeriodo), [filtradas, d.diasPeriodo]);
  const maxDia = Math.max(1, ...evolucao.map((e) => e.quantidade));

  if (linhas.length === 0) return <p className="py-6 text-center text-sm text-[var(--fg-3)]">Nenhum cadastro neste recorte.</p>;

  return (
    <div className="min-w-0 space-y-3">
      <Tabs tabs={SUBABAS} active={sub} onChange={(k) => setSub(k as SubAba)} idBase={`perfil-${base}`} label="Perfil dos leads" />

      <nav aria-label="Filtros do perfil" className="flex flex-wrap items-center gap-1.5 text-xs">
        {trilha.map((p, i) => (
          <span key={i} className="inline-flex items-center gap-1.5">
            {i > 0 && <span aria-hidden="true" className="text-[var(--fg-3)]">→</span>}
            {p.item ? (
              <button type="button" onClick={() => alternar(p.item!.dim, p.item!.valor)} title="Tirar este filtro"
                className="rounded-full border border-[var(--border-accent)] bg-[var(--surface-3)] px-2 py-0.5 text-[var(--fg)] max-md:min-h-11">
                {p.rotulo} <span className="tabular text-[var(--accent)]">{inteiro(p.quantidade)}</span> <span aria-hidden="true">×</span>
              </button>
            ) : (
              <span className="rounded-full bg-[var(--surface-3)] px-2 py-0.5 text-[var(--fg-2)]">{p.rotulo} <span className="tabular text-[var(--fg)]">{inteiro(p.quantidade)}</span></span>
            )}
          </span>
        ))}
        {filtro.length > 0 && <button type="button" onClick={() => setFiltro([])} className="text-[var(--accent)] underline-offset-2 hover:underline max-md:min-h-11 max-md:px-2">Limpar</button>}
      </nav>

      <div role="tabpanel" id={idsAba(`perfil-${base}`, 'resumo').panel} aria-labelledby={idsAba(`perfil-${base}`, 'resumo').tab} hidden={sub !== 'resumo'}>
        {sub === 'resumo' && (
          <div className="space-y-4 atm-historico-panel-enter">
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-6">
              <Mini rotulo="Cadastros" valor={inteiro(filtradas.length)} />
              <Mini rotulo="Pessoas únicas" valor={inteiro(pessoasUnicas(filtradas))} />
              {JANELAS_GRUPO.map((h) => <Mini key={h} rotulo={`Grupo em ${h}h`} valor={<Taxa taxa={ingressoGrupo(filtradas, h, d.agora)} />} />)}
            </div>
            <div className="grid gap-5 md:grid-cols-2">
              {dimensoes.map(({ dim, itens }) => (itens.length <= LIMITE_ROSCA
                ? <RoscaClicavel key={dim.id} titulo={dim.titulo} nota={dim.nota} itens={itens} selecionado={escolhido(dim.id)} onSelect={(v) => alternar(dim.id, v)} />
                : <BarrasClicaveis key={dim.id} titulo={dim.titulo} nota={dim.nota} itens={itens} selecionado={escolhido(dim.id)} onSelect={(v) => alternar(dim.id, v)} />))}
              {!ocultar.includes('uf') && (
                <MapaBrasilBolhas porUf={mapa.porUf} semUf={mapa.semUf} outros={mapa.outros} selecionada={escolhido('uf')} onSelect={(uf) => alternar('uf', uf)} />
              )}
            </div>
          </div>
        )}
      </div>

      <div role="tabpanel" id={idsAba(`perfil-${base}`, 'leads').panel} aria-labelledby={idsAba(`perfil-${base}`, 'leads').tab} hidden={sub !== 'leads'}>
        {sub === 'leads' && <TabelaLeads d={d} linhas={filtradas} />}
      </div>

      <div role="tabpanel" id={idsAba(`perfil-${base}`, 'evolucao').panel} aria-labelledby={idsAba(`perfil-${base}`, 'evolucao').tab} hidden={sub !== 'evolucao'}>
        {sub === 'evolucao' && (
          <figure className="atm-historico-panel-enter">
            <figcaption className="mb-2 text-xs text-[var(--fg-3)]">Cadastros por dia (dia de São Paulo)</figcaption>
            <div className="flex h-40 items-end gap-px" role="img" aria-label={evolucao.map((e) => `${dataCurta(e.dia)}: ${e.quantidade}`).join(', ')}>
              {evolucao.map((e) => (
                <div key={e.dia} title={`${dataCurta(e.dia)}: ${inteiro(e.quantidade)}`} className="flex h-full min-w-0 flex-1 items-end">
                  <div className="w-full rounded-t-[2px] bg-[var(--accent)]" style={{ height: `${(e.quantidade / maxDia) * 100}%`, minHeight: e.quantidade > 0 ? 2 : 0 }} />
                </div>
              ))}
            </div>
            {evolucao.length > 0 && (
              <div className="mt-1 flex justify-between text-[10px] text-[var(--fg-3)]"><span>{dataCurta(evolucao[0].dia)}</span><span>{dataCurta(evolucao[evolucao.length - 1].dia)}</span></div>
            )}
          </figure>
        )}
      </div>
    </div>
  );
}

function Mini({ rotulo, valor }: { rotulo: string; valor: React.ReactNode }) {
  return (
    <div className="min-w-0 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-1)] p-2">
      <div className="truncate text-[11px] text-[var(--fg-3)]">{rotulo}</div>
      <div className="mt-0.5 text-sm font-semibold text-[var(--fg)]">{valor}</div>
    </div>
  );
}
