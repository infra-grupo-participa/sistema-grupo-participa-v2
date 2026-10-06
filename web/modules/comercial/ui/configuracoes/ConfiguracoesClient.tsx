'use client';

// Configuração do CRM do Comercial: o que hoje fica na Clint (distribuição, funil, motivos, links, integrações)
// e as notificações de cada pessoa. Só o gestor grava a configuração; o vendedor vê em modo leitura.
import Link from 'next/link';
import { useState } from 'react';
import {
  Button, Card, FilterSelect, Input, Loading, SectionCard, SectionTitle, Tabs, Toast, Toggle, idsAba, useFlash,
} from '@/shared/ui/components';
import { Icon } from '@/shared/ui/icons';
import { ETAPAS, ORIGENS_HOTMART, PRODUTOS, ROTULO_CAMPO, ROTULO_ORIGEM } from '../../domain/catalogo';
import type { ConfigComercial, LinkRastreavel, ProdutoKey, Vendedor } from '../../domain/types';
import {
  Campo, Carregando, EsqueletoLista, FaixaNumeros, NotaRodape, PaginaComercial, Pessoa, ProdutoTag, Vazio, useAbaHash, useEquipe,
} from '../comum';
import { InfoIndicador, type TextoIndicador } from '../InfoIndicador';
import { avisarMudanca, repo, useDados } from '../repositorio';
import {
  aplicarRascunho, estadoDistribuicao, fmtMinutos, normalizarPercentual, previaSck, rascunhoDe, simularDistribuicao,
  type RascunhoDistribuicao,
} from './configuracao';
import { AbaIntegracoes } from './AbaIntegracoes';
import { AbaMotivos } from './AbaMotivos';
import { AbaNotificacoes } from './AbaNotificacoes';

type Aba = 'distribuicao' | 'funil' | 'motivos' | 'links' | 'integracoes' | 'notificacoes';
const ABAS: readonly Aba[] = ['distribuicao', 'funil', 'motivos', 'links', 'integracoes', 'notificacoes'];
const ID_ABAS = 'config-comercial';

// Link interno com visual de Button ghost (sm).
const CLS_LINK_GHOST = 'inline-flex items-center justify-center gap-2 rounded-[var(--r-md)] border border-[var(--border)] px-3 py-1.5 text-xs font-semibold text-[var(--fg-2)] hover:text-[var(--fg)] hover:border-[var(--border-strong)] hover:bg-[var(--surface-3)] transition-colors';

export function ConfiguracoesClient() {
  const [aba, setAba] = useAbaHash<Aba>(ABAS, 'distribuicao');
  const { sessao, vendedores, nomeDe, gestor } = useEquipe();
  const { toast, flash } = useFlash();
  const leitura = !gestor && !!sessao;

  return (
    <PaginaComercial
      titulo="Configurações"
      subtitulo={(
        <>
          Distribuição de leads, motivos de perda, links, integrações e suas notificações.
          {leitura && <span title="Só o gestor do Comercial altera"> · Somente leitura</span>}
        </>
      )}
    >
      <Tabs
        idBase={ID_ABAS}
        label="Configurações do Comercial"
        active={aba}
        onChange={(k) => setAba(k as Aba)}
        tabs={[
          { k: 'distribuicao', l: 'Distribuição' }, { k: 'funil', l: 'Modelo do funil' }, { k: 'motivos', l: 'Motivos de perda' },
          { k: 'links', l: 'Links rastreáveis' }, { k: 'integracoes', l: 'Integrações' }, { k: 'notificacoes', l: 'Notificações' },
        ]}
      />
      <div role="tabpanel" id={idsAba(ID_ABAS, aba).panel} aria-labelledby={idsAba(ID_ABAS, aba).tab}>
        {!sessao || !vendedores.length ? <Loading /> : aba === 'distribuicao' ? (
          // key: quando a equipe salva muda, o rascunho recomeça do salvo.
          <Distribuicao key={vendedores.map((v) => `${v.id}:${v.percentual}:${v.ativo}`).join('|')} vendedores={vendedores} gestor={gestor} flash={flash} />
        ) : aba === 'funil' ? <FunilConfig gestor={gestor} />
          : aba === 'motivos' ? <AbaMotivos gestor={gestor} flash={flash} />
          : aba === 'links' ? <Links vendedores={vendedores} meuId={sessao.vendedorId} gestor={gestor} nomeDe={nomeDe} flash={flash} />
          : aba === 'integracoes' ? <AbaIntegracoes />
          : <AbaNotificacoes key={sessao.vendedorId} flash={flash} />}
      </div>
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

// ── #distribuicao ──

/** Definição dos números desta tela que não estão em domain/metricas.ts. */
const INFO = {
  recebendo: { nome: 'Recebendo leads', oQueE: 'Vendedores ativos na distribuição, contando o rascunho ainda não salvo.', paraQue: 'Vendedor ausente sai antes das 9h para não receber lead que ninguém vai atender.' },
  soma: { nome: 'Soma dos ativos', oQueE: 'Soma dos percentuais de quem está recebendo.', comoConta: 'Só vendedores ativos entram na conta.', meta: 'Exatamente 100% para poder salvar.' },
  percentual: { nome: 'Percentual por vendedor', oQueE: 'Parte dos leads novos sem dono que cada vendedor recebe.', comoConta: 'O lead vai para quem está mais abaixo da sua cota no ciclo. Contato que já tem dono não entra na conta.' },
  simulador: { nome: 'Simulador', oQueE: 'Para quem iriam os próximos 10 leads sem dono com o percentual da tela.', comoConta: 'Aplica a regra de distribuição em sequência; cada escolha conta para a seguinte.' },
  sla: { nome: 'Atenção / crítico', oQueE: 'Tempo máximo parado em cada etapa antes do alerta.', comoConta: 'Conta desde que o negócio entrou na etapa. Atenção = amarelo; crítico = vermelho e aviso ao gestor.', paraQue: 'É onde se perde venda por silêncio.' },
  ticket: { nome: 'Ticket de referência', oQueE: 'Preço de referência do produto, usado como valor inicial do negócio.', comoConta: 'O valor real é o da oferta paga na Hotmart.' },
} satisfies Record<string, TextoIndicador>;

const REGRAS_DISTRIBUICAO: { titulo: string; texto: string }[] = [
  { titulo: 'Contato com dono mantém o dono', texto: 'Negócio novo de quem já é contato de alguém vai para o mesmo vendedor, em qualquer produto.' },
  { titulo: 'Sem dono, vai pelo percentual', texto: 'O lead novo vai para quem está mais abaixo da sua cota. Sem sorteio: o mesmo cenário dá o mesmo dono.' },
  { titulo: 'Exceções definidas antes da campanha', texto: 'Lista VIP, produto específico ou vendedor dedicado: o gestor define antes de abrir a campanha, nunca no meio.' },
  { titulo: 'Troca de dono só pelo gestor', texto: 'Sempre com nota explicando o motivo. Vendedor não puxa lead do colega.' },
  { titulo: 'Vendedor ausente', texto: 'O gestor redistribui a carteira do dia antes das 9h e tira o ausente da distribuição.' },
  { titulo: 'Caixa "não atribuídos" zerada', texto: 'Lead sem dono por mais de 15 min dispara alerta no #comercial-alertas.' },
];

function Distribuicao({ vendedores, gestor, flash }: { vendedores: Vendedor[]; gestor: boolean; flash: (m: string) => void }) {
  const [rascunho, setRascunho] = useState<RascunhoDistribuicao>(() => rascunhoDe(vendedores));
  const [salvando, setSalvando] = useState(false);
  const rNegocios = useDados(() => repo.negocios());
  const rConfig = useDados(() => repo.config());
  const negocios = rNegocios.dados;
  const est = estadoDistribuicao(vendedores, rascunho);
  const simulados = simularDistribuicao(aplicarRascunho(vendedores, rascunho), 10);
  const nome = (id: string | null) => (id ? vendedores.find((v) => v.id === id)?.nome ?? '—' : 'Ninguém elegível');
  const semDono = (negocios ?? []).filter((n) => n.status === 'aberto' && !n.donoId).length;
  const recebendo = vendedores.filter((v) => (rascunho[v.id] ?? v).ativo).length;

  const mudar = (id: string, p: Partial<{ percentual: number; ativo: boolean }>) =>
    setRascunho((r) => ({ ...r, [id]: { ...r[id], ...p } }));

  async function salvar() {
    setSalvando(true);
    const r = await repo.salvarDistribuicao(rascunho);
    setSalvando(false);
    if (r.ok) { flash('Distribuição salva.'); avisarMudanca(); } else flash(r.msg ?? 'Não foi possível salvar.');
  }

  return (
    <div className="space-y-4">
      <FaixaNumeros itens={[
        {
          rotulo: 'Não atribuídos agora',
          valor: rNegocios.erro ? '—' : negocios ? semDono : '…',
          alerta: semDono > 0,
          metrica: 'sem_dono',
        },
        { rotulo: 'Recebendo leads', valor: `${recebendo} de ${vendedores.length}`, info: INFO.recebendo },
        { rotulo: 'Soma dos ativos', valor: `${est.soma}%`, alerta: !est.valida, info: INFO.soma },
      ]} />

      <div className="grid gap-4 xl:grid-cols-[3fr_2fr]">
        <div className="min-w-0 space-y-4">
          <SectionCard
            title={<>Percentual por vendedor <InfoIndicador texto={INFO.percentual} className="font-normal" /></>}
            subtitle="A soma dos ativos precisa dar 100%. O gestor fica com 0% para não disputar lead com o time."
          >
            {/* Uma linha por vendedor que quebra em tela estreita (sem tabela com rolagem). */}
            <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)]">
              {vendedores.map((v) => {
                const r = rascunho[v.id] ?? { percentual: v.percentual, ativo: v.ativo };
                return (
                  <li key={v.id} className="flex flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2.5">
                    <div className="min-w-0 flex-1 basis-48">
                      <Pessoa nome={v.nome} sub={`${v.papel === 'gestor' ? 'Gestor' : 'Vendedor'} · sigla ${v.sigla}`} size={28} />
                    </div>
                    <Toggle checked={r.ativo} disabled={!gestor} onChange={(ativo) => mudar(v.id, { ativo })} label={r.ativo ? 'Recebe' : 'Fora'} />
                    <div className="inline-flex items-center gap-1.5">
                      <Input
                        type="number" min={0} max={100} step={5} inputMode="numeric"
                        value={r.percentual}
                        disabled={!gestor || !r.ativo}
                        onChange={(e) => mudar(v.id, { percentual: normalizarPercentual(e.target.value) })}
                        aria-label={`Percentual de ${v.nome}`}
                        className="!w-20 text-right tabular"
                      />
                      <span className="text-sm text-[var(--fg-3)]">%</span>
                    </div>
                  </li>
                );
              })}
              <li className="flex items-center justify-between gap-3 bg-[var(--surface-3)] px-3 py-2.5 rounded-b-[var(--r-md)]">
                <span className="text-sm font-semibold text-[var(--fg)]">Soma dos ativos</span>
                <span className={`text-sm font-semibold tabular ${est.valida ? 'text-[var(--fg)]' : 'text-[var(--red)]'}`}>{est.soma}%</span>
              </li>
            </ul>
            {!est.valida && <p className="mt-2 text-xs text-[var(--red)]">A soma está em {est.soma}%: ajuste para 100% antes de salvar.</p>}

            {/* Rodapé fixo da seção: só aparece quando há alteração (e só para o gestor). */}
            {gestor && est.alterada && (
              <div className="sticky bottom-0 -mx-5 -mb-5 mt-4 flex flex-wrap items-center gap-2 rounded-b-[var(--r-lg)] border-t border-[var(--border)] bg-[var(--surface-2)] px-5 py-3">
                <span className="text-xs text-[var(--fg-3)]">Alteração não salva</span>
                <span className="flex-1" />
                <Button size="sm" variant="ghost" disabled={salvando} onClick={() => setRascunho(rascunhoDe(vendedores))}>Desfazer</Button>
                <Button size="sm" disabled={!est.valida || salvando} onClick={salvar}><Icon name="check" size={14} /> {salvando ? 'Salvando…' : 'Salvar'}</Button>
              </div>
            )}
          </SectionCard>

          <SectionCard title={<>Simulador <InfoIndicador texto={INFO.simulador} className="font-normal" /></>} subtitle="Com o percentual acima, os próximos 10 leads sem dono iriam para:">
            <ol className="flex flex-wrap gap-2">
              {simulados.map((id, i) => (
                <li key={i} className="inline-flex items-center gap-1.5 rounded-[var(--r-sm)] border border-[var(--border)] bg-[var(--surface-3)] px-2 py-1 text-xs">
                  <span className="tabular text-[var(--fg-3)]">{i + 1}.</span>
                  <span className={id ? 'text-[var(--fg)]' : 'text-[var(--red)]'}>{nome(id)}</span>
                </li>
              ))}
            </ol>
            <NotaRodape className="mt-2">Contato que já tem dono não entra nessa conta: continua com o dono dele.</NotaRodape>
          </SectionCard>
        </div>

        <div className="min-w-0 space-y-4">
          <SectionCard title="Regras da distribuição">
            <ul className="space-y-3">
              {REGRAS_DISTRIBUICAO.map((r) => (
                <li key={r.titulo} className="flex gap-2.5">
                  <Icon name="check-circle" size={14} className="mt-0.5 shrink-0 text-[var(--fg-3)]" />
                  <div className="min-w-0">
                    <div className="text-sm font-medium text-[var(--fg)]">{r.titulo}</div>
                    <div className="text-xs text-[var(--fg-2)] leading-relaxed">{r.texto}</div>
                  </div>
                </li>
              ))}
            </ul>
          </SectionCard>

          <SectionCard title="Operação" subtitle="Valores de partida; o gestor fecha depois de 30 dias de dado.">
            <Carregando dados={rConfig.dados} erro={rConfig.erro} onTentar={() => { void rConfig.recarregar(); }} esqueleto={<Loading minHeight={80} />}>
              {(config) => <ConfigOperacao config={config} />}
            </Carregando>
          </SectionCard>
        </div>
      </div>
    </div>
  );
}

function ConfigOperacao({ config }: { config: ConfigComercial }) {
  return (
    <dl className="space-y-3 text-sm">
      <div>
        <dt className="text-xs text-[var(--fg-3)]">Horário de contato com lead</dt>
        <dd className="text-[var(--fg)]">{config.horarioContato}</dd>
      </div>
      <div>
        <dt className="text-xs text-[var(--fg-3)]">Limite de negócios abertos por vendedor <InfoIndicador metrica="abertos" /></dt>
        <dd className="text-[var(--fg)]">{config.limiteNegociosAbertos ?? 'A definir depois de 30 dias de dado'}</dd>
      </div>
    </dl>
  );
}

// ── #funil ──

/** Referência do playbook: o construtor de funis (EditorFunil) é onde se cria e edita. */
function FunilConfig({ gestor }: { gestor: boolean }) {
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <p className="text-sm text-[var(--fg-2)] min-w-0">
          Modelo do playbook (Venda ativa): o ponto de partida de todo funil novo. Funis, etapas e campanhas se editam no construtor.
        </p>
        <Link href="/comercial/funil" className={CLS_LINK_GHOST}>
          <Icon name="kanban" size={14} /> {gestor ? 'Editar funis' : 'Abrir os funis'}
        </Link>
      </div>

      <div>
        <SectionTitle right={<span className="inline-flex items-center gap-1 text-[11px] text-[var(--fg-3)]">Prazo atenção / crítico <InfoIndicador texto={INFO.sla} /></span>}>
          Etapas do modelo
        </SectionTitle>
        {/* Uma etapa por cartão (sem tabela larga): duas colunas em tela grande. */}
        <ol className="grid gap-2 lg:grid-cols-2">
          {ETAPAS.map((e, i) => (
            <li key={e.key} className="min-w-0">
              <Card className="h-full p-3 space-y-1">
                <div className="flex items-baseline justify-between gap-3">
                  <span className="text-sm font-medium text-[var(--fg)]"><span className="tabular text-[var(--fg-3)] mr-1.5">{i + 1}.</span>{e.label}</span>
                  <span className="text-xs tabular text-[var(--fg-3)] whitespace-nowrap" title="Atenção / crítico">{textoSla(e.slaAtencaoMin, e.slaCriticoMin)}</span>
                </div>
                <p className="text-xs text-[var(--fg-2)]">{e.descricao}</p>
                {e.criterio && <p className="text-xs text-[var(--fg-3)]">Para passar: {e.criterio}</p>}
                {e.camposObrigatorios.length > 0 && (
                  <p className="text-xs text-[var(--fg-3)]">Obrigatórios para entrar: {e.camposObrigatorios.map((c) => ROTULO_CAMPO[c]).join(', ')}</p>
                )}
              </Card>
            </li>
          ))}
        </ol>
        <NotaRodape className="mt-1.5">&quot;Fechado&quot; só pela Hotmart: ganho é pagamento aprovado, ninguém arrasta para lá.</NotaRodape>
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <SectionCard title="Origens automáticas da Hotmart" subtitle="Nascem sozinhas pelo webhook; o vendedor não cria.">
          <ul className="grid gap-x-4 gap-y-1.5 sm:grid-cols-2 text-sm text-[var(--fg-2)]">
            {ORIGENS_HOTMART.map((o) => (
              <li key={o} className="flex items-center gap-2">
                <Icon name="zap" size={13} className="shrink-0 text-[var(--fg-3)]" />{ROTULO_ORIGEM[o]}
              </li>
            ))}
          </ul>
        </SectionCard>

        <SectionCard
          title="Produtos (agrupadores)"
          subtitle="Escada A = serviço do escritório (cliente final). Escada B = infoproduto (profissional). Nunca misturar."
          right={<span className="inline-flex shrink-0 items-center gap-1 text-xs text-[var(--fg-3)]">Ticket <InfoIndicador texto={INFO.ticket} /></span>}
        >
          <ul className="divide-y divide-[var(--border-faint)]">
            {PRODUTOS.map((p) => (
              <li key={p.key} className="flex flex-wrap items-center justify-between gap-x-3 gap-y-1 py-2 first:pt-0 last:pb-0">
                <span className="min-w-0"><ProdutoTag k={p.key} /></span>
                <span className="flex items-center gap-3">
                  <span className="text-xs text-[var(--fg-3)]">{p.escada === 'A' ? 'A · serviço' : 'B · infoproduto'}</span>
                  <span className="tabular text-sm text-[var(--fg)]">{p.ticket.toLocaleString('pt-BR', { style: 'currency', currency: 'BRL', maximumFractionDigits: 0 })}</span>
                </span>
              </li>
            ))}
          </ul>
        </SectionCard>
      </div>
    </div>
  );
}

/** "30 min / 2 h" ou "—" quando a etapa não tem prazo. */
function textoSla(atencao: number | null | undefined, critico: number | null | undefined): string {
  if (atencao == null && critico == null) return '—';
  return `${atencao == null ? '—' : fmtMinutos(atencao)} / ${critico == null ? '—' : fmtMinutos(critico)}`;
}

// ── #links ──

const CANAIS = ['whatsapp', 'ligacao', 'email', 'instagram', 'grupo'];
const ROTULO_CANAL: Record<string, string> = { whatsapp: 'WhatsApp', ligacao: 'Ligação', email: 'E-mail', instagram: 'Instagram', grupo: 'Grupo' };

function Links({ vendedores, meuId, gestor, nomeDe, flash }: {
  vendedores: Vendedor[]; meuId: string; gestor: boolean; nomeDe: (id: string | null) => string; flash: (m: string) => void;
}) {
  const rLinks = useDados(() => repo.links());
  const [filtro, setFiltro] = useState<string>('todos');

  return (
    <div className="space-y-4">
      <SectionCard title="Como o link é montado" subtitle="Toda venda precisa dizer de onde veio e quem vendeu.">
        <ul className="grid gap-2 md:grid-cols-3 text-xs text-[var(--fg-2)]">
          <li><code className="text-[var(--fg)]">utm_campaign</code> = chave do projeto (ex.: ht33-meteorico)</li>
          <li><code className="text-[var(--fg)]">utm_content</code> = código da mensagem (o mesmo da ficha de disparo)</li>
          <li><code className="text-[var(--fg)]">sck</code> = produto-acao-data-canal-sigla do vendedor</li>
        </ul>
      </SectionCard>

      <NovoLink key={meuId} vendedores={vendedores} meuId={meuId} gestor={gestor} flash={flash} />

      <div>
        <SectionTitle right={
          <FilterSelect value={filtro} onChange={(e) => setFiltro(e.target.value)} aria-label="Filtrar por vendedor" className="!py-1 !text-xs">
            <option value="todos">Todos os vendedores</option>
            {vendedores.map((v) => <option key={v.id} value={v.id}>{v.nome}</option>)}
          </FilterSelect>
        }>Links por vendedor</SectionTitle>
        <Carregando
          dados={rLinks.dados}
          erro={rLinks.erro}
          onTentar={() => { void rLinks.recarregar(); }}
          esqueleto={<EsqueletoLista linhas={3} avatar={false} />}
        >
          {(links) => {
            const lista = links.filter((l) => filtro === 'todos' || l.vendedorId === filtro);
            if (!lista.length) {
              return (
                <Card>
                  <Vazio
                    titulo={links.length ? 'Nenhum link deste vendedor' : 'Nenhum link ainda'}
                    hint={links.length ? undefined : 'Crie o primeiro no formulário acima.'}
                    icone="link"
                    acao={links.length ? <Button size="sm" variant="ghost" onClick={() => setFiltro('todos')}>Limpar filtro</Button> : undefined}
                  />
                </Card>
              );
            }
            return (
              // Um cartão por link (sem tabela larga): duas colunas em tela grande.
              <ul className="grid gap-2 xl:grid-cols-2">
                {lista.map((l) => <CartaoLink key={l.id} l={l} nomeDe={nomeDe} flash={flash} />)}
              </ul>
            );
          }}
        </Carregando>
      </div>
    </div>
  );
}

function copiadorDeLink(l: LinkRastreavel, flash: (m: string) => void) {
  return async () => {
    try { await navigator.clipboard.writeText(l.url); flash('Link copiado.'); } catch { flash('Não foi possível copiar.'); }
  };
}

function CartaoLink({ l, nomeDe, flash }: { l: LinkRastreavel; nomeDe: (id: string | null) => string; flash: (m: string) => void }) {
  const copiar = copiadorDeLink(l, flash);
  return (
    <li>
      <Card className="h-full p-3 flex items-start justify-between gap-3">
        <div className="min-w-0 flex-1 space-y-0.5">
          <code className="block text-xs text-[var(--fg)] break-all">{l.sck}</code>
          <div className="flex flex-wrap items-center gap-x-2 text-xs text-[var(--fg-3)]">
            <span>{nomeDe(l.vendedorId)}</span><span aria-hidden>·</span><ProdutoTag k={l.produto} /><span aria-hidden>·</span><span>{l.acao}</span>
          </div>
          <span className="block truncate text-[11px] text-[var(--fg-4)]" title={l.url}>{l.url}</span>
        </div>
        <Button size="sm" variant="ghost" onClick={copiar} aria-label={`Copiar link ${l.sck}`} className="shrink-0 min-h-8"><Icon name="copy" size={14} /> Copiar</Button>
      </Card>
    </li>
  );
}

function NovoLink({ vendedores, meuId, gestor, flash }: { vendedores: Vendedor[]; meuId: string; gestor: boolean; flash: (m: string) => void }) {
  const [vendedorId, setVendedorId] = useState(meuId);
  const [produto, setProduto] = useState<ProdutoKey>('hm');
  const [acao, setAcao] = useState('');
  const [canal, setCanal] = useState('whatsapp');
  const [hoje] = useState(() => new Date());
  const [enviando, setEnviando] = useState(false);
  // Vendedor cria link só para si; o gestor cria para qualquer um.
  const opcoes = gestor ? vendedores : vendedores.filter((v) => v.id === meuId);
  const sigla = vendedores.find((v) => v.id === vendedorId)?.sigla;
  const sck = previaSck(produto, acao, canal, sigla, hoje);

  async function criar() {
    setEnviando(true);
    const r = await repo.criarLink(vendedorId, produto, acao, canal);
    setEnviando(false);
    if (r.ok) { flash('Link criado.'); setAcao(''); avisarMudanca(); } else flash(r.msg ?? 'Não foi possível criar.');
  }

  return (
    <SectionCard title="Novo link" subtitle="Um link por vendedor, produto e ação. A data entra sozinha.">
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Campo rotulo="Vendedor" dica={gestor ? undefined : 'Você cria link só para você.'}>
          <FilterSelect value={vendedorId} onChange={(e) => setVendedorId(e.target.value)} disabled={!gestor} className="w-full">
            {opcoes.map((v) => <option key={v.id} value={v.id}>{v.nome} ({v.sigla})</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Produto">
          <FilterSelect value={produto} onChange={(e) => setProduto(e.target.value as ProdutoKey)} className="w-full">
            {PRODUTOS.map((p) => <option key={p.key} value={p.key}>{p.nome}</option>)}
          </FilterSelect>
        </Campo>
        <Campo rotulo="Ação">
          <Input value={acao} onChange={(e) => setAcao(e.target.value)} placeholder="ex.: recuperacao, abordagem" maxLength={30} />
        </Campo>
        <Campo rotulo="Canal">
          <FilterSelect value={canal} onChange={(e) => setCanal(e.target.value)} className="w-full">
            {CANAIS.map((c) => <option key={c} value={c}>{ROTULO_CANAL[c]}</option>)}
          </FilterSelect>
        </Campo>
      </div>
      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <div className="min-w-0 text-xs text-[var(--fg-3)]" aria-live="polite">
          SCK: {sck ? <code className="text-sm text-[var(--fg)] break-all">{sck}</code> : <span>preencha a ação</span>}
        </div>
        <Button size="sm" disabled={!sck || enviando} onClick={criar}><Icon name="plus" size={14} /> {enviando ? 'Criando…' : 'Criar link'}</Button>
      </div>
    </SectionCard>
  );
}
