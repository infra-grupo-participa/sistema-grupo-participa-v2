'use client';

// Fila de cobrança do dia — o coração do controle ativo. Lista só o que a régua
// manda fazer AGORA, agrupado por tipo de ação e ordenado pelo dinheiro em jogo.
import { useMemo } from 'react';
import { Icon } from '@/shared/ui/icons';
import type { ContaReceber, ReguaPasso } from '../domain/types';
import { proximaAcao, type ProximaAcao, type TipoAcao } from '../domain/cobranca';
import {
  Badge, Button, Card, DataTable, EmptyState, SectionCard, SkeletonRows, Td, Th, Thead, Tr,
} from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';

interface Item { c: ContaReceber; acao: ProximaAcao }

const GRUPOS: { tipo: TipoAcao; titulo: string; hint: string; icon: string; cor: string }[] = [
  { tipo: 'cobrar', titulo: 'Cobrar hoje', hint: 'a régua venceu — falar com o aluno', icon: 'mail', cor: 'var(--red)' },
  { tipo: 'definir_acordo', titulo: 'Sem vencimento — combinar', hint: 'sem data combinada, a régua não roda', icon: 'calendar', cor: 'var(--accent)' },
  { tipo: 'calcular_valor', titulo: 'A calcular', hint: 'sem insumo de crédito — descobrir o valor', icon: 'notebook', cor: 'var(--yellow)' },
];

export function FilaCobranca({ contas, regua, loading, onAbrir }: {
  contas: ContaReceber[];
  regua: ReguaPasso[];
  loading: boolean;
  onAbrir: (contatoHmId: string) => void;
}) {
  const hojeISO = new Date().toISOString().slice(0, 10);

  const fila = useMemo(() => {
    const itens: Item[] = [];
    for (const c of contas) {
      const acao = proximaAcao(c, regua, hojeISO);
      if (acao.atrasada && acao.tipo !== 'nenhuma') itens.push({ c, acao });
    }
    return itens.sort((a, b) => (b.c.saldo_a_pagar ?? 0) - (a.c.saldo_a_pagar ?? 0));
  }, [contas, regua, hojeISO]);

  const total = fila.reduce((a, i) => a + (i.c.saldo_a_pagar ?? 0), 0);

  if (loading) {
    return (
      <SectionCard title="Fila do dia">
        <DataTable>
          <Thead><Th>Aluno</Th><Th>Canal</Th><Th>Ação</Th><Th>Vencimento</Th><Th>Última cobrança</Th><Th>{null}</Th></Thead>
          <tbody><SkeletonRows cols={[88, 64, 96, 64, 64, 40]} /></tbody>
        </DataTable>
      </SectionCard>
    );
  }

  if (!fila.length) {
    return (
      <Card className="p-4">
        <EmptyState title="Nada pendente hoje ✓" hint="A régua está em dia — nenhuma conta exige ação agora." icon="check" />
      </Card>
    );
  }

  return (
    <div className="space-y-4">
      {/* KPI do dia — quantas ações e quanto dinheiro está em jogo. */}
      <Card className="p-4" style={{ borderTop: '3px solid var(--accent)' }}>
        <div className="grid grid-cols-2 gap-x-6 sm:max-w-md">
          <div className="min-w-0 gp-rise">
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Ações hoje</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--fg)]">{fila.length.toLocaleString('pt-BR')}</div>
          </div>
          <div className="min-w-0 gp-rise" style={{ animationDelay: '45ms' }}>
            <div className="text-[10px] font-semibold uppercase tracking-wider text-[var(--fg-3)]">Em jogo</div>
            <div className="mt-1 text-[22px] font-bold tabular leading-none text-[var(--accent)] break-words">{fmtBRL(total)}</div>
          </div>
        </div>
      </Card>

      {GRUPOS.map((g) => {
        const itens = fila.filter((i) => i.acao.tipo === g.tipo);
        if (!itens.length) return null;
        return (
          <SectionCard
            key={g.tipo}
            title={
              <span className="inline-flex items-center gap-2">
                <span className="grid place-items-center w-6 h-6 rounded-[var(--r-md)]" style={{ background: `color-mix(in srgb, ${g.cor} 14%, transparent)`, color: g.cor }}>
                  <Icon name={g.icon} size={13} />
                </span>
                {g.titulo} ({itens.length})
              </span>
            }
            subtitle={g.hint}
          >
            <DataTable fixed>
              <Thead>
                <Th>Aluno</Th>
                <Th className="w-[170px]">Canal</Th>
                <Th className="w-[190px]">Ação</Th>
                <Th className="w-[100px]">Vencimento</Th>
                <Th className="w-[110px]">Última cobrança</Th>
                <Th className="w-[80px]"><span className="sr-only">Abrir</span></Th>
              </Thead>
              <tbody>
                {itens.map(({ c, acao }) => (
                  <Tr key={c.contato_hm_id} onClick={() => onAbrir(c.contato_hm_id)}>
                    <Td>
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 min-w-0">
                          <span className="truncate text-[13px] font-medium text-[var(--fg)]">{c.nome || '—'}</span>
                          {c.remarcacoes > 0 && (
                            <span className="shrink-0 inline-flex"><Badge tone="warning">remarcou {c.remarcacoes}x</Badge></span>
                          )}
                        </div>
                        <div className="text-[11px] tabular text-[var(--fg-3)]">{fmtBRL(c.saldo_a_pagar)}</div>
                      </div>
                    </Td>
                    <Td className="overflow-hidden"><Badge tone="neutral">{c.canal}</Badge></Td>
                    <Td className="overflow-hidden"><span className="block truncate text-xs text-[var(--fg-2)]" title={acao.titulo}>{acao.titulo}</span></Td>
                    <Td className="text-xs tabular text-[var(--fg-2)] whitespace-nowrap">{c.vencimento ? fmtData(c.vencimento) : '—'}</Td>
                    <Td className="text-xs tabular whitespace-nowrap">
                      {c.ultima_cobranca_em
                        ? <span className="text-[var(--fg-2)]">{fmtData(c.ultima_cobranca_em)}</span>
                        : <span className="text-[var(--fg-3)]">nunca</span>}
                    </Td>
                    <Td>
                      <Button variant="ghost" size="sm" onClick={(e) => { e.stopPropagation(); onAbrir(c.contato_hm_id); }}>
                        Abrir
                      </Button>
                    </Td>
                  </Tr>
                ))}
              </tbody>
            </DataTable>
          </SectionCard>
        );
      })}
    </div>
  );
}
