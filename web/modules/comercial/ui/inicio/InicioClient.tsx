'use client';

// Início do Comercial: o painel de quem abre o dia.
// Vendedor: números do dia e carga dele, o que pede ação agora (com a ação a um clique) e o painel personalizado.
// Gestor: números do time, "Agir agora" do time ao lado do controle das 9h (playbook, seção 5.2), carga por vendedor
// e o painel dele. "Ver: Ronan" mostra a tela inteira na perspectiva do vendedor, sem trocar a sessão.
import Link from 'next/link';
import { useEffect, useMemo, useState } from 'react';
import {
  Button, Card, EmptyState, FilterSelect, SectionCard, SectionTitle, Skeleton, Toast, useFlash,
} from '@/shared/ui/components';
import { fmtBRL } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ICONE_ATIVIDADE, ROTULO_STATUS_FICHA, produto as produtoDe } from '../../domain/catalogo';
import { calcularFechamento, type LinhaFechamento } from '../../domain/fechamento';
import { situacaoSla } from '../../domain/regras';
import { motivoSomenteLeitura, podeConcluirAtividade } from '../../domain/travas';
import type { Atividade, Contato, FichaDisparo, MetricaKey, Negocio, Vendedor } from '../../domain/types';
import { EstadoErro, FaixaNumeros, PaginaComercial, Segmentado, useEquipe } from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { NegocioDrawer } from '../NegocioDrawer';
import { repo, useAgora, useContatosPorIds, useDados } from '../repositorio';
import { tempoDesde } from '../atividades/agenda';
import { useConcluirComProximo } from '../atividades/ProximoPasso';
import { NumerosDoDia } from './FaixaNumeros';
import type { DadosPainel } from './metricas-painel';
import {
  ROTULO_URGENCIA, URGENCIA, VER_TIME, agruparPorUrgencia, cargaDe, cargaPorVendedor, controle9h, itensAgirAgora, nomeCurto,
  perspectiva, saudacao, type CargaPessoa, type ItemAcao,
} from './painel';
import { PainelPersonalizavel } from './PainelPersonalizavel';
import {
  INFO_AGIR_AGORA, INFO_CARGA, INFO_CONTROLE_9H, INFO_CONVERSAS_ESPERANDO, INFO_FICHAS, INFO_JA_ATENDIDO, INFO_URGENCIA,
} from './textos';

const LIMITE_AGIR = 10;

/** Os 9 inegociáveis do playbook, em versão de bolso. */
const INEGOCIAVEIS = [
  'Todo lead tem um dono só.',
  'Lead que não é seu não se toca.',
  'Se não está no CRM, não existe.',
  'Nenhum negócio aberto sem próxima atividade com data. Sem isso, vira perdido com motivo.',
  'Quem define o próximo passo é o vendedor, não o lead.',
  'Só se fala com lead pelo número oficial.',
  'Nenhum disparo por API sem ficha aprovada e registro no log.',
  'Nenhuma condição fora da oferta vigente.',
  'Marca: nunca prometer faturamento; garantia sempre adicional ao art. 49 do CDC; nunca dizer "blindagem"; nunca prometer replay do Holding Total.',
];

export function InicioClient() {
  const agora = useAgora();
  const { toast, flash } = useFlash();
  const { sessao, vendedores, nomeDe, verTudo, leitor } = useEquipe();
  const negQ = useDados(() => repo.negocios());
  const atvQ = useDados(() => repo.atividades());
  const evtQ = useDados(() => repo.eventos());
  const cvsQ = useDados(() => repo.conversas());
  // Só os contatos que o início mostra (negócios, atividades, conversas e eventos), não a base inteira.
  const conQ = useContatosPorIds(negQ.dados && atvQ.dados && cvsQ.dados && evtQ.dados
    ? [...negQ.dados.map((n) => n.contatoId), ...atvQ.dados.map((a) => a.contatoId),
       ...cvsQ.dados.map((c) => c.contatoId), ...evtQ.dados.map((e) => e.contatoId)]
    : null);
  const fchQ = useDados(() => repo.fichas());
  const funQ = useDados(() => repo.funis());
  const motQ = useDados(() => repo.motivosPerda());
  const consultas = [negQ, conQ, atvQ, evtQ, cvsQ, fchQ, funQ, motQ];
  const erro = consultas.find((q) => q.erro)?.erro ?? null;
  const negocios = negQ.dados, contatos = conQ.dados, atividades = atvQ.dados, eventos = evtQ.dados, conversas = cvsQ.dados, fichas = fchQ.dados;
  const funis = funQ.dados, motivos = motQ.dados;
  const [aberto, setAberto] = useState<string | null>(null);
  const [ver, setVer] = useState<string>(VER_TIME);
  const fluxo = useConcluirComProximo(flash, (n) => motivoSomenteLeitura(n, sessao, nomeDe));

  const eu = sessao?.vendedorId ?? null;
  const pronto = !!(sessao && negocios && contatos && atividades && eventos && conversas && fichas && funis && motivos);
  const contatoPorId = useMemo(() => new Map((contatos ?? []).map((c) => [c.id, c])), [contatos]);
  const p = sessao ? perspectiva(sessao, ver) : null;
  const alvo = p?.donoId ?? null;
  const time = verTudo && alvo == null;

  const agir = useMemo(
    () => (pronto ? itensAgirAgora({ negocios: negocios!, conversas: conversas!, atividades: atividades!, donoId: alvo, agora }) : []),
    [pronto, negocios, conversas, atividades, alvo, agora],
  );
  const fechamento = useMemo(
    () => (pronto ? calcularFechamento(negocios!, atividades!, eventos!, agora) : null),
    [pronto, negocios, atividades, eventos, agora],
  );
  const dadosPainel = useMemo<DadosPainel | null>(
    () => (pronto ? { negocios: negocios!, atividades: atividades!, eventos: eventos!, funis: funis!, motivos: motivos!, vendedores, agora, donoId: alvo } : null),
    [pronto, negocios, atividades, eventos, funis, motivos, vendedores, agora, alvo],
  );

  const ativos = vendedores.filter((v) => v.ativo);
  const nomeAlvo = alvo ? nomeCurto(nomeDe(alvo)) : '';
  const primeiroNome = sessao ? nomeDe(sessao.vendedorId).split(' ')[0] : '';
  const dataHoje = agora.toLocaleDateString('pt-BR', { timeZone: 'America/Sao_Paulo', weekday: 'long', day: 'numeric', month: 'long' });
  const doAlvo = alvo && fechamento ? fechamento.porVendedor[alvo] : undefined;
  const voltar = () => setVer(VER_TIME);

  const titulo = !verTudo ? 'Meu dia' : time ? 'Visão do time' : p?.deOutro ? `Vendo o painel de ${nomeAlvo}` : 'Meu dia como vendedor';
  const subtitulo = !sessao ? null : p?.deOutro
    ? <>O que {nomeAlvo} tem para agir agora, os números do dia dele e o painel dele. {leitor ? 'Somente leitura.' : 'Você continua como gestor.'}</>
    : <>{saudacao(agora)}, {primeiroNome}. Hoje é {dataHoje}.</>;

  const seletor = verTudo && ativos.length > 0 && (
    <>
      <span className="hidden sm:inline-flex items-center gap-2">
        <span className="text-xs text-[var(--fg-3)]">Ver</span>
        <Segmentado
          rotulo="Ver o painel de"
          valor={ver}
          onChange={setVer}
          opcoes={[{ valor: VER_TIME, rotulo: 'Time inteiro' }, ...ativos.map((v) => ({ valor: v.id, rotulo: nomeCurto(v.nome), title: v.nome }))]}
        />
      </span>
      <label className="sm:hidden inline-flex items-center gap-2">
        <span className="text-xs text-[var(--fg-3)]">Ver</span>
        <FilterSelect value={ver} onChange={(e) => setVer(e.target.value)} className="!py-1.5 !text-xs min-w-[150px]">
          <option value={VER_TIME}>Time inteiro</option>
          {ativos.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
        </FilterSelect>
      </label>
      {!time && (
        <Button size="sm" variant="ghost" onClick={voltar}><Icon name="arrow-left" size={14} /> Voltar ao time</Button>
      )}
    </>
  );

  const numeros = !pronto || !fechamento ? null : time
    ? <NumerosDoDia rotulo="Números do dia do time" principal={fechamento.total} outro={eu ? fechamento.porVendedor[eu] : undefined} rotuloOutro="meu" />
    : <NumerosDoDia rotulo={p?.deOutro ? `Números do dia de ${nomeAlvo}` : 'Meus números do dia'} principal={doAlvo} outro={fechamento.total} rotuloOutro="time" />;

  const agirAgora = (
    <AgirAgora
      itens={agir} contatoPorId={contatoPorId} agora={agora} time={time} nomeDe={nomeDe} onAbrir={setAberto}
      titulo={time ? 'Agir agora · time' : p?.deOutro ? `Agir agora · ${nomeAlvo}` : 'Agir agora'}
      onConcluir={(a, n) => fluxo.pedirResultado(a, n)}
      podeConcluir={(a) => podeConcluirAtividade(a, sessao)}
    />
  );

  return (
    <PaginaComercial titulo={titulo} subtitulo={subtitulo} acoes={seletor} meta={numeros}>
      {erro && !pronto ? (
        <EstadoErro mensagem={erro} onTentar={() => consultas.forEach((q) => q.recarregar())} />
      ) : !pronto || !fechamento || !dadosPainel || !sessao || !p ? (
        <EsqueletoInicio />
      ) : (
        <div className="space-y-6">
          {time ? (
            <>
              <div className="grid gap-4 xl:grid-cols-2 items-start">
                {agirAgora}
                <Controle9h negocios={negocios!} fichas={fichas!} contatoPorId={contatoPorId} agora={agora} nomeDe={nomeDe} onAbrir={setAberto} />
              </div>
              <CargaPorVendedor
                negocios={negocios!} atividades={atividades!} vendedores={vendedores} agora={agora} nomeDe={nomeDe}
                porVendedor={fechamento.porVendedor} onVer={setVer}
              />
            </>
          ) : (
            <>
              <FaixaCarga
                carga={cargaDe({ negocios: negocios!, atividades: atividades!, conversas: conversas!, donoId: alvo, agora })}
                rotulo={p.deOutro ? `Carga de ${nomeAlvo}` : 'Minha carga'}
              />
              {agirAgora}
            </>
          )}

          <PainelPersonalizavel
            key={p.painelDe}
            vendedorId={p.painelDe}
            padraoGestor={p.painelDe === eu ? verTudo : vendedores.find((v) => v.id === p.painelDe)?.papel === 'gestor'}
            dados={dadosPainel}
            funis={funis!}
            titulo={p.deOutro ? `Painel de ${nomeAlvo}` : 'Meu painel'}
            podeEditar={!leitor && (verTudo || p.painelDe === eu)}
            flash={flash}
          />

          <Inegociaveis />
        </div>
      )}

      {fluxo.modais}
      {aberto && <NegocioDrawer negocioId={aberto} onClose={() => setAberto(null)} />}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

/** Carga de quem está no painel: o que está nas mãos agora e o que já fugiu da regra. */
function FaixaCarga({ carga, rotulo }: { carga: CargaPessoa; rotulo: string }) {
  return (
    <FaixaNumeros
      rotulo={rotulo}
      itens={[
        { rotulo: 'Abertos', valor: carga.abertos, metrica: 'abertos' },
        { rotulo: 'Prazo crítico', valor: carga.criticos, alerta: carga.criticos > 0, metrica: 'criticos' },
        { rotulo: 'Sem próximo passo', valor: carga.semProximo, alerta: carga.semProximo > 0, metrica: 'sem_proximo' },
        { rotulo: 'Atrasadas', valor: carga.atrasadas, alerta: carga.atrasadas > 0, metrica: 'atrasadas' },
        { rotulo: 'Conversas esperando', valor: carga.conversasEsperando, alerta: carga.conversasEsperando > 0, info: INFO_CONVERSAS_ESPERANDO },
      ]}
    />
  );
}

/** Esqueleto no formato do painel: faixa de números e lista de ações. */
function EsqueletoInicio() {
  return (
    <div className="space-y-4" aria-busy="true" aria-label="Carregando o painel">
      <Skeleton h={40} className="!rounded-[var(--r-md)]" />
      <Card className="p-5 space-y-4">
        <Skeleton w={140} h={14} />
        {Array.from({ length: 5 }).map((_, i) => (
          <div key={i} className="flex items-center gap-3">
            <Skeleton w={16} h={16} />
            <div className="flex-1 space-y-1.5"><Skeleton w="35%" h={12} /><Skeleton w="55%" h={10} /></div>
            <Skeleton w={56} h={10} />
          </div>
        ))}
      </Card>
    </div>
  );
}

// ── Agir agora ──

const horaMin = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { timeZone: 'America/Sao_Paulo', hour: '2-digit', minute: '2-digit' });

/** Título de bloco com o (i) ao lado. */
function TituloInfo({ children, info }: { children: React.ReactNode; info: TextoIndicador }) {
  return <span className="inline-flex items-center gap-1">{children} <InfoIndicador texto={info} /></span>;
}

function AgirAgora({ itens, contatoPorId, agora, time, titulo, nomeDe, onAbrir, onConcluir, podeConcluir }: {
  itens: ItemAcao[]; contatoPorId: Map<string, Contato>; agora: Date; time: boolean; titulo: string;
  nomeDe: (id: string | null) => string; onAbrir: (negocioId: string) => void;
  onConcluir: (a: Atividade, n: Negocio | undefined) => void; podeConcluir: (a: Atividade) => boolean;
}) {
  const [todos, setTodos] = useState(false);
  // Corta depois de agrupar: o que está atrasado nunca fica escondido atrás do "Ver todos".
  const ordenados = agruparPorUrgencia(itens).flatMap((g) => g.itens);
  const visiveis = todos ? ordenados : ordenados.slice(0, LIMITE_AGIR);
  const grupos = agruparPorUrgencia(visiveis);
  const total = (u: string) => itens.filter((i) => URGENCIA[i.tipo] === u).length;

  return (
    <SectionCard
      title={<TituloInfo info={INFO_AGIR_AGORA}>{titulo}</TituloInfo>}
      right={itens.length > 0 && <span className="text-xs tabular text-[var(--fg-3)]">{itens.length} {itens.length === 1 ? 'item' : 'itens'}</span>}
      className="min-w-0"
    >
      {itens.length === 0 ? (
        <EmptyState title="Nada pendente agora" hint="Sem prazo estourado, lead esperando ou atividade atrasada." icon="check-circle" />
      ) : (
        <div className="space-y-5">
          {grupos.map((g) => (
            <section key={g.urgencia} aria-label={ROTULO_URGENCIA[g.urgencia]}>
              <SectionTitle right={<span className={`text-[11px] tabular ${g.urgencia === 'atrasado' ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg-3)]'}`}>{total(g.urgencia)}</span>}>
                <TituloInfo info={INFO_URGENCIA[g.urgencia]}>{ROTULO_URGENCIA[g.urgencia]}</TituloInfo>
              </SectionTitle>
              <ul className="-mx-2 divide-y divide-[var(--border-faint)]">
                {g.itens.map((i) => (
                  <LinhaAcao
                    key={i.id} item={i} c={contatoPorId.get(i.contatoId)} agora={agora} mostrarDono={time} nomeDe={nomeDe}
                    onAbrir={onAbrir}
                    onConcluir={i.atividade && podeConcluir(i.atividade) ? () => onConcluir(i.atividade!, i.negocio) : undefined}
                  />
                ))}
              </ul>
            </section>
          ))}
          {itens.length > LIMITE_AGIR && (
            <div className="text-center">
              <Button size="sm" variant="ghost" onClick={() => setTodos(!todos)} aria-expanded={todos}>
                {todos ? 'Mostrar menos' : `Ver todos (${itens.length})`}
              </Button>
            </div>
          )}
        </div>
      )}
    </SectionCard>
  );
}

function LinhaAcao({ item, c, agora, mostrarDono, nomeDe, onAbrir, onConcluir }: {
  item: ItemAcao; c: Contato | undefined; agora: Date; mostrarDono: boolean;
  nomeDe: (id: string | null) => string; onAbrir: (negocioId: string) => void; onConcluir?: () => void;
}) {
  const n = item.negocio;
  const nome = c?.nome ?? '—';
  let icone = 'clock';
  let rotuloIcone = 'Atividade';
  let descricao: React.ReactNode = null;
  let tempo: { txt: string; vermelho: boolean } = { txt: '', vermelho: false };

  if (item.tipo === 'sla_critico' || item.tipo === 'sla_atencao') {
    icone = 'flame';
    rotuloIcone = item.tipo === 'sla_critico' ? 'Prazo crítico' : 'Prazo em atenção';
    descricao = n ? <>Parado em {n.etapaNome}</> : null;
    const critico = n ? situacaoSla(n, agora) === 'critico' : item.tipo === 'sla_critico';
    tempo = { txt: n ? `${tempoDesde(n.etapaDesde, agora)} na etapa` : '', vermelho: critico };
  } else if (item.tipo === 'conversa' && item.conversa) {
    icone = 'message';
    rotuloIcone = 'Lead esperando resposta';
    descricao = <>{item.conversa.naoLidas} {item.conversa.naoLidas === 1 ? 'mensagem' : 'mensagens'} sem resposta · &ldquo;{item.conversa.ultimaMensagem.texto}&rdquo;</>;
    tempo = { txt: tempoDesde(item.conversa.ultimaMensagem.em, agora), vermelho: false };
  } else if (item.atividade) {
    icone = ICONE_ATIVIDADE[item.atividade.tipo];
    rotuloIcone = item.tipo === 'atividade_atrasada' ? 'Atividade atrasada' : 'Atividade de hoje';
    descricao = item.atividade.titulo;
    tempo = item.tipo === 'atividade_atrasada'
      ? { txt: `venceu ${tempoDesde(item.atividade.venceEm, agora)}`, vermelho: true }
      : { txt: `às ${horaMin(item.atividade.venceEm)}`, vermelho: false };
  }

  const meta: React.ReactNode[] = [];
  if (descricao) meta.push(<span key="d" className="truncate">{descricao}</span>);
  if (n) meta.push(<span key="p" className="shrink-0">{produtoDe(n.produto).nome}</span>);
  if (mostrarDono) meta.push(<span key="o" className={`shrink-0 ${item.donoId ? '' : 'text-[var(--red)] font-medium'}`}>{nomeDe(item.donoId)}</span>);

  const linkConversa = `/comercial/conversas?contato=${item.contatoId}`;
  const acaoCls = 'sm:opacity-0 sm:group-hover:opacity-100 sm:group-focus-within:opacity-100 transition-opacity';

  return (
    <li className="group flex items-center gap-3 px-2 py-2 rounded-[var(--r-md)] hover:bg-[var(--surface-3)] transition-colors">
      <span title={rotuloIcone} className="shrink-0 text-[var(--fg-3)]">
        <Icon name={icone} size={16} />
        <span className="sr-only">{rotuloIcone}:</span>
      </span>
      <div className="flex-1 min-w-0">
        {item.negocioId ? (
          <button type="button" onClick={() => onAbrir(item.negocioId!)} className="block max-w-full truncate text-left text-sm font-semibold text-[var(--fg)] hover:underline cursor-pointer">
            {nome}
          </button>
        ) : (
          <Link href={linkConversa} className="block max-w-full truncate text-sm font-semibold text-[var(--fg)] hover:underline">{nome}</Link>
        )}
        {meta.length > 0 && (
          <div className="mt-0.5 flex items-center gap-1.5 min-w-0 text-xs text-[var(--fg-3)]">
            {meta.flatMap((m, i) => (i ? [<span key={`s${i}`} aria-hidden className="shrink-0">·</span>, m] : [m]))}
          </div>
        )}
      </div>
      <span className={`shrink-0 text-xs tabular ${tempo.vermelho ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg-3)]'}`}>{tempo.txt}</span>
      <div className={`shrink-0 flex items-center gap-1 ${acaoCls}`}>
        {onConcluir && (
          <Button size="sm" variant="ghost" onClick={onConcluir} aria-label={`Concluir atividade de ${nome}`}>
            <Icon name="check" size={14} /> <span className="hidden md:inline">Concluir</span>
          </Button>
        )}
        {item.tipo === 'conversa' && (
          <Link
            href={linkConversa}
            aria-label={`Responder ${nome}`}
            className="inline-flex items-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-4)]"
          >
            <Icon name="message" size={14} /> <span className="hidden md:inline">Responder</span>
          </Link>
        )}
        {item.negocioId && (
          <Button size="sm" variant="ghost" onClick={() => onAbrir(item.negocioId!)} aria-label={`Abrir negócio de ${nome}`} title="Abrir a ficha do negócio">
            <Icon name="arrow-up-right" size={14} /> <span className="hidden md:inline">Abrir</span>
          </Button>
        )}
      </div>
    </li>
  );
}

// ── Controle das 9h (gestor) ──

function Controle9h({ negocios, fichas, contatoPorId, agora, nomeDe, onAbrir }: {
  negocios: Negocio[]; fichas: FichaDisparo[]; contatoPorId: Map<string, Contato>; agora: Date;
  nomeDe: (id: string | null) => string; onAbrir: (id: string) => void;
}) {
  const c = controle9h(negocios, fichas, agora);
  const linhaNegocio = (detalhe: (n: Negocio) => string) => function Linha(n: Negocio) {
    return <LinhaNegocioControle key={n.id} nome={contatoPorId.get(n.contatoId)?.nome ?? '—'} detalhe={detalhe(n)} valor={n.valor} onAbrir={() => onAbrir(n.id)} />;
  };

  return (
    <SectionCard title={<TituloInfo info={INFO_CONTROLE_9H}>Controle das 9h</TituloInfo>} subtitle="Conferência diária. A meta de cada lista é zero." className="min-w-0">
      <ul className="-mx-2 divide-y divide-[var(--border-faint)]">
        <ItemControle id="sem-dono" titulo="Negócios sem dono" metrica="sem_dono" n={c.semDono.length} vazio="Nenhum negócio sem dono.">
          {c.semDono.map(linhaNegocio((n) => `${produtoDe(n.produto).nome} · ${n.etapaNome}`))}
        </ItemControle>
        <ItemControle
          id="ja-atendido" titulo="Perdidos hoje por “já atendido por outro vendedor”" info={INFO_JA_ATENDIDO} n={c.perdidosOutroVendedor.length}
          vazio="Nenhuma falha de distribuição hoje." dica="Falha de distribuição: tratar hoje."
        >
          {c.perdidosOutroVendedor.map(linhaNegocio((n) => `${produtoDe(n.produto).nome} · perdido por ${nomeDe(n.donoId)}`))}
        </ItemControle>
        <ItemControle id="sem-proximo" titulo="Sem próxima atividade" metrica="sem_proximo" n={c.semProximo.length} vazio="Todo negócio aberto tem próximo passo.">
          {c.semProximo.map(linhaNegocio((n) => `${nomeDe(n.donoId)} · ${n.etapaNome}`))}
        </ItemControle>
        <ItemControle id="fichas" titulo="Fichas de disparo aguardando aprovação" info={INFO_FICHAS} n={c.fichasAguardando.length} vazio="Nenhuma ficha esperando." violacao={false}>
          {c.fichasAguardando.map((f) => (
            <li key={f.id}>
              <Link href="/comercial/disparos" className="flex items-center justify-between gap-3 rounded-[var(--r-md)] px-2 py-1.5 hover:bg-[var(--surface-3)]">
                <span className="min-w-0">
                  <span className="block text-sm font-medium text-[var(--fg)] truncate">{f.objetivo}</span>
                  <span className="block text-xs text-[var(--fg-3)] truncate">{f.codigo} · {f.quantidade} contatos · {nomeDe(f.operadorId)} · {ROTULO_STATUS_FICHA[f.status]}</span>
                </span>
                <Icon name="arrow-right" size={14} className="shrink-0 text-[var(--fg-3)]" />
              </Link>
            </li>
          ))}
        </ItemControle>
      </ul>
    </SectionCard>
  );
}

function LinhaNegocioControle({ nome, detalhe, valor, onAbrir }: { nome: string; detalhe: string; valor: number; onAbrir: () => void }) {
  return (
    <li>
      <button type="button" onClick={onAbrir} className="w-full flex items-center justify-between gap-3 rounded-[var(--r-md)] px-2 py-1.5 text-left hover:bg-[var(--surface-3)] cursor-pointer">
        <span className="min-w-0">
          <span className="block text-sm font-medium text-[var(--fg)] truncate">{nome}</span>
          <span className="block text-xs text-[var(--fg-3)] truncate">{detalhe}</span>
        </span>
        <span className="shrink-0 text-xs tabular text-[var(--fg-2)]">{fmtBRL(valor)}</span>
      </button>
    </li>
  );
}

/** Uma lista do controle: só o número; clica para ver os itens. `violacao` = número acima de zero quebra regra (vermelho). */
function ItemControle({ id, titulo, metrica, info, n, vazio, dica, violacao = true, children }: {
  id: string; titulo: string; metrica?: MetricaKey; info?: TextoIndicador; n: number; vazio: string; dica?: string; violacao?: boolean; children: React.ReactNode;
}) {
  const [aberto, setAberto] = useState(false);
  const painel = `controle-${id}`;
  const corN = n === 0 ? 'text-[var(--fg-3)]' : violacao ? 'text-[var(--red)]' : 'text-[var(--fg)]';
  return (
    <li>
      {/* (i) fica fora do botão: botão dentro de botão não pode. */}
      <div className="flex items-center gap-1 rounded-[var(--r-md)] hover:bg-[var(--surface-3)]">
        <button
          type="button"
          onClick={() => setAberto(!aberto)}
          aria-expanded={aberto}
          aria-controls={painel}
          title={dica}
          className="flex-1 min-w-0 flex items-center gap-3 min-h-10 px-2 py-2 text-left cursor-pointer"
        >
          <Icon name={aberto ? 'chevron-down' : 'chevron-right'} size={14} className="shrink-0 text-[var(--fg-4)]" />
          <span className="flex-1 min-w-0 text-sm text-[var(--fg-2)]">{titulo}</span>
          <span className={`shrink-0 text-sm font-semibold tabular ${corN}`}>{n}</span>
        </button>
        <InfoIndicador metrica={metrica} texto={info} className="shrink-0 mr-1.5" />
      </div>
      {aberto && (
        <div id={painel} className="pb-2 pl-6">
          {dica && n > 0 && <p className="px-2 pb-1 text-[11px] text-[var(--fg-3)]">{dica}</p>}
          {n === 0 ? <p className="px-2 py-1 text-xs text-[var(--fg-3)]">{vazio}</p> : <ul>{children}</ul>}
        </div>
      )}
    </li>
  );
}

// ── Carga por vendedor (gestor) ──

/** Colunas da carga: no celular cada vendedor vira um cartão; em tela larga, 6 colunas que cabem. */
const COLUNAS_CARGA: { k: 'abertos' | 'criticos' | 'semProximo' | 'atrasadas' | 'vendas'; rotulo: string; metrica: MetricaKey; zero: boolean }[] = [
  { k: 'abertos', rotulo: 'Abertos', metrica: 'abertos', zero: false },
  { k: 'criticos', rotulo: 'Críticos', metrica: 'criticos', zero: true },
  { k: 'semProximo', rotulo: 'Sem próximo', metrica: 'sem_proximo', zero: true },
  { k: 'atrasadas', rotulo: 'Atrasadas', metrica: 'atrasadas', zero: true },
  { k: 'vendas', rotulo: 'Vendas hoje', metrica: 'vendas', zero: false },
];

function CargaPorVendedor({ negocios, atividades, vendedores, agora, nomeDe, porVendedor, onVer }: {
  negocios: Negocio[]; atividades: Atividade[]; vendedores: Vendedor[]; agora: Date;
  nomeDe: (id: string | null) => string; porVendedor: Record<string, LinhaFechamento>; onVer: (vendedorId: string) => void;
}) {
  const carga = cargaPorVendedor(negocios, atividades, vendedores, agora).map((l) => ({ ...l, vendas: porVendedor[l.vendedorId]?.vendas ?? 0 }));
  const grade = 'sm:grid sm:grid-cols-[minmax(0,1.6fr)_repeat(5,minmax(0,1fr))] sm:items-center sm:gap-3';
  return (
    <SectionCard
      title={<TituloInfo info={INFO_CARGA}>Carga por vendedor</TituloInfo>}
      subtitle="Vermelho: acima da meta zero. Clique no vendedor para ver o painel dele."
    >
      <div className={`hidden ${grade} px-2 pb-2 text-[11px] font-semibold uppercase tracking-wider text-[var(--fg-3)]`}>
        <span>Vendedor</span>
        {COLUNAS_CARGA.map((c) => (
          <span key={c.k} className="inline-flex items-center justify-end gap-0.5 normal-case tracking-normal text-xs">
            {c.rotulo}<InfoIndicador metrica={c.metrica} />
          </span>
        ))}
      </div>
      <ul className="divide-y divide-[var(--border-faint)] -mx-2">
        {carga.map((l) => (
          <li key={l.vendedorId}>
            <button
              type="button"
              onClick={() => onVer(l.vendedorId)}
              aria-label={`Ver o painel de ${nomeDe(l.vendedorId)}`}
              className={`w-full text-left rounded-[var(--r-md)] px-2 py-2.5 hover:bg-[var(--surface-3)] cursor-pointer ${grade}`}
            >
              <span className="flex items-center gap-1.5 min-w-0 text-sm font-semibold text-[var(--fg)]">
                <span className="truncate">{nomeDe(l.vendedorId)}</span>
                <Icon name="arrow-right" size={13} className="shrink-0 text-[var(--fg-4)]" />
              </span>
              {/* Celular: os números em linha, com rótulo; tela larga: uma coluna por número. */}
              <span className="mt-1.5 flex flex-wrap gap-x-4 gap-y-1 sm:contents">
                {COLUNAS_CARGA.map((c) => {
                  const v = l[c.k];
                  const cor = c.zero ? (v ? 'text-[var(--red)] font-semibold' : 'text-[var(--fg-3)]') : 'text-[var(--fg)] font-semibold';
                  return (
                    <span key={c.k} className="inline-flex items-baseline gap-1 text-sm sm:justify-end">
                      <span className="sm:hidden text-xs text-[var(--fg-3)]">{c.rotulo}</span>
                      <span className={`tabular ${cor}`}>{v}</span>
                    </span>
                  );
                })}
              </span>
            </button>
          </li>
        ))}
      </ul>
    </SectionCard>
  );
}

// ── Inegociáveis ──

const CHAVE_INEGOCIAVEIS = 'comercial_inegociaveis_aberto';

/** Regras do playbook em versão de bolso. Recolhido por padrão; a escolha fica lembrada no navegador. */
function Inegociaveis() {
  const [aberto, setAberto] = useState(false);
  useEffect(() => {
    try {
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (window.localStorage.getItem(CHAVE_INEGOCIAVEIS) === '1') setAberto(true);
    } catch { /* sem armazenamento: fica recolhido */ }
  }, []);
  const alternar = () => {
    const v = !aberto;
    setAberto(v);
    try { window.localStorage.setItem(CHAVE_INEGOCIAVEIS, v ? '1' : '0'); } catch { /* ignora */ }
  };
  return (
    <Card className="px-5 py-3">
      <button
        type="button"
        onClick={alternar}
        aria-expanded={aberto}
        aria-controls="lista-inegociaveis"
        className="w-full flex items-center justify-between gap-3 text-left cursor-pointer"
      >
        <span className="text-sm font-semibold text-[var(--fg)]">Os 9 inegociáveis do playbook</span>
        <span className="inline-flex items-center gap-1 text-xs text-[var(--fg-3)]">
          {aberto ? 'Recolher' : 'Mostrar'} <Icon name={aberto ? 'chevron-up' : 'chevron-down'} size={14} />
        </span>
      </button>
      {aberto && (
        <ol id="lista-inegociaveis" className="mt-3 mb-1 space-y-2">
          {INEGOCIAVEIS.map((t, i) => (
            <li key={i} className="flex gap-3 text-sm text-[var(--fg-2)] leading-snug">
              <span className="w-4 shrink-0 text-right text-xs font-semibold tabular text-[var(--fg-3)] pt-px">{i + 1}</span>
              <span>{t}</span>
            </li>
          ))}
        </ol>
      )}
    </Card>
  );
}
