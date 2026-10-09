'use client';

// Caixa de entrada do WhatsApp oficial (substitui a inbox da Clint; backend futuro via Infobip).
// Regras do playbook no ponto onde bloqueiam: só pelo número oficial, lead que não é seu não se toca,
// fora da janela de 24 h só sai template aprovado, mensagem curta pelo nome do lead e sem emoji,
// toda conversa termina com próximo passo.
import { useEffect, useMemo, useRef, useState } from 'react';
import { AvatarInicial, Badge, Button, Card, Drawer, FilterSelect, SearchInput, Skeleton, Spinner, Toast, useFlash } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import { fmtTelefone } from '../../domain/regras';
import type { Contato, Conversa, Negocio } from '../../domain/types';
import { motivoSomenteLeitura, podeEscrever, podeEscreverContato, travaMover } from '../../domain/travas';
import { ModalNovaConversa } from './ModalNovaConversa';
import { BotaoPlaybook, EstadoErro, FaixaErroAtualizacao, FaixaNumeros, PaginaComercial, Segmentado, Vazio, useEquipe, useParamUrl } from '../comum';
import { ContatoDrawer } from '../contatos/ContatoDrawer';
import { ModalAtividade, NegocioDrawer } from '../NegocioDrawer';
import { avisarMudanca, recarregarSino, repo, useAgora, useAtualizacaoPeriodica, useContatosPorIds, useDados } from '../repositorio';
import { INFO_CAIXA } from './indicadores';
import { ModalAtribuir } from './ModalAtribuir';
import { canalDeResposta, rotuloCanal } from '../../domain/canais-whatsapp';
import { bloqueioCanalResposta, janelaDoCanal } from '../../domain/nova-conversa';
import { contaNaFila, contarPorAtendimento, estadoAtendimento, ROTULO_ATENDIMENTO, ROTULO_FILTRO_ATENDIMENTO, type FiltroAtendimento } from '../../domain/atendimento';
import { useAlturaDisponivel } from './pecas';
import { PainelConversa } from './PainelConversa';
import { PainelContato, type AcaoRapida } from './PainelContato';
import { ModalAgendarMensagem, ModalNota } from './acoes-ui';
import { duracaoCurta, esperaResposta, ordenarConversas, primeiroNome, resumoCaixa, type NivelEspera } from './regras-conversas';

type Filtro = 'minhas' | 'todas' | 'nao_atribuidas';

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
  // Status do atendimento (20261009153515): a lista abre nas abertas; em espera e encerradas ficam em filtros próprios.
  const [atend, setAtend] = useState<FiltroAtendimento>('aberto');
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
  // Ações rápidas do painel do contato (atividade, lembrete, nota, agendar mensagem).
  const [acao, setAcao] = useState<AcaoRapida | null>(null);
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
  // Em espera e encerradas não contam como "sem resposta" nem "além do prazo" (resumoCaixa).
  const doDono = useMemo(
    () => lista.filter((cv) => filtro === 'todas' || (filtro === 'minhas' ? cv.atribuidaA === sessao?.vendedorId : !cv.atribuidaA)),
    [lista, filtro, sessao],
  );
  const resumo = useMemo(() => resumoCaixa(doDono, agora), [doDono, agora]);
  const porAtendimento = useMemo(() => contarPorAtendimento(doDono), [doDono]);
  // Filtra e ordena aqui (não depende da ordem do repositório): quem espera há mais tempo primeiro.
  const visiveis = useMemo(() => {
    const q = busca.trim().toLowerCase();
    const dig = q.replace(/\D/g, '');
    const filtradas = lista.filter((cv) => {
      if (filtro === 'minhas' && cv.atribuidaA !== sessao?.vendedorId) return false;
      if (filtro === 'nao_atribuidas' && cv.atribuidaA) return false;
      if (numero && !(cv.canais ?? []).includes(numero)) return false;
      if (estadoAtendimento(cv) !== atend && cv.contatoId !== ativo) return false;
      if (!q) return true;
      const c = contatoPorId.get(cv.contatoId);
      if (`${c?.nome ?? ''} ${c?.email ?? ''} ${cv.ultimaMensagem.texto}`.toLowerCase().includes(q)) return true;
      return dig.length >= 4 && String(c?.telefone ?? '').replace(/\D/g, '').includes(dig);
    });
    return ordenarConversas(filtradas, agora);
  }, [lista, filtro, busca, numero, sessao, contatoPorId, agora, atend, ativo]);

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

  const donoAtual = conversa?.atribuidaA ?? contato?.donoId ?? null;
  const escreve = !!contato && podeEscreverContato({ donoId: donoAtual }, negociosDoContato, sessao);
  // Agendar mensagem: quem escreve, contato com telefone e sem opt-out, número da resposta disponível.
  const canalResposta = canalDeResposta(null, conversa?.canalId ?? null, canais);
  const podeMensagem = escreve && !!contato?.telefone && !contato?.optOut && !!canalResposta
    && !bloqueioCanalResposta(canalResposta, painelCanais ?? null, sessao);
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
      podeEscrever={escreve}
      podeMensagem={podeMensagem}
      onAcao={(a) => { setDetalhes(false); setAcao(a); }}
      flash={flash}
    />
  );
  // Atividade/lembrete pelo painel: no negócio aberto mais recente (ou só na pessoa, sem negócio).
  const criarAtividade = async (tipo: Parameters<typeof repo.criarAtividade>[0]['tipo'], titulo: string, venceEm: string) => {
    if (!contato) return;
    const n = negociosAbertos.find((x) => gestor || x.donoId === sessao?.vendedorId) ?? null;
    const r = await repo.criarAtividade({ negocioId: n?.id ?? null, contatoId: contato.id, tipo, titulo, venceEm });
    flash(r.ok ? r.msg ?? (acao === 'lembrete' ? 'Lembrete criado.' : 'Atividade agendada.') : r.msg ?? 'Não foi possível agendar.');
    if (r.ok) { setAcao(null); avisarMudanca(); }
  };

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
                <Segmentado<FiltroAtendimento>
                  className="w-full [&>button]:flex-1 [&>button]:justify-center"
                  rotulo="Status do atendimento"
                  valor={atend}
                  onChange={setAtend}
                  opcoes={(['aberto', 'espera', 'encerrado'] as const).map((e) => ({ valor: e, rotulo: ROTULO_FILTRO_ATENDIMENTO[e], n: porAtendimento[e] }))}
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
                      hint={busca.trim() ? 'Nada encontrado para essa busca.' : atend !== 'aberto' ? `Nenhuma conversa ${ROTULO_ATENDIMENTO[atend].toLowerCase()} neste filtro.` : filtro === 'minhas' ? 'Nenhuma conversa sua agora.' : 'Nenhuma conversa neste filtro.'}
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
                    titulo={ativo ? 'Você não tem acesso a este lead. Peça ao dono ou a um gestor.' : 'Escolha uma conversa'}
                    hint={ativo ? 'Se o link veio de alguém do time, confira se ele está completo.' : 'A lista já vem na ordem certa: quem espera há mais tempo fica no topo.'}
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
      {(acao === 'atividade' || acao === 'lembrete') && contato && (
        <ModalAtividade lembrete={acao === 'lembrete'} onClose={() => setAcao(null)} onConfirmar={criarAtividade} />
      )}
      {acao === 'nota' && contato && (
        <ModalNota contatoId={contato.id} negocioId={negociosAbertos[0]?.id ?? null} onClose={() => setAcao(null)} flash={flash} />
      )}
      {acao === 'mensagem' && contato && sessao && (
        <ModalAgendarMensagem
          contato={contato}
          canais={canais.filter((c) => !bloqueioCanalResposta(c, painelCanais ?? null, sessao) && c.envia && c.status === 'conectado')}
          canalInicial={canalResposta?.id ?? null}
          janelaAteEm={janelaDoCanal(conversa, canalResposta?.id)}
          templates={templates ?? []}
          remetente={nomeDe(sessao.vendedorId)}
          agora={agora}
          onClose={() => setAcao(null)}
          flash={flash}
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
  const espera = contaNaFila(cv) ? esperaResposta(m, agora) : null;
  const estado = estadoAtendimento(cv);
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
              {estado !== 'aberto' && (
                <Badge tone={estado === 'espera' ? 'warning' : 'neutral'}>{ROTULO_ATENDIMENTO[estado]}</Badge>
              )}
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
