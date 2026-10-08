'use client';

// Caixa de entrada do WhatsApp oficial (substitui a inbox da Clint; backend futuro via Infobip).
// Regras do playbook no ponto onde bloqueiam: só pelo número oficial, lead que não é seu não se toca,
// fora da janela de 24 h só sai template aprovado, mensagem curta pelo nome do lead e sem emoji,
// toda conversa termina com próximo passo.
import { useEffect, useId, useMemo, useRef, useState, type UIEvent } from 'react';
import {
  AvatarInicial, Badge, Button, Card, Drawer, FilterSelect, Row, SearchInput, SectionTitle, Skeleton,
  Spinner, Textarea, Toast, useFlash,
} from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { ROTULO_ATUA, ROTULO_PERFIL, produto as produtoDe } from '../../domain/catalogo';
import { fmtTelefone } from '../../domain/regras';
import type { Contato, Conversa, EtapaFunil, Mensagem, Negocio, SessaoComercial, StatusMensagem, Template } from '../../domain/types';
import { motivoSemEscrita, motivoSomenteLeitura, podeEscrever, podeTrocarDono, somenteLeitura, travaMover, type TravaMover } from '../../domain/travas';
import { bloqueioCanalResposta, janelaDoCanal, opcoesCanalResposta, rotuloProvedor } from '../../domain/nova-conversa';
import { ModalNovaConversa } from './ModalNovaConversa';
import { BotaoPlaybook, Dono, EstadoErro, FaixaErroAtualizacao, FaixaNumeros, PaginaComercial, Segmentado, Vazio, useEquipe, useParamUrl } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { ContatoDrawer } from '../contatos/ContatoDrawer';
import { CardNegocio } from '../funil/CardNegocio';
import { ModalAtividade, NegocioDrawer } from '../NegocioDrawer';
import { avisarMudanca, recarregarSino, repo, useAgora, useAtualizacaoPeriodica, useContatosPorIds, useDados } from '../repositorio';
import { estaNoFim } from '../atualizacao';
import { INFO_CAIXA } from './indicadores';
import { ModalAtribuir } from './ModalAtribuir';
import { ModalExcluirConversa } from './ModalExcluirConversa';
import { Menu } from '../funil/pecas';
import { conversasExcluiveis, mensagensDoCanal, podeExcluirConversa } from '../../domain/excluir-conversa';
import { BotaoAnexar } from './Anexar';
import { BotaoGravarAudio } from './GravarAudio';
import { MidiaMensagem } from './MidiaMensagem';
import { legendaDaMensagem } from '../../domain/midia';
import { bloqueioEnvio, canalDeResposta, rotuloCanal, semJanela, type CanalWhatsapp, type PainelCanais } from '../../domain/canais-whatsapp';
import { MenuRespostas, useAlturaDisponivel } from './pecas';
import {
  chaveDia, criarTravaEnvio, duracaoCurta, esperaResposta, janelaRestante, ordenarConversas, preencherTemplate, primeiroNome,
  resumoCaixa, rotuloDia, temEmoji, type NivelEspera,
} from './regras-conversas';

type Filtro = 'minhas' | 'todas' | 'nao_atribuidas';

/** Frases do playbook para qualificar sem enrolar. */
const RESPOSTAS_RAPIDAS = [
  'O que motivou você a se inscrever?',
  'Você atua como advogado, contador ou em outra área?',
  'Já trabalha com holding ou está começando?',
  'Te ligo amanhã às 10h ou às 15h?',
];

/** Regras do playbook para a conversa (no botão "Playbook" do cabeçalho; cada uma também bloqueia no ponto de ação). */
const REGRAS_PLAYBOOK = [
  'Só se fala pelos números do Comercial (oficial ou conectado por QR), e a resposta sai pelo número em que o lead escreveu.',
  'Lead que não é seu não se toca: transfira pelo gestor.',
  'Fora da janela de 24 h só sai template aprovado.',
  'Mensagem curta, pelo nome do lead, sem emoji.',
  'Toda conversa termina com próximo passo e data.',
];

const COR_ESPERA: Record<NivelEspera, string> = { ok: 'var(--fg-3)', atencao: 'var(--yellow)', critico: 'var(--red)' };

export function ConversasClient() {
  const agora = useAgora();
  const { toast, flash } = useFlash(4000);
  const { sessao, vendedores, nomeDe, gestor, verTudo } = useEquipe();
  const rConversas = useDados(() => repo.conversas());
  const rNegocios = useDados(() => repo.negocios());
  // Só os contatos das conversas (não a base inteira).
  const rContatos = useContatosPorIds(rConversas.dados?.map((c) => c.contatoId));
  const rTemplates = useDados(() => repo.templates());
  // Números de WhatsApp (oficial + QR): filtro, selo e número de resposta.
  const rCanais = useDados(() => repo.canais());
  const painelCanais = rCanais.dados;
  const canais = useMemo(() => painelCanais?.canais ?? [], [painelCanais]);
  const variosNumeros = canais.length > 1;
  const [numero, setNumero] = useState('');
  const { dados: funis } = useDados(() => repo.funis());
  const conversas = rConversas.dados;
  const contatos = rContatos.dados;
  const negocios = rNegocios.dados;
  const templates = rTemplates.dados;
  const erro = rConversas.erro ?? rContatos.erro ?? rNegocios.erro ?? rTemplates.erro;
  const recarregar = () => { rConversas.recarregar(); rContatos.recarregar(); rNegocios.recarregar(); rTemplates.recarregar(); };
  // Lista sozinha: mensagem nova sobe a conversa, muda a prévia/status e o contador de não lidas (sem F5).
  useAtualizacaoPeriodica(rConversas.recarregar, 'listaConversas');

  // Padrão: vendedor vê as dele, gestor vê todas. A escolha vale enquanto a sessão não mudar ("Ver como").
  const [escolha, setEscolha] = useState<{ de: string; f: Filtro } | null>(null);
  const padrao: Filtro = verTudo ? 'todas' : 'minhas';
  const filtro: Filtro = escolha && escolha.de === sessao?.vendedorId ? escolha.f : padrao;
  const trocarFiltro = (f: Filtro) => { if (sessao) setEscolha({ de: sessao.vendedorId, f }); };
  const [busca, setBusca] = useState('');
  const [sel, setSel] = useState<string | null>(null);
  const paramContato = useParamUrl('contato');
  const ativo = sel ?? paramContato;
  // Link "Conversa" (ficha, funil, agenda, Início) para quem ainda não tem conversa: o contato não vem da lista
  // (crm_conversas). Carrega só ele e abre a conversa vazia; a 1ª mensagem cria a crm.conversa no banco.
  const foraDaLista = !!ativo && !!contatos && !contatos.some((c) => c.id === ativo);
  const rAvulso = useDados(async () => (foraDaLista && ativo ? repo.contatosPorIds([ativo]) : null), [foraDaLista ? ativo : null]);
  const [negocioAberto, setNegocioAberto] = useState<string | null>(null);
  const [fichaContato, setFichaContato] = useState<string | null>(null);
  const [detalhes, setDetalhes] = useState(false);
  const [agendar, setAgendar] = useState<Negocio | null>(null);
  const [atribuir, setAtribuir] = useState<Contato | null>(null);
  // Nova conversa: abre o painel da pessoa já com o número escolhido (`n` remonta o painel se for a mesma pessoa).
  const [novaConversa, setNovaConversa] = useState(false);
  const [inicio, setInicio] = useState<{ contatoId: string; canalId: string; n: number } | null>(null);
  const { ref: area, altura } = useAlturaDisponivel<HTMLDivElement>(320);

  // Abrir a conversa marca como lida, mas só para o dono (ou o gestor, em conversa sem dono):
  // quem só espia a conversa de outro não pode sumir com o aviso de não lida do dono.
  // Mensagem que chega com a conversa aberta (pela atualização periódica) também é marcada como lida.
  const cvAtiva = conversas?.find((c) => c.contatoId === ativo);
  const donoAtivo = cvAtiva?.atribuidaA ?? null;
  const temNaoLida = (cvAtiva?.naoLidas ?? 0) > 0;
  const podeMarcarLida = !!ativo && !!sessao && (donoAtivo === sessao.vendedorId || (!donoAtivo && gestor));
  const marcadaPara = useRef<string | null>(null);
  useEffect(() => {
    if (!ativo || !podeMarcarLida) return;
    if (marcadaPara.current === ativo && !temNaoLida) return;
    marcadaPara.current = ativo;
    // Só a lista (contador de não lidas) e o sino mudam: não recarrega a tela inteira.
    const recarregarLista = rConversas.recarregar;
    repo.marcarConversaLida(ativo).then((r) => { if (r.ok) { void recarregarLista(); recarregarSino(); } });
  }, [ativo, podeMarcarLida, temNaoLida, rConversas.recarregar]);

  const contatoPorId = useMemo(
    () => new Map([...(contatos ?? []), ...(rAvulso.dados ?? [])].map((c) => [c.id, c])),
    [contatos, rAvulso.dados],
  );
  const lista = useMemo(() => conversas ?? [], [conversas]);
  const contagem = {
    minhas: lista.filter((c) => c.atribuidaA === sessao?.vendedorId).length,
    todas: lista.length,
    nao_atribuidas: lista.filter((c) => !c.atribuidaA).length,
  };
  // Números da faixa: no escopo do filtro de dono (sem a busca); "Sem dono" é sempre da caixa inteira.
  const resumo = useMemo(() => {
    const doFiltro = lista.filter((cv) => filtro === 'todas' || (filtro === 'minhas' ? cv.atribuidaA === sessao?.vendedorId : !cv.atribuidaA));
    return resumoCaixa(doFiltro, agora);
  }, [lista, filtro, sessao, agora]);
  // Filtra e ordena aqui (não depende da ordem do repositório): quem espera há mais tempo primeiro.
  const visiveis = useMemo(() => {
    const q = busca.trim().toLowerCase();
    const dig = q.replace(/\D/g, '');
    const filtradas = lista.filter((cv) => {
      if (filtro === 'minhas' && cv.atribuidaA !== sessao?.vendedorId) return false;
      if (filtro === 'nao_atribuidas' && cv.atribuidaA) return false;
      if (numero && !(cv.canais ?? []).includes(numero)) return false;
      if (!q) return true;
      const c = contatoPorId.get(cv.contatoId);
      if (`${c?.nome ?? ''} ${c?.email ?? ''} ${cv.ultimaMensagem.texto}`.toLowerCase().includes(q)) return true;
      return dig.length >= 4 && String(c?.telefone ?? '').replace(/\D/g, '').includes(dig);
    });
    return ordenarConversas(filtradas, agora);
  }, [lista, filtro, busca, numero, sessao, contatoPorId, agora]);

  const conversa = lista.find((c) => c.contatoId === ativo) ?? null;
  const contato = ativo ? contatoPorId.get(ativo) ?? null : null;
  // Todos os negócios da pessoa (qualquer status): dono de algum deles pode escrever (crm.pode_escrever_pessoa).
  const negociosDoContato = useMemo(() => (negocios ?? []).filter((n) => n.contatoId === ativo), [negocios, ativo]);
  const negociosAbertos = useMemo(
    () => (negocios ?? []).filter((n) => n.contatoId === ativo && n.status === 'aberto').sort((a, b) => b.criadoEm.localeCompare(a.criadoEm)),
    [negocios, ativo],
  );

  const fecharConversa = () => {
    setSel(null);
    setDetalhes(false);
    if (paramContato) window.history.replaceState(null, '', window.location.pathname + window.location.hash);
  };

  const carregando = !conversas || !contatos || !negocios || !templates || !sessao;
  // Contato do link ainda chegando (fora da lista): mostra carregando no painel, não "não encontrado".
  const buscandoAvulso = foraDaLista && !contato && (rAvulso.carregando || (!rAvulso.dados && !rAvulso.erro));
  const alturaEstilo = altura ? { height: altura } : undefined;

  const painelContato = contato && (
    <PainelContato
      c={contato}
      negocios={negociosAbertos}
      agora={agora}
      nomeDe={nomeDe}
      etapasDe={(n) => funis?.find((f) => f.id === n.funilId)?.etapas ?? []}
      leituraDe={(n) => motivoSomenteLeitura(n, sessao, nomeDe)}
      travaPara={(n, etapaId) => {
        const f = funis?.find((x) => x.id === n.funilId);
        return f ? travaMover(n, f, etapaId, sessao, nomeDe) : { permitido: false, motivo: 'Funil do negócio não encontrado.', faltam: [] };
      }}
      onAbrirNegocio={setNegocioAberto}
      onAgendar={setAgendar}
      onMover={async (n, etapaId) => {
        const r = await repo.moverEtapa(n.id, etapaId);
        flash(r.ok ? r.msg ?? 'Negócio movido.' : r.msg ?? 'Não foi possível mover.');
        if (r.ok) avisarMudanca();
      }}
      onCopiarTelefone={async (tel) => {
        try { await navigator.clipboard.writeText(tel); flash('Telefone copiado.'); } catch { flash('Não foi possível copiar.'); }
      }}
      onAbrirFicha={() => setFichaContato(contato.id)}
    />
  );

  return (
    <PaginaComercial
      titulo="Conversas"
      subtitulo="Caixa do WhatsApp (oficial e números por QR). Responda primeiro quem espera há mais tempo."
      acoes={<>
        {podeEscrever(sessao) && !carregando && (
          <Button size="sm" onClick={() => setNovaConversa(true)} aria-label="Nova conversa" title="Nova conversa">
            <Icon name="plus" size={14} /><span className="hidden sm:inline">Nova conversa</span>
          </Button>
        )}
        <BotaoPlaybook regras={REGRAS_PLAYBOOK} />
      </>}
      meta={!carregando && (
        // No celular, com conversa aberta, a faixa sai: a altura fica para as mensagens.
        <div className={ativo ? 'hidden lg:block' : undefined}>
        <FaixaNumeros
          rotulo="Caixa agora"
          itens={[
            { rotulo: 'Sem resposta', valor: resumo.esperando, info: INFO_CAIXA.esperando },
            { rotulo: 'Além do prazo', valor: resumo.criticas, alerta: resumo.criticas > 0, info: INFO_CAIXA.criticas },
            { rotulo: 'Não lidas', valor: resumo.naoLidas, info: INFO_CAIXA.naoLidas },
            {
              rotulo: 'Sem dono', valor: contagem.nao_atribuidas, alerta: contagem.nao_atribuidas > 0, info: INFO_CAIXA.semDono,
              ativo: filtro === 'nao_atribuidas', onClick: () => trocarFiltro(filtro === 'nao_atribuidas' ? padrao : 'nao_atribuidas'),
            },
          ]}
        />
        </div>
      )}
    >
      {erro && !carregando && <FaixaErroAtualizacao className="mb-2" mensagem={erro} onTentar={recarregar} />}
      <div ref={area} style={alturaEstilo} className="min-h-[320px]">
        {erro && carregando ? (
          <Card className="h-full grid place-items-center">
            <EstadoErro mensagem={erro} onTentar={recarregar} />
          </Card>
        ) : carregando ? (
          <EsqueletoCaixa />
        ) : (
          <div className="h-full grid grid-rows-[minmax(0,1fr)] gap-3 lg:grid-cols-[300px_minmax(0,1fr)] 2xl:grid-cols-[300px_minmax(0,1fr)_300px]">
            {/* Lista */}
            <Card className={`h-full min-h-0 flex-col min-w-0 overflow-hidden ${ativo ? 'hidden lg:flex' : 'flex'}`}>
              <div className="shrink-0 p-3 border-b border-[var(--border)] space-y-2">
                <Segmentado<Filtro>
                  className="w-full [&>button]:flex-1 [&>button]:justify-center"
                  rotulo="Filtro de conversas"
                  valor={filtro}
                  onChange={trocarFiltro}
                  opcoes={[
                    { valor: 'minhas', rotulo: 'Minhas', n: contagem.minhas },
                    { valor: 'todas', rotulo: 'Todas', n: contagem.todas },
                    { valor: 'nao_atribuidas', rotulo: 'Sem dono', n: contagem.nao_atribuidas, title: 'Não atribuídas' },
                  ]}
                />
                {variosNumeros && (
                  <FilterSelect value={numero} onChange={(e) => setNumero(e.target.value)} aria-label="Filtrar por número" className="w-full">
                    <option value="">Todos os números</option>
                    {canais.map((c) => <option key={c.id} value={c.id}>{rotuloCanal(c)}</option>)}
                  </FilterSelect>
                )}
                <SearchInput placeholder="Buscar nome, telefone ou texto" value={busca} onChange={(e) => setBusca(e.target.value)} onLimpar={() => setBusca('')} />
              </div>
              <ul className="flex-1 min-h-0 overflow-y-auto overscroll-contain" aria-label="Conversas">
                {visiveis.length === 0 && (
                  <li className="px-3">
                    <Vazio
                      titulo="Nenhuma conversa"
                      hint={busca.trim() ? 'Nada encontrado para essa busca.' : filtro === 'minhas' ? 'Nenhuma conversa sua agora.' : 'Nenhuma conversa neste filtro.'}
                      icone="message"
                      acao={busca.trim() ? (
                        <Button size="sm" variant="ghost" onClick={() => setBusca('')}>Limpar busca</Button>
                      ) : filtro !== 'todas' && contagem.todas > 0 ? (
                        <Button size="sm" variant="ghost" onClick={() => trocarFiltro('todas')}>Ver todas</Button>
                      ) : undefined}
                    />
                  </li>
                )}
                {visiveis.map((cv) => (
                  <ItemConversa
                    key={cv.contatoId}
                    cv={cv}
                    c={contatoPorId.get(cv.contatoId)}
                    agora={agora}
                    ativa={cv.contatoId === ativo}
                    donoNome={filtro !== 'minhas' && cv.atribuidaA ? nomeDe(cv.atribuidaA) : null}
                    semDono={!cv.atribuidaA}
                    selo={variosNumeros ? rotuloCanal(canais.find((c) => c.id === cv.canalId)) : null}
                    onClick={() => setSel(cv.contatoId)}
                  />
                ))}
              </ul>
            </Card>

            {/* Conversa */}
            <div className={`h-full min-h-0 min-w-0 ${ativo ? '' : 'hidden lg:block'}`}>
              {ativo && contato ? (
                <PainelConversa
                  key={inicio?.contatoId === ativo ? `${ativo}:${inicio.n}` : ativo}
                  canalInicial={inicio?.contatoId === ativo ? inicio.canalId : null}
                  contato={contato}
                  conversa={conversa}
                  negocio={negociosAbertos[0] ?? null}
                  negociosDoContato={negociosDoContato}
                  templates={templates}
                  canais={canais}
                  painelCanais={painelCanais ?? null}
                  sessao={sessao}
                  gestor={gestor}
                  nomeDe={nomeDe}
                  agora={agora}
                  flash={flash}
                  onAtribuir={() => setAtribuir(contato)}
                  onExcluida={(msg) => { flash(msg); fecharConversa(); void rConversas.recarregar(); recarregarSino(); }}
                  onVoltar={fecharConversa}
                  onAbrirNegocio={setNegocioAberto}
                  onAgendar={setAgendar}
                  onDetalhes={() => setDetalhes(true)}
                />
              ) : buscandoAvulso ? (
                <Card className="h-full grid place-items-center text-[var(--fg-3)]">
                  <span className="inline-flex items-center gap-3 text-sm"><Spinner size={20} /> Abrindo conversa…</span>
                </Card>
              ) : ativo && rAvulso.erro ? (
                <Card className="h-full grid place-items-center">
                  <EstadoErro mensagem={rAvulso.erro} onTentar={rAvulso.recarregar} />
                </Card>
              ) : (
                <Card className="h-full grid place-items-center">
                  <Vazio
                    titulo={ativo ? 'Contato não encontrado' : 'Escolha uma conversa'}
                    hint={ativo ? 'Esse contato não está mais na base ou o link está errado.' : 'A lista já vem na ordem certa: quem espera há mais tempo fica no topo.'}
                    icone="message"
                    acao={ativo ? <Button size="sm" variant="ghost" onClick={fecharConversa}>Voltar para a lista</Button> : undefined}
                  />
                </Card>
              )}
            </div>

            {/* Painel do contato: coluna própria só em telas largas; abaixo disso, botão "Detalhes" */}
            {ativo && contato && (
              <Card className="hidden 2xl:block h-full min-h-0 min-w-0 overflow-y-auto overscroll-contain p-4">{painelContato}</Card>
            )}
          </div>
        )}
      </div>

      {detalhes && contato && !negocioAberto && !fichaContato && (
        <Drawer
          onClose={() => setDetalhes(false)}
          title={contato.nome}
          subtitle={`${fmtTelefone(contato.telefone)} · ${nomeDe(conversa?.atribuidaA ?? contato.donoId)}`}
          avatar={<AvatarInicial nome={contato.nome} size={40} />}
          width="max-w-md"
        >
          {painelContato}
        </Drawer>
      )}
      {agendar && (
        <ModalAtividade
          onClose={() => setAgendar(null)}
          onConfirmar={async (tipo, titulo, venceEm) => {
            const r = await repo.criarAtividade({ negocioId: agendar.id, contatoId: agendar.contatoId, tipo, titulo, venceEm });
            if (!r.ok) { flash(r.msg ?? 'Não foi possível agendar.'); return; }
            flash(r.msg ?? 'Próximo passo agendado.');
            setAgendar(null);
            avisarMudanca();
          }}
        />
      )}
      {atribuir && (
        <ModalAtribuir
          contatoId={atribuir.id}
          nome={atribuir.nome}
          vendedores={vendedores}
          onClose={() => setAtribuir(null)}
          onFeito={(msg) => { setAtribuir(null); flash(msg); }}
        />
      )}
      {novaConversa && sessao && (
        <ModalNovaConversa
          canais={canais}
          painel={painelCanais ?? null}
          sessao={sessao}
          conversas={lista}
          nomeDe={nomeDe}
          agora={agora}
          onClose={() => setNovaConversa(false)}
          onComecar={(contatoId, canalId) => {
            setNovaConversa(false);
            setInicio({ contatoId, canalId, n: Date.now() });
            setSel(contatoId);
            setDetalhes(false);
          }}
        />
      )}
      {negocioAberto && <NegocioDrawer negocioId={negocioAberto} onClose={() => setNegocioAberto(null)} />}
      {fichaContato && !negocioAberto && (
        <ContatoDrawer key={fichaContato} contatoId={fichaContato} onClose={() => setFichaContato(null)} onAbrirContato={setFichaContato} />
      )}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

/** Carregando no formato da caixa: lista à esquerda, conversa ao lado. */
function EsqueletoCaixa() {
  return (
    <div className="h-full grid grid-rows-[minmax(0,1fr)] gap-3 lg:grid-cols-[300px_minmax(0,1fr)] 2xl:grid-cols-[300px_minmax(0,1fr)_300px]" aria-busy="true">
      <Card className="h-full overflow-hidden">
        <div className="p-3 border-b border-[var(--border)] space-y-2">
          <Skeleton h={30} />
          <Skeleton h={34} />
        </div>
        {Array.from({ length: 7 }).map((_, i) => (
          <div key={i} className="flex gap-3 px-3 py-3 border-b border-[var(--border-faint)]">
            <span className="gp-skeleton w-9 h-9 rounded-full shrink-0" />
            <div className="flex-1 space-y-2 pt-0.5">
              <Skeleton w="60%" h={12} />
              <Skeleton w="85%" h={10} />
            </div>
          </div>
        ))}
      </Card>
      <Card className="hidden lg:grid h-full place-items-center text-[var(--fg-3)]">
        <span className="inline-flex items-center gap-3 text-sm"><Spinner size={20} /> Carregando conversas…</span>
      </Card>
      <Card className="hidden 2xl:block h-full p-4 space-y-3">
        <Skeleton w="40%" h={10} />
        {Array.from({ length: 5 }).map((_, i) => <Skeleton key={i} h={14} />)}
      </Card>
    </div>
  );
}

// ── Lista ──

function ItemConversa({ cv, c, agora, ativa, donoNome, semDono, selo, onClick }: {
  cv: Conversa; c: Contato | undefined; agora: Date; ativa: boolean; donoNome: string | null; semDono: boolean; selo: string | null; onClick: () => void;
}) {
  const m = cv.ultimaMensagem;
  const espera = esperaResposta(m, agora);
  const desde = Math.max(0, Math.floor((agora.getTime() - new Date(m.em).getTime()) / 60000));
  return (
    <li>
      <button
        type="button"
        onClick={onClick}
        aria-current={ativa ? 'true' : undefined}
        className={`w-full text-left px-3 py-3 border-b border-[var(--border-faint)] flex gap-3 transition-colors ${ativa ? 'bg-[var(--accent-subtle)]' : 'hover:bg-[var(--surface-3)]'}`}
      >
        <AvatarInicial nome={c?.nome ?? '?'} size={36} />
        <span className="min-w-0 flex-1">
          <span className="flex items-baseline justify-between gap-2">
            <span className={`text-sm truncate text-[var(--fg)] ${cv.naoLidas ? 'font-semibold' : 'font-medium'}`}>{c?.nome ?? fmtTelefone(null)}</span>
            {/* Um único sinal de urgência: o tempo esperando, em texto (a cor só reforça). */}
            {espera ? (
              <span
                className={`text-[11px] tabular shrink-0 ${espera.nivel === 'ok' ? '' : 'font-semibold'}`}
                style={{ color: COR_ESPERA[espera.nivel] }}
                title={`Esperando resposta desde ${fmtDataHora(m.em)}${espera.nivel === 'critico' ? ' · prazo crítico' : espera.nivel === 'atencao' ? ' · prazo de atenção' : ''}`}
              >
                esperando {duracaoCurta(espera.minutos)}
              </span>
            ) : (
              <span className="text-[11px] tabular text-[var(--fg-3)] shrink-0" title={fmtDataHora(m.em)}>{desde < 1 ? 'agora' : duracaoCurta(desde)}</span>
            )}
          </span>
          <span className="flex items-center justify-between gap-2 mt-0.5">
            <span className={`text-xs truncate ${cv.naoLidas ? 'text-[var(--fg-2)]' : 'text-[var(--fg-3)]'}`}>
              {m.direcao === 'saida' ? (m.externa ? 'Celular: ' : 'Você: ') : ''}{m.texto}
            </span>
            <span className="flex items-center gap-1.5 shrink-0 text-[var(--fg-3)]">
              {selo && (
                <span title={`Número: ${selo}`} className="text-[10px] max-w-[84px] truncate rounded-[var(--r-pill)] border border-[var(--border)] px-1.5 leading-4">{selo}</span>
              )}
              {donoNome && <span className="text-[11px] max-w-[72px] truncate">{primeiroNome(donoNome)}</span>}
              {semDono && (
                <span title="Sem dono: o gestor atribui antes de qualquer conversa" className="inline-flex">
                  <Icon name="user-x" size={12} /><span className="sr-only">Sem dono</span>
                </span>
              )}
              {c?.optOut && (
                <span title="Não quer contato" className="inline-flex">
                  <Icon name="lock" size={12} /><span className="sr-only">Não quer contato</span>
                </span>
              )}
              {cv.naoLidas > 0 && (
                <span className="min-w-[18px] h-[18px] px-1 grid place-items-center rounded-[var(--r-pill)] bg-[var(--surface-4)] text-[var(--fg)] text-[11px] font-semibold tabular">
                  {cv.naoLidas}<span className="sr-only"> não lidas</span>
                </span>
              )}
            </span>
          </span>
        </span>
      </button>
    </li>
  );
}

// ── Conversa ──

function PainelConversa({ canalInicial, contato, conversa, negocio, negociosDoContato, templates, canais, painelCanais, sessao, gestor, nomeDe, agora, flash, onVoltar, onAbrirNegocio, onAgendar, onDetalhes, onAtribuir, onExcluida }: {
  /** Número escolhido na "Nova conversa" (a 1ª mensagem cria a conversa nele). */
  canalInicial?: string | null;
  contato: Contato; conversa: Conversa | null; negocio: Negocio | null; negociosDoContato: Negocio[]; templates: Template[];
  canais: CanalWhatsapp[]; painelCanais: PainelCanais | null; sessao: SessaoComercial;
  gestor: boolean; nomeDe: (id: string | null) => string; agora: Date; flash: (m: string) => void; onVoltar: () => void;
  onAbrirNegocio: (id: string) => void; onAgendar: (n: Negocio) => void; onDetalhes: () => void; onAtribuir: () => void;
  /** Gestor excluiu a conversa: avisa, fecha o painel e recarrega a lista. */
  onExcluida: (msg: string) => void;
}) {
  const { dados, erro, carregando: carregandoMsgs, recarregar } = useDados(() => repo.mensagens(contato.id), [contato.id]);
  // Conversa aberta sozinha: mensagem nova, mídia que sai de "pendente" e status (enviada → entregue → lida).
  useAtualizacaoPeriodica(recarregar, 'conversaAberta');
  const mensagens = useMemo(() => (dados ?? []).filter((m) => m.contatoId === contato.id && m.canal === 'whatsapp'), [dados, contato.id]);
  // Rola SÓ a coluna de mensagens (scrollIntoView rolava a página inteira junto e sumia com o topo e o compositor).
  // Ao abrir e quando chega mensagem: vai ao fim só se o vendedor já estava perto do fim; senão, botão "novas mensagens".
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
  // Seletor: oficial + todo número que esta pessoa pode usar (QR conectado, regra de dono) + os já usados na conversa.
  const opcoesCanal = opcoesCanalResposta(canais, conversa?.canais ?? (conversa?.canalId ? [conversa.canalId] : []), painelCanais, sessao, canalEscolhido);
  // Janela de 24 h DO NÚMERO da resposta: quem só falou pelo QR tem a do oficial fechada.
  const janela = janelaRestante(janelaDoCanal(conversa, canal?.id), agora);
  const porQr = semJanela(canal);
  const variosNaConversa = new Set(mensagens.map((m) => m.canalId).filter(Boolean)).size > 1;
  const nomeCanal = (id: string | null | undefined) => rotuloCanal(canais.find((c) => c.id === id));
  const podeAgendar = !!negocio && (gestor || negocio.donoId === sessao.vendedorId);
  // Conversa sem dono: só o gestor define quem atende (playbook: ninguém responde lead sem dono).
  const podeAtribuir = podeTrocarDono(sessao) && !dono;
  // Excluir conversa (ex.: teste): só o gestor de verdade; o banco confere de novo (crm_excluir_conversa).
  const excluiveis = podeExcluirConversa(sessao) ? conversasExcluiveis(conversa) : [];
  const [excluir, setExcluir] = useState(false);

  // Quem pode escrever: espelho de crm.pode_escrever_pessoa (dono do contato, dono de algum negócio da pessoa ou gestor).
  const bloqueio: string | null = somenteLeitura(sessao)
    ? 'Você acompanha a conversa, mas não responde (acesso só de leitura).'
    : contato.optOut
    ? 'Este contato pediu para não receber contato. Nenhuma mensagem sai para ele.'
    : !contato.telefone
      ? 'Contato sem telefone.'
      : motivoSemEscrita({ donoId: dono }, negociosDoContato, sessao, nomeDe);
  // O número escolhido não envia (QR desconectado, de outra pessoa…): troca no seletor acima, não é "somente leitura".
  const bloqueioNumero = bloqueio ? null : bloqueioEnvio(canal, painelCanais) ?? bloqueioCanalResposta(canal, painelCanais, sessao);

  // Agrupa por dia para o separador.
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

  return (
    <Card className="h-full flex flex-col overflow-hidden">
      <div className="shrink-0 flex flex-wrap items-center gap-x-3 gap-y-2 px-3 py-2 border-b border-[var(--border)]">
        <button type="button" onClick={onVoltar} aria-label="Voltar para a lista" className="lg:hidden -ml-1 w-8 h-8 grid place-items-center rounded-[var(--r-md)] text-[var(--fg-2)] hover:bg-[var(--surface-3)]">
          <Icon name="arrow-left" size={16} />
        </button>
        <AvatarInicial nome={contato.nome} size={32} />
        <div className="min-w-[120px] flex-1">
          <h2 className="text-sm font-semibold text-[var(--fg)] truncate">{contato.nome}</h2>
          <div className="text-xs text-[var(--fg-3)] truncate">{fmtTelefone(contato.telefone)} · {dono ? nomeDe(dono) : 'sem dono'}</div>
        </div>
        <div className="flex flex-wrap items-center justify-end gap-2 ml-auto">
          {opcoesCanal.length > 1 ? (
            <FilterSelect value={canal?.id ?? ''} onChange={(e) => setCanalEscolhido(e.target.value || null)} aria-label="Responder pelo número" title="Responder pelo número">
              {opcoesCanal.map((c) => <option key={c.id} value={c.id}>{rotuloCanal(c)} ({rotuloProvedor(c)})</option>)}
            </FilterSelect>
          ) : canal && canais.length > 1 ? (
            <span title="Número desta conversa: a resposta sai por ele"><Badge>{rotuloCanal(canal)}</Badge></span>
          ) : null}
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
          {podeAgendar && (
            <Button size="sm" variant="ghost" onClick={() => onAgendar(negocio)} aria-label="Agendar próximo passo" title="Agendar próximo passo">
              <Icon name="calendar" size={14} /><span className="hidden md:inline">Próximo passo</span>
            </Button>
          )}
          {negocio && (
            <Button size="sm" variant="ghost" onClick={() => onAbrirNegocio(negocio.id)} aria-label="Abrir negócio" title="Abrir negócio">
              <Icon name="briefcase" size={14} /><span className="hidden md:inline">Negócio</span>
            </Button>
          )}
          <button
            type="button"
            onClick={onDetalhes}
            aria-label="Detalhes do contato"
            title="Detalhes do contato"
            className="2xl:hidden w-8 h-8 grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
          >
            <Icon name="panel-open" size={15} className="scale-x-[-1]" />
          </button>
          {excluiveis.length > 0 && (
            <Menu
              rotulo="Mais ações da conversa"
              itens={[{ rotulo: 'Excluir conversa', icone: 'trash', titulo: 'Some do CRM para todos (não apaga no WhatsApp do cliente)', onEscolher: () => setExcluir(true) }]}
              classeGatilho="w-8 h-8 grid place-items-center rounded-[var(--r-md)] border border-[var(--border)] text-[var(--fg-2)] hover:text-[var(--fg)] hover:bg-[var(--surface-3)]"
              gatilho={<span aria-hidden className="text-base leading-none">⋯</span>}
            />
          )}
        </div>
      </div>
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
            {/* Separador do dia fica preso no topo enquanto rola as mensagens daquele dia. */}
            <div className="sticky top-0 z-[1] flex justify-center py-2 pointer-events-none">
              <span className="rounded-[var(--r-pill)] border border-[var(--border)] bg-[var(--surface-2)] px-2.5 py-0.5 text-[11px] text-[var(--fg-3)] shadow-[var(--highlight-surface)]">
                {rotuloDia(g.itens[0].em, agora)}
              </span>
            </div>
            <div className="space-y-2">
              {g.itens.map((m) => (
                <Bolha key={m.id} m={m} nomeTemplate={nomeTemplate} autor={m.autorId ? nomeDe(m.autorId) : m.externa ? 'Celular/Clint' : null}
                       numero={variosNaConversa ? nomeCanal(m.canalId) : null} />
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
        />
      )}
    </Card>
  );
}

const ROTULO_STATUS: Record<StatusMensagem, string> = { enviada: 'Enviada', entregue: 'Entregue', lida: 'Lida', falhou: 'Falhou' };

function StatusEnvio({ s, envio, erro }: { s: StatusMensagem | null; envio?: Mensagem['envio']; erro?: string | null }) {
  // Saída ainda não aceita pelo provedor: o banco devolve status null + envio.
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

function Bolha({ m, nomeTemplate, autor, numero }: { m: Mensagem; nomeTemplate: (id: string | null) => string | null; autor: string | null; numero: string | null }) {
  const saida = m.direcao === 'saida';
  const hora = new Date(m.em).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
  const legenda = legendaDaMensagem(m);
  return (
    <div className={`flex ${saida ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`min-w-0 max-w-[85%] sm:max-w-[68%] px-3 py-2 text-sm text-[var(--fg)] border ${
          saida ? 'rounded-[var(--r-lg)] rounded-br-[var(--r-sm)]' : 'rounded-[var(--r-lg)] rounded-bl-[var(--r-sm)]'
        } ${
          m.status === 'falhou' ? 'border-[var(--red-border)] bg-[var(--red-subtle)]'
            : saida ? 'border-[var(--border-strong)] bg-[var(--surface-4)]' : 'border-[var(--border)] bg-[var(--surface-2)]'
        }`}
      >
        {m.templateId && (
          <div className="mb-1 inline-flex items-center gap-1 text-[11px] text-[var(--fg-3)]">
            <Icon name="file" size={12} /> Template · {nomeTemplate(m.templateId)}
          </div>
        )}
        <MidiaMensagem m={m} />
        {legenda && <div className="whitespace-pre-wrap break-words leading-relaxed">{legenda}</div>}
        <div className="mt-1 flex items-center justify-end gap-1.5 text-[11px] text-[var(--fg-3)] tabular">
          {numero && <span className="truncate" title="Número da mensagem">{numero} ·</span>}
          {saida && autor && <span className="truncate">{primeiroNome(autor)}</span>}
          <span>{hora}</span>
          {saida && <StatusEnvio s={m.status} envio={m.envio} erro={m.erro} />}
        </div>
      </div>
    </div>
  );
}

// ── Envio ──

function Envio({ contato, negocio, canalId, porQr, janelaAberta, templates, remetente, flash }: {
  contato: Contato; negocio: Negocio | null; canalId: string | null; porQr: boolean; janelaAberta: boolean; templates: Template[]; remetente: string; flash: (m: string) => void;
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
    ? preencherTemplate(tpl.texto, {
      nome,
      vendedor: primeiroNome(remetente),
      produto: prodNome,
      evento: contato.tags[0] ?? prodNome,
    })
    : null;

  const enviar = async (corpo: string, tId: string | null) => {
    if (!corpo.trim()) return;
    const chave = trava.current.comecar(`${tId ?? ''}|${corpo}`);
    if (!chave) return;
    setEnviando(true);
    let r: Awaited<ReturnType<typeof repo.enviarMensagem>>;
    try { r = await repo.enviarMensagem(contato.id, corpo, tId, chave, canalId); } catch { r = { ok: false, msg: 'Não foi possível enviar.' }; }
    trava.current.terminar(r.ok);
    setEnviando(false);
    if (!r.ok) { flash(r.msg ?? 'Não foi possível enviar.'); return; }
    if (!tId) setTexto('');
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
      <div className="relative flex flex-wrap sm:flex-nowrap items-end justify-end gap-2">
        {menu && <MenuRespostas id={idMenu} frases={RESPOSTAS_RAPIDAS} ancora={botaoMenu} onEscolher={inserir} onFechar={fecharMenu} />}
        <Textarea
          ref={campo}
          rows={2}
          value={texto}
          onChange={(e) => setTexto(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); enviar(texto, null); return; }
            // "/" com o campo vazio abre as respostas rápidas (como nos apps de atendimento).
            if (e.key === '/' && !texto.trim()) { e.preventDefault(); setMenu(true); }
          }}
          placeholder={`Mensagem para ${nome || 'o lead'} (sem emoji)`}
          aria-label="Mensagem"
          className="!resize-none basis-full sm:basis-0 sm:flex-1"
        />
        <BotaoAnexar contatoId={contato.id} nomeContato={nome || contato.nome} desabilitado={enviando} flash={flash} canalId={canalId} />
        <BotaoGravarAudio contatoId={contato.id} nomeContato={nome || contato.nome} desabilitado={enviando} flash={flash} canalId={canalId} />
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

// ── Painel do contato ──

function PainelContato({ c, negocios, agora, nomeDe, etapasDe, leituraDe, travaPara, onAbrirNegocio, onAgendar, onMover, onCopiarTelefone, onAbrirFicha }: {
  c: Contato; negocios: Negocio[]; agora: Date; nomeDe: (id: string | null) => string;
  etapasDe: (n: Negocio) => EtapaFunil[];
  leituraDe: (n: Negocio) => string | null;
  travaPara: (n: Negocio, etapaId: string) => TravaMover;
  onAbrirNegocio: (id: string) => void; onAgendar: (n: Negocio) => void; onMover: (n: Negocio, etapaId: string) => void;
  onCopiarTelefone: (tel: string) => void; onAbrirFicha: () => void;
}) {
  return (
    <div className="space-y-6">
      <section>
        <SectionTitle right={<Button size="sm" variant="link" onClick={onAbrirFicha}>Ver ficha</Button>}>Contato</SectionTitle>
        <div>
          <Row k="Telefone" v={fmtTelefone(c.telefone)} />
          <Row k="E-mail" v={c.email ?? '—'} />
          <Row k="Cidade" v={c.cidade ? `${c.cidade}/${c.uf ?? ''}` : '—'} />
          <Row k="Perfil" v={c.perfil ? ROTULO_PERFIL[c.perfil] : '—'} />
          <Row k="Holding" v={c.atuaComHolding ? ROTULO_ATUA[c.atuaComHolding] : '—'} />
          <Row k="Dono" v={<Dono id={c.donoId} nomeDe={nomeDe} />} />
        </div>
        {c.tags.length > 0 && (
          <p className="mt-2 text-xs text-[var(--fg-3)]">
            <span className="sr-only">Tags: </span>{c.tags.join(' · ')}
          </p>
        )}
      </section>

      <section>
        <SectionTitle>{negocios.length > 1 ? `Negócios abertos (${negocios.length})` : 'Negócio aberto'}</SectionTitle>
        {negocios.length === 0 ? (
          <div className="text-xs text-[var(--fg-3)] leading-relaxed">
            Nenhum negócio aberto. Se não está no CRM, não existe.
            <Button size="sm" variant="link" className="ml-1 !text-xs" onClick={onAbrirFicha}>Abrir pela ficha</Button>
          </div>
        ) : (
          <div className="space-y-2">
            {negocios.map((n) => (
              <div key={n.id}>
                <CardNegocio
                  n={n}
                  c={c}
                  agora={agora}
                  nomeDe={nomeDe}
                  etapas={etapasDe(n)}
                  leitura={leituraDe(n)}
                  travaPara={(etapaId) => travaPara(n, etapaId)}
                  onAbrir={() => onAbrirNegocio(n.id)}
                  onAgendar={() => onAgendar(n)}
                  onMover={(etapaId) => onMover(n, etapaId)}
                  onCopiarTelefone={onCopiarTelefone}
                  arrastavel={false}
                />
                <div className="mt-1 flex items-center justify-between gap-2 text-[11px] text-[var(--fg-3)]">
                  <span className="truncate">{n.etapaNome}</span>
                  <Button size="sm" variant="link" className="!text-xs" onClick={() => onAbrirNegocio(n.id)}>Abrir</Button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>
    </div>
  );
}
