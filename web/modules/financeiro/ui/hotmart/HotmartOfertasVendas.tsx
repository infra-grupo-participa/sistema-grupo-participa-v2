'use client';

// Visão "Ofertas" da Hotmart — o que cada código é, quanto vendeu, se está no
// catálogo. Extraído de ui/Hotmart.tsx em 27/09/2026. Sem tela própria ainda:
// será pendurada em Ofertas por outro agente.
import { Badge, DataTable, Loading, SectionCard, Td, Th, Thead, Tr } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import type { FinanceiroRepository } from '../../application/ports';
import type { FamiliaHotmart, OfertaHotmart } from '../../domain/hotmart';
import { Erro, useCarga } from './comum';

export function HotmartOfertasVendas({ repo, familia }: { repo: FinanceiroRepository; familia: FamiliaHotmart }) {
  const { dados, erro } = useCarga<OfertaHotmart[]>(() => repo.loadHotmartOfertas(familia), [familia]);
  if (erro) return <Erro msg={erro} />;
  if (!dados) return <Loading label="Carregando ofertas…" minHeight={200} />;
  const fora = dados.filter((o) => !o.no_catalogo && o.vendas_pagas > 0).length;
  return (
    <SectionCard title={`${dados.length} oferta(s) com movimento na Hotmart`}
      subtitle={fora ? `${fora} oferta(s) com venda paga estão FORA do catálogo — venda nelas não vira card no board.` : 'Todas as ofertas com venda paga estão no catálogo.'}>
      <DataTable minWidth={1000}>
        <Thead><Th>Oferta</Th><Th>Produto</Th><Th>Tipo</Th><Th>Preço</Th><Th>Pagas</Th><Th>Bruto</Th><Th>Líquido</Th><Th>Reemb.</Th><Th>Recusas</Th><Th>Última venda</Th><Th>Catálogo</Th></Thead>
        <tbody>
          {dados.map((o) => (
            <Tr key={o.oferta_codigo}>
              <Td className="font-mono text-xs">{o.oferta_codigo}{o.nome_comercial && <div className="font-sans text-[11px] text-[var(--fg-3)]">{o.nome_comercial}</div>}</Td>
              <Td className="text-xs">{o.produto}<div className="text-[10px] text-[var(--fg-3)]">{o.papel_produto}</div></Td>
              <Td className="text-[11px] text-[var(--fg-3)]">{o.modo_pagamento ?? '—'}</Td>
              <Td className="tabular">{o.preco_oferta != null ? fmtBRL(Number(o.preco_oferta)) : '—'}</Td>
              <Td className="tabular">{o.vendas_pagas}</Td>
              <Td className="tabular">{fmtBRL(Number(o.receita_oferta))}</Td>
              <Td className="tabular text-[var(--green)]">{fmtBRL(Number(o.receita_liquida))}</Td>
              <Td className="tabular">{o.estornos || '—'}</Td>
              <Td className="tabular text-[var(--fg-3)]">{o.recusadas || '—'}</Td>
              <Td className="tabular">{o.ultima_venda ? fmtData(o.ultima_venda) : '—'}</Td>
              <Td>{o.no_catalogo
                ? <Badge tone="success">{o.categoria_catalogo ?? 'sem categoria'}{o.papel_catalogo ? ` · ${o.papel_catalogo}` : ''}</Badge>
                : <Badge tone={o.vendas_pagas > 0 ? 'danger' : 'neutral'}>fora do catálogo</Badge>}</Td>
            </Tr>
          ))}
        </tbody>
      </DataTable>
    </SectionCard>
  );
}
