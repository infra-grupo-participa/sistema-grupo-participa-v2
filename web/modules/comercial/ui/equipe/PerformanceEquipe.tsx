'use client';

// Aba Equipe dos Relatórios: performance por vendedor, como um gestor comercial lê o time. Período com
// comparação ao anterior e à média do time, cartão por vendedor (sem tabela larga), ranking por critério
// explícito e o detalhe do vendedor (?vendedor=id). Cálculo em performance.ts.
import { useMemo, useState } from 'react';
import { Button, Card, Input, SectionTitle, Toolbar } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import type { Atividade, EventoTimeline, MotivoPerdaConfig, Negocio, Vendedor } from '../../domain/types';
import { Carregando, combinarDados, EsqueletoLista, FaixaNumeros, NotaRodape, Pessoa, Segmentado, Vazio, useParamUrl } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { ymdLocal } from '../relatorios/indicadores';
import { repo, useDados } from '../repositorio';
import { CartaoVendedor } from './CartaoVendedor';
import { DetalheVendedor } from './DetalheVendedor';
import {
  CRITERIOS, diferencaPp, indicadoresVendedor, intervaloEquipe, rankingPor, referenciaTime, ROTULO_PERIODO_EQUIPE, selosVendedor,
  tendenciaReceita, variacaoPct, type BaseEquipe, type CriterioRanking, type IndicadoresVendedor, type PeriodoEquipe,
} from './performance';
import { infoCriterio, INFO_EQUIPE } from './textos';
import { fmtMin, fmtPct } from './visuais';

const PERIODOS: PeriodoEquipe[] = ['hoje', '7d', '30d', 'mes', 'personalizado'];
const ORDEM_CRITERIOS = Object.keys(CRITERIOS) as CriterioRanking[];

/** Nota do critério formatada para a lista do ranking. */
function fmtNota(c: CriterioRanking, v: number | null): string {
  if (v == null) return 'sem base';
  return c === 'volume' ? fmtBRL(v) : `${Math.round(v)}${c === 'conversao' || c === 'qualidade' ? '%' : ' pts'}`;
}

/** Troca ?vendedor= na URL sem recarregar (link direto para o detalhe). */
function marcarVendedorNaUrl(id: string | null) {
  const u = new URL(window.location.href);
  if (id) u.searchParams.set('vendedor', id);
  else u.searchParams.delete('vendedor');
  window.history.replaceState(null, '', `${u.pathname}${u.search}${u.hash}`);
}

export function PerformanceEquipe({ negocios, atividades, eventos, motivos, vendedores, nomeDe, agora }: {
  negocios: Negocio[]; atividades: Atividade[]; eventos: EventoTimeline[]; motivos: MotivoPerdaConfig[];
  vendedores: Vendedor[]; nomeDe: (id: string | null) => string; agora: Date;
}) {
  // Dados que só esta aba usa.
  const rFunis = useDados(() => repo.funis());
  const rConversas = useDados(() => repo.conversas());
  const rContatos = useDados(() => repo.contatos());
  const carga = combinarDados(rFunis, rConversas, rContatos);
  return (
    <Carregando dados={carga.dados} erro={carga.erro} onTentar={carga.onTentar} esqueleto={<EsqueletoLista linhas={4} />}>
      {([funis, conversas, contatos]) => (
        <Painel
          base={{ negocios, atividades, eventos, motivos, funis, conversas, agora }}
          contatos={contatos}
          vendedores={vendedores}
          nomeDe={nomeDe}
        />
      )}
    </Carregando>
  );
}

function Painel({ base, contatos, vendedores, nomeDe }: {
  base: BaseEquipe; contatos: Awaited<ReturnType<typeof repo.contatos>>; vendedores: Vendedor[]; nomeDe: (id: string | null) => string;
}) {
  const agora = base.agora;
  const [periodo, setPeriodo] = useState<PeriodoEquipe>('30d');
  const [de, setDe] = useState(() => ymdLocal(new Date(agora.getTime() - 13 * 24 * 3600_000)));
  const [ate, setAte] = useState(() => ymdLocal(agora));
  const [criterio, setCriterio] = useState<CriterioRanking>('volume');
  const paramVendedor = useParamUrl('vendedor');
  // undefined = segue o ?vendedor= da URL (link de Slack, sininho); null = fechado pelo usuário.
  const [escolhido, setEscolhido] = useState<string | null | undefined>(undefined);
  const aberto = escolhido === undefined ? paramVendedor : escolhido;

  const { atual, anterior } = useMemo(() => intervaloEquipe(periodo, agora, de, ate), [periodo, agora, de, ate]);

  // Time da comparação: quem é vendedor ou tem negócio/atividade no período.
  const calc = useMemo(() => {
    const comDado = (id: string) => base.negocios.some((n) => n.donoId === id) || base.atividades.some((a) => a.donoId === id);
    const time = vendedores.filter((v) => v.ativo && (v.papel === 'vendedor' || comDado(v.id))).map((v) => v.id);
    const linhas = time.map((id) => indicadoresVendedor(base, id, atual));
    const linhasAnt = time.map((id) => indicadoresVendedor(base, id, anterior));
    const ref = referenciaTime(linhas);
    const totalAtual = indicadoresVendedor(base, null, atual);
    const totalAnt = indicadoresVendedor(base, null, anterior);
    return { time, linhas, linhasAnt, ref, totalAtual, totalAnt };
  }, [base, vendedores, atual, anterior]);

  const { time, linhas, linhasAnt, ref, totalAtual, totalAnt } = calc;
  const ranking = rankingPor(linhas, criterio, (id) => nomeDe(id));
  const porId = new Map(linhas.map((l) => [l.vendedorId!, l]));
  const ordemCartoes = ranking.map((r) => porId.get(r.vendedorId)!).filter(Boolean);
  const rotuloPeriodo = periodo === 'personalizado' ? `${de.split('-').reverse().join('/')} a ${ate.split('-').reverse().join('/')}` : ROTULO_PERIODO_EQUIPE[periodo];
  const fmtIntervalo = (i: { ini: number; fim: number }) =>
    `${new Date(i.ini).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Sao_Paulo' })} a ${new Date(i.fim).toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit', timeZone: 'America/Sao_Paulo' })}`;

  const abrir = (id: string | null) => { setEscolhido(id); marcarVendedorNaUrl(id); };
  const linhaAberta: IndicadoresVendedor | null = aberto ? porId.get(aberto) ?? null : null;

  return (
    <div className="space-y-4">
      <Toolbar>
        <Segmentado
          rotulo="Período"
          valor={periodo}
          onChange={setPeriodo}
          opcoes={PERIODOS.map((p) => ({ valor: p, rotulo: ROTULO_PERIODO_EQUIPE[p] }))}
        />
        {periodo === 'personalizado' && (
          <>
            <Input type="date" value={de} max={ate} onChange={(e) => setDe(e.target.value)} aria-label="Início do período" className="!w-auto" />
            <Input type="date" value={ate} min={de} max={ymdLocal(agora)} onChange={(e) => setAte(e.target.value)} aria-label="Fim do período" className="!w-auto" />
          </>
        )}
        <span className="text-xs text-[var(--fg-3)]">
          {fmtIntervalo(atual)} · comparado com {fmtIntervalo(anterior)} e com a média do time
        </span>
      </Toolbar>

      <FaixaNumeros rotulo="Time no período" itens={[
        { rotulo: 'Vendas', valor: <>{totalAtual.vendas} <Variacao v={variacaoPct(totalAtual.vendas, totalAnt.vendas)} /></>, metrica: 'vendas' },
        { rotulo: 'Receita', valor: <>{fmtBRL(totalAtual.receita)} <Variacao v={variacaoPct(totalAtual.receita, totalAnt.receita)} /></>, metrica: 'receita' },
        { rotulo: 'Conversão', valor: <>{fmtPct(totalAtual.conversao)} <Variacao v={diferencaPp(totalAtual.conversao, totalAnt.conversao)} pp /></>, metrica: 'conversao' },
        { rotulo: '1º contato', valor: fmtMin(totalAtual.tempoPrimeiroContatoMin), metrica: 'tempo_primeiro_contato' },
        { rotulo: 'Atrasadas', valor: totalAtual.atrasadas, metrica: 'atrasadas', alerta: totalAtual.atrasadas > 0 },
      ]} />

      {/* Ranking com critério explícito. */}
      <section>
        <SectionTitle right={<InfoIndicador texto={INFO_EQUIPE.ranking} />}>Ranking</SectionTitle>
        <Card className="p-4">
          <div className="flex flex-wrap items-center gap-x-3 gap-y-2">
            <Segmentado rotulo="Critério do ranking" valor={criterio} onChange={setCriterio} opcoes={ORDEM_CRITERIOS.map((c) => ({ valor: c, rotulo: CRITERIOS[c].rotulo }))} />
            <span className="inline-flex min-w-0 items-center gap-1 text-xs text-[var(--fg-3)]">{CRITERIOS[criterio].comoConta} <InfoIndicador texto={infoCriterio(criterio)} /></span>
          </div>
          {ranking.length === 0 ? (
            <Vazio titulo="Nenhum vendedor no time" icone="users" />
          ) : (
            <ol className="mt-3 divide-y divide-[var(--border-faint)]" aria-label={`Ranking por ${CRITERIOS[criterio].rotulo}`}>
              {ranking.map((r) => (
                <li key={r.vendedorId} className="flex flex-wrap items-center gap-x-3 gap-y-1 py-2">
                  <span className="w-7 text-sm font-semibold tabular text-[var(--fg-2)]">{r.posicao == null ? '—' : `${r.posicao}º`}</span>
                  <span className="min-w-0 flex-1"><Pessoa nome={nomeDe(r.vendedorId)} size={24} onClick={() => abrir(r.vendedorId)} rotuloAcao={`Abrir o detalhe de ${nomeDe(r.vendedorId)}`} /></span>
                  <span className="text-sm font-semibold tabular text-[var(--fg)]">{fmtNota(criterio, r.nota)}</span>
                  <span className="hidden basis-full pl-10 text-[11px] text-[var(--fg-3)] sm:block sm:basis-auto sm:pl-0">
                    {ORDEM_CRITERIOS.filter((c) => c !== criterio).map((c) => {
                      const p = rankingPor(linhas, c).find((x) => x.vendedorId === r.vendedorId)?.posicao;
                      return `${CRITERIOS[c].rotulo} ${p == null ? '—' : `${p}º`}`;
                    }).join(' · ')}
                  </span>
                </li>
              ))}
            </ol>
          )}
          <NotaRodape className="mt-2">Quem mais vende não é necessariamente o melhor vendedor. Reembolso e condição especial entram com o backend e passam a pesar em Qualidade.</NotaRodape>
        </Card>
      </section>

      <section>
        <SectionTitle>Por vendedor</SectionTitle>
        {ordemCartoes.length ? (
          <div className="grid gap-3 md:grid-cols-2 2xl:grid-cols-3">
            {ordemCartoes.map((l) => {
              const id = l.vendedorId!;
              return (
                <CartaoVendedor
                  key={id}
                  nome={nomeDe(id)}
                  l={l}
                  anterior={linhasAnt[time.indexOf(id)]}
                  time={ref}
                  selos={selosVendedor(l, ref, linhas)}
                  tendencia={tendenciaReceita(base, id, atual)}
                  onAbrir={() => abrir(id)}
                />
              );
            })}
          </div>
        ) : (
          <Card>
            <Vazio
              titulo="Nenhum vendedor com dado no período"
              icone="users"
              acao={periodo !== '30d' ? <Button size="sm" variant="ghost" onClick={() => setPeriodo('30d')}>Ver últimos 30 dias</Button> : undefined}
            />
          </Card>
        )}
        <NotaRodape className="mt-1.5">
          Cartões na ordem do ranking. Vendas e receita comparam com o período anterior; as demais, com a média do time. Carga, atrasadas e sem próximo passo são retrato de agora.
        </NotaRodape>
      </section>

      {aberto && linhaAberta && (
        <DetalheVendedor
          vendedorId={aberto}
          nome={nomeDe(aberto)}
          base={base}
          intervalo={atual}
          periodo={rotuloPeriodo}
          linha={linhaAberta}
          linhas={linhas}
          time={time}
          selos={selosVendedor(linhaAberta, ref, linhas)}
          contatos={contatos}
          onClose={() => abrir(null)}
        />
      )}
    </div>
  );
}

/** Variação curta dentro da faixa de números ("+12%"), cor só quando muda. */
function Variacao({ v, pp = false }: { v: number | null; pp?: boolean }) {
  if (v == null) return null;
  const cor = v > 0 ? 'text-[var(--green)]' : v < 0 ? 'text-[var(--red)]' : 'text-[var(--fg-3)]';
  return (
    <span className={`text-[11px] font-normal ${cor}`} title="Contra o período anterior">
      {v > 0 ? '+' : v < 0 ? '−' : ''}{Math.abs(v)}{pp ? ' pp' : '%'}
      <span className="sr-only"> contra o período anterior</span>
    </span>
  );
}

