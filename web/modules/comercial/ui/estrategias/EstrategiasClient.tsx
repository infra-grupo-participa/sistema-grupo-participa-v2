'use client';

// Estratégias (ex-"Recuperação", 07/10/2026). Duas abas:
// - Solicitações: pedidos de estratégia ao Comercial, com situação e placar. Quem pede vê os dele; o gestor comercial vê
//   todos, analisa e transforma em ação.
// - Filas de recuperação (só quem é do Comercial): a tela que antes era a Recuperação, sem mudança.
// Quem só pede estratégia (sem acesso ao CRM) não vê a aba de filas nem o sino do CRM.
import { useMemo, useState } from 'react';
import { Badge, Button, Toast, useFlash } from '@/shared/ui/components';
import { fmtBRL, fmtData } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  ROTULO_PRIORIDADE, ROTULO_SITUACAO, ROTULO_TIPO_ACAO, TOM_SITUACAO, ordenarPedidos, resumoFiltros,
  type Estrategia, type OpcoesFiltro,
} from '../../domain/estrategias';
import { EsqueletoLista, EstadoErro, FaixaNumeros, PaginaComercial, Segmentado, Vazio, useAbaHash, useParamUrl } from '../comum';
import { RecuperacaoClient } from '../recuperacao/RecuperacaoClient';
import { avisarMudanca, useDados } from '../repositorio';
import { ModalSolicitacao } from './ModalSolicitacao';
import { PedidoDrawer } from './PedidoDrawer';
import { repoEstrategias } from './repositorio-estrategias';

type Aba = 'pedidos' | 'filas';
type FiltroSituacao = 'abertos' | 'encerrados' | 'todos';
const ABAS: readonly Aba[] = ['pedidos', 'filas'];
const aberto = (e: Estrategia) => e.situacao !== 'concluida' && e.situacao !== 'recusada';

export function EstrategiasClient({ doComercial, podeSolicitar }: { doComercial: boolean; podeSolicitar: boolean }) {
  const { dados: acesso, erro: erroAcesso, recarregar: recAcesso } = useDados(() => repoEstrategias.acesso());
  const vePedidos = !!acesso && (acesso.gestor || acesso.solicitar || !!acesso.leitor);
  const [aba, setAba] = useAbaHash(ABAS, podeSolicitar || !doComercial ? 'pedidos' : 'filas');
  // Quem não vê pedidos (vendedor sem a função) fica nas filas; quem não é do Comercial fica nos pedidos.
  const abaEfetiva: Aba = !doComercial ? 'pedidos' : acesso && !vePedidos ? 'filas' : aba;

  const conteudo = (
    <div className="space-y-4">
      {doComercial && vePedidos && (
        <Segmentado rotulo="Seção" valor={abaEfetiva} onChange={setAba} opcoes={[
          { valor: 'pedidos', rotulo: <><Icon name="target" size={13} /> Solicitações</> },
          { valor: 'filas', rotulo: <><Icon name="list-checks" size={13} /> Filas de recuperação</> },
        ]} />
      )}
      {abaEfetiva === 'filas'
        ? <RecuperacaoClient embutido />
        : erroAcesso && !acesso ? <EstadoErro mensagem={erroAcesso} onTentar={recAcesso} />
          : !acesso ? <EsqueletoLista linhas={4} avatar={false} />
            : !vePedidos ? <Vazio titulo="Sem acesso às solicitações" icone="lock" hint='Peça a permissão "Solicitar estratégia" ao administrador.' />
              : <Solicitacoes gestor={acesso.gestor} verTime={acesso.gestor || !!acesso.leitor} solicitar={acesso.solicitar} />}
    </div>
  );

  const titulo = 'Estratégias';
  const subtitulo = 'Pedidos de estratégia ao Comercial, a ação de cada um e as filas de recuperação.';
  if (doComercial) return <PaginaComercial titulo={titulo} subtitulo={subtitulo}>{conteudo}</PaginaComercial>;
  return (
    <div className="min-w-0">
      <header className="mb-4">
        <h1 className="text-xl font-bold leading-tight text-[var(--fg)]">{titulo}</h1>
        <p className="mt-0.5 text-sm text-[var(--fg-3)]">Peça uma estratégia ao Comercial e acompanhe o andamento e o placar.</p>
      </header>
      {conteudo}
    </div>
  );
}

function Solicitacoes({ gestor, verTime = gestor, solicitar }: { gestor: boolean; verTime?: boolean; solicitar: boolean }) {
  const { dados: pedidos, erro, recarregar } = useDados(() => repoEstrategias.pedidos());
  const { dados: modelos } = useDados(() => repoEstrategias.modelos());
  const { dados: opcoes } = useDados<OpcoesFiltro | null>(() => repoEstrategias.opcoes().catch(() => null));
  const { toast, flash } = useFlash();
  const pedidoUrl = useParamUrl('pedido');
  const [aberta, setAberta] = useState<string | null>(null);
  const [fechouUrl, setFechouUrl] = useState(false);
  const [novo, setNovo] = useState(false);
  const [filtro, setFiltro] = useState<FiltroSituacao>('abertos');
  const idAberto = aberta ?? (fechouUrl ? null : pedidoUrl);

  const lista = useMemo(() => ordenarPedidos(pedidos ?? []), [pedidos]);
  const visiveis = lista.filter((e) => filtro === 'todos' || (filtro === 'abertos' ? aberto(e) : !aberto(e)));
  const numeros = useMemo(() => {
    const ls = pedidos ?? [];
    const comAcao = ls.filter((e) => e.placar);
    return {
      abertos: ls.filter(aberto).length,
      execucao: ls.filter((e) => e.situacao === 'em_execucao').length,
      pessoas: comAcao.reduce((s, e) => s + (e.placar?.naLista ?? 0), 0),
      vendas: comAcao.reduce((s, e) => s + (e.placar?.vendas ?? 0), 0),
      receita: comAcao.reduce((s, e) => s + (e.placar?.receita ?? 0), 0),
    };
  }, [pedidos]);
  const nomeProduto = (id: string) => opcoes?.produtos.find((p) => p.id === id)?.nome ?? id;

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <Segmentado rotulo="Situação" valor={filtro} onChange={setFiltro} opcoes={[
          { valor: 'abertos', rotulo: 'Abertos', n: numeros.abertos },
          { valor: 'encerrados', rotulo: 'Encerrados' },
          { valor: 'todos', rotulo: 'Todos', n: pedidos?.length },
        ]} />
        {solicitar && <Button size="sm" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Nova solicitação</Button>}
      </div>

      <FaixaNumeros
        rotulo={verTime ? 'Pedidos do time' : 'Meus pedidos'}
        itens={[
          { rotulo: 'Abertos', valor: numeros.abertos },
          { rotulo: 'Em execução', valor: numeros.execucao },
          { rotulo: 'Pessoas em ação', valor: numeros.pessoas.toLocaleString('pt-BR') },
          { rotulo: 'Vendas', valor: numeros.vendas.toLocaleString('pt-BR') },
          { rotulo: 'Receita', valor: fmtBRL(numeros.receita) },
        ]}
      />

      {erro && !pedidos ? <EstadoErro mensagem={erro} onTentar={recarregar} />
        : !pedidos ? <EsqueletoLista linhas={4} avatar={false} />
          : visiveis.length === 0 ? (
            <Vazio
              titulo={filtro === 'abertos' ? 'Nenhum pedido aberto' : 'Nenhum pedido aqui'}
              icone="inbox"
              hint={solicitar ? 'Peça uma estratégia ao Comercial: o que quer, para quem e até quando.' : 'Os pedidos aparecem aqui quando alguém solicitar.'}
              acao={solicitar ? <Button size="sm" onClick={() => setNovo(true)}><Icon name="plus" size={14} /> Nova solicitação</Button> : undefined}
            />
          ) : (
            <ul className="grid gap-3 lg:grid-cols-2">
              {visiveis.map((e) => (
                <li key={e.id}>
                  <button type="button" onClick={() => setAberta(e.id)}
                    className="w-full min-w-0 text-left rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-4 transition-colors hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)]">
                    <div className="flex items-start justify-between gap-3">
                      <span className="min-w-0">
                        <span className="block truncate font-semibold text-[var(--fg)]">{e.titulo}</span>
                        <span className="block truncate text-xs text-[var(--fg-3)]">
                          {verTime ? `${e.solicitanteNome} · ` : ''}{fmtData(e.criadoEm)}{e.prazo ? ` · prazo ${fmtData(e.prazo)}` : ''}
                        </span>
                      </span>
                      <Badge tone={TOM_SITUACAO[e.situacao]} dot>{ROTULO_SITUACAO[e.situacao]}</Badge>
                    </div>
                    <p className="mt-2 line-clamp-2 text-sm text-[var(--fg-2)]">{e.objetivo}</p>
                    <div className="mt-3 flex flex-wrap gap-1.5">
                      <Badge tone={e.prioridade === 'urgente' || e.prioridade === 'alta' ? 'warning' : 'neutral'}>{ROTULO_PRIORIDADE[e.prioridade]}</Badge>
                      {e.acaoTipo && <Badge tone="info">{ROTULO_TIPO_ACAO[e.acaoTipo]}</Badge>}
                      {resumoFiltros(e.filtros, nomeProduto).slice(1, 3).map((t) => <Badge key={t}>{t}</Badge>)}
                    </div>
                    {e.placar && (
                      <div className="mt-3 grid grid-cols-3 gap-2 border-t border-[var(--border-faint)] pt-3 text-center sm:grid-cols-5">
                        <Numero rotulo="Na lista" valor={e.placar.naLista} />
                        <Numero rotulo="Abordadas" valor={e.placar.abordadas} />
                        <Numero rotulo="Em conversa" valor={e.placar.emConversa} className="hidden sm:block" />
                        <Numero rotulo="Vendas" valor={e.placar.vendas} />
                        <Numero rotulo="Receita" valor={fmtBRL(e.placar.receita)} className="hidden sm:block" />
                      </div>
                    )}
                  </button>
                </li>
              ))}
            </ul>
          )}

      {idAberto && (
        <PedidoDrawer id={idAberto} gestor={gestor} opcoes={opcoes ?? null} flash={flash}
          onClose={() => { setAberta(null); setFechouUrl(true); }} />
      )}
      {novo && (
        <ModalSolicitacao modelos={modelos ?? []} opcoes={opcoes ?? null} onClose={() => setNovo(false)}
          onSalvo={(id, msg) => { setNovo(false); flash(msg); avisarMudanca(); setAberta(id); }} />
      )}
      <Toast>{toast}</Toast>
    </div>
  );
}

function Numero({ rotulo, valor, className = '' }: { rotulo: string; valor: React.ReactNode; className?: string }) {
  return (
    <span className={`min-w-0 ${className}`}>
      <span className="block text-sm font-semibold tabular text-[var(--fg)]">{typeof valor === 'number' ? valor.toLocaleString('pt-BR') : valor}</span>
      <span className="block truncate text-[11px] text-[var(--fg-3)]">{rotulo}</span>
    </span>
  );
}
