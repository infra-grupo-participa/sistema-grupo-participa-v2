'use client';

// Uma conversa (histórico + compositor), usada na tela de Conversas e no painel flutuante do Funil (dock).
// Regras do playbook no ponto onde bloqueiam: só pelos números do Comercial, lead que não é seu não se toca, fora da
// janela de 24 h só sai template aprovado, mensagem curta pelo nome do lead e sem emoji.
// 20261009153515: menu na mensagem (copiar, responder citando, editar, apagar para todos), status do atendimento
// (em espera / encerrar / reabrir), link da conversa e mensagens agendadas (cancelar antes do envio).
import { useEffect, useId, useMemo, useRef, useState, type UIEvent } from 'react';
import { AvatarInicial, Badge, Button, Card, FilterSelect, Input, Modal, Skeleton, Textarea } from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { produto as produtoDe } from '../../domain/catalogo';
import { fmtTelefone } from '../../domain/regras';
import type { Contato, Conversa, Mensagem, Negocio, SessaoComercial, StatusMensagem, Template } from '../../domain/types';
import { motivoSemEscrita, podeEscreverContato, podeTrocarDono, somenteLeitura } from '../../domain/travas';
import { bloqueioCanalResposta, janelaDoCanal, opcoesCanalResposta, rotuloProvedor } from '../../domain/nova-conversa';
import { bloqueioEnvio, canalDeResposta, rotuloCanal, semJanela, type CanalWhatsapp, type PainelCanais } from '../../domain/canais-whatsapp';
import { conversasExcluiveis, mensagensDoCanal, podeExcluirConversa } from '../../domain/excluir-conversa';
import { legendaDaMensagem } from '../../domain/midia';
import { acoesDaMensagem, trechoCitado } from '../../domain/acoes-mensagem';
import { estadoAtendimento, proximosEstados, ROTULO_ACAO_ATENDIMENTO, ROTULO_ATENDIMENTO, type EstadoAtendimento } from '../../domain/atendimento';
import { linkDaConversa, rotuloAgendada } from '../../domain/agendamento';
import { EstadoErro, FaixaErroAtualizacao, Vazio } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { Menu, type ItemMenu } from '../funil/pecas';
import { avisarMudanca, repo, useAtualizacaoPeriodica, useDados } from '../repositorio';
import { estaNoFim } from '../atualizacao';
import { INFO_CAIXA } from './indicadores';
import { ModalExcluirConversa } from './ModalExcluirConversa';
import { BotaoAnexar } from './Anexar';
import { BotaoGravarAudio } from './GravarAudio';
import { MidiaMensagem } from './MidiaMensagem';
import { MenuRespostas } from './pecas';
import { ModalApagarMensagem, ModalEditarMensagem } from './acoes-ui';
import { chaveDia, criarTravaEnvio, janelaRestante, preencherTemplate, primeiroNome, rotuloDia, temEmoji } from './regras-conversas';

/** Frases do playbook para qualificar sem enrolar. */
const RESPOSTAS_RAPIDAS = [
  'O que motivou você a se inscrever?',
  'Você atua como advogado, contador ou em outra área?',
  'Já trabalha com holding ou está começando?',
  'Te ligo amanhã às 10h ou às 15h?',
];

const BTN_CAB = 'w-8 h-8 grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]';

export interface PropsPainelConversa {
  /** Número escolhido na "Nova conversa" (a 1ª mensagem cria a conversa nele). */
  canalInicial?: string | null;
  contato: Contato; conversa: Conversa | null; negocio: Negocio | null; negociosDoContato: Negocio[]; templates: Template[];
  canais: CanalWhatsapp[]; painelCanais: PainelCanais | null; sessao: SessaoComercial;
  gestor: boolean; nomeDe: (id: string | null) => string; agora: Date; flash: (m: string) => void;
  /** Botão "voltar" (celular, tela de Conversas). */
  onVoltar?: () => void;
  onAbrirNegocio: (id: string) => void; onAgendar: (n: Negocio) => void;
  /** Abre o painel do contato (telas estreitas). Sem ele, o botão some (dock). */
  onDetalhes?: () => void;
  onAtribuir?: () => void;
  /** Gestor excluiu a conversa: avisa, fecha o painel e recarrega a lista. */
  onExcluida: (msg: string) => void;
  /** Botões extras no cabeçalho (dock: minimizar, abrir na tela de Conversas, fechar). */
  extrasCabecalho?: React.ReactNode;
  /** Cabeçalho enxuto (dock). */
  compacto?: boolean;
}

export function PainelConversa({
  canalInicial, contato, conversa, negocio, negociosDoContato, templates, canais, painelCanais, sessao, gestor, nomeDe, agora, flash,
  onVoltar, onAbrirNegocio, onAgendar, onDetalhes, onAtribuir, onExcluida, extrasCabecalho, compacto = false,
}: PropsPainelConversa) {
  const { dados, erro, carregando: carregandoMsgs, recarregar } = useDados(() => repo.mensagens(contato.id), [contato.id]);
  // Conversa aberta sozinha: mensagem nova, mídia que sai de "pendente" e status (enviada → entregue → lida).
  useAtualizacaoPeriodica(recarregar, 'conversaAberta');
  const mensagens = useMemo(() => (dados ?? []).filter((m) => m.contatoId === contato.id && m.canal === 'whatsapp'), [dados, contato.id]);
  const porId = useMemo(() => new Map(mensagens.map((m) => [m.id, m])), [mensagens]);
  // Rola SÓ a coluna de mensagens; vai ao fim só se o vendedor já estava perto do fim; senão, botão "novas mensagens".
  const rolagem = useRef<HTMLDivElement>(null);
  const noFim = useRef(true);
  const [novas, setNovas] = useState(false);
  const irAoFim = () => {
    const el = rolagem.current;
    if (el) el.scrollTop = el.scrollHeight;
    noFim.current = true;
    setNovas(false);
  };
  const aoRolar = (e: UIEvent<HTMLDivElement>) => {
    const el = e.currentTarget;
    noFim.current = estaNoFim(el.scrollTop, el.scrollHeight, el.clientHeight);
    if (noFim.current) setNovas(false);
  };
  const ultimaId = mensagens.at(-1)?.id;
  const vistaUltima = useRef<string | undefined>(undefined);
  useEffect(() => {
    if (!ultimaId || vistaUltima.current === ultimaId) return;
    const primeira = vistaUltima.current === undefined;
    vistaUltima.current = ultimaId;
    if (primeira || noFim.current) {
      const el = rolagem.current;
      if (el) el.scrollTop = el.scrollHeight;
      noFim.current = true;
    } else setNovas(true);
  }, [ultimaId]);

  const dono = conversa?.atribuidaA ?? contato.donoId;
  // Número da resposta: o escolhido; senão o da conversa mais recente; senão o oficial (mesmo critério do banco).
  const [canalEscolhido, setCanalEscolhido] = useState<string | null>(canalInicial ?? null);
  const canal = canalDeResposta(canalEscolhido, conversa?.canalId ?? null, canais);
  const opcoesCanal = opcoesCanalResposta(canais, conversa?.canais ?? (conversa?.canalId ? [conversa.canalId] : []), painelCanais, sessao, canalEscolhido);
  // Janela de 24 h DO NÚMERO da resposta: quem só falou pelo QR tem a do oficial fechada.
  const janelaAte = janelaDoCanal(conversa, canal?.id);
  const janela = janelaRestante(janelaAte, agora);
  const porQr = semJanela(canal);
  const variosNaConversa = new Set(mensagens.map((m) => m.canalId).filter(Boolean)).size > 1;
  const nomeCanal = (id: string | null | undefined) => rotuloCanal(canais.find((c) => c.id === id));
  const provedorDe = (id: string | null | undefined) => canais.find((c) => c.id === id)?.provedor ?? null;
  const podeAgendar = !!negocio && (gestor || negocio.donoId === sessao.vendedorId);
  const podeAtribuir = !!onAtribuir && podeTrocarDono(sessao) && !dono;
  const excluiveis = podeExcluirConversa(sessao) ? conversasExcluiveis(conversa) : [];
  const [excluir, setExcluir] = useState(false);
  const escreve = podeEscreverContato({ donoId: dono }, negociosDoContato, sessao);

  // Quem pode escrever: espelho de crm.pode_escrever_pessoa (dono do contato, dono de algum negócio da pessoa ou gestor).
  const bloqueio: string | null = somenteLeitura(sessao)
    ? 'Você acompanha a conversa, mas não responde (acesso só de leitura).'
    : contato.optOut
    ? 'Este contato pediu para não receber contato. Nenhuma mensagem sai para ele.'
    : !contato.telefone
      ? 'Contato sem telefone.'
      : motivoSemEscrita({ donoId: dono }, negociosDoContato, sessao, nomeDe);
  const bloqueioNumero = bloqueio ? null : bloqueioEnvio(canal, painelCanais) ?? bloqueioCanalResposta(canal, painelCanais, sessao);

  // Status do atendimento (20261009153515): mudar é de quem escreve para o contato (dono/gestor; leitor não).
  const estado = estadoAtendimento(conversa);
  const [mudandoEstado, setMudandoEstado] = useState(false);
  const mudarEstado = async (para: EstadoAtendimento) => {
    if (mudandoEstado) return;
    setMudandoEstado(true);
    const r = await repo.mudarAtendimento(contato.id, para);
    setMudandoEstado(false);
    flash(r.ok ? r.msg ?? 'Atualizado.' : r.msg ?? 'Não foi possível mudar o status.');
    if (r.ok) avisarMudanca();
  };
  // Sem permissão de área de transferência (navegador/iframe), mostra o link para copiar à mão.
  const [linkManual, setLinkManual] = useState<string | null>(null);
  const copiarLink = async () => {
    const url = linkDaConversa(contato.id);
    try { await navigator.clipboard.writeText(url); flash('Link da conversa copiado. Quem abrir vê só se tiver acesso ao lead.'); } catch { setLinkManual(url); }
  };

  // Ações na mensagem
  const [citando, setCitando] = useState<Mensagem | null>(null);
  const [editando, setEditando] = useState<Mensagem | null>(null);
  const [apagando, setApagando] = useState<Mensagem | null>(null);
  const itensDaMensagem = (m: Mensagem): ItemMenu[] => {
    const provedor = provedorDe(m.canalId);
    const a = acoesDaMensagem(m, { provedor, sessao, podeEscrever: escreve && !bloqueio, agora });
    const item = (rotulo: string, icone: string, e: { ok: boolean; motivo: string | null }, onEscolher: () => void): ItemMenu => ({
      rotulo, icone, desativado: !e.ok, titulo: e.motivo ?? undefined, nota: e.ok ? undefined : e.motivo ?? undefined, onEscolher,
    });
    const itens: ItemMenu[] = [
      item('Copiar texto', 'copy', a.copiar, async () => {
        try { await navigator.clipboard.writeText(m.texto); flash('Texto copiado.'); } catch { flash('Não foi possível copiar.'); }
      }),
      item('Responder citando', 'reply', a.responder, () => {
        setCitando(m);
        // a citação só vale no mesmo número: troca o compositor para o número da mensagem
        if (m.canalId && m.canalId !== canal?.id && opcoesCanal.some((c) => c.id === m.canalId)) setCanalEscolhido(m.canalId);
      }),
    ];
    if (m.direcao === 'saida') {
      itens.push(item('Editar', 'pencil', a.editar, () => setEditando(m)));
      itens.push(item('Apagar para todos', 'trash', a.apagar, () => setApagando(m)));
    }
    return itens;
  };
  const cancelarAgendada = async (m: Mensagem) => {
    const r = await repo.cancelarAgendada(m.id);
    flash(r.ok ? r.msg ?? 'Agendamento cancelado.' : r.msg ?? 'Não foi possível cancelar.');
    if (r.ok) avisarMudanca();
  };

  const grupos = useMemo(() => {
    const g: { dia: string; itens: Mensagem[] }[] = [];
    for (const m of mensagens) {
      const k = chaveDia(m.em);
      if (g.at(-1)?.dia !== k) g.push({ dia: k, itens: [] });
      g.at(-1)!.itens.push(m);
    }
    return g;
  }, [mensagens]);
  const nomeTemplate = (id: string | null) => templates.find((t) => t.id === id)?.nome ?? id;

  const itensMais: ItemMenu[] = [
    { rotulo: 'Copiar link da conversa', icone: 'link', titulo: 'Quem abrir vê só se tiver acesso ao lead', onEscolher: copiarLink },
    ...(excluiveis.length > 0 ? [{ rotulo: 'Excluir conversa', icone: 'trash', titulo: 'Some do CRM para todos (não apaga no WhatsApp do cliente)', onEscolher: () => setExcluir(true) }] : []),
  ];

  return (
    <Card className="h-full flex flex-col overflow-hidden">
      <div className="shrink-0 flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2 border-b border-[var(--border)]">
        {onVoltar && (
          <button type="button" onClick={onVoltar} aria-label="Voltar para a lista" className="lg:hidden -ml-1 w-8 h-8 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
            <Icon name="arrow-left" size={16} />
          </button>
        )}
        <AvatarInicial nome={contato.nome} size={32} />
        <div className="min-w-[120px] flex-1">
          <h2 className="text-sm font-semibold text-[var(--fg)] truncate">{contato.nome}</h2>
          <div className="text-xs text-[var(--fg-3)] truncate">{fmtTelefone(contato.telefone)} · {dono ? nomeDe(dono) : 'sem dono'}</div>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-2 ml-auto">
          {extrasCabecalho}
          {!compacto && (opcoesCanal.length > 1 ? (
            <FilterSelect value={canal?.id ?? ''} onChange={(e) => setCanalEscolhido(e.target.value || null)} aria-label="Responder pelo número" title="Responder pelo número">
              {opcoesCanal.map((c) => <option key={c.id} value={c.id}>{rotuloCanal(c)} ({rotuloProvedor(c)})</option>)}
            </FilterSelect>
          ) : canal && canais.length > 1 ? (
            <span title="Número desta conversa: a resposta sai por ele"><Badge>{rotuloCanal(canal)}</Badge></span>
          ) : null)}
          {!compacto && (
            <span className="inline-flex items-center">
              {porQr ? (
                <span title="Número conectado por QR: sem janela de 24 h e sem template. Sem disparo em massa."><Badge tone="info">WhatsApp por QR</Badge></span>
              ) : janela ? (
                <span title={`Janela de 24 h aberta pela última mensagem do lead: fecha em ${janela.rotulo}`}>
                  <Badge tone={janela.minutos < 120 ? 'warning' : 'info'}>Janela: {janela.rotulo}</Badge>
                </span>
              ) : (
                <span title="Fora da janela de 24 h: só sai template aprovado"><Badge tone="neutral">Janela fechada</Badge></span>
              )}
              <InfoIndicador texto={INFO_CAIXA.janela} />
            </span>
          )}
          {!compacto && podeAgendar && (
            <Button size="sm" variant="ghost" onClick={() => onAgendar(negocio)} aria-label="Agendar próximo passo" title="Agendar próximo passo">
              <Icon name="calendar" size={14} /><span className="hidden md:inline">Próximo passo</span>
            </Button>
          )}
          {negocio && (
            <Button size="sm" variant="ghost" onClick={() => onAbrirNegocio(negocio.id)} aria-label="Abrir negócio" title="Abrir negócio">
              <Icon name="briefcase" size={14} /><span className={compacto ? 'sr-only' : 'hidden md:inline'}>Negócio</span>
            </Button>
          )}
          {!compacto && (
            <button type="button" onClick={copiarLink} aria-label="Copiar link da conversa" title="Copiar link da conversa (quem abrir vê só se tiver acesso ao lead)" className={BTN_CAB}>
              <Icon name="link" size={15} />
            </button>
          )}
          {onDetalhes && (
            <button type="button" onClick={onDetalhes} aria-label="Detalhes do contato" title="Detalhes do contato" className={`2xl:hidden ${BTN_CAB}`}>
              <Icon name="panel-open" size={15} className="scale-x-[-1]" />
            </button>
          )}
          <Menu
            rotulo="Mais ações da conversa"
            itens={itensMais}
            classeGatilho={BTN_CAB}
            gatilho={<span aria-hidden className="text-base leading-none">⋯</span>}
          />
        </div>
      </div>
      {conversa && (
        <BarraAtendimento estado={estado} pode={escreve && !somenteLeitura(sessao)} ocupado={mudandoEstado} onMudar={mudarEstado}
                          quem={conversa.atendimentoPor ? nomeDe(conversa.atendimentoPor) : null} />
      )}
      {excluir && (
        <ModalExcluirConversa
          nome={contato.nome}
          conversas={excluiveis}
          canalInicial={canal?.id ?? conversa?.canalId ?? null}
          contarMensagens={(id) => mensagensDoCanal(mensagens, id)}
          rotuloCanal={(id) => nomeCanal(id) || 'WhatsApp'}
          onClose={() => setExcluir(false)}
          onFeito={(msg) => { setExcluir(false); onExcluida(msg); }}
        />
      )}
      {linkManual && (
        <Modal onClose={() => setLinkManual(null)} title="Link da conversa" width="max-w-md"
               footer={<Button size="sm" variant="ghost" onClick={() => setLinkManual(null)}>Fechar</Button>}>
          <Input readOnly value={linkManual} aria-label="Link da conversa" onFocus={(e) => e.currentTarget.select()} autoFocus />
          <p className="mt-2 text-xs text-[var(--fg-3)]">Copie o link (Ctrl/⌘ + C). Quem abrir vê a conversa só se tiver acesso ao lead (dono, gestor ou leitor).</p>
        </Modal>
      )}
      {editando && <ModalEditarMensagem m={editando} onClose={() => setEditando(null)} flash={flash} />}
      {apagando && <ModalApagarMensagem m={apagando} onClose={() => setApagando(null)} flash={flash} />}

      <div className="relative flex-1 min-h-0">
      <div ref={rolagem} onScroll={aoRolar} className="h-full overflow-y-auto overscroll-contain px-4 pb-3 bg-[var(--surface-1)]" aria-live="polite" aria-label={`Mensagens com ${contato.nome}`} role="log">
        {erro && dados && !carregandoMsgs && <FaixaErroAtualizacao className="mb-2" mensagem={erro} onTentar={recarregar} />}
        {erro && !dados ? (
          <EstadoErro mensagem={erro} onTentar={recarregar} />
        ) : !dados ? (
          <div className="space-y-3 pt-2" aria-busy="true">
            {[60, 45, 70, 35].map((w, i) => (
              <div key={i} className={`flex ${i % 2 ? 'justify-end' : 'justify-start'}`}>
                <Skeleton w={`${w}%`} h={44} className="rounded-[var(--r-lg)]" />
              </div>
            ))}
          </div>
        ) : mensagens.length === 0 ? (
          <Vazio
            titulo="Sem mensagens ainda"
            hint={porQr ? 'Número por QR: escreva a primeira mensagem. A conversa aparece na lista assim que ela sair.'
              : janela ? 'Janela aberta: escreva a primeira mensagem.' : 'Fora da janela de 24 h, a primeira mensagem sai por template aprovado.'}
            icone="message"
          />
        ) : grupos.map((g) => (
          <div key={g.dia}>
            <div className="sticky top-0 z-[1] flex justify-center py-2 pointer-events-none">
              <span className="rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-0.5 text-[11px] text-[var(--fg-3)] shadow-[var(--highlight-surface)]">
                {rotuloDia(g.itens[0].em, agora)}
              </span>
            </div>
            <div className="space-y-2">
              {g.itens.map((m) => (
                <Bolha key={m.id} m={m} agora={agora} nomeTemplate={nomeTemplate} autor={m.autorId ? nomeDe(m.autorId) : m.externa ? 'Celular/Clint' : null}
                       numero={variosNaConversa ? nomeCanal(m.canalId) : null}
                       citada={m.citadaId ? porId.get(m.citadaId) ?? null : null}
                       itens={itensDaMensagem(m)}
                       onCancelarAgendada={m.agendadaPara && m.envio === 'na_fila' && (gestor || m.autorId === sessao.vendedorId) && !somenteLeitura(sessao)
                         ? () => cancelarAgendada(m) : undefined} />
              ))}
            </div>
          </div>
        ))}
      </div>
      {novas && (
        <button
          type="button"
          onClick={irAoFim}
          className="absolute bottom-3 left-1/2 -translate-x-1/2 inline-flex items-center gap-1.5 rounded-[var(--r-pill)] border border-[var(--border-strong)] bg-[var(--surface-2)] px-3 py-1.5 text-xs font-medium text-[var(--fg)] shadow-[var(--shadow-overlay)] hover:bg-[var(--surface-3)]"
        >
          <Icon name="arrow-down" size={13} /> Novas mensagens
        </button>
      )}
      </div>

      {podeAtribuir && (
        <div className="shrink-0 flex flex-wrap items-center justify-between gap-2 border-t border-[var(--border)] bg-[var(--surface-2)] px-4 py-2 text-xs text-[var(--fg-2)]">
          <span className="inline-flex items-center gap-2">
            <Icon name="user-x" size={14} className="shrink-0 text-[var(--fg-3)]" />
            Conversa sem dono. Defina quem atende antes de responder.
          </span>
          <Button size="sm" variant="subtle" onClick={onAtribuir}><Icon name="user-check" size={13} /> Atribuir dono</Button>
        </div>
      )}
      {bloqueio ? (
        <div className="shrink-0 flex items-start gap-2 border-t border-[var(--border)] bg-[var(--surface-3)] px-4 py-3 text-sm text-[var(--fg-2)]">
          <Icon name="lock" size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
          <span><strong className="text-[var(--fg)]">Somente leitura.</strong> {bloqueio}</span>
        </div>
      ) : bloqueioNumero ? (
        <div className="shrink-0 flex items-start gap-2 border-t border-[var(--border)] bg-[var(--surface-3)] px-4 py-3 text-sm text-[var(--fg-2)]">
          <Icon name="alert" size={16} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
          <span><strong className="text-[var(--fg)]">Número indisponível.</strong> {bloqueioNumero}{opcoesCanal.length > 1 ? ' Escolha outro número acima.' : ''}</span>
        </div>
      ) : (
        <Envio
          key={canal?.id ?? 'padrao'}
          contato={contato}
          negocio={negocio}
          canalId={canal?.id ?? null}
          porQr={porQr}
          janelaAberta={porQr || !!janela}
          templates={templates}
          remetente={nomeDe(sessao.vendedorId)}
          flash={flash}
          citando={citando && citando.canalId === canal?.id ? citando : null}
          citandoOutroNumero={!!citando && citando.canalId !== canal?.id}
          onCancelarCitacao={() => setCitando(null)}
        />
      )}
    </Card>
  );
}

/** Status do atendimento + botões (Em espera / Encerrar atendimento / Reabrir). */
function BarraAtendimento({ estado, pode, ocupado, quem, onMudar }: {
  estado: EstadoAtendimento; pode: boolean; ocupado: boolean; quem: string | null; onMudar: (e: EstadoAtendimento) => void;
}) {
  if (!pode && estado === 'aberto') return null;
  return (
    <div className="shrink-0 flex flex-wrap items-center gap-2 border-b border-[var(--border)] bg-[var(--surface-2)] px-3 py-1.5 text-xs text-[var(--fg-2)]">
      <span className="inline-flex items-center gap-1.5">
        <span className="text-[var(--fg-3)]">Atendimento:</span>
        <Badge tone={estado === 'aberto' ? 'info' : estado === 'espera' ? 'warning' : 'neutral'}>{ROTULO_ATENDIMENTO[estado]}</Badge>
        {estado !== 'aberto' && <span className="text-[var(--fg-3)]">{estado === 'espera' ? 'SLA pausado' : 'fora da fila'}{quem ? ` · ${primeiroNome(quem)}` : ''}</span>}
      </span>
      {pode && (
        <span className="ml-auto inline-flex flex-wrap gap-1.5">
          {proximosEstados(estado).map((e) => (
            <Button key={e} size="sm" variant={e === 'encerrado' ? 'subtle' : 'ghost'} disabled={ocupado} onClick={() => onMudar(e)}
                    title={e === 'espera' ? 'Pausa o alerta de SLA até o contato responder' : e === 'encerrado' ? 'Sai da fila e dos contadores; volta sozinha se o contato escrever' : 'Volta para a fila'}>
              <Icon name={e === 'espera' ? 'pause' : e === 'encerrado' ? 'check-circle' : 'rotate'} size={13} /> {ROTULO_ACAO_ATENDIMENTO[e]}
            </Button>
          ))}
        </span>
      )}
    </div>
  );
}

const ROTULO_STATUS: Record<StatusMensagem, string> = { enviada: 'Enviada', entregue: 'Entregue', lida: 'Lida', falhou: 'Falhou' };

function StatusEnvio({ s, envio, erro, agendada, agora }: { s: StatusMensagem | null; envio?: Mensagem['envio']; erro?: string | null; agendada?: string | null; agora: Date }) {
  if (!s && envio === 'na_fila' && agendada && new Date(agendada).getTime() > agora.getTime()) {
    return <span className="inline-flex items-center gap-1"><Icon name="clock" size={12} /> {rotuloAgendada(agendada)}</span>;
  }
  if (!s && envio) return <span className="inline-flex items-center gap-1"><Icon name="clock" size={12} /> {envio === 'enviando' ? 'Enviando' : 'Na fila'}</span>;
  if (!s) return null;
  if (s === 'falhou') return <span className="inline-flex items-center gap-1 font-semibold text-[var(--red)]" title={erro ?? undefined}><Icon name="alert" size={12} /> Falhou{erro ? `: ${erro}` : ''}</span>;
  const duplo = s === 'entregue' || s === 'lida';
  return (
    <span className="inline-flex items-center" title={ROTULO_STATUS[s]} style={{ color: s === 'lida' ? 'var(--info)' : 'var(--fg-3)' }}>
      <Icon name="check" size={12} strokeWidth={2.5} />
      {duplo && <Icon name="check" size={12} strokeWidth={2.5} className="-ml-[7px]" />}
      <span className="sr-only">{ROTULO_STATUS[s]}</span>
    </span>
  );
}

/** Toque longo (celular) abre o menu da mensagem. */
function useToqueLongo(abrir: () => void) {
  const t = useRef<ReturnType<typeof setTimeout> | null>(null);
  const parar = () => { if (t.current) { clearTimeout(t.current); t.current = null; } };
  useEffect(() => parar, []);
  return {
    onTouchStart: () => { parar(); t.current = setTimeout(abrir, 500); },
    onTouchEnd: parar, onTouchMove: parar, onTouchCancel: parar,
  };
}

function Bolha({ m, nomeTemplate, autor, numero, citada, itens, onCancelarAgendada, agora }: {
  m: Mensagem; agora: Date; nomeTemplate: (id: string | null) => string | null; autor: string | null; numero: string | null;
  citada: Mensagem | null; itens: ItemMenu[]; onCancelarAgendada?: () => void;
}) {
  const saida = m.direcao === 'saida';
  const hora = new Date(m.em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  const apagada = !!m.apagadaEm;
  const legenda = apagada ? null : legendaDaMensagem(m);
  const caixa = useRef<HTMLDivElement>(null);
  const toque = useToqueLongo(() => caixa.current?.querySelector<HTMLButtonElement>('button[aria-haspopup="menu"]')?.click());
  const agendada = !!m.agendadaPara && m.envio === 'na_fila';
  return (
    <div className={`group flex items-start gap-1 ${saida ? 'justify-end' : 'justify-start'}`} ref={caixa} {...toque}>
      {saida && <MenuBolha itens={itens} />}
      <div
        className={`min-w-0 max-w-[85%] sm:max-w-[68%] px-3 py-2 text-sm text-[var(--fg)] border ${
          saida ? 'rounded-[var(--r-lg)] rounded-br-[var(--r-sm)]' : 'rounded-[var(--r-lg)] rounded-bl-[var(--r-sm)]'
        } ${
          m.status === 'falhou' ? 'border-[var(--red-border)] bg-[var(--red-subtle)]'
            : agendada ? 'border-dashed border-[var(--border-strong)] bg-[var(--surface-2)]'
            : saida ? 'border-[var(--border-strong)] bg-[var(--surface-4)]' : 'border-[var(--border)] bg-[var(--surface-2)]'
        }`}
      >
        {m.citadaId && (
          <div className="mb-1.5 border-l-2 border-[var(--accent)] bg-[var(--surface-3)] rounded-[var(--r-sm)] px-2 py-1 text-xs text-[var(--fg-2)]">
            <span className="block font-semibold text-[var(--fg-3)]">{citada ? (citada.direcao === 'saida' ? 'Você' : 'Contato') : 'Mensagem citada'}</span>
            <span className="block truncate">{citada ? trechoCitado(citada.texto) : '…'}</span>
          </div>
        )}
        {m.templateId && !apagada && (
          <div className="mb-1 inline-flex items-center gap-1 text-[11px] text-[var(--fg-3)]">
            <Icon name="file" size={12} /> Template · {nomeTemplate(m.templateId)}
          </div>
        )}
        {apagada ? (
          <div className="italic text-[var(--fg-3)] inline-flex items-center gap-1.5"><Icon name="x" size={13} /> Mensagem apagada</div>
        ) : (
          <>
            <MidiaMensagem m={m} />
            {legenda && <div className="whitespace-pre-wrap break-words leading-relaxed">{legenda}</div>}
          </>
        )}
        <div className="mt-1 flex flex-wrap items-center justify-end gap-x-1.5 text-[11px] text-[var(--fg-3)] tabular">
          {numero && <span className="truncate" title="Número da mensagem">{numero} ·</span>}
          {saida && autor && <span className="truncate">{primeiroNome(autor)}</span>}
          {saida && m.origem === 'mcp' && <span title="Enviada pelo Claude, no nome de quem pediu">via Claude</span>}
          {m.editadaEm && !apagada && <span title={`Editada em ${new Date(m.editadaEm).toLocaleString('pt-BR')}`}>editada ·</span>}
          {!agendada && <span>{hora}</span>}
          {saida && <StatusEnvio s={m.status} envio={m.envio} erro={m.erro} agendada={m.agendadaPara} agora={agora} />}
          {onCancelarAgendada && (
            <button type="button" onClick={onCancelarAgendada} className="ml-1 font-semibold text-[var(--fg-2)] underline hover:text-[var(--fg)]">Cancelar</button>
          )}
        </div>
      </div>
      {!saida && <MenuBolha itens={itens} />}
    </div>
  );
}

/** "⋯" ao passar o mouse (no celular fica sempre visível; toque longo também abre). */
function MenuBolha({ itens }: { itens: ItemMenu[] }) {
  return (
    <span className="shrink-0 self-center opacity-100 sm:opacity-0 sm:group-hover:opacity-100 sm:focus-within:opacity-100 transition-opacity">
      <Menu
        rotulo="Ações da mensagem"
        itens={itens}
        largura={260}
        classeGatilho="w-7 h-7 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-3)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
        gatilho={<span aria-hidden className="text-base leading-none">⋯</span>}
      />
    </span>
  );
}

// ── Envio ──

function Envio({ contato, negocio, canalId, porQr, janelaAberta, templates, remetente, flash, citando, citandoOutroNumero, onCancelarCitacao }: {
  contato: Contato; negocio: Negocio | null; canalId: string | null; porQr: boolean; janelaAberta: boolean; templates: Template[]; remetente: string; flash: (m: string) => void;
  citando: Mensagem | null; citandoOutroNumero: boolean; onCancelarCitacao: () => void;
}) {
  const aprovados = templates.filter((t) => t.aprovado);
  const pendentes = templates.length - aprovados.length;
  const [texto, setTexto] = useState('');
  const [templateId, setTemplateId] = useState<string>(aprovados[0]?.id ?? '');
  const [enviando, setEnviando] = useState(false);
  // Trava síncrona (o estado `enviando` só vale no próximo render: duplo clique passaria) + chave de idempotência.
  const trava = useRef(criarTravaEnvio());
  const [menu, setMenu] = useState(false);
  const campo = useRef<HTMLTextAreaElement>(null);
  const botaoMenu = useRef<HTMLButtonElement>(null);
  const idMenu = useId();
  const nome = primeiroNome(contato.nome);
  const tpl = aprovados.find((t) => t.id === templateId) ?? null;
  const prodNome = negocio ? produtoDe(negocio.produto).nome : null;
  const preview = tpl
    ? preencherTemplate(tpl.texto, { nome, vendedor: primeiroNome(remetente), produto: prodNome, evento: contato.tags[0] ?? prodNome })
    : null;
  useEffect(() => { if (citando) campo.current?.focus(); }, [citando]);

  const enviar = async (corpo: string, tId: string | null) => {
    if (!corpo.trim()) return;
    const chave = trava.current.comecar(`${tId ?? ''}|${citando?.id ?? ''}|${corpo}`);
    if (!chave) return;
    setEnviando(true);
    let r: Awaited<ReturnType<typeof repo.enviarMensagem>>;
    try {
      r = citando && !tId ? await repo.responderMensagem(citando.id, corpo, chave) : await repo.enviarMensagem(contato.id, corpo, tId, chave, canalId);
    } catch { r = { ok: false, msg: 'Não foi possível enviar.' }; }
    trava.current.terminar(r.ok);
    setEnviando(false);
    if (!r.ok) { flash(r.msg ?? 'Não foi possível enviar.'); return; }
    if (!tId) setTexto('');
    if (citando) onCancelarCitacao();
    flash(r.msg ?? 'Mensagem enviada.');
    avisarMudanca();
  };

  const fecharMenu = () => { setMenu(false); campo.current?.focus(); };
  const inserir = (f: string) => {
    setTexto((t) => (t.trim() ? `${t.trimEnd()} ${f}` : `${nome}, ${f.charAt(0).toLowerCase()}${f.slice(1)}`));
    fecharMenu();
  };

  if (!janelaAberta) {
    return (
      <div className="shrink-0 border-t border-[var(--border)] px-4 py-3 space-y-2">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-[var(--fg-2)]">
          <Icon name="lock" size={13} className="text-[var(--fg-3)]" />
          Janela de 24 h fechada: só sai template aprovado.
          {pendentes > 0 && <span className="text-[var(--fg-3)]">({pendentes} aguardando aprovação não aparecem)</span>}
        </div>
        {aprovados.length === 0 ? (
          <p className="text-sm text-[var(--fg-3)]">Nenhum template aprovado disponível.</p>
        ) : (
          <>
            <FilterSelect value={templateId} onChange={(e) => setTemplateId(e.target.value)} aria-label="Template">
              {aprovados.map((t) => <option key={t.id} value={t.id}>{t.nome} · {t.categoria === 'utility' ? 'utilidade' : 'marketing'}</option>)}
            </FilterSelect>
            {preview && (
              <div className="rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-3)] px-3 py-2 text-sm text-[var(--fg)] whitespace-pre-wrap" aria-label="Prévia do template">
                {preview.texto}
              </div>
            )}
            {preview && preview.faltando.length > 0 && (
              <p className="text-xs text-[var(--red)]">Sem valor para: {preview.faltando.map((v) => `{{${v}}}`).join(', ')}. Complete o contato ou escolha outro template.</p>
            )}
            <div className="flex justify-end">
              <Button size="sm" disabled={!preview || preview.faltando.length > 0 || enviando} onClick={() => preview && enviar(preview.texto, templateId)}>
                <Icon name="send" size={14} /> Enviar template
              </Button>
            </div>
          </>
        )}
      </div>
    );
  }

  const emoji = temEmoji(texto);
  return (
    <div className="shrink-0 border-t border-[var(--border)] px-4 pt-3 pb-2">
      {(citando || citandoOutroNumero) && (
        <div className="mb-2 flex items-start gap-2 rounded-[var(--r-md)] border-l-2 border-[var(--accent)] bg-[var(--surface-3)] px-2 py-1.5 text-xs text-[var(--fg-2)]">
          <Icon name="reply" size={13} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
          <span className="min-w-0 flex-1">
            {citando ? <>Respondendo a <span className="text-[var(--fg)]">{trechoCitado(citando.texto, 120)}</span></>
              : 'A mensagem citada é de outro número: troque o número acima para responder citando.'}
          </span>
          <button type="button" onClick={onCancelarCitacao} aria-label="Cancelar citação" className="shrink-0 text-[var(--fg-3)] hover:text-[var(--fg)]"><Icon name="x" size={13} /></button>
        </div>
      )}
      <div className="relative flex flex-wrap sm:flex-nowrap items-end justify-end gap-2">
        {menu && <MenuRespostas id={idMenu} frases={RESPOSTAS_RAPIDAS} ancora={botaoMenu} onEscolher={inserir} onFechar={fecharMenu} />}
        <Textarea
          ref={campo}
          rows={2}
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); enviar(texto, null); return; }
            if (e.key === 'Escape' && citando) { e.preventDefault(); onCancelarCitacao(); return; }
            // "/" com o campo vazio abre as respostas rápidas (como nos apps de atendimento).
            if (e.key === '/' && !texto.trim()) { e.preventDefault(); setMenu(true); }
          }}
          placeholder={`Mensagem para ${nome || 'o lead'} (sem emoji)`}
          aria-label="Mensagem"
          className="!resize-none basis-full sm:basis-0 sm:flex-1"
        />
        {!citando && <BotaoAnexar contatoId={contato.id} nomeContato={nome || contato.nome} desabilitado={enviando} flash={flash} canalId={canalId} />}
        {!citando && <BotaoGravarAudio contatoId={contato.id} nomeContato={nome || contato.nome} desabilitado={enviando} flash={flash} canalId={canalId} />}
        <Button
          ref={botaoMenu}
          variant="ghost"
          size="md"
          className="!px-3"
          onClick={() => setMenu((v) => !v)}
          aria-label="Respostas rápidas"
          title="Respostas rápidas ( / )"
          aria-haspopup="menu"
          aria-expanded={menu}
          aria-controls={menu ? idMenu : undefined}
        >
          <Icon name="message" size={15} />
        </Button>
        <Button size="md" className="!px-3" disabled={!texto.trim() || enviando} onClick={() => enviar(texto, null)} aria-label="Enviar" title="Enviar (Ctrl/⌘ + Enter)">
          <Icon name="send" size={15} />
        </Button>
      </div>
      <div className="mt-1.5 flex flex-wrap items-center justify-between gap-x-3 gap-y-0.5 text-[11px] text-[var(--fg-3)]">
        <span>Ctrl/⌘ + Enter envia · / abre respostas rápidas · termine com próximo passo e data{porQr ? ' · número por QR: conversa 1 a 1, sem disparo' : ''}</span>
        {emoji && <span className="font-semibold text-[var(--yellow)]" role="status">Playbook: mensagem sem emoji</span>}
      </div>
    </div>
  );
}
