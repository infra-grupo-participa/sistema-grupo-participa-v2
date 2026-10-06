'use client';

// Marketing > Tráfego: a Central do Tráfego. Resumo do dia no topo (20261005r), tabela de projetos com filtros, "a vida do
// projeto" no clique, cadastro de contas e campanhas fora do padrão. Só admin/dev (gate no layout, na page e no banco).
// Migrations 20261005p e 20261005r. 20261006a: filtros por tipo e unidade, "Novo projeto" (cadastro do evento), progresso
// do checklist de montagem. 20261006d: aba de modelos de lançamento (no lugar de pacotes e checklist).
import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Badge, Button, DataTable, EmptyState, FilterSelect, KpiCard, Loading, SectionCard, Tabs, Td, Th, Thead, Toast, Toggle, Tr, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { PROJETO_FORM_VAZIO, type ListasCadastro } from '../domain/cadastro';
import { FILTROS_INICIAIS, comKpis, filtrar, situacaoRitmo, totais, type FiltrosCentral } from '../domain/kpis';
import { ROTULO_TIPO, type ConfigTrafego, type Conta, type LinhaResumo, type Tipo } from '../domain/tipos';
import { MODO_DEMO, carregarConfig, carregarListasCadastro, carregarResumo, listarContas } from '../infrastructure/trafego-data';
import { CampanhasPainel } from './CampanhasPainel';
import { ContasPainel } from './ContasPainel';
import { ProgressoMontagem } from './MontagemProjeto';
import { ModelosPainel } from './ModelosPainel';
import { ModalProjetoCadastro } from './ProjetoCadastro';
import { ResumoDia } from './ResumoDia';
import { SEM_DADO, centavos, inteiro, pct, reais } from './formato';
import { VidaProjeto } from './VidaProjeto';

type Aba = 'central' | 'campanhas' | 'contas' | 'modelos';

/** Célula de KPI: "sem dado" discreto quando não há fonte. */
function Kpi({ v, titulo }: { v: string; titulo?: string }) {
  return v === SEM_DADO
    ? <span className="text-xs text-[var(--fg-3)]" title={titulo ?? 'Ainda não há fonte para este número'}>{SEM_DADO}</span>
    : <span className="tabular">{v}</span>;
}

function Filtros({ f, set, config, listas }: { f: FiltrosCentral; set: (f: FiltrosCentral) => void; config: ConfigTrafego; listas: ListasCadastro | null }) {
  const unidades = (listas?.unidades ?? []).filter((u) => !f.tipo || u.tipo === f.tipo);
  return (
    <div className="flex flex-wrap items-center gap-2">
      <FilterSelect value={f.tipo} onChange={(e) => set({ ...f, tipo: e.target.value as '' | Tipo, unidade: '' })} aria-label="Interno ou externo">
        <option value="">Interno e externo</option>
        {(Object.keys(ROTULO_TIPO) as Tipo[]).map((t) => <option key={t} value={t}>{ROTULO_TIPO[t]}</option>)}
      </FilterSelect>
      {listas && (
        <FilterSelect value={f.unidade} onChange={(e) => set({ ...f, unidade: e.target.value })} aria-label="Unidade">
          <option value="">Todas as unidades</option>
          {unidades.map((u) => <option key={u.codigo} value={u.codigo}>{u.nome}</option>)}
          <option value="sem">Sem unidade marcada</option>
        </FilterSelect>
      )}
      <FilterSelect value={f.gestor} onChange={(e) => set({ ...f, gestor: e.target.value })} aria-label="Gestor">
        <option value="">Todos os gestores</option>
        {config.gestores.map((g) => <option key={g.sigla} value={g.sigla}>{g.sigla} · {g.nome}</option>)}
      </FilterSelect>
      <FilterSelect value={f.status} onChange={(e) => set({ ...f, status: e.target.value })} aria-label="Situação">
        <option value="">Todas as situações</option>
        {config.status.map((s) => <option key={s.codigo} value={s.codigo}>{s.nome}</option>)}
        <option value="sem">Sem status marcado</option>
      </FilterSelect>
      <Toggle checked={f.inativos} onChange={(v) => set({ ...f, inativos: v })} label="Projetos desativados" />
    </div>
  );
}

function TabelaCentral({ linhas, onAbrir }: { linhas: LinhaResumo[]; onAbrir: (id: number) => void }) {
  if (linhas.length === 0) return <EmptyState title="Nenhum projeto com esses filtros" />;
  return (
    <DataTable minWidth={1500}>
      <Thead>
        <Th>Status</Th><Th>Projeto</Th><Th>Receita gerada</Th><Th>Investido</Th><Th>Verba máxima</Th><Th>% da verba</Th>
        <Th>CPL</Th><Th>Leads</Th><Th>CTR</Th><Th>CPM</Th><Th>Connect rate</Th><Th>Conversão da página</Th><Th>% MQL</Th><Th>Gestor</Th><Th>Montagem</Th>
      </Thead>
      <tbody>
        {linhas.map((l) => {
          const acima = situacaoRitmo(l.ritmo_ontem) === 'acima';
          return (
            <Tr key={l.projeto_id} onClick={() => onAbrir(l.projeto_id)}>
              <Td>{l.status_nome ? <Badge tone={l.status === 'ativo' ? 'success' : l.status === 'pausado' ? 'warning' : 'neutral'}>{l.status_nome}</Badge> : <Kpi v={SEM_DADO} titulo="Status não marcado" />}</Td>
              <Td>
                <div className="font-mono font-semibold">{l.sigla}</div>
                <div className="text-xs text-[var(--fg-3)]">{l.nome}{l.tipo ? ` · ${ROTULO_TIPO[l.tipo]}${l.unidade_nome ? ` ${l.unidade_nome}` : ''}` : ''}</div>
                {l.tipo_lancamento_nome && <div className="text-[11px] text-[var(--fg-3)]">{l.tipo_lancamento_nome}</div>}
                {l.campanhas_fora_padrao > 0 && <div className="mt-0.5 text-[11px] text-[var(--yellow)]">{l.campanhas_fora_padrao} campanha(s) fora do padrão</div>}
              </Td>
              <Td>{l.receita_aplica === false ? <span className="text-xs text-[var(--fg-3)]" title="Receita dos externos não entra por ora (Victor, 06/10/2026)">não se aplica</span> : <Kpi v={reais(l.receita)} titulo={l.receita_vinculos ? 'Vínculo sem período: ligue com data em "de" ou cadastre o início do projeto' : 'Sem produto da Hotmart ligado ao projeto (cadastre na vida do projeto)'} />}</Td>
              <Td><Kpi v={reais(l.investido)} titulo="Sem gasto coletado (a coleta Meta/Google é a etapa 2)" />
                {acima && <div className="text-[11px] text-[var(--red)]">ontem acima da diária</div>}</Td>
              <Td><Kpi v={reais(l.verba_maxima)} titulo="Verba não cadastrada" /></Td>
              <Td><Kpi v={pct(l.pct_verba)} /></Td>
              <Td><Kpi v={centavos(l.cpl)} titulo="Precisa de gasto e de leads da base" /></Td>
              <Td><Kpi v={inteiro(l.leads)} titulo="Leads da nossa base (base de pessoas)" /></Td>
              <Td><Kpi v={pct(l.ctr, 2)} /></Td>
              <Td><Kpi v={centavos(l.cpm)} /></Td>
              <Td><Kpi v={pct(l.connect_rate)} titulo="Page views da Web fase 2 (visitas vindas das campanhas) ÷ cliques no link" /></Td>
              <Td><Kpi v={pct(l.conversao_pagina)} titulo="Leads da página ÷ page views (a mesma conta da Web fase 2)" /></Td>
              <Td><Kpi v={pct(l.pct_mql)} /></Td>
              <Td>{l.gestores.length ? l.gestores.join(', ') : (l.gestores_campanhas.length ? <span className="text-[var(--fg-2)]" title="Gestores das campanhas">{l.gestores_campanhas.join(', ')}</span> : <Kpi v={SEM_DADO} titulo="Gestor não marcado" />)}</Td>
              <Td><ProgressoMontagem feitos={l.checklist_feitos} total={l.checklist_total} /></Td>
            </Tr>
          );
        })}
      </tbody>
    </DataTable>
  );
}

export function TrafegoClient() {
  const [config, setConfig] = useState<ConfigTrafego | null | undefined>(undefined);
  const [linhas, setLinhas] = useState<LinhaResumo[] | null | undefined>(undefined);
  const [aba, setAba] = useState<Aba>('central');
  const [filtros, setFiltros] = useState<FiltrosCentral>(FILTROS_INICIAIS);
  const [aberto, setAberto] = useState<number | null>(null);
  const [versao, setVersao] = useState(0);
  const [listas, setListas] = useState<ListasCadastro | null>(null);
  const [contas, setContas] = useState<Conta[]>([]);
  const [novo, setNovo] = useState(false);
  const { toast, flash } = useFlash();

  useEffect(() => {
    let vivo = true;
    carregarListasCadastro().then((l) => { if (vivo) setListas(l); });
    listarContas().then((c) => { if (vivo) setContas(c ?? []); });
    return () => { vivo = false; };
  }, [versao]);

  useEffect(() => {
    let vivo = true;
    carregarConfig().then((c) => { if (vivo) setConfig(c); });
    return () => { vivo = false; };
  }, []);

  useEffect(() => {
    let vivo = true;
    // o banco já devolve os KPIs; recalcular pelo domínio garante a mesma regra no modo de demonstração
    carregarResumo().then((r) => { if (vivo) setLinhas(r ? r.map(comKpis) : null); });
    return () => { vivo = false; };
  }, [versao]);

  const mudou = useCallback(() => setVersao((v) => v + 1), []);
  const visiveis = useMemo(() => filtrar(linhas ?? [], filtros), [linhas, filtros]);
  const t = useMemo(() => totais(visiveis), [visiveis]);

  if (config === undefined || linhas === undefined) return <Loading />;

  return (
    <div className="max-w-[1600px] space-y-5">
      <div>
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing · Tráfego</div>
        <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Central do Tráfego</h1>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Tudo o que a equipe opera em mídia paga, por projeto. Clique no projeto para ver a vida dele. &quot;Sem dado&quot; = ainda não há fonte ligada.
        </p>
      </div>

      {MODO_DEMO && (
        <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
          <b>Dados de demonstração.</b> Contas, campanhas, gasto, verba e leads inventados para ver a tela (NEXT_PUBLIC_TRAFEGO_DEMO=1, só no
          computador local). Nada é gravado; recarregar a página volta ao começo.
        </p>
      )}

      {!config || !linhas ? (
        <SectionCard>
          <p role="alert" className="text-sm text-[var(--red)]">
            Não foi possível carregar (erro de rede, sem acesso, ou a migration 20261005p ainda não foi aplicada).
          </p>
        </SectionCard>
      ) : (
        <>
          <Tabs
            tabs={[
              { k: 'central', l: 'Projetos' },
              { k: 'campanhas', l: 'Campanhas fora do padrão', n: linhas.reduce((a, l) => a + l.campanhas_fora_padrao, 0) || undefined },
              { k: 'contas', l: 'Contas de anúncio' },
              { k: 'modelos', l: 'Modelos de lançamento' },
            ]}
            active={aba}
            onChange={(k) => setAba(k as Aba)}
            idBase="trafego"
            label="Telas do Tráfego"
          />
          <div role="tabpanel" id="trafego-panel" className="space-y-5">
            {aba === 'central' && (
              <>
                <ResumoDia versao={versao} onAbrir={setAberto} />
                <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
                  <KpiCard label="Investido (filtro)" value={reais(t.investido)} hint="Soma do gasto coletado das plataformas" />
                  <KpiCard label="Verba máxima (filtro)" value={reais(t.verba)} hint="Planejamento à mão" bar="purple" />
                  <KpiCard label="Ontem acima da verba diária" value={t.acimaRitmo} bar={t.acimaRitmo ? 'red' : 'green'} hint={`Dia ${config.dia_ontem.split('-').reverse().join('/')}`} />
                  <KpiCard label="Campanhas fora do padrão" value={t.foraPadrao} bar={t.foraPadrao ? 'yellow' : 'green'} hint="Nas linhas filtradas" />
                </div>
                {!config.base_pessoas && (
                  <p className="text-xs text-[var(--fg-3)]">
                    Leads, CPL e % MQL vêm da base de pessoas (migration 20261005o), que ainda não existe neste banco: aparecem como &quot;sem dado&quot;.
                  </p>
                )}
                {!config.base_web && (
                  <p className="text-xs text-[var(--fg-3)]">
                    Connect rate e conversão da página usam as page views da Web fase 2 (migration 20261005q, a mesma conta da tela da Web), que ainda não existe neste banco: aparecem como &quot;sem dado&quot;.
                  </p>
                )}
                <SectionCard right={<div className="flex flex-wrap items-center gap-2">
                  <Filtros f={filtros} set={setFiltros} config={config} listas={listas} />
                  {listas && <Button size="sm" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Novo projeto</Button>}
                </div>} title="Projetos" subtitle={`${visiveis.length} de ${linhas.length}`}>
                  <TabelaCentral linhas={visiveis} onAbrir={setAberto} />
                </SectionCard>
              </>
            )}
            {aba === 'campanhas' && <CampanhasPainel linhas={linhas} versao={versao} flash={flash} onMudou={mudou} />}
            {aba === 'contas' && <ContasPainel config={config} flash={flash} onMudou={mudou} />}
            {aba === 'modelos' && <ModelosPainel listas={listas} config={config} versao={versao} flash={flash} onMudou={mudou} />}
          </div>
        </>
      )}

      {aberto != null && config && (
        <VidaProjeto id={aberto} config={config} listas={listas} contas={contas} versao={versao} onFechar={() => setAberto(null)} flash={flash} onMudou={mudou} />
      )}
      {novo && config && listas && (
        <ModalProjetoCadastro inicial={{ ...PROJETO_FORM_VAZIO }} listas={listas} config={config} contas={contas}
          onFechar={() => setNovo(false)} onSalvo={(m) => { setNovo(false); flash(m); mudou(); }} />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
