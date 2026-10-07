import { KpiCard } from '@/shared/ui/components';
import type { ResumoPresencial } from '../domain/presencial';
import { centavos, inteiro, percentual, reais } from './formato';

export function CardsResumo({ resumo, abrirLeads, abrirVendas }: { resumo: ResumoPresencial; abrirLeads: () => void; abrirVendas: () => void }) {
  return <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
    <KpiCard label="Custo por disparo" value={centavos(resumo.custo_disparo_centavos)} hint={resumo.disparos_sem_custo > 0 ? `${inteiro(resumo.disparos_sem_custo)} sem custo lançado` : undefined} />
    <button type="button" onClick={abrirLeads} className="text-left rounded-[var(--r-lg)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]" aria-label="Abrir pré-checkout"><KpiCard label="Pré-checkout" value={inteiro(resumo.pre_checkout_pessoas)} hint="Ver leads e resumo" /></button>
    <KpiCard label="Custo por pré-checkout" value={centavos(resumo.custo_por_pre_checkout_centavos)} />
    <button type="button" onClick={abrirVendas} className="text-left rounded-[var(--r-lg)] focus-visible:outline-2 focus-visible:outline-[var(--accent)]" aria-label="Abrir vendas"><KpiCard label="Total de vendas" value={inteiro(resumo.vendas)} hint={resumo.vendas_fora_brl > 0 ? `${inteiro(resumo.vendas_fora_brl)} fora de BRL` : 'Ver vendas e resumo'} /></button>
    <KpiCard label="Conversão de vendas" value={percentual(resumo.conversao_pct)} hint={`${inteiro(resumo.compradores_no_pre_checkout)} compradores no pré-checkout`} title="Compradores únicos divididos por pessoas únicas do pré-checkout" />
    <KpiCard label="Receita" value={reais(resumo.receita_liquida)} hint={`Bruta: ${reais(resumo.receita_bruta)}`} />
    <KpiCard label="CAC" value={centavos(resumo.cac_centavos)} />
  </div>;
}
