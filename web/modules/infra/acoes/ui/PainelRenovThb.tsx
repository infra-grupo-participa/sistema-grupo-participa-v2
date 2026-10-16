'use client';

// Aplicações do /renov (hm.timeholdingbrasil.com.br/renov), acessos da página e vendas das duas ofertas, 16/10/2026.
// Uma RPC (dados_renov_thb), lida ao abrir, no Atualizar e ao ligar "ver testes". Cards filtram a tabela.
// Marcar teste por linha só para master (renov_marcar_teste); e-mail @advmais.com é sempre teste.
import { useCallback, useEffect, useState } from 'react';
import { createBrowserSupabase } from '@/shared/infrastructure/supabase/browser-client';
import { EmptyState, KpiCard, SectionCard } from '@/shared/ui/components';
import {
  filtrarAplicacoesRenov, LINK_OFERTA_RENOV, mapearPainelRenov, mesmoFiltroRenov, OFERTAS_RENOV, rotuloOpcaoRenov,
  type FiltroRenov, type PainelRenov,
} from '../domain/renov';

const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 });
const pct = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 1 });
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { timeZone: 'America/Sao_Paulo', day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
const botao = 'min-h-9 rounded-[var(--r-md)] border border-[var(--border)] px-3 text-xs font-medium text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50';

function CardFiltro({ ativo, onClick, children }: { ativo: boolean; onClick: () => void; children: React.ReactNode }) {
  return <button type="button" onClick={onClick} aria-pressed={ativo}
    className={`text-left rounded-[var(--r-lg)] ${ativo ? 'ring-2 ring-[var(--accent)]' : ''}`}>{children}</button>;
}

export function PainelRenovThb() {
  const [dados, setDados] = useState<PainelRenov | null>(null);
  const [erro, setErro] = useState<string | null>(null);
  const [lendo, setLendo] = useState(false);
  const [verTestes, setVerTestes] = useState(false);
  const [filtro, setFiltro] = useState<FiltroRenov>(null);
  const [marcando, setMarcando] = useState<string | null>(null);

  const ler = useCallback(async (comTestes: boolean) => {
    setLendo(true);
    const { data, error } = await createBrowserSupabase().rpc('dados_renov_thb', { p_incluir_teste: comTestes });
    if (error) setErro('Não foi possível ler as aplicações agora.');
    else { setErro(null); setDados(mapearPainelRenov(data)); }
    setLendo(false);
  }, []);
  useEffect(() => { void ler(verTestes); }, [ler, verTestes]);

  const alternar = (f: FiltroRenov) => setFiltro((atual) => (mesmoFiltroRenov(atual, f) ? null : f));
  const marcarTeste = async (id: string, teste: boolean) => {
    setMarcando(id);
    const { error } = await createBrowserSupabase().rpc('renov_marcar_teste', { p_id: id, p_teste: teste });
    if (error) setErro(error.code === '42501' ? 'Só master marca teste.' : 'Não foi possível marcar agora.');
    await ler(verTestes);
    setMarcando(null);
  };

  const linhas = dados ? filtrarAplicacoesRenov(dados.aplicacoes, filtro) : [];

  return <SectionCard title="Aplicações do /renov e vendas"
    subtitle="hm.timeholdingbrasil.com.br/renov. Aplicações sem testes (e-mail @advmais.com conta sempre como teste). Vendas: todas as aprovadas e completas das duas ofertas."
    right={<div className="flex flex-wrap items-center gap-2">
      <label className="flex items-center gap-1.5 text-xs text-[var(--fg-2)]"><input type="checkbox" checked={verTestes} onChange={(e) => setVerTestes(e.target.checked)} /> Ver testes</label>
      <button type="button" onClick={() => void ler(verTestes)} disabled={lendo} className={botao}>{lendo ? 'Lendo…' : 'Atualizar'}</button>
    </div>}>
    {erro && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erro}</p>}
    {!dados ? <EmptyState title={lendo ? 'Carregando…' : 'Sem dado ainda'} /> : <div className="space-y-5">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <KpiCard label="Acessos à página" value={dados.acessos} hint={`${dados.visitantes} visitantes únicos`} bar="gray" />
        <KpiCard label="Visitante para aplicação" value={dados.taxaAplicacao === null ? 'Sem dado' : `${pct.format(dados.taxaAplicacao)}%`}
          hint={`${dados.visitantesQueAplicaram} de ${dados.visitantes} visitantes`} bar="gray" />
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <CardFiltro ativo={filtro === null} onClick={() => setFiltro(null)}><KpiCard label="Aplicações" value={dados.total} hint={filtro ? 'clique para limpar o filtro' : undefined} /></CardFiltro>
        {dados.porOpcao.map((o) => <CardFiltro key={o.chave} ativo={mesmoFiltroRenov(filtro, { tipo: 'opcao', opcao: o.chave })} onClick={() => alternar({ tipo: 'opcao', opcao: o.chave })}>
          <KpiCard label={o.rotulo} value={o.n} bar={o.chave === 'nao-renovar' ? 'gray' : 'accent'} />
        </CardFiltro>)}
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {dados.vendas.map((v) => <CardFiltro key={v.oferta} ativo={mesmoFiltroRenov(filtro, { tipo: 'oferta', oferta: v.oferta })} onClick={() => alternar({ tipo: 'oferta', oferta: v.oferta })}>
          <KpiCard label={`Vendas: ${v.rotulo}`} value={v.vendas} hint={moeda.format(v.valor)} bar="green" />
        </CardFiltro>)}
        <CardFiltro ativo={mesmoFiltroRenov(filtro, { tipo: 'pagou' })} onClick={() => alternar({ tipo: 'pagou' })}>
          <KpiCard label="Aplicaram e pagaram" value={dados.aplicaramEPagaram} hint="pessoas, cruzado pelo e-mail" bar="green" />
        </CardFiltro>
      </div>
      <div className="overflow-x-auto">
        <h3 className="mb-2 text-sm font-semibold text-[var(--fg)]">Aplicações{filtro ? ` (filtrado: ${linhas.length})` : ''}</h3>
        {linhas.length === 0 ? <p className="text-sm text-[var(--fg-3)]">Nenhuma aplicação {filtro ? 'neste filtro' : 'ainda'}.</p> :
          <table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">
            {['Data', 'Opção', 'Origem', 'Acessos antes', 'Pagou', ...(dados.veContato ? ['Nome', 'E-mail', 'Telefone'] : []), ...(dados.ehMaster ? ['Teste'] : [])].map((c) => <th key={c} className="p-2">{c}</th>)}
          </tr></thead><tbody>{linhas.map((a) => <tr key={a.id || a.criadoEm} className={`border-t border-[var(--border)] ${a.teste ? 'opacity-60' : ''}`}>
            <td className="p-2 whitespace-nowrap">{dataHora(a.criadoEm)}</td><td className="p-2">{rotuloOpcaoRenov(a.opcao)}</td>
            <td className="p-2">{a.origem || 'direto'}</td><td className="p-2">{a.acessosAntes === null ? '-' : a.acessosAntes}</td>
            <td className="p-2">{a.pagou ? 'Sim' : 'Não'}</td>
            {dados.veContato && <><td className="p-2">{a.nome}</td><td className="p-2">{a.email}</td><td className="p-2 whitespace-nowrap">{a.telefone}</td></>}
            {dados.ehMaster && <td className="p-2">{a.testeFixo ? <span className="text-xs text-[var(--fg-3)]">sempre teste</span> :
              <button type="button" disabled={marcando === a.id || !a.id} onClick={() => void marcarTeste(a.id, !a.teste)} className={botao}>{a.teste ? 'Desmarcar' : 'Marcar teste'}</button>}</td>}
          </tr>)}</tbody></table>}
      </div>
      <div className="overflow-x-auto">
        <h3 className="mb-2 text-sm font-semibold text-[var(--fg)]">Últimas vendas das ofertas</h3>
        {dados.ultimasVendas.length === 0 ? <p className="text-sm text-[var(--fg-3)]">Nenhuma venda ainda nas ofertas {Object.keys(OFERTAS_RENOV).map((cod, i) => <span key={cod}>{i > 0 ? ' e ' : ''}<a href={LINK_OFERTA_RENOV(cod)} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] underline">{cod}</a></span>)}.</p> :
          <table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">
            {['Data', 'Oferta', 'Valor', 'Aplicou no /renov', ...(dados.veContato ? ['Nome', 'E-mail'] : [])].map((c) => <th key={c} className="p-2">{c}</th>)}
          </tr></thead><tbody>{dados.ultimasVendas.map((v, i) => <tr key={`${v.em}-${i}`} className="border-t border-[var(--border)]">
            <td className="p-2 whitespace-nowrap">{dataHora(v.em)}</td>
            <td className="p-2"><a href={LINK_OFERTA_RENOV(v.oferta)} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] underline">{OFERTAS_RENOV[v.oferta] ?? v.oferta}</a></td>
            <td className="p-2">{moeda.format(v.valor)}</td><td className="p-2">{v.aplicou ? 'Sim' : 'Não'}</td>
            {dados.veContato && <><td className="p-2">{v.nome}</td><td className="p-2">{v.email}</td></>}
          </tr>)}</tbody></table>}
        <p className="mt-2 text-xs text-[var(--fg-3)]">Ofertas: {Object.entries(OFERTAS_RENOV).map(([cod, rotulo], i) => <span key={cod}>{i > 0 ? ' · ' : ''}<a href={LINK_OFERTA_RENOV(cod)} target="_blank" rel="noopener noreferrer" className="text-[var(--accent)] underline">{cod}</a> {rotulo}</span>)}</p>
      </div>
    </div>}
  </SectionCard>;
}
