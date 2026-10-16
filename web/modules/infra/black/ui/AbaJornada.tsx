'use client';

// Aba 2, Jornada: "onde o lead está vazando?". O fluxograma do Arthur com número e taxa em cada etapa. Clicar
// num nó abre a gaveta lateral (não modal: o mapa continua visível) com Etapa · Criativos · Perfil.
import { useMemo } from 'react';
import { SectionCard } from '@/shared/ui/components';
import { ROTULO_FILTRO_FUNIL } from '../domain/tipos';
import { moeda } from './pecas';
import type { AlvoGaveta, DadosTela } from './contexto';
import { dadosJornada } from './jornada-dados';
import { MapaJornada } from './MapaJornada';
import { ResumoLeads } from './ResumoLeads';

export function AbaJornada({ d, gaveta }: { d: DadosTela; gaveta?: AlvoGaveta | null }) {
  const { metricas, semDetalheMista } = useMemo(() => dadosJornada(d), [d]);
  const ativo = gaveta?.tipo === 'etapa' ? gaveta.id : null;
  return (
    <SectionCard title="Jornada do lead"
      subtitle={<>Fluxograma do Arthur com o número de cada etapa no período. Clique numa etapa para ver o detalhe, os criativos e o perfil de quem entrou.
        {d.recorte.funil !== 'todos' && <> Filtro: <strong className="text-[var(--fg)]">{ROTULO_FILTRO_FUNIL[d.recorte.funil]}</strong>; os outros caminhos ficam apagados.</>}</>}>
      <MapaJornada metricas={metricas} funil={d.recorte.funil} ativo={ativo} onAbrir={(id) => d.abrirGaveta({ tipo: 'etapa', id })} />
      {semDetalheMista > 0 && ['todos', 'c2', 'consultoria', 'iscas'].includes(d.recorte.funil) && (
        <p role="note" className="mt-3 rounded-[var(--r-md)] border border-[var(--border-accent)] p-3 text-xs text-[var(--fg-2)]">
          <strong className="tabular text-[var(--fg)]">{moeda(semDetalheMista)}</strong> sem detalhe por anúncio: gasto da campanha mista de Consultoria e Iscas
          que nenhum anúncio explica no período (a coleta de anúncios atrasou). Entra no total da captação, mas não está dividido entre os nós de Consultoria e Iscas.
        </p>
      )}
      <ResumoLeads linhas={d.linhas.filter((l) => l.pagina !== 'consultoria_respondi')} idx={d.idx} grupo={d.grupo.data} compacto semDado={d.perfilSemDado} />
      <p className="mt-3 text-xs text-[var(--fg-3)]">
        Espessura da seta acompanha o volume que passa por ela. Etapa sem fonte mostra &ldquo;Sem dado&rdquo; com o motivo na dica. Textos das caixas: os do fluxograma do Arthur.
      </p>
    </SectionCard>
  );
}
