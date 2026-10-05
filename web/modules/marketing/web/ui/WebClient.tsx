'use client';

// Marketing > Web: o Radar dentro da central. Filtro por projeto (mkt.projetos, projeto = edição) e período (até 92
// dias), e uma aba por pergunta: visão geral, páginas, funil, origem, velocidade, rolagem e leitura, cliques e erros,
// formulário, instalação. Só admin/dev (gate no layout, na page e no banco: mkt.pode_ver('mkt_web')).
import { useEffect, useMemo, useState } from 'react';
import { useSearchParams } from 'next/navigation';
import { FilterSelect, Input, Loading, SectionCard, Tabs, Toast, useFlash } from '@/shared/ui/components';
import { ultimosDias, validarPeriodo, type Periodo } from '../domain/periodo';
import type { Formulario, Funil, Instalacao, Leitura, LinhaPagina, Origem, Problemas, Velocidade, Visao } from '../domain/tipos';
import { carregar, ligarColeta, listarPaginas, listarProjetos, MODO_DEMO, type PaginaWeb, type ProjetoWeb } from '../infrastructure/web-data';
import {
  PainelFormulario, PainelFunil, PainelInstalacao, PainelLeitura, PainelOrigem, PainelPaginas, PainelProblemas, PainelVelocidade, PainelVisao,
} from './paineis';

const ABAS = [
  { k: 'visao', l: 'Visão geral' },
  { k: 'paginas', l: 'Páginas' },
  { k: 'funil', l: 'Funil' },
  { k: 'origem', l: 'Origem e UTMs' },
  { k: 'velocidade', l: 'Velocidade' },
  { k: 'leitura', l: 'Rolagem e leitura' },
  { k: 'problemas', l: 'Cliques e erros' },
  { k: 'formulario', l: 'Formulário' },
  { k: 'instalacao', l: 'Instalação' },
] as const;
type Aba = (typeof ABAS)[number]['k'];
const PRECISA_PAGINA: ReadonlySet<Aba> = new Set(['leitura', 'formulario']);

type Dados =
  | { aba: 'visao'; v: Visao } | { aba: 'paginas'; v: LinhaPagina[] } | { aba: 'funil'; v: Funil[] } | { aba: 'origem'; v: Origem }
  | { aba: 'velocidade'; v: Velocidade } | { aba: 'leitura'; v: Leitura } | { aba: 'problemas'; v: Problemas }
  | { aba: 'formulario'; v: Formulario } | { aba: 'instalacao'; v: Instalacao };

const abaValida = (a: string | null): Aba => (ABAS.find((x) => x.k === a)?.k ?? 'visao') as Aba;

export function WebClient() {
  const [projetos, setProjetos] = useState<ProjetoWeb[] | null>(null);
  const [projeto, setProjeto] = useState<number | null>(null);
  const [paginas, setPaginas] = useState<PaginaWeb[]>([]);
  const [pagina, setPagina] = useState<number | null>(null);
  const [periodo, setPeriodo] = useState<Periodo>(() => ultimosDias(7));
  const busca = useSearchParams();
  const [aba, setAba] = useState<Aba>(() => abaValida(busca.get('aba')));
  // o resultado guarda a "chave" do pedido (aba, projeto, período, página): carregando = a chave mudou e não chegou
  const [resultado, setResultado] = useState<{ chave: string; dados: Dados | null } | null>(null);
  const [falhouProjetos, setFalhouProjetos] = useState(false);
  const [versao, setVersao] = useState(0);
  const [ocupado, setOcupado] = useState(false);
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
  const chave = [aba, projeto, periodo.de, periodo.ate, pagina, versao].join('|');

  useEffect(() => {
    if (projeto == null || erroPeriodo) return;
    if (PRECISA_PAGINA.has(aba) && pagina == null) return;
    let vivo = true;
    const { de, ate } = periodo;
    const p: Promise<Dados | null> =
      aba === 'visao' ? carregar.visao(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'paginas' ? carregar.paginas(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'funil' ? carregar.funil(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'origem' ? carregar.origem(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'velocidade' ? carregar.velocidade(projeto, de, ate).then((v) => v && { aba, v })
      : aba === 'leitura' ? carregar.leitura(projeto, pagina!, de, ate).then((v) => v && { aba, v })
      : aba === 'problemas' ? carregar.problemas(projeto, pagina, de, ate).then((v) => v && { aba, v })
      : aba === 'formulario' ? carregar.formulario(projeto, pagina!, de, ate).then((v) => v && { aba, v })
      : carregar.instalacao().then((v) => v && { aba: 'instalacao' as const, v });
    p.then((d) => { if (vivo) setResultado({ chave, dados: d }); });
    return () => { vivo = false; };
  }, [projeto, periodo, aba, pagina, erroPeriodo, chave]);

  const atual = resultado?.chave === chave ? resultado : null;
  const carregando = !atual;
  const dados = atual?.dados ?? null;
  const falhou = falhouProjetos || (atual != null && atual.dados == null);

  const base = useMemo(() => (typeof window === 'undefined' ? 'https://grupoparticipa.app.br' : window.location.origin), []);

  async function onLigar(id: number, ligada: boolean) {
    setOcupado(true);
    const r = await ligarColeta(id, ligada);
    setOcupado(false);
    flash(r.msg);
    if (r.ok) setVersao((v) => v + 1);
  }

  if (!projetos) return <Loading />;

  const mostraPagina = aba === 'leitura' || aba === 'formulario' || aba === 'problemas';
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

      <Tabs tabs={ABAS.map((a) => ({ k: a.k, l: a.l }))} active={aba} onChange={trocarAba} idBase="web" label="Telas da Web" />

      {falhou && !carregando && (
        <p role="alert" className="text-sm text-[var(--red)]">
          Não foi possível carregar (erro de rede, sem acesso, ou a migration 20261005n ainda não foi aplicada).
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
          {dados.aba === 'visao' && <PainelVisao v={dados.v} />}
          {dados.aba === 'paginas' && <PainelPaginas linhas={dados.v} />}
          {dados.aba === 'funil' && <PainelFunil funis={dados.v} />}
          {dados.aba === 'origem' && <PainelOrigem o={dados.v} />}
          {dados.aba === 'velocidade' && <PainelVelocidade v={dados.v} />}
          {dados.aba === 'leitura' && <PainelLeitura l={dados.v} />}
          {dados.aba === 'problemas' && <PainelProblemas p={dados.v} />}
          {dados.aba === 'formulario' && <PainelFormulario f={dados.v} />}
          {dados.aba === 'instalacao' && <PainelInstalacao i={dados.v} base={base} onLigar={onLigar} ocupado={ocupado} />}
        </div>
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}
