'use client';

// Funis de venda, no modelo da Clint: agrupadores (pastas) com funis dentro; cada funil tem etapas próprias,
// campanhas de entrada e distribuição. O título da página é o funil aberto; o seletor troca de funil.
// O gestor cria funis pelo assistente passo a passo (ou vários de uma vez em "Comecei um novo projeto") e edita
// pelo editor por abas; todo mundo trabalha os negócios (arrastar, menu "Mover para…" ou a ficha).
import { useEffect, useMemo, useState } from 'react';
import { Button, FilterSelect, SearchInput, Skeleton, Toast, useFlash } from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_ORIGEM } from '../../domain/catalogo';
import { motivoSomenteLeitura, travaMover } from '../../domain/travas';
import type { Funil, Negocio } from '../../domain/types';
import { Aviso, EstadoErro, FaixaErroAtualizacao, FaixaNumeros, PaginaComercial, useEquipe, useParamUrl, Vazio } from '../comum';
import { ContatoDrawer } from '../contatos/ContatoDrawer';
import { ModalNovoNegocio } from '../ModalNovoNegocio';
import { ModalAtividade, NegocioDrawer } from '../NegocioDrawer';
import { avisarMudanca, repo, useAgora, useContatosPorIds, useDados } from '../repositorio';
import { iconeDoFunil } from './assistente';
import { AssistenteFunil } from './AssistenteFunil';
import { EditorFunil } from './EditorFunil';
import { ModalNovoProjeto } from './ModalNovoProjeto';
import { PainelAtivacao } from './PainelAtivacao';
import { KanbanFunil } from './KanbanFunil';
import { useAlturaRestante } from './pecas';
import { filtrarNegocios, resumoFunil, type FiltroAlerta, type FiltroDono } from './regras-funil';
import { SeletorFunil } from './SeletorFunil';

const CHAVE_FUNIL = 'gp_comercial_funil';

export function FunilClient() {
  const agora = useAgora();
  const { toast, flash } = useFlash();
  const { sessao, vendedores, nomeDe, gestor, verTudo, leitor } = useEquipe();
  const qFunis = useDados(() => repo.funis());
  const qAgrupadores = useDados(() => repo.agrupadores());
  const qNegocios = useDados(() => repo.negocios());
  // Ativação (20261007135415): sem a migration no banco, a faixa só não aparece (o kanban segue).
  const qAtivacao = useDados(() => repo.ativacao());
  // Só os contatos dos negócios carregados (não a base inteira).
  const qContatos = useContatosPorIds(qNegocios.dados?.map((n) => n.contatoId));
  const funis = qFunis.dados;
  const agrupadores = qAgrupadores.dados;
  const negocios = qNegocios.dados;
  const contatos = qContatos.dados;
  const paramNegocio = useParamUrl('negocio');
  const paramFunil = useParamUrl('f');

  const [funilId, setFunilId] = useState<string | null>(null);
  const [dono, setDono] = useState<FiltroDono>('todos');
  const [busca, setBusca] = useState('');
  const [fichaPessoa, setFichaPessoa] = useState<string | null>(null);
  const [alerta, setAlerta] = useState<FiltroAlerta>(null);
  const [aberto, setAberto] = useState<string | null>(null);
  const [novoNegocio, setNovoNegocio] = useState(false);
  const [agendando, setAgendando] = useState<Negocio | null>(null);
  const [editando, setEditando] = useState<Funil | null>(null);
  const [criandoFunil, setCriandoFunil] = useState(false);
  const [novoProjeto, setNovoProjeto] = useState(false);
  const [refKanban, alturaKanban] = useAlturaRestante<HTMLDivElement>();

  // Funil inicial: ?f= na URL, o último aberto, ou o primeiro da lista. O negócio de ?negocio= puxa o funil dele.
  useEffect(() => {
    if (!funis?.length || funilId) return;
    let ultimo: string | null = null;
    try { ultimo = localStorage.getItem(CHAVE_FUNIL); } catch { /* sem storage */ }
    const doNegocio = paramNegocio ? negocios?.find((n) => n.id === paramNegocio)?.funilId : undefined;
    const escolha = [doNegocio, paramFunil, ultimo].find((id) => id && funis.some((f) => f.id === id)) ?? funis[0].id;
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setFunilId(escolha);
  }, [funis, funilId, paramFunil, paramNegocio, negocios]);

  const escolher = (id: string) => {
    setFunilId(id);
    setAlerta(null);
    try { localStorage.setItem(CHAVE_FUNIL, id); } catch { /* sem storage */ }
    const url = new URL(window.location.href);
    url.searchParams.set('f', id);
    url.searchParams.delete('negocio');
    window.history.replaceState(null, '', url);
  };

  const funil = funis?.find((f) => f.id === funilId) ?? null;
  const contatoPorId = useMemo(() => new Map((contatos ?? []).map((c) => [c.id, c])), [contatos]);
  const doFunil = useMemo(() => (negocios ?? []).filter((n) => n.funilId === funilId), [negocios, funilId]);
  // A faixa conta pelo dono e pela busca, sem o filtro de alerta: o número não some quando você clica nele.
  const semAlerta = useMemo(
    () => filtrarNegocios(doFunil, { dono, busca, alerta: null, vendedorId: sessao?.vendedorId }, contatoPorId, agora),
    [doFunil, dono, busca, sessao, contatoPorId, agora],
  );
  const filtrados = useMemo(
    () => (alerta ? filtrarNegocios(semAlerta, { dono: 'todos', busca: '', alerta, vendedorId: null }, contatoPorId, agora) : semAlerta),
    [semAlerta, alerta, contatoPorId, agora],
  );
  const resumo = resumoFunil(semAlerta, agora);
  const filtrando = dono !== 'todos' || busca.trim() !== '' || alerta !== null;
  const limparFiltros = () => { setDono('todos'); setBusca(''); setAlerta(null); };
  const alternar = (a: Exclude<FiltroAlerta, null>) => setAlerta((x) => (x === a ? null : a));

  const leituraDe = (n: Negocio) => motivoSomenteLeitura(n, sessao, nomeDe);
  const travaPara = (n: Negocio, etapaId: string) => {
    const f = funis?.find((x) => x.id === n.funilId);
    return f ? travaMover(n, f, etapaId, sessao, nomeDe) : { permitido: false, motivo: 'Funil do negócio não encontrado.', faltam: [] };
  };

  const mover = async (negocioId: string, etapaId: string) => {
    // A mesma trava do banco antes de chamar: sem ida e volta para ouvir "não".
    const n = negocios?.find((x) => x.id === negocioId);
    const t = n ? travaPara(n, etapaId) : null;
    if (t && !t.permitido) {
      flash(t.motivo ?? 'Não dá para mover.');
      if (t.faltam.length) setAberto(negocioId);
      return;
    }
    const r = await repo.moverEtapa(negocioId, etapaId);
    if (!r.ok) { flash(r.msg ?? 'Não foi possível mover.'); setAberto(negocioId); return; }
    avisarMudanca();
  };

  const copiarTelefone = async (tel: string) => {
    try { await navigator.clipboard.writeText(tel); flash('Telefone copiado.'); } catch { flash(`Telefone: ${tel}`); }
  };

  const negocioAberto = aberto ?? paramNegocio;
  const erro = qFunis.erro ?? qAgrupadores.erro ?? qNegocios.erro ?? qContatos.erro;
  const carregando = !funis || !agrupadores || !negocios || !contatos;
  const recarregarTudo = () => { qFunis.recarregar(); qAgrupadores.recarregar(); qNegocios.recarregar(); qContatos.recarregar(); };
  const agrupadorAtual = agrupadores?.find((a) => a.id === funil?.agrupadorId) ?? agrupadores?.[0];
  const novoFunil = () => setCriandoFunil(true);

  const acoes = !carregando && funis.length > 0 && (
    <>
      <SeletorFunil
        funis={funis}
        agrupadores={agrupadores}
        negocios={negocios}
        atualId={funilId}
        agora={agora}
        gestor={gestor}
        onEscolher={escolher}
        onNovoFunil={novoFunil}
      />
      {gestor && (
        <Button size="sm" variant="ghost" className="min-h-8" onClick={() => setNovoProjeto(true)} title="Cria de uma vez os funis do tipo de projeto, com a chave nas campanhas">
          <Icon name="megaphone" size={14} /> Comecei um novo projeto
        </Button>
      )}
      {gestor && funil && (
        <Button size="sm" variant="ghost" aria-label="Editar funil" title="Editar funil" className="!px-2 min-h-8" onClick={() => setEditando(funil)}>
          <Icon name="settings" size={16} />
        </Button>
      )}
      {!leitor && funil?.tipo === 'manual' && <Button size="sm" className="min-h-8" onClick={() => setNovoNegocio(true)}><Icon name="plus" size={14} /> Novo negócio</Button>}
    </>
  );

  return (
    <PaginaComercial
      titulo={funil ? (
        <span className="flex items-center gap-2 min-w-0">
          <Icon name={iconeDoFunil(funil)} size={20} className="shrink-0 text-[var(--fg-3)]" />
          <span className="truncate">{funil.nome}</span>
        </span>
      ) : 'Funis de venda'}
      subtitulo={funil ? <LinhaFunil funil={funil} agrupador={agrupadores?.find((a) => a.id === funil.agrupadorId)?.nome} /> : 'Negócios por etapa, do primeiro contato ao pagamento.'}
      acoes={acoes || undefined}
    >
      {/* Erro ao atualizar com o quadro já na tela: faixa, sem sumir com o quadro. Sem dado: estado de erro. */}
      {erro && !carregando && <FaixaErroAtualizacao className="mb-3" mensagem={erro} onTentar={recarregarTudo} />}
      {erro && carregando ? (
        <EstadoErro mensagem={erro} onTentar={recarregarTudo} />
      ) : carregando ? (
        <EsqueletoKanban />
      ) : !funis.length ? (
        <Vazio
          icone="kanban"
          titulo="Nenhum funil ainda"
          hint={gestor ? 'Crie o primeiro funil passo a passo, ou todos os funis de um projeto de uma vez.' : 'O gestor comercial cria os funis.'}
          acao={gestor ? (
            <div className="flex flex-wrap justify-center gap-2">
              <Button size="sm" onClick={novoFunil}><Icon name="plus" size={14} /> Novo funil</Button>
              <Button size="sm" variant="ghost" onClick={() => setNovoProjeto(true)}><Icon name="megaphone" size={14} /> Comecei um novo projeto</Button>
            </div>
          ) : undefined}
        />
      ) : !funil ? (
        <EsqueletoKanban />
      ) : (
        <div className="space-y-3">
          {/* Números + filtros numa linha só. Os números com meta zero filtram o kanban. */}
          <div className="flex flex-col lg:flex-row lg:items-center gap-3">
            <FaixaNumeros
              className="lg:flex-1 min-w-0"
              onLimpar={() => setAlerta(null)}
              itens={[
                { rotulo: 'Abertos', valor: resumo.abertos, metrica: 'abertos', extraSr: `${fmtBRL(resumo.valor)} em aberto` },
                { rotulo: 'Em negociação', valor: fmtBRL(resumo.valorNegociacao), metrica: 'em_negociacao', extraSr: `${resumo.emNegociacao} negócios` },
                { rotulo: 'Prazo crítico', valor: resumo.criticos, metrica: 'criticos', alerta: resumo.criticos > 0, ativo: alerta === 'critico', onClick: () => alternar('critico') },
                { rotulo: 'Sem próximo passo', valor: resumo.semProximo, metrica: 'sem_proximo', alerta: resumo.semProximo > 0, ativo: alerta === 'sem_proximo', onClick: () => alternar('sem_proximo') },
                { rotulo: 'Sem dono', valor: resumo.semDono, metrica: 'sem_dono', alerta: resumo.semDono > 0, ativo: alerta === 'sem_dono', onClick: () => alternar('sem_dono') },
              ]}
            />
            <div className="flex flex-col sm:flex-row gap-2 lg:w-[480px] shrink-0">
              <FilterSelect value={dono} onChange={(e) => setDono(e.target.value)} aria-label="Dono" className="sm:w-48">
                <option value="todos">Todos os donos</option>
                <option value="meus">Meus negócios</option>
                <option value="sem_dono">Sem dono</option>
                {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
              </FilterSelect>
              <SearchInput placeholder="Buscar nome, e-mail ou telefone" aria-label="Buscar negócio" value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} />
            </div>
          </div>

          {funil.projeto && qAtivacao.dados && (
            <PainelAtivacao
              funil={funil}
              painel={qAtivacao.dados}
              gestor={gestor}
              verTudo={verTudo}
              eu={sessao?.vendedorId ?? null}
              nomeDe={nomeDe}
              onFlash={flash}
              onAbrirFunil={escolher}
            />
          )}

          {filtrando && filtrados.length === 0 && (
            <Aviso acao={<Button size="sm" variant="ghost" onClick={limparFiltros}>Limpar filtros</Button>}>
              Nenhum negócio com esses filtros neste funil.
            </Aviso>
          )}

          <div ref={refKanban}>
            <KanbanFunil
              funil={funil}
              negocios={filtrados}
              contatoPorId={contatoPorId}
              agora={agora}
              nomeDe={nomeDe}
              altura={alturaKanban}
              ocultarGanho={alerta !== null}
              leituraDe={leituraDe}
              travaPara={travaPara}
              onAbrir={setAberto}
              onAbrirPessoa={setFichaPessoa}
              onMover={mover}
              onAgendar={setAgendando}
              onCopiarTelefone={copiarTelefone}
            />
          </div>
          {funil.tipo === 'hotmart' && (
            <p className="text-[11px] text-[var(--fg-3)]">Funil automático: os negócios nascem dos eventos da Hotmart, não à mão.</p>
          )}
        </div>
      )}

      {fichaPessoa && <ContatoDrawer key={fichaPessoa} contatoId={fichaPessoa} onClose={() => setFichaPessoa(null)} onAbrirContato={setFichaPessoa} />}
      {negocioAberto && (
        <NegocioDrawer
          negocioId={negocioAberto}
          onClose={() => {
            setAberto(null);
            if (paramNegocio) {
              const url = new URL(window.location.href);
              url.searchParams.delete('negocio');
              window.history.replaceState(null, '', url);
            }
          }}
        />
      )}
      {agendando && (
        <ModalAtividade
          onClose={() => setAgendando(null)}
          onConfirmar={async (tipo, titulo, venceEm) => {
            const n = agendando;
            const r = await repo.criarAtividade({ negocioId: n.id, contatoId: n.contatoId, tipo, titulo, venceEm });
            if (!r.ok) { flash(r.msg ?? 'Não foi possível agendar.'); return; }
            setAgendando(null);
            avisarMudanca();
            flash('Próximo passo agendado.');
          }}
        />
      )}
      {novoNegocio && funil && (
        <ModalNovoNegocio
          funilInicial={funil.id}
          onClose={() => setNovoNegocio(false)}
          onCriado={({ negocioId, donoId }) => {
            setNovoNegocio(false);
            avisarMudanca();
            flash(donoId ? `Negócio criado. Dono: ${nomeDe(donoId)}.` : 'Negócio criado sem dono.');
            setAberto(negocioId);
          }}
        />
      )}
      {editando && agrupadores && (
        <EditorFunil
          inicial={editando}
          agrupadores={agrupadores}
          vendedores={vendedores}
          negociosDoFunil={(negocios ?? []).filter((n) => n.funilId === editando.id)}
          onClose={() => setEditando(null)}
          onSalvo={(id, msg) => {
            setEditando(null);
            flash(msg);
            if (id) escolher(id); else setFunilId(null);
          }}
        />
      )}
      {criandoFunil && agrupadores && (
        <AssistenteFunil
          agrupadores={agrupadores}
          agrupadorInicial={agrupadorAtual}
          vendedores={vendedores}
          onClose={() => setCriandoFunil(false)}
          onCriado={(id, msg) => {
            setCriandoFunil(false);
            flash(msg);
            escolher(id);
          }}
        />
      )}
      {novoProjeto && agrupadores && (
        <ModalNovoProjeto
          agrupadores={agrupadores}
          agrupadorInicial={agrupadorAtual}
          onClose={() => setNovoProjeto(false)}
          onCriado={(ids, msg) => {
            setNovoProjeto(false);
            flash(msg);
            escolher(ids[0]);
          }}
        />
      )}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

/** Uma linha de texto com o que define o funil: agrupador, tipo, entradas e distribuição. Sem chips. */
function LinhaFunil({ funil, agrupador }: { funil: Funil; agrupador?: string }) {
  const entradas = funil.tipo === 'hotmart'
    ? (funil.eventosHotmart.length ? `eventos: ${funil.eventosHotmart.map((o) => ROTULO_ORIGEM[o]).join(', ')}` : 'sem evento configurado')
    : (funil.campanhas.length ? `entradas: ${funil.campanhas.map((c) => `${c.nome}${c.ativa ? '' : ' (pausada)'}`).join(', ')}` : 'sem campanha de entrada');
  const partes = [agrupador, funil.projeto && `projeto ${funil.projeto}`, funil.tipo === 'hotmart' ? 'Automático Hotmart' : 'Manual', entradas, funil.distribuicao && 'distribuição própria'].filter(Boolean);
  const texto = partes.join(' · ');
  return <span className="block max-w-[90ch] truncate text-[var(--fg-3)]" title={texto}>{texto}</span>;
}

/** Carregando no formato do kanban: colunas com cards de 3 linhas. */
function EsqueletoKanban() {
  return (
    <div aria-busy="true" aria-label="Carregando funil" className="space-y-3">
      <Skeleton h={40} className="w-full" />
      <div className="flex gap-3 overflow-hidden">
        {[4, 3, 2, 2, 1].map((qtd, i) => (
          <div key={i} className={`${i > 0 ? 'hidden md:flex' : 'flex'} w-full md:w-[272px] shrink-0 flex-col gap-2 rounded-[var(--r-lg)] border border-[var(--border)] bg-[var(--surface-1)] p-2`}>
            <div className="px-1 py-1 space-y-1.5"><Skeleton w={120} h={12} /><Skeleton w={64} h={10} /></div>
            {Array.from({ length: qtd }).map((_, j) => (
              <div key={j} className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 space-y-2">
                <div className="flex justify-between"><Skeleton w={130} h={12} /><Skeleton w={48} h={12} /></div>
                <Skeleton w={150} h={10} />
                <div className="flex justify-between"><Skeleton w={90} h={10} /><Skeleton w={20} h={20} className="!rounded-full" /></div>
              </div>
            ))}
          </div>
        ))}
      </div>
    </div>
  );
}
