'use client';

import { LinkVoltar } from '@/shared/ui/departamentos/LinkVoltar';
import { useCallback, useEffect, useRef, useState } from 'react';
import { publicEnv } from '@/shared/infrastructure/config/env';
import { dashboardAtmSemDado, type DashboardAtm, type CanalDisparoAtm, type LeadAtm, type LeadGrupoAtm } from '@/modules/infra/atm/domain/dashboard';
import { carregarAtmGrupoLeads, carregarAtmLeads, desmarcarAtmTeste, marcarAtmTeste, type DisparoDetalheAtm, type Resultado } from '@/modules/infra/atm/infrastructure/atm-data';
import { ENTRADAS_GRUPO_ACAO_DEMO } from '../infrastructure/grupo-leads-demo';
import { chaveListaAtm, criarCarregadorListasAtm } from '@/modules/infra/atm/ui/carregador-listas';
import { useListaAtm } from '@/modules/infra/atm/ui/useListaAtm';
import { EmptyState, KpiCard, SectionCard, Tabs, idsAba } from '@/shared/ui/components';
import { CANAIS_DISPARO_ATM } from '@/modules/infra/atm/domain/dashboard';
import { DisparosDetalhe } from '@/modules/infra/atm/ui/DisparosDetalhe';
import { cardsResumoAcaoBlack } from '../domain/resumo';
import { carregarDadosAcoesBlack, mensagemEmPreparacao, type EstadoDadosAcoesBlack, type LinhaAcoes } from '../infrastructure/dados';
import { registroAcoesBlack } from '../domain/registro';
import { contarLeadsAcao, exibicaoCardLeads } from '../domain/leads';
import { ModalLeadsAcao } from './ModalLeadsAcao';
import { ModalIngressoGrupoAcao } from './ModalIngressoGrupoAcao';

const cardsComparecimento = [
  ['Pico de audiência', 'pico_audiencia', 'inteiro'], ['Comparecimento do grupo', 'presentes_grupo', 'inteiro'],
  ['Comparecimento dos leads', 'presentes_leads', 'inteiro'], ['Total de leads', 'total_leads', 'inteiro'],
  ['Total no grupo', 'total_grupo', 'inteiro'], ['Pessoas da equipe na sala', 'equipe_na_sala', 'inteiro'],
  ['Vendas', 'vendas', 'inteiro'], ['Conversão', 'conversao_pct', 'percentual'],
  ['Conversão no grupo', 'conversao_grupo_pct', 'percentual'], ['Conversão sobre o pico', 'conversao_pico_pct', 'percentual'],
] as const;

const vazioLinhas: Resultado<LinhaAcoes[]> = { data: [], semDado: true, erro: null };
const vazioDisparos: Resultado<DisparoDetalheAtm[]> = { data: [], semDado: true, erro: null };
const inteiro = new Intl.NumberFormat('pt-BR', { maximumFractionDigits: 0 });
const moeda = new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' });

function numero(valor: unknown): number | null {
  if (valor === null || valor === undefined || valor === '') return null;
  const n = Number(valor);
  return Number.isFinite(n) ? n : null;
}
function formatar(valor: number, formato: string): string {
  if (formato === 'moeda') return moeda.format(valor);
  if (formato === 'percentual') return `${valor.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}%`;
  if (formato === 'multiplicador') return `${valor.toLocaleString('pt-BR', { maximumFractionDigits: 2 })}x`;
  return inteiro.format(valor);
}
function nomeCanal(canal: CanalDisparoAtm): string {
  return canal === 'api' ? 'whatsapp_api' : canal;
}

function PainelEmBreve({ nome }: { nome: string }) {
  return <SectionCard title={nome}>
    <EmptyState title="Ação em breve" hint="A etiqueta e a fonte serão configuradas quando esta ação for preparada." />
  </SectionCard>;
}

function preservarSeFalha<T>(atual: Resultado<T>, proximo: Resultado<T>): Resultado<T> {
  return proximo.semDado ? { ...atual, erro: proximo.erro } : proximo;
}

export function DashboardAcoesBlackClient({ isMaster = false, podeVerContato = false }: { isMaster?: boolean; podeVerContato?: boolean }) {
  const [acaoId, setAcaoId] = useState(registroAcoesBlack[0].id);
  const [modalLeads, setModalLeads] = useState(false);
  const [modalIngressoGrupo, setModalIngressoGrupo] = useState(false);
  const [incluirTeste, setIncluirTeste] = useState(isMaster);
  const [versaoListas, setVersaoListas] = useState(0);
  const [listas] = useState(criarCarregadorListasAtm);
  const [canalAtivo, setCanalAtivo] = useState<CanalDisparoAtm>('api');
  const [dadosCarregados, setDadosCarregados] = useState<{ acaoId: string; dados: EstadoDadosAcoesBlack } | null>(null);
  const [preparacaoCarregada, setPreparacaoCarregada] = useState<{ acaoId: string; emPreparacao: boolean } | null>(null);
  const [horarioAtualizacao, setHorarioAtualizacao] = useState<{ acaoId: string; atualizado: Date } | null>(null);
  const [atualizando, setAtualizando] = useState(false);
  const emCurso = useRef(false);
  const acao = registroAcoesBlack.find((item) => item.id === acaoId) ?? registroAcoesBlack[0];
  const tabs = registroAcoesBlack.map((item) => ({
    k: item.id,
    l: item.estado === 'em breve' ? `${item.nome} · em breve` : item.nome,
  }));
  const idsAcao = idsAba('acoes-black', acao.id);
  const dados = dadosCarregados?.acaoId === acao.id ? dadosCarregados.dados : null;
  const emPreparacao = preparacaoCarregada?.acaoId === acao.id && preparacaoCarregada.emPreparacao;
  const atualizado = horarioAtualizacao?.acaoId === acao.id ? horarioAtualizacao.atualizado : null;

  const atualizar = useCallback(async () => {
    if (acao.estado !== 'ativa' || !acao.etiqueta || emCurso.current) return;
    emCurso.current = true;
    setAtualizando(true);
    setVersaoListas((v) => v + 1);
    try {
      const novos = await carregarDadosAcoesBlack(acao);
      if (!novos) return;
      setPreparacaoCarregada({ acaoId: acao.id, emPreparacao: novos.emPreparacao });
      setDadosCarregados((estadoAnterior) => {
        const anteriores = estadoAnterior?.acaoId === acao.id ? estadoAnterior.dados : null;
        return { acaoId: acao.id, dados: {
        emPreparacao: novos.emPreparacao,
        resumo: preservarSeFalha(anteriores?.resumo ?? { data: dashboardAtmSemDado(acao.etiqueta!), semDado: true, erro: null }, novos.resumo),
        serie: preservarSeFalha(anteriores?.serie ?? vazioLinhas, novos.serie),
        canais: preservarSeFalha(anteriores?.canais ?? vazioLinhas, novos.canais),
        disparos: preservarSeFalha(anteriores?.disparos ?? vazioDisparos, novos.disparos),
        comparecimento: preservarSeFalha(anteriores?.comparecimento ?? vazioLinhas, novos.comparecimento),
        }};
      });
      if ([novos.resumo, novos.serie, novos.canais, novos.disparos, novos.comparecimento].some((item) => !item.semDado)) {
        setHorarioAtualizacao({ acaoId: acao.id, atualizado: new Date() });
      }
    } finally {
      emCurso.current = false;
      setAtualizando(false);
    }
  }, [acao]);

  useEffect(() => {
    if (acao.estado !== 'ativa' || !acao.etiqueta) return;
    void atualizar();
    const timer = window.setInterval(() => {
      if (document.visibilityState === 'visible') void atualizar();
    }, 60_000);
    const visibilidade = () => {
      if (document.visibilityState === 'visible') void atualizar();
    };
    document.addEventListener('visibilitychange', visibilidade);
    return () => {
      window.clearInterval(timer);
      document.removeEventListener('visibilitychange', visibilidade);
    };
  }, [acao.estado, acao.etiqueta, atualizar]);

  // Lista de leads da ação: lida sempre que a ação está ativa, porque os cards de leads válidos e de ingresso dependem dela
  // (o modal só a mostra). Só master pede as linhas de teste.
  const comTeste = isMaster && incluirTeste;
  const etiqueta = acao.estado === 'ativa' ? acao.etiqueta : null;
  const listaLeads = useListaAtm<LeadAtm>(listas, podeVerContato && etiqueta ? chaveListaAtm('dados_atm_leads', etiqueta, null, comTeste) : null, () => carregarAtmLeads(etiqueta!, undefined, comTeste), versaoListas);
  const chaveGrupoLeads = podeVerContato && modalIngressoGrupo && etiqueta ? chaveListaAtm('dados_atm_grupo_leads', etiqueta, null, false) : null;
  const demonstracaoGrupo = publicEnv.blackDemo;
  const listaGrupoLeads = useListaAtm<LeadGrupoAtm>(listas, chaveGrupoLeads, () => demonstracaoGrupo
    ? Promise.resolve({ data: ENTRADAS_GRUPO_ACAO_DEMO, semDado: false, erro: null })
    : carregarAtmGrupoLeads(etiqueta!), versaoListas);
  // Marcar lead como teste (15/10/2026): mesma RPC do ATM; o banco aceita a chave da ação (modelo acao-black). Só master.
  const toggleLead = async (lead: LeadAtm, teste: boolean): Promise<string | null> => {
    if (!isMaster) return 'Só masters podem marcar ou desmarcar testes.';
    if (!etiqueta) return 'Ação sem etiqueta cadastrada.';
    const r = teste ? await marcarAtmTeste(etiqueta, lead.email, lead.telefone) : await desmarcarAtmTeste(etiqueta, lead.email, lead.telefone);
    if (r.erro) return r.erro;
    setVersaoListas((v) => v + 1);
    void atualizar();
    return null;
  };
  const contagemLeads = listaLeads?.data ? contarLeadsAcao(listaLeads.data) : null;
  const resultadoResumo = dados?.resumo;
  const dashboard: DashboardAtm | null = resultadoResumo && !resultadoResumo.semDado ? resultadoResumo.data : null;
  const cards = cardsResumoAcaoBlack(dashboard, acao.ofertaHotmart);
  const canalNome = nomeCanal(canalAtivo);
  const canal = dados?.canais.data.find((item) => item.canal === canalNome);
  const comparecimento = dados?.comparecimento.data[0];
  const ofertaPendente = acao.ofertaHotmart === null;
  const erros = [dados?.resumo.erro, dados?.serie.erro, dados?.canais.erro, dados?.disparos.erro, dados?.comparecimento.erro].filter((item): item is string => Boolean(item));
  const erroResumo = dados?.resumo.erro;
  const erroSerie = dados?.serie.erro;
  const erroCanal = dados?.canais.erro;
  const erroComparecimento = dados?.comparecimento.erro;

  return <div className="max-w-7xl space-y-5">
    <header>
      <LinkVoltar href="/infra/dashboards/csm" para="Academy" />
      <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards / Academy</div>
      <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Ações da Black Friday</h1>
      <p className="mt-1 text-sm text-[var(--fg-2)]">Uma aba por ação, configurada pelo registro.{atualizado ? ` Atualizado às ${atualizado.toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo' })}.` : ''}</p>
    </header>

    <Tabs idBase="acoes-black" label="Ações da Black Friday" active={acao.id} onChange={setAcaoId} tabs={tabs} />
    <div role="tabpanel" id={idsAcao.panel} aria-labelledby={idsAcao.tab}>
      {acao.estado === 'em breve' ? <PainelEmBreve nome={acao.nome} /> : <div className="space-y-5">
        {emPreparacao && <p role="status" className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 text-sm text-[var(--fg-2)]">{mensagemEmPreparacao()}</p>}
        {erros.length > 0 && !emPreparacao && <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">{erros[0]} Os dados anteriores foram mantidos.</p>}

        <SectionCard title={acao.nome}>
          <div className="flex flex-wrap items-start justify-between gap-3">
            <div>
              <p className="text-xs text-[var(--fg-3)]">Etiqueta {acao.etiqueta} · origem {acao.origem}</p>
              {!emPreparacao && <p role="status" className="mt-3 text-sm text-[var(--fg-2)]">Fonte de dados conectada ao evento.</p>}
              {ofertaPendente && <p className="mt-1 text-xs text-[var(--fg-3)]">Pré-checkout e vendas aguardam a abertura do carrinho. A oferta Holding Masters ainda não foi configurada.</p>}
            </div>
            <div className="flex items-center gap-2">
              <span className="rounded-full border border-[var(--border)] px-2.5 py-1 text-xs text-[var(--fg-2)]">{atualizando ? 'Atualizando…' : emPreparacao ? 'Em preparação' : atualizado ? 'Atualizado' : 'Aguardando leitura'}</span>
              <button type="button" onClick={() => void atualizar()} disabled={atualizando} className="min-h-9 rounded-[var(--r-md)] border border-[var(--border)] px-3 text-xs font-medium text-[var(--fg)] hover:bg-[var(--surface-3)] disabled:opacity-50">Atualizar</button>
            </div>
          </div>
        </SectionCard>

        <section aria-label="Indicadores da ação">
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            {cards.map((card) => {
              const aguardaOferta = ofertaPendente && ['vendas', 'cac', 'faturamentoBruto', 'faturamentoLiquido', 'roas'].includes(card.chave);
              const semDado = !dashboard || card.metrica.semDado;
              const validos = !aguardaOferta && !semDado && contagemLeads ? exibicaoCardLeads(card.chave, card.metrica, contagemLeads) : null;
              const valor = aguardaOferta ? 'Aguardando oferta' : validos ? formatar(validos.valor, validos.formato) : semDado ? 'Sem dado' : formatar(card.metrica.valor, card.formato);
              const hint = aguardaOferta ? 'oferta ainda não configurada' : validos ? validos.hint : semDado ? 'sem dado ainda' : undefined;
              const kpi = <KpiCard key={card.chave} label={card.rotulo} value={valor} hint={hint} bar={card.chave === 'vendas' ? 'green' : 'accent'} />;
              return card.chave === 'leads' || card.chave === 'ingressosGrupo'
                ? <button key={card.chave} type="button" onClick={() => card.chave === 'leads' ? setModalLeads(true) : setModalIngressoGrupo(true)} className="text-left" aria-label={card.chave === 'leads' ? 'Abrir os leads da ação' : 'Abrir os números que entraram no grupo'}>{kpi}</button>
                : kpi;
            })}
          </div>
          {erroResumo && <p role="status" className="mt-2 text-xs text-[var(--yellow)]">Resumo: {erroResumo}</p>}
        </section>

        <SectionCard title="Evolução diária" subtitle="Custo com disparo, entradas no grupo, pré-checkouts e vendas.">
          {erroSerie && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erroSerie}</p>}
          {dados?.serie.data.length ? <div className="overflow-x-auto"><table className="w-full text-sm"><thead><tr className="text-left text-xs text-[var(--fg-3)]">{['Dia', 'Custo com disparo', 'Entradas no grupo', 'Pré-checkout', 'Vendas'].map((rotulo) => <th key={rotulo} className="p-2">{rotulo}</th>)}</tr></thead><tbody>{dados.serie.data.map((linha, i) => <tr key={String(linha.dia ?? i)} className="border-t border-[var(--border)]"><td className="p-2">{String(linha.dia ?? 'Sem dado')}</td><td className="p-2">{numero(linha.custo_disparo_centavos) === null ? 'Sem dado' : moeda.format((numero(linha.custo_disparo_centavos) ?? 0) / 100)}</td><td className="p-2">{numero(linha.grupo_entradas) === null ? 'Sem dado' : inteiro.format(numero(linha.grupo_entradas) ?? 0)}</td><td className="p-2">{numero(linha.pre_checkout) === null ? 'Sem dado' : inteiro.format(numero(linha.pre_checkout) ?? 0)}</td><td className="p-2">{ofertaPendente ? 'Aguardando oferta' : numero(linha.vendas) === null ? 'Sem dado' : inteiro.format(numero(linha.vendas) ?? 0)}</td></tr>)}</tbody></table></div> : <EmptyState title="Série diária sem dado ainda" hint={emPreparacao ? 'A série fica disponível quando o evento for cadastrado.' : 'A fonte ainda não devolveu dados para este período.'} />}
        </SectionCard>

        <SectionCard title="Visão do disparo" subtitle="Filtre por canal e abra cada registro para consultar os detalhes, como no ATM.">
          <div className="mb-4">
            <Tabs label="Canal do disparo" active={canalAtivo} onChange={(k) => setCanalAtivo(k as CanalDisparoAtm)} tabs={CANAIS_DISPARO_ATM.map((item) => ({ k: item.canal, l: item.rotulo }))} />
          </div>
          {erroCanal && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erroCanal}</p>}
          {canal ? <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{[['Disparos', 'disparos'], ['Enviados', 'enviados'], ['Entregues', 'entregues'], ['Lidas / atendidas', 'lidas'], ['Cliques', 'cliques'], ['Falhas', 'falhas'], ['Custo', 'custo_centavos']].map(([rotulo, campo]) => { const n = numero(canal[campo]); const dinheiro = campo === 'custo_centavos'; return <KpiCard key={campo} label={rotulo} value={n === null ? 'Sem dado' : formatar(dinheiro ? n / 100 : n, dinheiro ? 'moeda' : 'inteiro')} hint={n === null ? 'sem dado ainda' : undefined} />; })}</div> : <p className="mb-3 text-xs text-[var(--fg-3)]">{emPreparacao ? mensagemEmPreparacao() : 'Sem resumo para este canal.'}</p>}
          <DisparosDetalhe result={dados?.disparos ?? vazioDisparos} canal={canalNome} />
        </SectionCard>

        <SectionCard title="Comparecimento" subtitle="Reunião de 16/10 às 14h no Zoom. O pico da equipe entra quando houver dado disponível.">
          {erroComparecimento && <p role="status" className="mb-3 text-sm text-[var(--yellow)]">{erroComparecimento}</p>}
          {comparecimento ? <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">{cardsComparecimento.map(([rotulo, campo, formato]) => { const n = numero(comparecimento[campo]); const aguardaOferta = ofertaPendente && campo === 'vendas'; return <KpiCard key={campo} label={rotulo} value={aguardaOferta ? 'Aguardando oferta' : n === null ? 'Sem dado' : formatar(n, formato)} hint={aguardaOferta ? 'oferta ainda não configurada' : n === null ? 'sem dado ainda' : undefined} bar="gray" />; })}</div> : <EmptyState title="Comparecimento sem dado ainda" hint={emPreparacao ? 'O bloco será carregado quando o evento for cadastrado.' : 'A fonte ainda não devolveu a sessão.'} />}
        </SectionCard>
      </div>}
    </div>
    <ModalLeadsAcao open={modalLeads} onClose={() => setModalLeads(false)} nomeAcao={acao.nome} lista={listaLeads} card={dashboard?.resumo.leads ?? { valor: 0, semDado: true }} periodoLabel="período do cadastro" isMaster={isMaster} podeVerContato={podeVerContato} incluirTeste={comTeste} onIncluirTeste={setIncluirTeste} onToggleLead={toggleLead} />
    <ModalIngressoGrupoAcao open={modalIngressoGrupo} onClose={() => setModalIngressoGrupo(false)} nomeAcao={acao.nome} card={dashboard?.resumo.ingressosGrupo ?? { valor: 0, semDado: true }} lista={listaGrupoLeads} podeVerContato={podeVerContato} demonstracao={demonstracaoGrupo} />
  </div>;
}
