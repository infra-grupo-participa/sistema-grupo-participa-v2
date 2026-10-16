'use client';

// Aplicações do /renov (hm.timeholdingbrasil.com.br/renov) e vendas das duas ofertas do checkout, 16/10/2026.
// Uma RPC só (dados_renov_thb), lida ao abrir e no botão Atualizar. Contato só para quem tem contato.ver.
import { useCallback, useEffect, useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { EmptyState, KpiCard, SectionCard } from '@/shared/ui/components';
import { mapearPainelRenov, rotuloOpcaoRenov, OFERTAS_RENOV, type PainelRenov } from '../domain/renov';

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });

export function PainelRenovThb() {
  const [dados, setDados] = useState<PainelRenov | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [lendo, setLendo] = useState(false);

  const ler = useCallback(async () => {
    setLendo(true);
    const { data, error } = await createBrowserSupabase().rpc('dados_renov_thb', { p_incluir_teste: false });
    if (error) setErro('Não foi possível ler as aplicações agora.');
    else { setErro(null); setDados(mapearPainelRenov(data)); }
    setLendo(false);
  }, []);
  useEffect(() => { void ler(); }, [ler]);

  return <SectionCard title="Aplicações do /renov e vendas" subtitle="hm.timeholdingbrasil.com.br/renov. Aplicações sem as de teste. Vendas pelas ofertas do checkout (aprovadas e completas)."
    right={<button type="button" onClick={() => void ler()} disabled={lendo} className="min-h-9 rounded-[var(--r-md)] border border-[var(--border)] px-3 text-xs font-medium text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">{lendo ? 'Lendo…' : 'Atualizar'}</button>}>
    {erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erro}</p>}
    {!dados ? <EmptyState title={lendo ? 'Carregando…' : 'Sem dado ainda'} /> : <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Aplicações" value={dados.total} />
        {dados.porOpcao.map((o) => <KpiCard key={o.chave} label={o.rotulo} value={o.n} bar={o.chave === 'nao-renovar' ? 'gray' : 'accent'} />)}
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {dados.vendas.map((v) => <KpiCard key={v.oferta} label={`Vendas: ${v.rotulo}`} value={v.vendas} hint={moeda.format(v.valor)} bar="green" />)}
        <KpiCard label="Aplicaram e pagaram" value={dados.aplicaramEPagaram} hint="pessoas, cruzado pelo e-mail" bar="green" />
      </div>
      <div className="overflow-x-auto">
        <h3 className="mb-2 text-sm font-semibold text-[var(--fg)]">Aplicações</h3>
        {dados.aplicacoes.length === 0 ? <p className="text-sm text-[var(--fg-3)]">Nenhuma aplicação ainda.</p> :
          <table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">
            {['Data', 'Opção', 'Origem', 'Pagou', ...(dados.veContato ? ['Nome', 'E-mail', 'Telefone'] : [])].map((c) => <th key={c} className="p-2">{c}</th>)}
          </tr></thead><tbody>{dados.aplicacoes.map((a, i) => <tr key={`${a.criadoEm}-${i}`} className="border-t border-[var(--border)]">
            <td className="p-2 whitespace-nowrap">{dataHora(a.criadoEm)}</td><td className="p-2">{rotuloOpcaoRenov(a.opcao)}</td>
            <td className="p-2">{a.origem || 'direto'}</td><td className="p-2">{a.pagou ? 'Sim' : 'Não'}</td>
            {dados.veContato && <><td className="p-2">{a.nome}</td><td className="p-2">{a.email}</td><td className="p-2 whitespace-nowrap">{a.telefone}</td></>}
          </tr>)}</tbody></table>}
      </div>
      <div className="overflow-x-auto">
        <h3 className="mb-2 text-sm font-semibold text-[var(--fg)]">Últimas vendas das ofertas</h3>
        {dados.ultimasVendas.length === 0 ? <p className="text-sm text-[var(--fg-3)]">Nenhuma venda ainda nas ofertas {Object.keys(OFERTAS_RENOV).join(' e ')}.</p> :
          <table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">
            {['Data', 'Oferta', 'Valor', 'Aplicou no /renov', ...(dados.veContato ? ['Nome', 'E-mail'] : [])].map((c) => <th key={c} className="p-2">{c}</th>)}
          </tr></thead><tbody>{dados.ultimasVendas.map((v, i) => <tr key={`${v.em}-${i}`} className="border-t border-[var(--border)]">
            <td className="p-2 whitespace-nowrap">{dataHora(v.em)}</td><td className="p-2">{OFERTAS_RENOV[v.oferta] ?? v.oferta}</td>
            <td className="p-2">{moeda.format(v.valor)}</td><td className="p-2">{v.aplicou ? 'Sim' : 'Não'}</td>
            {dados.veContato && <><td className="p-2">{v.nome}</td><td className="p-2">{v.email}</td></>}
          </tr>)}</tbody></table>}
      </div>
    </div>}
  </SectionCard>;
}
