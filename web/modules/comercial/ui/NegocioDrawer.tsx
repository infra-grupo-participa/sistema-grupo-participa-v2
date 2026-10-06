'use client';

// Ficha do negócio: tudo que o vendedor precisa para agir sem sair da tela.
// Abre do funil, da lista de contatos, das atividades e do início. Regras do playbook à vista:
// campos obrigatórios por etapa, ganho só com pagamento, troca de dono só pelo gestor, motivo de perda da lista.
// Travas espelhadas do banco (domain/travas.ts): negócio de outro dono (ou sem dono, para vendedor) abre só para
// leitura; "Mover para" fica desabilitado com a lista do que falta; "Trocar" dono só aparece para o gestor.
// Anatomia igual à ficha do contato: cabeçalho (≤ 3 status) · ações rápidas · abas · rodapé com 1 primário à direita.
import Link from 'next/link';
import { useMemo, useState } from 'react';
import {
  AvatarInicial, Badge, Button, Drawer, EmptyState, FilterSelect, Input, Modal, Row, SectionTitle, Tabs, Textarea,
  Timeline, Toast, useFlash, type TimelineEntry,
} from '@/shared/ui/components';
import { fmtBRL, fmtDataHora, fmtRelativo } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import {
  ICONE_ATIVIDADE, OPCOES_CAMPO, ROTULO_ATIVIDADE, ROTULO_ATUA, ROTULO_CAMPO, ROTULO_ORIGEM,
  ROTULO_PERFIL, produto, rotuloMotivo,
} from '../domain/catalogo';
import { COR_ETAPA, bloqueioMoverNoFunil, camposFaltandoNoFunil } from '../domain/funis';
import { atividadeAtrasada, fmtTelefone, situacaoSla } from '../domain/regras';
import { motivoSomenteLeitura, podeTrocarDono, travaMover } from '../domain/travas';
import type { CampoKey, EventoTimeline, Funil, MotivoPerda, TipoAtividade } from '../domain/types';
import {
  Aviso, BotaoConversa, BotaoCopiar, Campo, Chip, Dono, EsqueletoLista, EstadoErro, NotaRodape, ProdutoTag, RodapeAcoes,
  SlaTag, useEquipe,
} from './comum';
import { avisarMudanca, repo, useAgora, useContatosPorIds, useDados } from './repositorio';
import { HistoricoAlteracoes } from './registro/HistoricoAlteracoes';

type Aba = 'resumo' | 'atividades' | 'historico' | 'conversa' | 'alteracoes';

const TOM_EVENTO: Partial<Record<EventoTimeline['tipo'], TimelineEntry['tone']>> = {
  ganho: 'green', perdido: 'red', etapa: 'accent', dono: 'purple', checkout: 'yellow', mensagem: 'info', compra: 'green',
};

const RESULTADOS_RAPIDOS = ['Respondeu', 'Não atendeu', 'Pediu retorno', 'Caixa postal'];

export function NegocioDrawer({ negocioId, onClose, flash: flashPagina }: {
  negocioId: string;
  onClose: () => void;
  /** Toast da página. Com ele a gaveta não monta o próprio (dois toasts no mesmo ponto se sobrepõem). */
  flash?: (msg: string) => void;
}) {
  const agora = useAgora();
  const local = useFlash();
  const flash = flashPagina ?? local.flash;
  const { sessao, vendedores, nomeDe } = useEquipe();
  const [aba, setAba] = useState<Aba>('resumo');
  const rNegocios = useDados(() => repo.negocios());
  const rFunis = useDados(() => repo.funis());
  const negocios = rNegocios.dados;
  const n = negocios?.find((x) => x.id === negocioId) ?? null;
  // Só o contato deste negócio (uma chamada pequena), não a base inteira.
  const rContatos = useContatosPorIds(negocios ? (n ? [n.contatoId] : []) : null);
  const c = rContatos.dados?.find((x) => x.id === n?.contatoId) ?? null;
  const { dados: atividades } = useDados(() => repo.atividades());
  const { dados: eventos } = useDados(() => (n ? repo.eventos(n.contatoId) : Promise.resolve([])), [n?.contatoId]);
  const { dados: mensagens } = useDados(() => (n ? repo.mensagens(n.contatoId) : Promise.resolve([])), [n?.contatoId]);

  const [perder, setPerder] = useState(false);
  const [transferir, setTransferir] = useState(false);
  const [novaAtv, setNovaAtv] = useState(false);

  const minhas = useMemo(() => (atividades ?? []).filter((a) => a.negocioId === negocioId).sort((a, b) => a.venceEm.localeCompare(b.venceEm)), [atividades, negocioId]);
  const abertas = minhas.filter((a) => !a.concluidaEm);
  const outrosNegocios = (negocios ?? []).filter((x) => x.contatoId === n?.contatoId && x.id !== negocioId);

  const funil = rFunis.dados?.find((f) => f.id === n?.funilId);

  // Carregamento dentro da própria gaveta (sem Modal "Carregando…" que depois pula para Drawer).
  if (!n || !c || !funil) {
    const erro = rNegocios.erro ?? rContatos.erro ?? rFunis.erro;
    const carregou = rNegocios.dados && rContatos.dados && rFunis.dados;
    return (
      <Drawer
        onClose={onClose}
        width="max-w-4xl"
        title={erro || carregou ? 'Negócio' : <span className="block w-[180px] h-4 rounded bg-[var(--surface-3)] animate-pulse" aria-label="Carregando" />}
        subtitle={erro || carregou ? undefined : <span className="block w-[240px] max-w-full h-2.5 mt-1.5 rounded bg-[var(--surface-3)] animate-pulse" />}
        avatar={<span className="block w-11 h-11 rounded-full bg-[var(--surface-3)] animate-pulse" />}
      >
        {erro ? (
          <EstadoErro mensagem={erro} onTentar={() => { void rNegocios.recarregar(); void rContatos.recarregar(); void rFunis.recarregar(); }} />
        ) : carregou ? (
          <EmptyState icon="inbox" title="Negócio não encontrado" hint="Ele pode ter sido removido ou você não tem acesso a ele." />
        ) : (
          <EsqueletoLista linhas={4} avatar={false} />
        )}
      </Drawer>
    );
  }

  const idx = funil.etapas.findIndex((e) => e.id === n.etapaId);
  const proxima = funil.etapas[idx + 1];
  const aberto = n.status === 'aberto';
  const leitura = motivoSomenteLeitura(n, sessao, nomeDe);
  // "Mexe" = aberto e meu (ou sou gestor). Sem isso, nenhuma ação de escrita aparece.
  const mexe = aberto && !leitura;
  const podeAvancar = !!proxima && proxima.papel !== 'fechado';
  const travaProxima = podeAvancar ? travaMover(n, funil, proxima.id, sessao, nomeDe) : null;
  const faltamProxima = travaProxima?.faltam ?? [];
  const atvProxima = n.proximaAtividade ? minhas.find((a) => a.id === n.proximaAtividade!.id) ?? null : null;

  const executar = async (p: Promise<{ ok: boolean; msg?: string }>, ok: string) => {
    const r = await p;
    flash(r.ok ? r.msg || ok : r.msg || 'Não foi possível.');
    if (r.ok) avisarMudanca();
    return r.ok;
  };

  const mover = (etapaId: string) =>
    executar(repo.moverEtapa(n.id, etapaId), `Movido para ${funil.etapas.find((e) => e.id === etapaId)?.nome ?? 'a etapa'}.`);

  const concluir = (atividadeId: string, res: string) => executar(repo.concluirAtividade(atividadeId, res), 'Atividade concluída.');

  // Sub: telefone · produto · origem · dono (produto e origem são metadado, não status).
  const subtitulo = [fmtTelefone(c.telefone), produto(n.produto).nome, ROTULO_ORIGEM[n.origem], n.donoId ? `dono ${nomeDe(n.donoId)}` : 'sem dono'].join(' · ');

  // Primário único: avançar etapa; sem etapa para avançar, agendar vira o primário.
  // Com campo faltando, o botão fica desabilitado e a lista do que falta aparece ao lado (não só no title).
  const primario = podeAvancar ? (
    <span className="inline-flex flex-wrap items-center justify-end gap-2">
      {faltamProxima.length > 0 && (
        <span id="falta-proxima" className="inline-flex items-center gap-1 text-xs text-[var(--fg-2)]">
          <Icon name="lock" size={12} className="shrink-0 text-[var(--fg-3)]" /> Falta: {faltamProxima.join(', ')}
        </span>
      )}
      <Button
        size="sm"
        disabled={!travaProxima?.permitido}
        aria-describedby={faltamProxima.length ? 'falta-proxima' : undefined}
        onClick={() => mover(proxima.id)}
        title={travaProxima?.motivo ?? (proxima.criterio ? `Critério: ${proxima.criterio}` : undefined)}
      >
        Mover para {proxima.nome} <Icon name="arrow-right" size={14} />
      </Button>
    </span>
  ) : (
    <Button size="sm" onClick={() => setNovaAtv(true)}><Icon name="plus" size={14} /> Próxima atividade</Button>
  );

  return (
    <>
      <Drawer
        onClose={onClose}
        width="max-w-4xl"
        title={c.nome}
        subtitle={subtitulo}
        avatar={<AvatarInicial nome={c.nome} size={44} />}
        actions={<>
          <BotaoConversa contatoId={c.id} />
          <BotaoCopiar texto={c.telefone} onCopiado={flash} />
        </>}
        badges={(!aberto || c.optOut || c.ehAluno || situacaoSla(n, agora) !== 'sem_sla') ? <>
          {n.status === 'ganho' && <Badge tone="success">Ganho</Badge>}
          {n.status === 'perdido' && <Badge tone="danger">Perdido · {rotuloMotivo(n.motivoPerda)}</Badge>}
          {aberto && <SlaTag n={n} agora={agora} variante={c.optOut ? 'texto' : 'badge'} />}
          {c.optOut && <Badge tone="danger">Não quer contato</Badge>}
          {c.ehAluno && <Badge>Já é aluno</Badge>}
        </> : undefined}
        footer={mexe ? (
          <RodapeAcoes
            perigo={<Button size="sm" variant="danger" onClick={() => setPerder(true)}>Marcar como perdido</Button>}
            secundario={podeAvancar ? <Button size="sm" variant="ghost" onClick={() => setNovaAtv(true)}><Icon name="plus" size={14} /> Próxima atividade</Button> : undefined}
            primario={primario}
          />
        ) : aberto ? (
          <span className="inline-flex items-center gap-1.5 text-xs text-[var(--fg-3)]"><Icon name="lock" size={12} /> Somente leitura. {leitura}</span>
        ) : (
          <span className="text-xs text-[var(--fg-3)]">Negócio encerrado em {fmtDataHora(n.fechadoEm)}.</span>
        )}
      >
        <Tabs
          tabs={[
            { k: 'resumo', l: 'Resumo' },
            { k: 'atividades', l: 'Atividades', n: abertas.filter((a) => atividadeAtrasada(a, agora)).length },
            { k: 'historico', l: 'Linha do tempo' },
            { k: 'conversa', l: 'Conversa' },
            { k: 'alteracoes', l: 'Alterações' },
          ]}
          active={aba}
          onChange={(k) => setAba(k as Aba)}
          label="Seções do negócio"
        />

        {aba === 'resumo' && (
          <div className="space-y-6">
            {aberto && leitura && (
              <Aviso tom="neutral" icone="lock">{leitura} Peça ao gestor se precisar transferir.</Aviso>
            )}
            {aberto && (
              <section>
                <SectionTitle right={n.proximaAtividade && mexe ? <Button size="sm" variant="link" onClick={() => setNovaAtv(true)}>Nova atividade</Button> : undefined}>
                  Próximo passo
                </SectionTitle>
                {n.proximaAtividade ? (
                  <LinhaAtividade
                    tipo={n.proximaAtividade.tipo}
                    titulo={n.proximaAtividade.titulo}
                    venceEm={n.proximaAtividade.venceEm}
                    concluidaEm={null}
                    resultado={null}
                    atrasada={atvProxima ? atividadeAtrasada(atvProxima, agora) : new Date(n.proximaAtividade.venceEm) < agora}
                    destaque
                    onConcluir={mexe ? (res) => concluir(n.proximaAtividade!.id, res) : undefined}
                    onAgendarProxima={mexe ? () => setNovaAtv(true) : undefined}
                  />
                ) : (
                  <Aviso
                    tom="danger"
                    acao={mexe ? <Button size="sm" variant="ghost" onClick={() => setNovaAtv(true)}><Icon name="calendar" size={14} /> Agendar agora</Button> : undefined}
                  >
                    Sem próxima atividade com data. Pelo playbook, negócio sem próximo passo vira perdido.
                  </Aviso>
                )}
              </section>
            )}

            <section>
              <SectionTitle right={<span className="text-xs text-[var(--fg-3)] truncate">{funil.nome}</span>}>Etapa</SectionTitle>
              <Funilzinho funil={funil} atual={n.etapaId} status={n.status} onMover={mexe ? mover : undefined} campos={n.campos} />
            </section>

            <CamposNegocio
              funil={funil} negocioId={n.id} campos={n.campos} etapaAtual={n.etapaId} editavel={mexe}
              onSalvo={() => { flash('Campos salvos.'); avisarMudanca(); }}
              onErro={(m) => flash(m)}
            />

            <div className="grid gap-6 md:grid-cols-2">
              <section>
                <SectionTitle>Negócio</SectionTitle>
                <Row k="Valor" v={<span className="tabular">{fmtBRL(n.valor)}</span>} />
                <Row k="Produto" v={<ProdutoTag k={n.produto} />} />
                <Row k="Origem" v={ROTULO_ORIGEM[n.origem]} />
                <Row k="Dono" v={
                  <span className="inline-flex items-center gap-2">
                    <Dono id={n.donoId} nomeDe={nomeDe} />
                    {podeTrocarDono(sessao) && aberto && <Button size="sm" variant="link" onClick={() => setTransferir(true)}>Trocar</Button>}
                  </span>
                } />
                <Row k="Criado" v={fmtDataHora(n.criadoEm)} />
                <Row k="Última interação" v={fmtRelativo(n.ultimaInteracaoEm).label} />
              </section>
              <section>
                <SectionTitle>Contato</SectionTitle>
                <Row k="E-mail" v={c.email ?? '—'} />
                <Row k="Perfil" v={c.perfil ? ROTULO_PERFIL[c.perfil] : '—'} />
                <Row k="Holding" v={c.atuaComHolding ? ROTULO_ATUA[c.atuaComHolding] : '—'} />
                <Row k="Cidade" v={c.cidade ? `${c.cidade} · ${c.uf}` : '—'} />
                <Row k="Origem (UTM)" v={[c.utm.source, c.utm.medium, c.utm.campaign].filter(Boolean).join(' / ') || '—'} />
                <Row k="Tags" v={c.tags.length ? <span className="text-xs text-[var(--fg-2)]">{c.tags.join(', ')}</span> : '—'} />
              </section>
            </div>

            {outrosNegocios.length > 0 && (
              <section>
                <SectionTitle>Outros negócios deste contato</SectionTitle>
                <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)]">
                  {outrosNegocios.map((o) => (
                    <li key={o.id} className="flex items-center justify-between gap-3 px-3 py-2">
                      <ProdutoTag k={o.produto} />
                      <span className="text-xs text-[var(--fg-3)] truncate">
                        {o.status === 'aberto' ? o.etapaNome : o.status === 'ganho' ? 'Ganho' : 'Perdido'}
                      </span>
                    </li>
                  ))}
                </ul>
              </section>
            )}
          </div>
        )}

        {aba === 'atividades' && (
          <div className="space-y-2">
            {mexe && minhas.length > 0 && (
              <div className="flex justify-end"><Button size="sm" variant="ghost" onClick={() => setNovaAtv(true)}><Icon name="plus" size={14} /> Nova atividade</Button></div>
            )}
            {minhas.length === 0 && (
              <div>
                <EmptyState title="Nenhuma atividade" hint="Todo negócio aberto precisa de uma próxima atividade com data." icon="clipboard" />
                {mexe && (
                  <div className="-mt-8 pb-12 flex justify-center">
                    <Button size="sm" variant="ghost" onClick={() => setNovaAtv(true)}><Icon name="calendar" size={14} /> Agendar atividade</Button>
                  </div>
                )}
              </div>
            )}
            {minhas.map((a) => (
              <LinhaAtividade
                key={a.id}
                tipo={a.tipo} titulo={a.titulo} venceEm={a.venceEm} concluidaEm={a.concluidaEm} resultado={a.resultado}
                atrasada={atividadeAtrasada(a, agora)}
                onConcluir={mexe && !a.concluidaEm ? (res) => concluir(a.id, res) : undefined}
                onAgendarProxima={mexe ? () => setNovaAtv(true) : undefined}
              />
            ))}
          </div>
        )}

        {aba === 'historico' && (
          <Historico eventos={eventos ?? []} nomeDe={nomeDe} onNota={!leitura ? (t) => executar(repo.adicionarNota(c.id, n.id, t), 'Nota registrada.') : undefined} />
        )}

        {aba === 'conversa' && (
          <div className="space-y-2">
            {(mensagens ?? []).length === 0 && <EmptyState title="Sem conversa no WhatsApp" hint="A conversa aparece aqui quando o número oficial estiver conectado." icon="message" />}
            {(mensagens ?? []).map((m) => (
              <div key={m.id} className={`flex ${m.direcao === 'saida' ? 'justify-end' : 'justify-start'}`}>
                <div className={`max-w-[80%] rounded-[var(--r-lg)] border px-3 py-2 text-sm text-[var(--fg)] ${m.direcao === 'saida' ? 'bg-[var(--surface-4)] border-[var(--border-strong)]' : 'bg-[var(--surface-3)] border-[var(--border)]'}`}>
                  <div className="whitespace-pre-wrap">{m.texto}</div>
                  <div className="mt-1 text-[11px] text-[var(--fg-3)] text-right">{fmtDataHora(m.em)}{m.templateId ? ' · template' : ''}</div>
                </div>
              </div>
            ))}
            <div className="pt-2 text-right">
              <Link href={`/comercial/conversas?contato=${encodeURIComponent(c.id)}`} className="inline-flex items-center gap-1 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:underline">
                Abrir na caixa de conversas <Icon name="arrow-right" size={12} />
              </Link>
            </div>
          </div>
        )}

        {aba === 'alteracoes' && <HistoricoAlteracoes entidadeId={n.id} />}
      </Drawer>

      {perder && (
        <ModalPerdido
          onClose={() => setPerder(false)}
          onConfirmar={async (motivo, nota) => { if (await executar(repo.marcarPerdido(n.id, motivo, nota), 'Negócio marcado como perdido.')) setPerder(false); }}
        />
      )}
      {transferir && (
        <ModalTransferir
          atual={n.donoId}
          vendedores={vendedores.filter((v) => v.ativo)}
          onClose={() => setTransferir(false)}
          onConfirmar={async (dono, motivo) => { if (await executar(repo.transferirDono(n.id, dono, motivo), 'Dono trocado.')) setTransferir(false); }}
        />
      )}
      {novaAtv && (
        <ModalAtividade
          onClose={() => setNovaAtv(false)}
          onConfirmar={async (tipo, titulo, venceEm) => {
            if (await executar(repo.criarAtividade({ negocioId: n.id, contatoId: c.id, tipo, titulo, venceEm }), 'Atividade agendada.')) setNovaAtv(false);
          }}
        />
      )}
      {!flashPagina && <Toast>{local.toast}</Toast>}
    </>
  );
}

type InfoEtapa = { id: string; nome: string; cor: string; i: number; ativa: boolean; feita: boolean; clicavel: boolean; title: string; motivo: string | null; faltam: string };

/** Etapas do funil do negócio. A etapa de Ganho não é clicável: fecha pela Hotmart.
 *  Celular: seletor "Mover para…" (motivo no rótulo). Tela larga: trilha com rolagem horizontal. */
function Funilzinho({ funil, atual, status, campos, onMover }: {
  funil: Funil; atual: string; status: string; campos: Partial<Record<CampoKey, string>>; onMover?: (etapaId: string) => void;
}) {
  const idx = funil.etapas.findIndex((e) => e.id === atual);
  const etapas: InfoEtapa[] = funil.etapas.map((e, i) => {
    const feita = i < idx || status === 'ganho';
    const ativa = i === idx && status !== 'ganho';
    const bloqueio = onMover ? bloqueioMoverNoFunil({ campos, status: 'aberto' }, funil, e.id) : 'negocio_encerrado';
    const faltam = bloqueio === 'campos_faltando' ? camposFaltandoNoFunil({ campos }, funil, e.id).map((c) => ROTULO_CAMPO[c]).join(', ') : '';
    const clicavel = !!onMover && !ativa && bloqueio !== 'ganho_so_com_pagamento';
    const title = e.papel === 'fechado' ? 'Ganho só com pagamento aprovado na Hotmart' : faltam ? `Falta preencher: ${faltam}` : e.criterio ? `Critério para passar: ${e.criterio}` : e.nome;
    const motivo = ativa ? 'etapa atual' : e.papel === 'fechado' ? 'só com pagamento' : faltam ? `falta ${faltam}` : null;
    return { id: e.id, nome: e.nome, cor: COR_ETAPA[e.cor], i, ativa, feita, clicavel, title, motivo, faltam };
  });

  return (
    <>
      {onMover && (
        <div className="sm:hidden">
          <FilterSelect
            aria-label="Mover para outra etapa"
            value=""
            onChange={(ev) => { if (ev.target.value) onMover(ev.target.value); }}
          >
            <option value="">Etapa atual: {funil.etapas[idx]?.nome ?? '—'} · mover para…</option>
            {etapas.filter((e) => !e.ativa).map((e) => (
              <option key={e.id} value={e.id} disabled={!e.clicavel || !!e.faltam}>
                {e.i + 1}. {e.nome}{e.motivo ? ` (${e.motivo})` : ''}
              </option>
            ))}
          </FilterSelect>
        </div>
      )}
      {/* Funil longo quebra em linhas (sem rolagem lateral). */}
      <ol className={`${onMover ? 'hidden sm:grid' : 'grid'} grid-cols-[repeat(auto-fill,minmax(120px,1fr))] gap-1 pb-1`} aria-label="Etapas do funil">
        {etapas.map((e) => (
          <li key={e.id} className="min-w-0">
            <button
              type="button"
              disabled={!e.clicavel}
              title={e.title}
              aria-current={e.ativa ? 'step' : undefined}
              onClick={() => onMover?.(e.id)}
              className={`w-full h-full min-h-12 text-left rounded-[var(--r-md)] border px-3 py-2 text-xs leading-tight transition-colors ${
                e.ativa ? 'border-[var(--accent)] bg-[var(--accent-subtle)] text-[var(--fg)] font-semibold'
                  : e.feita ? 'border-[var(--border)] bg-[var(--surface-3)] text-[var(--fg-2)]'
                  : 'border-dashed border-[var(--border)] text-[var(--fg-3)]'
              } ${e.clicavel ? 'hover:border-[var(--border-accent)] cursor-pointer' : 'cursor-default'}`}
            >
              <span className="flex items-center gap-1.5 text-[11px] tabular text-[var(--fg-3)] font-normal">
                <span className="w-1.5 h-1.5 rounded-full shrink-0" style={{ background: e.cor }} />{e.i + 1}
                {e.feita && <Icon name="check" size={11} />}
                {e.faltam && !e.ativa && <Icon name="lock" size={11} />}
                {e.feita && <span className="sr-only">(concluída)</span>}
              </span>
              <span className="mt-0.5 block">{e.nome}</span>
            </button>
          </li>
        ))}
      </ol>
    </>
  );
}

const LISTA_CAMPOS: CampoKey[] = ['perfil_profissional', 'atua_com_holding', 'produto_interesse', 'origem', 'objecao_principal', 'forma_pagamento'];

/** Campos do negócio. Abertos: os exigidos até a próxima etapa. O resto fica recolhido. */
function CamposNegocio({ funil, negocioId, campos, etapaAtual, editavel, onSalvo, onErro }: {
  funil: Funil; negocioId: string; campos: Partial<Record<CampoKey, string>>; etapaAtual: string; editavel: boolean;
  onSalvo: () => void; onErro: (msg: string) => void;
}) {
  const [rascunho, setRascunho] = useState(campos);
  const [salvando, setSalvando] = useState(false);
  const idx = funil.etapas.findIndex((e) => e.id === etapaAtual);
  const exigidoEm = (k: CampoKey) => funil.etapas.find((e) => e.camposObrigatorios.includes(k));
  const indiceExigido = (k: CampoKey) => { const e = exigidoEm(k); return e ? funil.etapas.indexOf(e) : -1; };
  const principais = LISTA_CAMPOS.filter((k) => { const ie = indiceExigido(k); return ie >= 0 && ie <= idx + 1; });
  const outros = LISTA_CAMPOS.filter((k) => !principais.includes(k));
  const mudou = LISTA_CAMPOS.some((k) => (rascunho[k] ?? '') !== (campos[k] ?? ''));
  const pendentes = principais.filter((k) => !String(rascunho[k] ?? '').trim()).length;

  const salvar = async () => {
    setSalvando(true);
    const r = await repo.salvarCampos(negocioId, rascunho);
    setSalvando(false);
    if (r.ok) onSalvo(); else onErro(r.msg ?? 'Não foi possível salvar.');
  };

  const campo = (k: CampoKey) => {
    const e = exigidoEm(k);
    const ie = indiceExigido(k);
    const vazio = !String(rascunho[k] ?? '').trim();
    const extra = vazio && ie >= 0 && ie <= idx ? <span className="font-medium text-[var(--red)]">obrigatório</span>
      : vazio && ie === idx + 1 ? <span className="text-[var(--yellow)]">para {e!.nome}</span>
      : null;
    const opcoes = OPCOES_CAMPO[k];
    return (
      <Campo key={k} rotulo={ROTULO_CAMPO[k]} extra={extra} dica={k === 'origem' ? 'Preenchido pela integração.' : undefined}>
        {opcoes ? (
          <FilterSelect disabled={!editavel} value={rascunho[k] ?? ''} onChange={(ev) => setRascunho({ ...rascunho, [k]: ev.target.value })}>
            <option value="">—</option>
            {opcoes.map((o) => <option key={o.value} value={o.value}>{o.label}</option>)}
          </FilterSelect>
        ) : (
          <Input disabled={!editavel || k === 'origem'} value={rascunho[k] ?? ''} onChange={(ev) => setRascunho({ ...rascunho, [k]: ev.target.value })} />
        )}
      </Campo>
    );
  };

  return (
    <section>
      <SectionTitle right={editavel && mudou ? (
        <span className="inline-flex items-center gap-2">
          <Button size="sm" variant="ghost" disabled={salvando} onClick={() => setRascunho(campos)}>Descartar</Button>
          <Button size="sm" variant="subtle" disabled={salvando} onClick={salvar}>{salvando ? 'Salvando…' : 'Salvar campos'}</Button>
        </span>
      ) : pendentes > 0 ? <span className="text-xs text-[var(--fg-3)]">{pendentes} a preencher</span> : undefined}>
        Campos do negócio
      </SectionTitle>
      {principais.length > 0 && <div className="grid gap-3 sm:grid-cols-2">{principais.map(campo)}</div>}
      {outros.length > 0 && (
        <details className="group mt-3" open={principais.length === 0}>
          <summary className="inline-flex items-center gap-1 cursor-pointer select-none text-xs text-[var(--fg-3)] hover:text-[var(--fg-2)] min-h-8">
            <Icon name="chevron-right" size={14} className="transition-transform group-open:rotate-90" />
            Outros campos ({outros.length})
          </summary>
          <div className="mt-2 grid gap-3 sm:grid-cols-2">{outros.map(campo)}</div>
        </details>
      )}
    </section>
  );
}

/**
 * Atividade em linha, com conclusão no lugar. Com `onAgendarProxima`, concluir oferece
 * "Concluir e agendar próxima": o playbook proíbe negócio aberto sem próximo passo.
 */
export function LinhaAtividade({ tipo, titulo, venceEm, concluidaEm, resultado, atrasada, onConcluir, extra, onAgendarProxima, destaque = false }: {
  tipo: TipoAtividade; titulo: string; venceEm: string; concluidaEm: string | null; resultado: string | null; atrasada: boolean;
  onConcluir?: (resultado: string) => void | Promise<unknown>; extra?: React.ReactNode;
  /** Abre o agendamento da próxima logo depois de concluir. */
  onAgendarProxima?: () => void;
  /** Visual de "próximo passo" (card surface-3). */
  destaque?: boolean;
}) {
  const [concluindo, setConcluindo] = useState(false);
  const [res, setRes] = useState('');
  const fechar = () => { setConcluindo(false); setRes(''); };
  const confirmar = async (agendar: boolean) => {
    await onConcluir?.(res);
    fechar();
    if (agendar) onAgendarProxima?.();
  };
  const caixa = concluidaEm ? 'border-[var(--border-faint)] opacity-70'
    : atrasada ? 'border-[var(--red-border)] bg-[var(--red-subtle)]'
    : destaque ? 'border-[var(--border)] bg-[var(--surface-3)]'
    : 'border-[var(--border)] bg-[var(--surface-2)]';
  return (
    <div className={`rounded-[var(--r-md)] border px-3 py-2 ${caixa}`}>
      <div className="flex items-center gap-3">
        <span className={`grid place-items-center w-8 h-8 rounded-full text-[var(--fg-2)] shrink-0 ${destaque ? 'bg-[var(--surface-4)]' : 'bg-[var(--surface-3)]'}`}>
          <Icon name={ICONE_ATIVIDADE[tipo]} size={15} />
        </span>
        <div className="flex-1 min-w-0">
          <div className={`text-sm font-medium ${concluidaEm ? 'line-through text-[var(--fg-3)]' : 'text-[var(--fg)]'}`}>{titulo}</div>
          <div className="text-xs text-[var(--fg-3)]">
            {ROTULO_ATIVIDADE[tipo]} · {concluidaEm ? `feita ${fmtDataHora(concluidaEm)}` : `vence ${fmtDataHora(venceEm)}`}
            {atrasada && !concluidaEm && <span className="ml-1 font-semibold text-[var(--red)]">· atrasada</span>}
            {resultado && <span> · {resultado}</span>}
          </div>
          {extra}
        </div>
        {onConcluir && !concluindo && (
          <Button size="sm" variant="ghost" onClick={() => setConcluindo(true)}><Icon name="check" size={14} /> Concluir</Button>
        )}
      </div>
      {concluindo && onConcluir && (
        <div className="mt-3 space-y-2">
          <div className="flex flex-wrap items-center gap-1.5" role="group" aria-label="Resultado">
            {RESULTADOS_RAPIDOS.map((r) => <Chip key={r} ativo={res === r} onClick={() => setRes(res === r ? '' : r)}>{r}</Chip>)}
          </div>
          <Input aria-label="Resultado" placeholder="Resultado (opcional)" value={res} onChange={(e) => setRes(e.target.value)} />
          <div className="flex flex-wrap items-center justify-end gap-2">
            <Button size="sm" variant="ghost" onClick={fechar}>Cancelar</Button>
            {onAgendarProxima ? (
              <>
                <Button size="sm" variant="ghost" onClick={() => confirmar(false)}>Só concluir</Button>
                <Button size="sm" variant="subtle" onClick={() => confirmar(true)}><Icon name="calendar" size={14} /> Concluir e agendar próxima</Button>
              </>
            ) : (
              <Button size="sm" variant="subtle" onClick={() => confirmar(false)}>Confirmar</Button>
            )}
          </div>
        </div>
      )}
    </div>
  );
}

/** Sem `onNota` (negócio de outro dono): só leitura, sem a caixa de nota. */
function Historico({ eventos, nomeDe, onNota }: { eventos: EventoTimeline[]; nomeDe: (id: string | null) => string; onNota?: (t: string) => Promise<boolean> }) {
  const [nota, setNota] = useState('');
  const itens: TimelineEntry[] = eventos.map((e) => ({
    tone: TOM_EVENTO[e.tipo] ?? 'base',
    done: e.tipo === 'ganho',
    title: e.titulo,
    meta: fmtDataHora(e.em),
    body: [e.tipo === 'perdido' && e.detalhe ? rotuloMotivo(e.detalhe.split(' · ')[0] as MotivoPerda) + (e.detalhe.includes(' · ') ? ` · ${e.detalhe.split(' · ').slice(1).join(' · ')}` : '') : e.tipo === 'etapa' ? null : e.detalhe, e.autorId ? `por ${nomeDe(e.autorId)}` : null].filter(Boolean).join(' · ') || undefined,
  }));
  return (
    <div className="space-y-4">
      {onNota && (
        <div className="flex gap-2">
          <Textarea aria-label="Nota interna" rows={2} placeholder="Nota interna (objeção, combinado, contexto)…" value={nota} onChange={(e) => setNota(e.target.value)} />
          <Button size="sm" variant="subtle" className="self-end" disabled={!nota.trim()} onClick={async () => { if (await onNota(nota)) setNota(''); }}>Registrar</Button>
        </div>
      )}
      {itens.length ? <Timeline items={itens} /> : <EmptyState title="Sem histórico" icon="clock" />}
    </div>
  );
}

export function ModalPerdido({ onClose, onConfirmar }: { onClose: () => void; onConfirmar: (m: MotivoPerda, nota: string) => void }) {
  const [motivo, setMotivo] = useState<MotivoPerda | ''>('');
  const [nota, setNota] = useState('');
  // Cadastro de motivos (os 9 de fábrica + os criados pelo gestor em Configurações), só os ativos.
  const { dados: cadastro } = useDados(() => repo.motivosPerda());
  const motivos = (cadastro ?? []).filter((m) => m.ativo);
  const sel = motivos.find((m) => m.key === motivo);
  return (
    <Modal
      onClose={onClose}
      title="Marcar como perdido"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button variant="danger" size="sm" disabled={!motivo} onClick={() => motivo && onConfirmar(motivo, nota)}>Confirmar perda</Button>
      </>}
    >
      <fieldset>
        <legend className="mb-2 text-xs font-medium text-[var(--fg-2)]">Motivo (lista única: motivo fora dela não existe)</legend>
        <div className="grid gap-1.5">
          {motivos.map((m) => (
            <label key={m.key} className={`flex items-start gap-2 rounded-[var(--r-md)] border px-3 py-2 cursor-pointer transition-colors ${motivo === m.key ? 'border-[var(--border-accent)] bg-[var(--surface-3)]' : 'border-[var(--border)] hover:bg-[var(--surface-3)]'}`}>
              <input type="radio" name="motivo" className="mt-1 accent-[var(--accent)]" checked={motivo === m.key} onChange={() => setMotivo(m.key)} />
              <span className="text-sm text-[var(--fg)]">{m.label}{m.nota && <span className="block text-[11px] text-[var(--fg-3)]">{m.nota}</span>}</span>
            </label>
          ))}
        </div>
      </fieldset>
      {sel?.alertaGestor && (
        <Aviso tom="warning" className="mt-3">Este motivo mede falha de processo. O gestor é avisado para tratar hoje.</Aviso>
      )}
      {sel?.bloqueia && (
        <Aviso tom="danger" className="mt-3">A pessoa vai para a lista de bloqueio e não recebe mais contato.</Aviso>
      )}
      <Campo rotulo="Nota (opcional)" className="mt-4">
        <Textarea rows={2} value={nota} onChange={(e) => setNota(e.target.value)} />
      </Campo>
    </Modal>
  );
}

function ModalTransferir({ atual, vendedores, onClose, onConfirmar }: {
  atual: string | null; vendedores: { id: string; nome: string }[]; onClose: () => void; onConfirmar: (dono: string, motivo: string) => void;
}) {
  const [dono, setDono] = useState('');
  const [motivo, setMotivo] = useState('');
  return (
    <Modal
      onClose={onClose}
      title="Trocar dono do negócio"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!dono || !motivo.trim()} onClick={() => onConfirmar(dono, motivo)}>Trocar dono</Button>
      </>}
    >
      <div className="space-y-4">
        <Campo rotulo="Novo dono">
          <FilterSelect value={dono} onChange={(e) => setDono(e.target.value)}>
            <option value="">Escolha…</option>
            {vendedores.filter((v) => v.id !== atual).map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Motivo" extra={<span className="text-[var(--fg-3)]">obrigatório</span>}>
          <Textarea rows={2} value={motivo} onChange={(e) => setMotivo(e.target.value)} />
        </Campo>
        <NotaRodape>Só o gestor troca dono, sempre com o motivo registrado. O contato acompanha o novo dono.</NotaRodape>
      </div>
    </Modal>
  );
}

export function ModalAtividade({ onClose, onConfirmar }: { onClose: () => void; onConfirmar: (tipo: TipoAtividade, titulo: string, venceEm: string) => void }) {
  const amanha10 = () => {
    const d = new Date();
    d.setDate(d.getDate() + 1);
    d.setHours(10, 0, 0, 0);
    const p = (x: number) => String(x).padStart(2, '0');
    return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T10:00`;
  };
  const [tipo, setTipo] = useState<TipoAtividade>('ligacao');
  const [titulo, setTitulo] = useState('');
  const [quando, setQuando] = useState(amanha10);
  const pronto = !!titulo.trim() && !!quando;
  return (
    <Modal
      onClose={onClose}
      title="Agendar próxima atividade"
      footer={<>
        <Button variant="ghost" size="sm" onClick={onClose}>Cancelar</Button>
        <Button size="sm" disabled={!pronto} onClick={() => onConfirmar(tipo, titulo, new Date(quando).toISOString())}>Agendar</Button>
      </>}
    >
      <form
        className="space-y-4"
        onSubmit={(e) => { e.preventDefault(); if (pronto) onConfirmar(tipo, titulo, new Date(quando).toISOString()); }}
      >
        <div>
          <span className="mb-1 block text-xs font-medium text-[var(--fg-2)]" id="atv-tipo">Tipo</span>
          <div className="flex flex-wrap gap-1.5" role="group" aria-labelledby="atv-tipo">
            {(['ligacao', 'whatsapp', 'email', 'reuniao', 'tarefa'] as TipoAtividade[]).map((t) => (
              <Chip key={t} ativo={tipo === t} icone={ICONE_ATIVIDADE[t]} onClick={() => setTipo(t)}>{ROTULO_ATIVIDADE[t]}</Chip>
            ))}
          </div>
        </div>
        <Campo rotulo="O que fazer">
          <Input autoFocus placeholder="Ex.: Ligar para apresentar a oferta" value={titulo} onChange={(e) => setTitulo(e.target.value)} />
        </Campo>
        <Campo rotulo="Quando">
          <Input type="datetime-local" value={quando} onChange={(e) => setQuando(e.target.value)} />
        </Campo>
        <NotaRodape>Quem define o próximo passo é o vendedor, não o lead.</NotaRodape>
      </form>
    </Modal>
  );
}
