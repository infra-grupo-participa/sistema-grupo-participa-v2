'use client';

// Aba 2, Jornada: "onde o lead está vazando?". O fluxograma do Arthur com número e taxa em cada etapa. Clicar
// num nó abre a gaveta lateral (não modal: o mapa continua visível) com Etapa · Criativos · Perfil.
import { useMemo } from 'react';
import { SectionCard } from '@/shared/ui/components';
import { ROTULO_FUNIL } from '../domain/tipos';
import type { AlvoGaveta, DadosTela } from './contexto';
import { dadosJornada } from './jornada-dados';
import { MapaJornada } from './MapaJornada';

export function AbaJornada({ d, gaveta }: { d: DadosTela; gaveta?: AlvoGaveta | null }) {
  const { metricas } = useMemo(() => dadosJornada(d), [d]);
  const ativo = gaveta?.tipo === 'etapa' ? gaveta.id : null;
  return (
    <SectionCard title="Jornada do lead"
      subtitle={<>Fluxograma do Arthur com o número de cada etapa no período. Clique numa etapa para ver o detalhe, os criativos e o perfil de quem entrou.
        {d.recorte.funil !== 'todos' && <> Filtro: <strong className="text-[var(--fg)]">{ROTULO_FUNIL[d.recorte.funil]}</strong>; os outros caminhos ficam apagados.</>}</>}>
      <MapaJornada metricas={metricas} funil={d.recorte.funil} ativo={ativo} onAbrir={(id) => d.abrirGaveta({ tipo: 'etapa', id })} />
      <p className="mt-3 text-xs text-[var(--fg-3)]">
        Espessura da seta acompanha o volume que passa por ela. Etapa sem fonte mostra &ldquo;Sem dado&rdquo; com o motivo na dica. Textos das caixas: os do fluxograma do Arthur.
      </p>
    </SectionCard>
  );
}
