'use client';

// Marketing > Web: o Radar dentro da central. Filtro por projeto (mkt.projetos, projeto = edição) e período (até 92
// dias), e uma aba por pergunta: visão geral, páginas, funil, fluxo, origem, velocidade, rolagem e leitura, mapa de calor,
// cliques e erros, formulário, melhorias, instalação. Só admin/dev (gate no layout, na page e no banco:
// mkt.pode_ver('mkt_web')). Fluxo, mapa de calor, melhorias, laboratório do Google, leads na base de pessoas e connect
// rate são da fase 2 (migration 20261006h).
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { FilterSelect, Input, Loading, SectionCard, Tabs, Toast, useFlash } from '@/shared/ui/components';
import { ultimosDias, validarPeriodo, type Periodo } from '../domain/periodo';
import type {
  Calor, Connect, Formulario, Fluxo, Funil, Instalacao, Lab, LeadsPessoas, Leitura, LinhaPagina, Melhorias, Origem, Problemas, Velocidade, Visao,
} from '../domain/tipos';
import { diaSP } from '../domain/periodo';
import { carregar, ligarColeta, listarPaginas, listarProjetos, MODO_DEMO, type PaginaWeb, type ProjetoWeb } from '../infrastructure/web-data';
import {
  PainelFormulario, PainelFunil, PainelInstalacao, PainelLeitura, PainelOrigem, PainelPaginas, PainelProblemas, PainelVelocidade, PainelVisao,
} from './paineis';
import { PainelAchados, PainelFluxo, PainelTestesAB, SecaoConnect, SecaoLab, SecaoLeads } from './paineis-fase2';
import { PainelCalor, type Camada } from './MapaCalor';
import { Comparar } from './Comparar';

const ABAS = [
  { k: 'visao', l: 'Visão geral' },
  { k: 'paginas', l: 'Páginas' },
  { k: 'funil', l: 'Funil' },
  { k: 'fluxo', l: 'Fluxo' },
  { k: 'origem', l: 'Origem e UTMs' },
  { k: 'velocidade', l: 'Velocidade' },
  { k: 'leitura', l: 'Rolagem e leitura' },
  { k: 'calor', l: 'Mapa de calor' },
  { k: 'problemas', l: 'Cliques e erros' },
  { k: 'formulario', l: 'Formulário' },
  { k: 'melhorias', l: 'Melhorias' },
  { k: 'instalacao', l: 'Instalação' },
] as const;
type Aba = (typeof ABAS)[number]['k'];
const PRECISA_PAGINA: ReadonlySet<Aba> = new Set(['leitura', 'formulario', 'calor']);

type Dados =
  | { aba: 'visao'; v: Visao; leads: LeadsPessoas | null } | { aba: 'paginas'; v: LinhaPagina[] } | { aba: 'funil'; v: Funil[] }
  | { aba: 'origem'; v: Origem; connect: Connect | null } | { aba: 'velocidade'; v: Velocidade; lab: Lab | null } | { aba: 'leitura'; v: Leitura }
  | { aba: 'problemas'; v: Problemas } | { aba: 'formulario'; v: Formulario } | { aba: 'instalacao'; v: Instalacao }
  | { aba: 'fluxo'; v: Fluxo } | { aba: 'calor'; v: Calor } | { aba: 'melhorias'; v: Melhorias };
type VistaMelhorias = 'achados' | 'testes' | 'comparar';
const DISPOSITIVOS = [{ k: 'mobile', l: 'Celular' }, { k: 'desktop', l: 'Computador' }, { k: 'tablet', l: 'Tablet' }] as const;

const abaValida = (a: string | null): Aba => (ABAS.find((x) => x.k === a)?.k ?? 'visao') as Aba;

export function WebClient({ canEdit = true }: { canEdit?: boolean }) {
  const [projetos, setProjetos] = useState<ProjetoWeb[] | null>(null);
  const [projeto, setProjeto] = useState<number | null>(null);
  const [paginas, setPaginas] = useState<PaginaWeb[]>([]);
  const [pagina, setPagina] = useState<number | null>(null);
  const [periodo, setPeriodo] = useState<Periodo>(() => ultimosDias(7));
  const busca = useSearchParams();
  const [aba, setAba] = useState<Aba>(() => { const inicial = abaValida(busca.get('aba')); return !canEdit && inicial === 'instalacao' ? 'visao' : inicial; });
  // o resultado guarda a "chave" do pedido (aba, projeto, período, página): carregando = a chave mudou e não chegou
  const [resultado, setResultado] = useState<{ chave: string; dados: Dados | null } | null>(null);
  const [falhouProjetos, setFalhouProjetos] = useState(false);
  const [versao, setVersao] = useState(0);
  const [ocupado, setOcupado] = useState(false);
  const [dispositivo, setDispositivo] = useState<string>('mobile');
  const [camada, setCamada] = useState<Camada>('cliques');
  const [vista, setVista] = useState<VistaMelhorias>('achados');
  const { toast, flash } = useFlash();

  const trocarAba = (k: string) => {
    setAba(k as Aba);
    try { const u = new URL(window.location.href); u.searchParams.set('aba', k); window.history.replaceState(null, '', u); } catch { /* sem URL */ }
  };

  // projetos (o ativo com mais chance de ter dado primeiro: o PB26 quando existe)
  useEffect(() => {
    let vivo = true;
    listarProjetos().then((p) => {
      if (!vivo) return;
      setProjetos(p ?? []);
      if (!p) setFalhouProjetos(true);
      const pb = p?.find((x) => x.sigla === 'PB26') ?? p?.[0];
      if (pb) setProjeto(pb.id);
    });
    return () => { vivo = false; };
  }, []);

  // páginas do projeto (para as abas por página)
  useEffect(() => {
    if (projeto == null) return;
    let vivo = true;
    listarPaginas(projeto).then((g) => {
      if (!vivo) return;
      const lista = g ?? [];
      setPaginas(lista);
      setPagina((atual) => (lista.some((x) => x.id === atual) ? atual : (lista.find((x) => x.funcao === 'captura') ?? lista[0])?.id ?? null));
    });
    return () => { vivo = false; };
  }, [projeto]);

  const erroPeriodo = validarPeriodo(periodo);
  const chave = [aba, projeto, periodo.de, periodo.ate, pagina, versao, aba === 'calor' ? dispositivo : ''].join('|');

  useEffect(() => {
    if (projeto == null || erroPeriodo) return;
    if (PRECISA_PAGINA.has(aba) && pagina == null) return;
    let vivo = true;
    const { de, ate } = periodo;
    // as seções da fase 2 dentro das abas antigas (leads, connect rate, laboratório) não derrubam a aba se falharem
    // (migration 20261006h não aplicada): voltam nulas e somem da tela
    const p: Promise<Dados | null> =
      aba === 'visao' ? Promise.all([carregar.visao(projeto, de, ate), carregar.leads(projeto, de, ate)]).then(([v, leads]) => v && { aba, v, leads })
      : aba === 'paginas' ? carregar.paginas(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'funil' ? carregar.funil(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'fluxo' ? carregar.fluxo(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'origem' ? Promise.all([carregar.origem(projeto, de, ate), carregar.connect(projeto, de, ate)]).then(([v, connect]) => v && { aba, v, connect })
      : aba === 'velocidade' ? Promise.all([carregar.velocidade(projeto, de, ate), carregar.lab(projeto)]).then(([v, lab]) => v && { aba, v, lab })
      : aba === 'calor' ? carregar.calor(projeto, pagina!, dispositivo, de, ate).then((v) => v && { aba, v })
      : aba === 'melhorias' ? carregar.melhorias(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'leitura' ? carregar.leitura(projeto, pagina!, de, ate).then((v) => v && { aba, v })
      : aba === 'problemas' ? carregar.problemas(projeto, pagina, de, ate).then((v) => v && { aba, v })
      : aba === 'formulario' ? carregar.formulario(projeto, pagina!, de, ate).then((v) => v && { aba, v })
      : carregar.instalacao().then((v) => v && { aba: 'instalacao' as const, v });
    p.then((d) => { if (vivo) setResultado({ chave, dados: d }); });
    return () => { vivo = false; };
  }, [projeto, periodo, aba, pagina, erroPeriodo, chave, dispositivo]);

  const atual = resultado?.chave === chave ? resultado : null;
  const carregando = !atual;
  const dados = atual?.dados ?? null;
  const falhou = falhouProjetos || (atual != null && atual.dados == null);

  const base = useMemo(() => (typeof window === 'undefined' ? 'https://grupoparticipa.app.br' : window.location.origin), []);

  async function onLigar(id: number, ligada: boolean) {
    if (!canEdit) return;
    setOcupado(true);
    const r = await ligarColeta(id, ligada);
    setOcupado(false);
    flash(r.msg);
    if (r.ok) setVersao((v) => v + 1);
  }

  if (!projetos) return <Loading />;

  const mostraPagina = aba === 'leitura' || aba === 'formulario' || aba === 'problemas' || aba === 'calor';
  const mostraFiltros = aba !== 'instalacao';

  return (
    <div className="max-w-6xl space-y-5">
      <div>
        <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Marketing</div>
        <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">Web</h1>
        <p className="mt-1 text-sm text-[var(--fg-2)]">
          Como as pessoas usam as páginas de cada projeto: visitas, funil, origem, velocidade, leitura, cliques e formulário. Sem dado pessoal.
        </p>
      </div>

      {MODO_DEMO && (
        <p role="status" className="rounded-[var(--r-md)] border border-[var(--yellow)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)]">
          <b>Dados de demonstração.</b> Números inventados para ver a tela (NEXT_PUBLIC_WEB_DEMO=1, só no computador local). Não usar para análise.
        </p>
      )}

      <SectionCard>
        <div className="flex flex-wrap items-end gap-3">
          <label className="block">
            <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Projeto</span>
            <FilterSelect value={projeto ?? ''} onChange={(e) => setProjeto(e.target.value ? Number(e.target.value) : null)} aria-label="Projeto">
              {projetos.length === 0 && <option value="">Nenhum projeto cadastrado</option>}
              {projetos.map((p) => <option key={p.id} value={p.id}>{p.sigla} · {p.nome}</option>)}
            </FilterSelect>
          </label>
          {mostraFiltros && (
            <>
              <label className="block">
                <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Período</span>
                <FilterSelect value="" onChange={(e) => e.target.value && setPeriodo(ultimosDias(Number(e.target.value)))} aria-label="Período pronto">
                  <option value="">Escolher…</option>
                  <option value="1">Hoje</option>
                  <option value="7">Últimos 7 dias</option>
                  <option value="30">Últimos 30 dias</option>
                  <option value="90">Últimos 90 dias</option>
                </FilterSelect>
              </label>
              <label className="block">
                <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">De</span>
                <Input type="date" value={periodo.de} onChange={(e) => setPeriodo((x) => ({ ...x, de: e.target.value }))} />
              </label>
              <label className="block">
                <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Até</span>
                <Input type="date" value={periodo.ate} onChange={(e) => setPeriodo((x) => ({ ...x, ate: e.target.value }))} />
              </label>
            </>
          )}
          {aba === 'calor' && (
            <label className="block">
              <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Aparelho</span>
              <FilterSelect value={dispositivo} onChange={(e) => setDispositivo(e.target.value)} aria-label="Aparelho">
                {DISPOSITIVOS.map((d) => <option key={d.k} value={d.k}>{d.l}</option>)}
              </FilterSelect>
            </label>
          )}
          {aba === 'melhorias' && (
            <label className="block">
              <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Ver</span>
              <FilterSelect value={vista} onChange={(e) => setVista(e.target.value as VistaMelhorias)} aria-label="Melhorias">
                <option value="achados">Achados automáticos</option>
                <option value="testes">Testes A/B</option>
                <option value="comparar">Comparar</option>
              </FilterSelect>
            </label>
          )}
          {mostraPagina && (
            <label className="block">
              <span className="block text-xs font-medium text-[var(--fg-2)] mb-1">Página</span>
              <FilterSelect value={pagina ?? ''} onChange={(e) => setPagina(e.target.value ? Number(e.target.value) : null)} aria-label="Página">
                {aba === 'problemas' && <option value="">Todas as páginas</option>}
                {paginas.length === 0 && aba !== 'problemas' && <option value="">Nenhuma página cadastrada</option>}
                {paginas.map((g) => <option key={g.id} value={g.id}>{g.nome} ({g.caminho})</option>)}
              </FilterSelect>
            </label>
          )}
        </div>
        {erroPeriodo && mostraFiltros && <p role="alert" className="mt-2 text-sm text-[var(--red)]">{erroPeriodo}</p>}
      </SectionCard>

      <Tabs tabs={ABAS.filter((a) => canEdit || a.k !== 'instalacao').map((a) => ({ k: a.k, l: a.l }))} active={!canEdit && aba === 'instalacao' ? 'visao' : aba} onChange={trocarAba} idBase="web" label="Telas da Web" />

      {falhou && !carregando && (
        <p role="alert" className="text-sm text-[var(--red)]">
          Não foi possível carregar (sem conexão ou sem acesso). Recarregue a página; se continuar, avise quem cuida do sistema.
        </p>
      )}
      {projeto == null ? (
        <SectionCard><p className="text-sm text-[var(--fg-2)]">Cadastre um projeto em Marketing &gt; Projetos e páginas.</p></SectionCard>
      ) : PRECISA_PAGINA.has(aba) && pagina == null ? (
        <SectionCard><p className="text-sm text-[var(--fg-2)]">Este projeto não tem página cadastrada. Cadastre em Marketing &gt; Projetos e páginas.</p></SectionCard>
      ) : erroPeriodo ? null : carregando || !dados || dados.aba !== aba ? (
        falhou ? null : <Loading />
      ) : (
        <div role="tabpanel" id="web-panel" aria-label={ABAS.find((a) => a.k === aba)?.l}>
          {dados.aba === 'visao' && <div className="space-y-4"><PainelVisao v={dados.v} /><SecaoLeads l={dados.leads} /></div>}
          {dados.aba === 'paginas' && <PainelPaginas linhas={dados.v} />}
          {dados.aba === 'funil' && <PainelFunil funis={dados.v} />}
          {dados.aba === 'fluxo' && <PainelFluxo f={dados.v} />}
          {dados.aba === 'origem' && <div className="space-y-4"><PainelOrigem o={dados.v} /><SecaoConnect c={dados.connect} /></div>}
          {dados.aba === 'velocidade' && <div className="space-y-4"><PainelVelocidade v={dados.v} /><SecaoLab lab={dados.lab} /></div>}
          {dados.aba === 'calor' && <PainelCalor key={chave} c={dados.v} camada={camada} onCamada={setCamada} />}
          {dados.aba === 'melhorias' && (vista === 'achados' ? <PainelAchados m={dados.v} />
            : vista === 'testes' ? <PainelTestesAB m={dados.v} hoje={diaSP(new Date())} />
            : <Comparar key={projeto} paginas={paginas} periodo={periodo}
                carregar={(a, b) => carregar.comparar(projeto, a, b)} />)}
          {dados.aba === 'leitura' && <PainelLeitura l={dados.v} />}
          {dados.aba === 'problemas' && <PainelProblemas p={dados.v} />}
          {dados.aba === 'formulario' && <PainelFormulario f={dados.v} />}
          {canEdit && dados.aba === 'instalacao' && <PainelInstalacao i={dados.v} base={base} onLigar={onLigar} ocupado={ocupado} />}
        </div>
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
