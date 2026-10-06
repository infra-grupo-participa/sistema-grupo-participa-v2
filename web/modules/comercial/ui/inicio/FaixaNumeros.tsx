'use client';

// Números do dia do Início, na faixa compacta padrão do Comercial (FaixaNumeros de comum.tsx).
import { fmtBRL } from '@/shared/ui/format';
import type { LinhaFechamento } from '../../domain/fechamento';
import { FaixaNumeros } from '../comum';

const ZERADA: LinhaFechamento = { abordados: 0, entraramEmContato: 0, responderam: 0, emNegociacao: 0, entraramEmNegociacaoHoje: 0, vendas: 0, receita: 0 };

/**
 * Números do dia (playbook, seção 12) com as mesmas definições do Fechamento em Relatórios.
 * `principal` aparece; `outro` (o do time para o vendedor, o meu para o gestor) vai no tooltip.
 */
export function NumerosDoDia({ principal, outro, rotuloOutro, rotulo = 'Números do dia', className }: {
  principal: LinhaFechamento | undefined; outro?: LinhaFechamento; rotuloOutro?: string; rotulo?: string; className?: string;
}) {
  const p = principal ?? ZERADA;
  const def = (definicao: string, v: (l: LinhaFechamento) => string | number) => ({
    title: outro && rotuloOutro ? `${definicao}. ${rotuloOutro}: ${v(outro)}` : definicao,
    extraSr: outro && rotuloOutro ? `${rotuloOutro}: ${v(outro)}` : undefined,
  });
  return (
    <FaixaNumeros
      rotulo={rotulo}
      className={className}
      itens={[
        { rotulo: 'Abordados', valor: p.abordados, metrica: 'abordados', ...def('Leads únicos com WhatsApp ou ligação concluída hoje', (l) => l.abordados) },
        { rotulo: 'Responderam', valor: p.responderam, metrica: 'responderam', ...def('Leads que passaram para Qualificar hoje', (l) => l.responderam) },
        { rotulo: 'Em negociação', valor: p.emNegociacao, metrica: 'em_negociacao', ...def('Negócios abertos em Negociar ou Aguardar pagamento', (l) => l.emNegociacao) },
        { rotulo: 'Vendas', valor: p.vendas, metrica: 'vendas', ...def('Ganhos com pagamento aprovado hoje', (l) => l.vendas) },
        { rotulo: 'Receita', valor: fmtBRL(p.receita), metrica: 'receita', ...def('Receita das vendas de hoje', (l) => fmtBRL(l.receita)) },
      ]}
    />
  );
}
