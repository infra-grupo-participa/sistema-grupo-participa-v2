'use client';

// "A vida do projeto" (clique na linha da Central do Tráfego): investido × verba, ritmo, KPIs × metas, fases planejado ×
// gasto, campanhas (e as fora do padrão), receita da Hotmart (vínculo de produto, 20261006i) e atividades do ClickUp com o
// gasto diário (20261006i). Cadastro de planejamento, fases e produtos aqui. 20261006j: cadastro do projeto (editar),
// campanhas sugeridas, modelo de lançamento (20261006l), checklist de montagem por momento e gerador de nome de campanha e UTM.
import { useEffect, useState } from 'react';
import {
  Badge, Button, ConfirmDialog, DataTable, Drawer, EmptyState, FilterSelect, Input, Loading, Modal, ProgressBar, Row, SectionCard,
  Td, Th, Thead, Tr,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { motivoErro } from '../../projetos/domain/campanha';
import { comKpis, esperadoAte, situacaoRitmo } from '../domain/kpis';
import { formDoCadastro, type ListasCadastro, type ProjetoCadastro } from '../domain/cadastro';
import { marcarCriadas } from '../domain/modelos';
import { numeroParaBanco, numeroParaCampo } from '../domain/numero';
import { ROTULO_AVISO, ROTULO_TIPO, type AcaoChecklist, type ConfigTrafego, type Conta, type FaseProjeto, type Resposta, type VidaProjeto as Vida } from '../domain/tipos';
import {
  ajustarCampanha, apagarFase, carregarCadastro, carregarProjeto, salvarFase, salvarPlanejamento, type FaseForm, type PlanejamentoForm,
} from '../infrastructure/trafego-data';
import { CadastroResumo, ChecklistPainel, GeradorCampanha, ModalAplicarModelo } from './MontagemProjeto';
import { ModalProjetoCadastro } from './ProjetoCadastro';
import { ClickupPainel } from './ClickupPainel';
import { SEM_DADO, centavos, dataBR, inteiro, pct, reais, rotuloStatusPlataforma, tomStatus } from './formato';
import { ProdutosHotmart } from './ProdutosHotmart';

type Flash = (msg: string) => void;

const txt = numeroParaCampo;
const msgAvisos = (r: Resposta) => [r.msg, ...(r.avisos ?? []).map((a) => ROTULO_AVISO[a] ?? a)].join(' ');

function Campo({ rotulo, dica, children }: { rotulo: string; dica?: string; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">
        {rotulo}{dica && <span className="font-normal text-[var(--fg-3)]"> · {dica}</span>}
      </span>
      {children}
    </label>
  );
}

type CampoNumerico = 'verba_maxima' | 'verba_diaria' | 'meta_leads' | 'meta_receita' | 'meta_cpl' | 'meta_pct_mql';
const ROTULO_NUMERO: Record<CampoNumerico, string> = {
  verba_maxima: 'Verba máxima', verba_diaria: 'Verba diária', meta_leads: 'Meta de leads', meta_receita: 'Meta de receita',
  meta_cpl: 'Meta de CPL', meta_pct_mql: 'Meta de % MQL',
};

function ModalPlanejamento({ vida, onFechar, onSalvo, onEditarProjeto }: {
  vida: Vida; onFechar: () => void; onSalvo: (m: string) => void; onEditarProjeto?: () => void;
}) {
  const r = vida.resumo;
  const [f, setF] = useState<PlanejamentoForm>({
    projeto_id: r.projeto_id, verba_maxima: txt(r.verba_maxima), verba_diaria: txt(r.verba_diaria),
    meta_leads: txt(r.meta_leads), meta_receita: txt(r.meta_receita), meta_cpl: txt(r.meta_cpl), meta_pct_mql: txt(r.meta_pct_mql), obs: r.obs ?? '',
  });
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  const set = (k: Exclude<keyof PlanejamentoForm, 'projeto_id'>, v: string) => setF((x) => ({ ...x, [k]: v }));
  const numero = (k: CampoNumerico) => (
    <Input inputMode="decimal" value={f[k]} aria-label={ROTULO_NUMERO[k]} onChange={(e) => set(k, e.target.value)} />
  );

  async function salvar() {
    if (salvando) return;
    const p = { ...f };
    for (const k of Object.keys(ROTULO_NUMERO) as CampoNumerico[]) {
      const v = numeroParaBanco(f[k]);
      if (v === null) { setErro(`${ROTULO_NUMERO[k]}: número inválido.`); return; }
      p[k] = v;
    }
    setSalvando(true);
    const x = await salvarPlanejamento(p);
    setSalvando(false);
    if (!x.ok) { setErro(x.msg); return; }
    onSalvo(msgAvisos(x));
  }

  return (
    <Modal onClose={onFechar} title={`Planejamento de ${r.sigla}`} width="max-w-2xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      {/* status e gestores se editam só no cadastro do projeto (auditoria 06/10/2026); aqui, só leitura */}
      <div className="mb-3 flex flex-wrap items-center gap-x-4 gap-y-1 rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm">
        <span><span className="text-xs text-[var(--fg-3)]">Status </span>{r.status_nome ? <Badge tone={tomStatus(r.status)}>{r.status_nome}</Badge> : <span className="text-[var(--fg-3)]">sem status</span>}</span>
        <span><span className="text-xs text-[var(--fg-3)]">Gestores </span>{r.gestores.length ? r.gestores.join(', ') : <span className="text-[var(--fg-3)]">nenhum</span>}</span>
        {onEditarProjeto && (
          <button type="button" className="ml-auto text-xs font-semibold text-[var(--accent)] hover:underline focus-visible:underline" onClick={onEditarProjeto}>
            Editar no projeto
          </button>
        )}
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Verba máxima (R$)">{numero('verba_maxima')}</Campo>
        <Campo rotulo="Verba diária (R$)">{numero('verba_diaria')}</Campo>
        <Campo rotulo="Meta de leads">{numero('meta_leads')}</Campo>
        <Campo rotulo="Meta de receita (R$)">{numero('meta_receita')}</Campo>
        <Campo rotulo="Meta de CPL (R$)" dica="teto">{numero('meta_cpl')}</Campo>
        <Campo rotulo="Meta de % MQL">{numero('meta_pct_mql')}</Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
      </div>
      <p className="mt-2 text-xs text-[var(--fg-3)]">Vazio = não definido. Vírgula para centavos, ponto de milhar opcional (10.000 ou 10.000,50).</p>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

function ModalFase({ inicial, config, captacao, onFechar, onSalvo }: {
  inicial: FaseForm; config: ConfigTrafego; captacao?: { inicio: string | null; fim: string | null }; onFechar: () => void; onSalvo: (m: string) => void;
}) {
  const [f, setF] = useState<FaseForm>(inicial);
  const [erro, setErro] = useState<string | null>(null);
  const [salvando, setSalvando] = useState(false);
  // a fase de captação nova vem com o período de captação do projeto (20261006j); dá para mudar
  const set = (k: keyof FaseForm, v: string) => setF((x) => (k === 'fase' && v === 'captacao' && !x.id && !x.inicio && !x.fim && captacao?.inicio
    ? { ...x, fase: v, inicio: captacao.inicio, fim: captacao.fim ?? '' } : { ...x, [k]: v }));

  async function salvar() {
    if (salvando) return;
    if (!f.fase) { setErro('Escolha a fase.'); return; }
    const verba = numeroParaBanco(f.verba);
    if (verba === null) { setErro('Verba planejada: número inválido.'); return; }
    setSalvando(true);
    const x = await salvarFase({ ...f, verba });
    setSalvando(false);
    if (!x.ok) { setErro(x.msg); return; }
    onSalvo(msgAvisos(x));
  }

  return (
    <Modal onClose={onFechar} title={f.id ? 'Editar fase' : 'Nova fase'} width="max-w-xl" footer={<>
      <Button variant="ghost" size="sm" onClick={onFechar}>Cancelar</Button>
      <Button size="sm" onClick={salvar} disabled={salvando}>{salvando ? 'Salvando…' : 'Salvar'}</Button>
    </>}>
      <div className="grid gap-3 sm:grid-cols-2">
        <Campo rotulo="Fase">
          <FilterSelect value={f.fase} onChange={(e) => set('fase', e.target.value)}>
            <option value="">Escolha</option>
            {config.fases.map((x) => <option key={x.codigo} value={x.codigo}>{x.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Verba planejada (R$)">
          <Input inputMode="decimal" value={f.verba} onChange={(e) => set('verba', e.target.value)} placeholder="10.000,00" />
        </Campo>
        <Campo rotulo="Início"><Input type="date" value={f.inicio} onChange={(e) => set('inicio', e.target.value)} /></Campo>
        <Campo rotulo="Fim"><Input type="date" value={f.fim} onChange={(e) => set('fim', e.target.value)} /></Campo>
        <div className="sm:col-span-2">
          <Campo rotulo="Observação"><Input value={f.obs} onChange={(e) => set('obs', e.target.value)} maxLength={1000} /></Campo>
        </div>
      </div>
      {erro && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erro}</p>}
    </Modal>
  );
}

function Fases({ vida, onEditar, onApagar }: { vida: Vida; onEditar: (f: FaseProjeto) => void; onApagar: (f: FaseProjeto) => void }) {
  if (vida.fases.length === 0 && vida.campanhas_sem_fase === 0) {
    return <EmptyState title="Nenhuma fase planejada" hint="Cadastre as fases (aquecimento, antecipação, captação, lembrete, remarketing, abertura de carrinho) com a verba e o período, ou use Aplicar modelo." />;
  }
  return (
    <DataTable minWidth={720}>
      <Thead><Th>Fase</Th><Th>Período</Th><Th>Planejado</Th><Th>Gasto</Th><Th>% da fase</Th><Th>Campanhas</Th><Th> </Th></Thead>
      <tbody>
        {vida.fases.map((f) => {
          const p = f.gasto != null && f.verba ? Math.round((f.gasto / f.verba) * 1000) / 10 : null;
          return (
            <Tr key={f.fase}>
              <Td><b>{f.nome}</b>{f.id == null && <div className="text-[11px] text-[var(--yellow)]">sem planejamento</div>}</Td>
              <Td>{f.inicio || f.fim ? `${dataBR(f.inicio)} a ${dataBR(f.fim)}` : SEM_DADO}</Td>
              <Td>{f.id == null ? <span className="text-xs text-[var(--fg-3)]">não planejado</span> : reais(f.verba)}</Td>
              <Td>{reais(f.gasto)}</Td>
              <Td>{p == null ? SEM_DADO : <div className="w-28"><ProgressBar value={p} tone={p > 100 ? 'red' : 'accent'} showLabel ariaLabel={`${pct(p)} da verba da fase`} /></div>}</Td>
              <Td>{f.campanhas}</Td>
              <Td>
                <div className="flex gap-1">
                  <Button size="sm" variant="ghost" onClick={() => onEditar(f)} aria-label={f.id == null ? `Planejar ${f.nome}` : `Editar ${f.nome}`}>
                    <Icon name={f.id == null ? 'plus' : 'pencil'} size={12} />
                  </Button>
                  {f.id != null && <Button size="sm" variant="danger" onClick={() => onApagar(f)} aria-label={`Apagar ${f.nome}`}><Icon name="trash" size={12} /></Button>}
                </div>
              </Td>
            </Tr>
          );
        })}
        <Tr>
          <Td><span className="text-[var(--fg-3)]">Sem fase</span></Td><Td> </Td><Td> </Td><Td>{reais(vida.gasto_sem_fase)}</Td><Td> </Td><Td>{vida.campanhas_sem_fase}</Td><Td> </Td>
        </Tr>
      </tbody>
    </DataTable>
  );
}

function Campanhas({ vida, config, flash, onMudou }: { vida: Vida; config: ConfigTrafego; flash: Flash; onMudou: () => void }) {
  if (vida.campanhas.length === 0) {
    return <EmptyState title="Nenhuma campanha ligada" hint="As campanhas chegam pela coleta das plataformas e se ligam ao projeto pela sigla no nome." />;
  }
  const nomeFase = (c: string | null) => config.fases.find((f) => f.codigo === c)?.nome ?? 'sem fase';
  async function trocarFase(id: number, fase: string) {
    const r = await ajustarCampanha({ id, fase: fase || null });
    flash(r.msg);
    if (r.ok) onMudou();
  }
  return (
    <DataTable minWidth={980}>
      <Thead><Th>Campanha</Th><Th>Plataforma</Th><Th>Status</Th><Th>Fase</Th><Th>Gasto</Th><Th>Impressões</Th><Th>Cliques no link</Th><Th>Leads (plataforma)</Th></Thead>
      <tbody>
        {vida.campanhas.map((c) => (
          <Tr key={c.id}>
            <Td>
              <div className="font-mono text-xs break-all">{c.nome}</div>
              {c.fora_padrao && <div className="mt-0.5 text-[11px] text-[var(--yellow)]">Fora do padrão: {c.erros.map((e) => motivoErro(e, { ...c, projeto: c.projeto_lido })).join('; ')}</div>}
              {c.projeto_manual && <div className="text-[11px] text-[var(--fg-3)]">Projeto ligado à mão</div>}
            </Td>
            <Td>{c.plataforma === 'meta' ? 'Meta' : c.plataforma === 'google' ? 'Google' : c.plataforma}</Td>
            <Td>{c.status_plataforma ? rotuloStatusPlataforma(c.status_plataforma) : SEM_DADO}</Td>
            <Td>
              <FilterSelect value={c.fase_manual ?? ''} aria-label="Fase da campanha"
                onChange={(e) => void trocarFase(c.id, e.target.value)}>
                <option value="">Pelo objetivo ({nomeFase(c.fase_objetivo)})</option>
                {config.fases.map((f) => <option key={f.codigo} value={f.codigo}>À mão: {f.nome}</option>)}
              </FilterSelect>
              {c.fase == null && <div className="mt-0.5 text-[11px] text-[var(--yellow)]">sem fase</div>}
            </Td>
            <Td>{reais(c.gasto)}</Td>
            <Td>{inteiro(c.impressoes)}</Td>
            <Td>{inteiro(c.cliques_link)}</Td>
            <Td>{inteiro(c.leads_plataforma)}</Td>
          </Tr>
        ))}
      </tbody>
    </DataTable>
  );
}

export function VidaProjeto({ id, config, listas, contas, versao, onFechar, flash, onMudou }: {
  id: number; config: ConfigTrafego; listas: ListasCadastro | null; contas: Conta[]; versao: number; onFechar: () => void; flash: Flash; onMudou: () => void;
}) {
  const [vida, setVida] = useState<Vida | null | undefined>(undefined);
  const [cad, setCad] = useState<ProjetoCadastro | null>(null);
  const [editProjeto, setEditProjeto] = useState(false);
  const [editPlan, setEditPlan] = useState(false);
  const [editFase, setEditFase] = useState<FaseForm | null>(null);
  const [apagar, setApagar] = useState<FaseProjeto | null>(null);
  const [aplicar, setAplicar] = useState(false);

  useEffect(() => {
    let vivo = true;
    carregarProjeto(id).then((v) => { if (vivo) setVida(v ? { ...v, resumo: comKpis(v.resumo) } : null); });
    carregarCadastro(id).then((c) => { if (vivo) setCad(c); });
    return () => { vivo = false; };
  }, [id, versao]);

  const salvo = (msg: string) => { setEditPlan(false); setEditFase(null); setEditProjeto(false); flash(msg); onMudou(); };

  if (vida === undefined) return <Drawer onClose={onFechar} title="Carregando…"><Loading /></Drawer>;
  if (vida === null) {
    return <Drawer onClose={onFechar} title="Projeto"><p role="alert" className="text-sm text-[var(--red)]">Não foi possível carregar o projeto.</p></Drawer>;
  }

  const r = vida.resumo;
  const esperado = esperadoAte(vida.fases, config.dia_ontem);
  const acima = situacaoRitmo(r.ritmo_ontem) === 'acima';
  const plataformas = r.por_plataforma ? Object.entries(r.por_plataforma) : [];
  const irPara = (id: string) => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  // checklist que leva à ação: cada item pendente abre o lugar onde se resolve
  const acao = (a: AcaoChecklist) => {
    if (a === 'projeto') setEditProjeto(true);
    else if (a === 'planejamento') setEditPlan(true);
    else if (a === 'modelo') setAplicar(true);
    else if (a === 'paginas') window.open('/marketing/projetos', '_blank', 'noopener');
    else irPara({ fases: 'vp-fases', gerador: 'vp-gerador', campanhas: 'vp-campanhas', hotmart: 'vp-hotmart' }[a]);
  };
  const esperadas = cad ? marcarCriadas(cad.esperadas ?? [], vida.campanhas.map((c) => ({ objetivo: c.objetivo, pagina: c.pagina }))) : [];

  return (
    <Drawer
      onClose={onFechar}
      width="max-w-5xl"
      title={<span><span className="font-mono">{r.sigla}</span> · {r.nome}</span>}
      subtitle={[r.tipo ? `${ROTULO_TIPO[r.tipo]}${r.unidade_nome ? ` · ${r.unidade_nome}` : ' · unidade não marcada'}` : 'Tipo não marcado',
        r.tipo_lancamento_nome ?? null, r.gestores.length ? `Gestores ${r.gestores.join(', ')}` : null].filter(Boolean).join(' · ')}
      badges={<>
        {r.status_nome ? <Badge tone={tomStatus(r.status)}>{r.status_nome}</Badge> : <Badge>Sem status</Badge>}
        {r.campanhas_fora_padrao > 0 && <Badge tone="warning">{r.campanhas_fora_padrao} fora do padrão</Badge>}
      </>}
      actions={<div className="flex gap-2">
        {cad && listas && <Button size="sm" variant="subtle" onClick={() => setEditProjeto(true)}><Icon name="pencil" size={12} /> Projeto</Button>}
        <Button size="sm" variant="subtle" onClick={() => setEditPlan(true)}><Icon name="pencil" size={12} /> Planejamento</Button>
      </div>}
    >
      <div className="space-y-5">
        {cad && listas && (
          <SectionCard title="Cadastro do projeto" subtitle="Tipo, unidade, lançamento, especialista, períodos e contas de anúncio. Editar no botão Projeto.">
            <CadastroResumo cad={cad} listas={listas} contas={contas} flash={flash} onMudou={onMudou} onAplicarModelo={() => setAplicar(true)} />
          </SectionCard>
        )}
        {listas && (
          <SectionCard title="Checklist de montagem" subtitle="Por momento: antes de subir as campanhas, durante e encerramento. O sistema confere os automáticos (o link leva até onde se resolve); os manuais alguém marca.">
            <ChecklistPainel projetoId={r.projeto_id} versao={versao} flash={flash} onMudou={onMudou} onAcao={acao} />
          </SectionCard>
        )}
        <SectionCard title="Investido × verba">
          <div className="grid gap-4 sm:grid-cols-2">
            <div>
              <div className="text-2xl font-bold tabular">{reais(r.investido)} <span className="text-sm font-normal text-[var(--fg-3)]">de {reais(r.verba_maxima)}</span></div>
              {r.pct_verba != null && <div className="mt-2"><ProgressBar value={r.pct_verba} tone={r.pct_verba > 100 ? 'red' : 'accent'} showLabel ariaLabel={`${pct(r.pct_verba)} da verba usada`} /></div>}
              <div className="mt-2 text-xs text-[var(--fg-3)]">
                {plataformas.length ? plataformas.map(([p, v]) => `${p === 'meta' ? 'Meta' : p === 'google' ? 'Google' : p}: ${reais(v)}`).join(' · ') : 'Sem gasto coletado ainda.'}
                {r.moedas.some((m) => m !== 'BRL') && <span className="text-[var(--yellow)]"> · Há conta em outra moeda: a soma mistura moedas.</span>}
              </div>
            </div>
            <div>
              <Row k={`Gasto ontem (${dataBR(config.dia_ontem)})`} v={reais(r.gasto_ontem)} />
              <Row k="Verba diária" v={reais(r.verba_diaria)} />
              <Row k="Ritmo de ontem" v={<span className={acima ? 'text-[var(--red)] font-semibold' : ''}>{pct(r.ritmo_ontem)}{acima ? ' (acima da diária)' : ''}</span>} />
              <Row k="Deveria ter gasto até ontem (pelas fases)" v={reais(esperado.valor)} />
              {esperado.semPeriodo > 0 && <p className="text-[11px] text-[var(--fg-3)]">{esperado.semPeriodo} fase(s) com verba e sem período ficaram fora da conta.</p>}
              <Row k="Soma das fases" v={`${reais(r.verba_fases)}${r.verba_maxima != null && r.verba_fases > r.verba_maxima ? ' (acima da verba máxima)' : ''}`} />
            </div>
          </div>
        </SectionCard>

        <SectionCard title="Indicadores × metas" subtitle="Lead = lead da nossa base de pessoas. Leads da plataforma ficam só nas campanhas.">
          <div className="grid gap-x-6 sm:grid-cols-2">
            <Row k="Receita gerada" v={r.receita_aplica === false ? 'não se aplica (externo)' : `${reais(r.receita)} · meta ${reais(r.meta_receita)}`} />
            <Row k="Leads" v={`${inteiro(r.leads)} · meta ${inteiro(r.meta_leads)}`} />
            <Row k="CPL" v={`${centavos(r.cpl)} · meta ${centavos(r.meta_cpl)}`} />
            <Row k="% MQL" v={`${pct(r.pct_mql)} · meta ${pct(r.meta_pct_mql)}`} />
            <Row k="CTR (cliques no link)" v={pct(r.ctr, 2)} />
            <Row k="CPC (cliques no link)" v={centavos(r.cpc)} />
            <Row k="Page views (visitas vindas das campanhas, Web)" v={inteiro(r.page_views)} />
            <Row k="Leads da página (dessas visitas)" v={inteiro(r.leads_pagina)} />
            <Row k="CPM" v={centavos(r.cpm)} />
            <Row k="Connect rate (page views ÷ cliques no link)" v={pct(r.connect_rate)} />
            <Row k="Conversão da página (leads da página ÷ page views)" v={pct(r.conversao_pagina)} />
          </div>
        </SectionCard>

        <div id="vp-fases" />
        <SectionCard title="Fases: planejado × gasto" subtitle="A fase da campanha sai do objetivo do nome (LEADS e VENDAS = captação; AQUECIMENTO; ANTECIPAÇÃO, logo antes da captação; LEMBRETE; REMARKETING; CARRINHO = abertura de carrinho). A correção à mão na campanha prevalece. DISTRIBUIÇÃO fica sem fase até alguém marcar."
          right={<Button size="sm" onClick={() => setEditFase({ projeto_id: r.projeto_id, fase: '', verba: '', inicio: '', fim: '', obs: '' })}><Icon name="plus" size={14} /> Nova fase</Button>}>
          {r.captacao_inicio && <p className="mb-2 text-xs text-[var(--fg-3)]">Fase de captação sem data: vale o período de captação do projeto ({dataBR(r.captacao_inicio)} a {dataBR(r.captacao_fim)}) como padrão.</p>}
          <Fases vida={vida} onApagar={setApagar} onEditar={(f) => setEditFase({
            id: f.id ?? undefined, projeto_id: r.projeto_id, fase: f.fase, verba: txt(f.verba), inicio: f.inicio ?? '', fim: f.fim ?? '', obs: f.obs ?? '',
          })} />
        </SectionCard>

        <div id="vp-campanhas" />
        <SectionCard title="Campanhas do projeto" subtitle={`${vida.campanhas.length} campanha(s); as fora do padrão aparecem marcadas.`}>
          <Campanhas vida={vida} config={config} flash={flash} onMudou={onMudou} />
        </SectionCard>

        {listas && cad && (
          <div id="vp-gerador"><SectionCard title="Gerador de nome de campanha e UTM" subtitle="Monta o nome no padrão GESTOR | PROJETO | OBJETIVO | DESCRIÇÃO | PÁGINA e a linha de parâmetros do Meta.">
            <GeradorCampanha sigla={r.sigla} listas={listas} config={config} paginas={cad.paginas} gestoresProjeto={r.gestores} esperadas={esperadas} flash={flash} onMudou={onMudou} />
          </SectionCard></div>
        )}

        <div id="vp-hotmart" />
        {r.receita_aplica === false ? (
          <SectionCard title="Receita gerada (Hotmart)"><p className="text-sm text-[var(--fg-3)]">Não se aplica: a receita dos projetos externos não entra por ora (Victor, 06/10/2026).</p></SectionCard>
        ) : (
          <SectionCard title="Receita gerada (Hotmart)" subtitle="Compras aprovadas dos produtos ligados a este projeto, no período (sem período no vínculo: do início da captação ao fim do evento, regra provisória). O vínculo é cadastrado à mão.">
            <ProdutosHotmart resumo={r} versao={versao} flash={flash} onMudou={onMudou} />
          </SectionCard>
        )}

        <SectionCard title="Atividades do ClickUp e gasto diário" subtitle="O que a equipe fez (pela etiqueta do projeto) no mesmo eixo do gasto, para ver o efeito de cada ação.">
          <ClickupPainel projetoId={r.projeto_id} serie={vida.serie} ate={config.dia_ontem} versao={versao} />
        </SectionCard>
      </div>

      {editPlan && <ModalPlanejamento vida={vida} onFechar={() => setEditPlan(false)} onSalvo={salvo}
        onEditarProjeto={cad && listas ? () => { setEditPlan(false); setEditProjeto(true); } : undefined} />}
      {editFase && <ModalFase inicial={editFase} config={config} captacao={{ inicio: r.captacao_inicio ?? null, fim: r.captacao_fim ?? null }} onFechar={() => setEditFase(null)} onSalvo={salvo} />}
      {editProjeto && cad && listas && (
        <ModalProjetoCadastro inicial={formDoCadastro(cad)} listas={listas} config={config} contas={contas} onFechar={() => setEditProjeto(false)} onSalvo={salvo} />
      )}
      {aplicar && <ModalAplicarModelo projetoId={r.projeto_id} config={config} onFechar={() => setAplicar(false)} onAplicado={(m) => { setAplicar(false); flash(m); onMudou(); }} />}
      {apagar && apagar.id != null && (
        <ConfirmDialog
          title="Apagar fase"
          message={`Apagar o planejamento da fase ${apagar.nome}? As campanhas continuam nela (pelo objetivo ou à mão), sem verba planejada.`}
          confirmLabel="Apagar"
          danger
          onCancel={() => setApagar(null)}
          onConfirm={async () => { const id = apagar.id!; setApagar(null); const x = await apagarFase(id); flash(x.msg); if (x.ok) onMudou(); }}
        />
      )}
    </Drawer>
  );
}
