'use client';

// Dashboard da Black Friday 2026 (Infra › Dashboards › CSM, modelo 'jornada-captacao').
// Lê pela FonteDadosBlack (demonstração ou real), cada bloco com timeout e try/catch próprios: falha segura a
// última leitura, esmaece e mostra a idade. Recorte na URL (router.replace, sem rolar). Releitura a cada 5 min
// só com a aba do navegador visível (molde do ATM). Contrato: docs/dashboard-black/README.md.
import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { Button, EmptyState, Loading, SectionCard, Tabs, idsAba } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import type { FonteDadosBlack } from '../application/ports';
import { obterFonte } from '../infrastructure/fonte';
import { alinharIds } from '../domain/alinhar';
import { chaveRecorte, recorteDaTela } from '../domain/grupo';
import { filtrarDias, filtrarLinhas, indexar } from '../domain/metricas';
import { diaDe, diasDoPeriodo, escreverRecorte, periodoDe } from '../domain/recorte';
import type { AbaBlack, ConfigBlack, GrupoResumoBlack, LinhaPerfil, Marcos, MensageriaBlack, Recorte, Resultado, TotalPeriodo, TrafegoBlack } from '../domain/tipos';
import type { AlvoGaveta, DadosTela } from './contexto';
import { AvisoBloco } from './pecas';
import { SeletorGlobal } from './SeletorGlobal';
import { AbaVisaoGeral } from './AbaVisaoGeral';
import { AbaJornada } from './AbaJornada';
import { AbaCriativosPaginas } from './AbaCriativosPaginas';
import { AbaMensageria } from './AbaMensageria';
import { AbaHistorico } from './AbaHistorico';
import { GavetaLateral } from './GavetaLateral';

const TEMPO_LIMITE_MS = 15_000;
const RELEITURA_MS = 5 * 60_000;

const ABAS_TELA: { k: AbaBlack; l: string }[] = [
  { k: 'visao', l: 'Visão geral' },
  { k: 'jornada', l: 'Jornada' },
  { k: 'criativos', l: 'Criativos e páginas' },
  { k: 'mensageria', l: 'Mensageria' },
  { k: 'historico', l: 'Histórico' },
];

interface Bloco<T> { data: T | null; semDado: boolean; erro: string | null; aviso: string | null; lidoEm: Date | null }
const vazio = <T,>(): Bloco<T> => ({ data: null, semDado: false, erro: null, aviso: null, lidoEm: null });

function comTempo<T>(p: Promise<T>, ms = TEMPO_LIMITE_MS): Promise<T> {
  return new Promise<T>((ok, falha) => {
    const t = setTimeout(() => falha(new Error('tempo esgotado')), ms);
    p.then((v) => { clearTimeout(t); ok(v); }, (e) => { clearTimeout(t); falha(e); });
  });
}

/** Lê um bloco. Erro (ou timeout) mantém a última leitura e marca o erro; sem dado legítimo substitui. */
async function lerBloco<T>(nome: string, f: () => Promise<Resultado<T>>, set: (fn: (b: Bloco<T>) => Bloco<T>) => void) {
  try {
    const r = await comTempo(f());
    if (r.erro) set((b) => ({ ...b, erro: `Falha ao ler ${nome}: ${r.erro}` }));
    else set(() => ({ data: r.data, semDado: r.semDado, erro: null, aviso: r.aviso ?? null, lidoEm: new Date() }));
  } catch (e) {
    const motivo = e instanceof Error && e.message === 'tempo esgotado' ? 'tempo esgotado' : 'erro na leitura';
    set((b) => ({ ...b, erro: `Falha ao ler ${nome} (${motivo}).` }));
  }
}

const horaCurta = (d: Date) => d.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });
const dataHora = (iso: string) => new Date(iso).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit', timeZone: 'America/Sao_Paulo' });

export function DashboardBlackClient({ chave, titulo, relogio, recorteInicial, isMaster = false }: {
  chave: string; titulo: string; relogio: string | null; recorteInicial: Recorte;
  /** Master vê e marca os testes (padrão do ATM). */
  isMaster?: boolean;
}) {
  const router = useRouter();
  const [recorte, setRecorte] = useState<Recorte>(recorteInicial);
  const [fonte, setFonte] = useState<FonteDadosBlack | null>(null);
  const [erroFonte, setErroFonte] = useState<string | null>(null);
  const [config, setConfig] = useState<Bloco<ConfigBlack>>(vazio);
  const [trafego, setTrafego] = useState<Bloco<TrafegoBlack>>(vazio);
  const [totais, setTotais] = useState<Bloco<TotalPeriodo[]>>(vazio);
  const [perfil, setPerfil] = useState<Bloco<LinhaPerfil[]>>(vazio);
  const [mensageria, setMensageria] = useState<Bloco<MensageriaBlack>>(vazio);
  const [marcos, setMarcos] = useState<Bloco<Marcos>>(vazio);
  const [grupo, setGrupo] = useState<Bloco<GrupoResumoBlack>>(vazio);
  const [versao, setVersao] = useState(0);
  const [lida, setLida] = useState<string | null>(null);
  const [gaveta, setGaveta] = useState<AlvoGaveta | null>(null);
  const [relogioTela, setRelogioTela] = useState(() => new Date());
  const ultimaLeitura = useRef(0);

  useEffect(() => {
    let vivo = true;
    obterFonte(relogio).then((f) => { if (vivo) setFonte(f); }, () => { if (vivo) setErroFonte('Não foi possível abrir a fonte de dados.'); });
    return () => { vivo = false; };
  }, [relogio]);

  // Período escolhido, calculado só quando a config chega.
  const agora = useMemo(() => (fonte ? fonte.agora() : null), [fonte, versao]); // eslint-disable-line react-hooks/exhaustive-deps
  const cfg = config.data;
  const periodo = useMemo(() => (cfg && agora ? periodoDe(recorte.periodo, agora, cfg) : null), [cfg, agora, recorte.periodo]);
  const completo = useMemo(() => (cfg && agora ? periodoDe('desde-inicio', agora, cfg) : null), [cfg, agora]);

  // 1) config
  useEffect(() => {
    if (!fonte) return;
    void lerBloco('a configuração', () => fonte.config(chave), setConfig);
  }, [fonte, chave, versao]);

  // 2) o resto, em paralelo, depois da config
  const de = periodo?.de; const ate = periodo?.ate; const inicio = completo?.de; const hoje = completo?.ate;
  useEffect(() => {
    if (!fonte || !de || !ate || !inicio || !hoje) return;
    const periodo = { de, ate }; const completo = { de: inicio, ate: hoje };
    let vivo = true;
    const marca = `${de}|${ate}|${inicio}|${hoje}|${versao}`;
    Promise.all([
      lerBloco('o tráfego', () => fonte.trafego(chave, completo), setTrafego),
      lerBloco('o alcance do período', async () => {
        const r = await fonte.trafego(chave, periodo);
        return { data: r.data.totais, semDado: r.semDado, erro: r.erro };
      }, setTotais),
      // Master recebe também os testes (para ver e desmarcar); a tela tira os testes de todas as contas.
      lerBloco('os cadastros', () => fonte.perfil(chave, completo, { incluirTeste: isMaster }), setPerfil),
      lerBloco('a mensageria', () => fonte.mensageria(chave, periodo), setMensageria),
      lerBloco('os marcos da live', () => fonte.marcos(chave), setMarcos),
    ]).finally(() => { if (vivo) { setLida(marca); ultimaLeitura.current = Date.now(); setRelogioTela(new Date()); } });
    return () => { vivo = false; };
  }, [fonte, chave, de, ate, inicio, hoje, versao, isMaster]);

  // 3) grupo: período e nó da tela (funil, ou o anúncio/conjunto/campanha/página escolhido, pelo id do Meta) vão ao
  // servidor (p_recorte); sem teste.
  const { campanha: fCampanha, conjunto: fConjunto, anuncio: fAnuncio, pagina: fPagina } = recorte.criativos;
  const alvoGrupo = useMemo(
    () => recorteDaTela({ funil: recorte.funil, canal: recorte.canal, criativos: { campanha: fCampanha, conjunto: fConjunto, anuncio: fAnuncio, pagina: fPagina } }, trafego.data),
    [recorte.funil, recorte.canal, fCampanha, fConjunto, fAnuncio, fPagina, trafego.data],
  );
  const marcaRecorte = alvoGrupo.ok ? chaveRecorte(alvoGrupo.recorte) : 'sem-numero';
  useEffect(() => {
    if (!fonte || !de || !ate || !alvoGrupo.ok) return;
    void lerBloco('o grupo', () => fonte.grupo(chave, { de, ate }, alvoGrupo.recorte), setGrupo);
  }, [fonte, chave, de, ate, marcaRecorte, versao]); // eslint-disable-line react-hooks/exhaustive-deps

  // Releitura a cada 5 min, só com a aba visível; ao voltar para a aba, relê se passou do prazo.
  useEffect(() => {
    const reler = () => { if (document.visibilityState === 'visible') setVersao((v) => v + 1); };
    const id = window.setInterval(reler, RELEITURA_MS);
    const aoVoltar = () => { if (document.visibilityState === 'visible' && Date.now() - ultimaLeitura.current > RELEITURA_MS) reler(); };
    document.addEventListener('visibilitychange', aoVoltar);
    return () => { window.clearInterval(id); document.removeEventListener('visibilitychange', aoVoltar); };
  }, []);

  const irPara = useCallback((m: Partial<Recorte>) => {
    const novo: Recorte = { ...recorte, ...m, criativos: m.criativos ?? recorte.criativos };
    setRecorte(novo);
    const extras = new URLSearchParams();
    if (relogio) extras.set('relogio', relogio);
    router.replace(`?${escreverRecorte(novo, extras)}`, { scroll: false });
  }, [recorte, relogio, router]);

  const dados = useMemo<DadosTela | null>(() => {
    if (!fonte || !cfg || !agora || !periodo || !trafego.data || !perfil.data) return null;
    const t = trafego.data;
    const idx = indexar(t);
    const diasPeriodoSemFiltro = t.dias.filter((d) => d.dia >= periodo.de && d.dia <= periodo.ate);
    // O lead traz os ids do Meta; o tráfego, os internos. Casa pelo anúncio (domain/alinhar.ts).
    const linhasBase = alinharIds(perfil.data, t);
    const linhasTodas = linhasBase.filter((l) => !l.teste);
    const noPeriodo = (l: LinhaPerfil) => { const d = diaDe(l.criadoEm); return d >= periodo.de && d <= periodo.ate; };
    const linhasPeriodoSemFiltro = linhasTodas.filter((l) => { const d = diaDe(l.criadoEm); return d >= periodo.de && d <= periodo.ate; });
    const filtro = { funil: recorte.funil, canal: recorte.canal };
    return {
      chave, fonte, config: cfg, agora, recorte, periodo, diasPeriodo: diasDoPeriodo(periodo),
      trafego: t, totaisPeriodo: totais.data ?? [], idx, paginas: new Map(t.paginas.map((p) => [p.id, p])),
      diasTodos: t.dias, diasPeriodoSemFiltro, dias: filtrarDias(diasPeriodoSemFiltro, idx, filtro),
      linhasTodas, linhasPeriodoSemFiltro, linhas: filtrarLinhas(linhasPeriodoSemFiltro, filtro),
      mensageria: mensageria.data, mensageriaSemDado: mensageria.semDado || mensageria.data === null, marcos: marcos.data,
      perfilSemDado: perfil.semDado, avisoPerfil: perfil.aviso,
      linhasTeste: isMaster ? linhasBase.filter((l) => l.teste && noPeriodo(l)) : [],
      grupo: alvoGrupo.ok
        ? { data: grupo.data, semDado: grupo.semDado || grupo.data === null, aviso: grupo.aviso, motivo: null, erro: grupo.erro, descricao: alvoGrupo.descricao ?? null }
        : { data: null, semDado: true, aviso: null, motivo: alvoGrupo.motivo, erro: null, descricao: null },
      isMaster, recarregar: () => setVersao((v) => v + 1),
      irPara, abrirGaveta: setGaveta,
    };
  }, [fonte, cfg, agora, periodo, trafego.data, perfil.data, perfil.semDado, perfil.aviso, totais.data, mensageria.data, mensageria.semDado, marcos.data, grupo, alvoGrupo, isMaster, recorte, chave, irPara]);

  const marcaAtual = de && ate && inicio && hoje ? `${de}|${ate}|${inicio}|${hoje}|${versao}` : null;
  const lendo = marcaAtual !== null && lida !== marcaAtual;
  const erros = [config, trafego, totais, perfil, mensageria, marcos, grupo].filter((b) => b.erro);
  const avisos = ([['Tráfego', trafego], ['Cadastros', perfil], ['Grupo', grupo]] as const).filter(([, b]) => b.aviso && !b.erro);
  const esmaecido = Boolean(trafego.erro || perfil.erro || config.erro);
  const lidoEm = trafego.lidoEm ?? perfil.lidoEm;
  // Só a config derruba a tela inteira: sem tráfego ou sem cadastros, cada bloco mostra o seu "Sem dado".
  const semFonteReal = config.semDado;
  const ids = (k: AbaBlack) => idsAba('black-principal', k);

  return (
    <div className="mx-auto w-full max-w-7xl space-y-4 overflow-x-clip">
      <header className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <div className="text-xs font-semibold uppercase tracking-wide text-[var(--accent)]">Infra / Dashboards / CSM</div>
          <h1 className="mt-1 text-2xl font-bold text-[var(--fg)]">{titulo}</h1>
          <p className="mt-1 text-sm text-[var(--fg-2)]">
            {cfg?.liveEm ? `Live em ${dataHora(cfg.liveEm)}. ` : ''}
            {trafego.data?.coletadoEm ? `Tráfego coletado em ${dataHora(trafego.data.coletadoEm)}.` : 'Coleta do tráfego: sem dado.'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          {lidoEm && <span className="text-xs text-[var(--fg-3)]">Lido às {horaCurta(lidoEm)}</span>}
          <Button variant="ghost" size="sm" onClick={() => setVersao((v) => v + 1)} disabled={lendo || !fonte} aria-label="Atualizar os dados">
            <span className="inline-flex items-center gap-1.5"><Icon name="refresh" size={14} />{lendo ? 'Lendo…' : 'Atualizar'}</span>
          </Button>
        </div>
      </header>

      {fonte?.modo === 'demonstracao' && (
        <div role="note" className="rounded-[var(--r-md)] border border-[var(--yellow)]/40 bg-[var(--surface-2)] p-3 text-sm text-[var(--yellow)]">
          Dados de demonstração (fictícios). Nenhum número desta tela é real: campanhas com prefixo ZZ e a palavra FICTÍCIO, leads com nome de teste e e-mail em exemplo.test.
          {relogio ? ` Relógio da demonstração fixado em ${relogio.split('-').reverse().join('/')}.` : ' Relógio da demonstração: 03/11 às 18h.'}
        </div>
      )}

      <SeletorGlobal funil={recorte.funil} periodo={recorte.periodo} canal={recorte.canal} datas={periodo} onChange={irPara} />

      {erroFonte && <p role="alert" className="text-sm text-[var(--red)]">{erroFonte}</p>}
      {erros.map((b) => <AvisoBloco key={b.erro} erro={b.erro} lidoEm={b.lidoEm} agora={relogioTela} />)}
      {avisos.map(([nome, b]) => (
        <p key={nome} role="note" className="text-xs text-[var(--fg-3)]">{nome}: {b.aviso}. Os números deste bloco ficam como Sem dado.</p>
      ))}

      {!fonte || (!dados && !semFonteReal && (lendo || !config.lidoEm)) ? (
        <Loading label="Lendo os dados da Black…" />
      ) : semFonteReal ? (
        <SectionCard title="Sem dado">
          <EmptyState icon="chart" title="Dashboard sem cadastro"
            hint="A chave não tem cadastro na fonte real: todos os números ficam como Sem dado. Ver docs/dashboard-black/README.md." />
        </SectionCard>
      ) : !dados ? (
        <SectionCard title="Sem dado"><EmptyState title="Não há leitura para mostrar" hint="Tente Atualizar." /></SectionCard>
      ) : (
        <div className={esmaecido ? 'opacity-60 transition-opacity' : 'transition-opacity'}>
          <Tabs tabs={ABAS_TELA} active={recorte.aba} onChange={(k) => irPara({ aba: k as AbaBlack })} idBase="black-principal" label="Seções do dashboard" />
          {ABAS_TELA.map(({ k }) => (
            <section key={k} role="tabpanel" id={ids(k).panel} aria-labelledby={ids(k).tab} hidden={recorte.aba !== k} className="atm-historico-panel-enter">
              {recorte.aba === k && k === 'visao' && <AbaVisaoGeral d={dados} />}
              {recorte.aba === k && k === 'jornada' && <AbaJornada d={dados} gaveta={gaveta} />}
              {recorte.aba === k && k === 'criativos' && <AbaCriativosPaginas d={dados} gaveta={gaveta} />}
              {recorte.aba === k && k === 'mensageria' && <AbaMensageria d={dados} />}
              {recorte.aba === k && k === 'historico' && <AbaHistorico d={dados} />}
            </section>
          ))}
          <GavetaLateral d={dados} alvo={gaveta} onClose={() => setGaveta(null)} onTrocar={setGaveta} />
        </div>
      )}
    </div>
  );
}
