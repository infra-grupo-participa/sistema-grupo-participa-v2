'use client';

// Disparo por API com ficha (playbook, seção 7): fichas, agenda com a regra das 48 h e templates.
import { useMemo, useState } from 'react';
import { Badge, Button, Card, Loading, SectionTitle, Tabs, Toast, useFlash } from '@/shared/ui/components';
import { fmtDataHora } from '@/shared/ui/format';
import { Icon } from '@/shared/ui/icons';
import type { NovaFicha } from '../../application/ports';
import { produto as produtoDe, ROTULO_STATUS_FICHA, TOM_STATUS_FICHA } from '../../domain/catalogo';
import { montarSck } from '../../domain/regras';
import type { FichaDisparo, ProdutoKey, Template } from '../../domain/types';
import { EstadoErro, FaixaNumeros, PaginaComercial, useAbaHash, useEquipe, Vazio } from '../comum';
import { InfoIndicador } from '../InfoIndicador';
import { avisarMudanca, repo, useAgora, useDados } from '../repositorio';
import { DetalheFicha, NovaFichaModal, TextoTemplate } from './FichaModais';
import { INFO_DISPARO } from './indicadores';
import { contaNaAgenda, diasDaAgenda, fichasEmConflito, mesmoDia, resumoDisparos, taxasResultado } from './regras-disparo';

const ABAS = ['fichas', 'agenda', 'templates'] as const;
type Aba = (typeof ABAS)[number];

export function DisparosClient() {
  const agora = useAgora(60_000);
  const { sessao, vendedores, nomeDe, gestor } = useEquipe();
  const fichasQ = useDados(() => repo.fichas());
  const templatesQ = useDados(() => repo.templates());
  const contatosQ = useDados(() => repo.contatos());
  const negociosQ = useDados(() => repo.negocios());
  // Só o teto de destinatários; se falhar, a ficha segue (o banco confere o limite ao salvar).
  const { dados: whatsapp } = useDados(() => repo.whatsappStatus());
  const { dados: fichas } = fichasQ;
  const { dados: templates } = templatesQ;
  const { dados: contatos } = contatosQ;
  const { dados: negocios } = negociosQ;
  const [aba, setAba] = useAbaHash<Aba>(ABAS, 'fichas');
  const [aberta, setAberta] = useState<string | null>(null);
  const [nova, setNova] = useState(false);
  const { toast, flash } = useFlash();

  const eu = vendedores.find((v) => v.id === sessao?.vendedorId) ?? null;
  const podeDisparar = !!eu?.disparaApi;
  const conflitos = useMemo(() => fichasEmConflito(fichas ?? []), [fichas]);
  const resumo = useMemo(() => resumoDisparos(fichas ?? [], agora), [fichas, agora]);
  const aguardando = resumo.aguardando;
  const fichaAberta = aberta ? fichas?.find((f) => f.id === aberta) : undefined;

  async function decidir(id: string, aprovar: boolean) {
    const r = await repo.decidirFicha(id, aprovar);
    flash(r.ok ? (aprovar ? 'Ficha aprovada.' : 'Ficha reprovada.') : r.msg ?? 'Não foi possível decidir.');
    if (r.ok) { avisarMudanca(); setAberta(null); }
  }

  async function salvar(f: NovaFicha, enviar: boolean): Promise<string | null> {
    const r = await repo.salvarFicha(f, enviar);
    if (!r.ok) return r.msg ?? 'Não foi possível salvar.';
    const conta = r.quantidade !== undefined ? ` ${r.quantidade.toLocaleString('pt-BR')} contatos, ${(r.suprimidos ?? 0).toLocaleString('pt-BR')} suprimidos.` : '';
    flash(`${r.msg ?? 'Ficha salva.'}${conta}`);
    setNova(false);
    avisarMudanca();
    return null;
  }

  /** Link da ficha pelo banco (oferta vigente + SCK). Já existindo o mesmo SCK hoje, reaproveita. */
  async function gerarLink(produto: ProdutoKey, acao: string): Promise<{ url: string } | { erro: string }> {
    if (!eu) return { erro: 'Sessão sem vendedor.' };
    const r = await repo.criarLink(eu.id, produto, acao, 'whatsapp');
    if (r.ok && r.url) { avisarMudanca(); return { url: r.url }; }
    if (r.msg === 'Este link já existe.') {
      const sck = montarSck(produto, acao, agora, 'whatsapp', eu.sigla);
      try {
        const existente = (await repo.links()).find((l) => l.sck === sck && l.vendedorId === eu.id);
        if (existente) return { url: existente.url };
      } catch (e) {
        return { erro: e instanceof Error ? e.message : 'Não foi possível ler os links.' };
      }
    }
    return { erro: r.msg ?? 'Não foi possível gerar o link.' };
  }

  const carregando = !fichas || !templates || !contatos || !negocios || !sessao;
  const erro = fichasQ.erro ?? templatesQ.erro ?? contatosQ.erro ?? negociosQ.erro;
  const tentarDeNovo = () => { fichasQ.recarregar(); templatesQ.recarregar(); contatosQ.recarregar(); negociosQ.recarregar(); };
  const botaoNova = (
    <span title={podeDisparar ? undefined : 'Seu usuário não opera disparo por API. Peça ao Jonathan.'}>
      <Button size="sm" disabled={!podeDisparar} onClick={() => setNova(true)}><Icon name="plus" size={14} /> Nova ficha</Button>
    </span>
  );

  return (
    <PaginaComercial
      titulo="Disparos"
      subtitulo="Fichas, agenda e templates do disparo por API. Todo disparo entra na agenda e no log."
      acoes={botaoNova}
      meta={!carregando && (
        <FaixaNumeros
          rotulo="Disparos"
          itens={[
            {
              rotulo: 'Aguardando aprovação', valor: resumo.aguardando, alerta: gestor && resumo.aguardando > 0, info: INFO_DISPARO.aguardando,
              title: 'Ver as fichas', onClick: () => setAba('fichas'),
            },
            { rotulo: 'Próximos 7 dias', valor: resumo.proximos7, info: INFO_DISPARO.proximos7, title: 'Ver a agenda', onClick: () => setAba('agenda') },
            {
              rotulo: 'Conflitos 48 h', valor: resumo.conflitos, alerta: resumo.conflitos > 0, info: INFO_DISPARO.conflitos,
              title: 'Ver a agenda', onClick: () => setAba('agenda'),
            },
            { rotulo: 'Leitura', valor: resumo.leitura == null ? '—' : `${resumo.leitura}%`, info: INFO_DISPARO.leitura },
            { rotulo: 'Resposta', valor: resumo.resposta == null ? '—' : `${resumo.resposta}%`, info: INFO_DISPARO.resposta },
          ]}
        />
      )}
    >
      <Tabs
        label="Disparos"
        active={aba}
        onChange={(k) => setAba(k as Aba)}
        tabs={[
          { k: 'fichas', l: 'Fichas', n: gestor && aguardando ? aguardando : undefined },
          { k: 'agenda', l: 'Agenda', n: conflitos.size ? conflitos.size : undefined },
          { k: 'templates', l: 'Templates' },
        ]}
      />

      {erro && carregando ? <EstadoErro mensagem={erro} onTentar={tentarDeNovo} /> : carregando ? <Loading /> : (
        <>
          {aba === 'fichas' && (
            <>
              {sessao && eu && !podeDisparar && (
                <p className="mb-3 text-[11px] text-[var(--fg-3)]">Você consulta a agenda; disparo é com o Jonathan.</p>
              )}
              <AbaFichas
                fichas={fichas} templates={templates} nomeDe={nomeDe} gestor={gestor} conflitos={conflitos} onAbrir={setAberta}
                acaoVazia={podeDisparar ? <Button size="sm" variant="ghost" onClick={() => setNova(true)}><Icon name="plus" size={14} /> Nova ficha</Button> : undefined}
              />
            </>
          )}
          {aba === 'agenda' && <AbaAgenda fichas={fichas} agora={agora} conflitos={conflitos} nomeDe={nomeDe} onAbrir={setAberta} />}
          {aba === 'templates' && <AbaTemplates templates={templates} />}
        </>
      )}

      {fichaAberta && templates && (
        <DetalheFicha f={fichaAberta} templates={templates} nomeDe={nomeDe} gestor={gestor} onDecidir={(a) => decidir(fichaAberta.id, a)} onClose={() => setAberta(null)} />
      )}
      {nova && eu && podeDisparar && contatos && negocios && templates && fichas && (
        <NovaFichaModal
          eu={eu} gestor={gestor} contatos={contatos} negocios={negocios} templates={templates} fichas={fichas} agora={agora}
          maxDestinatarios={whatsapp?.maxDestinatarios ?? null}
          onSalvar={salvar} onGerarLink={gerarLink} onClose={() => setNova(false)}
        />
      )}
      <Toast>{toast}</Toast>
    </PaginaComercial>
  );
}

const pct = (n: number) => `${n.toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;

/** Resultado em uma linha (taxas); entregues e falhas completos no title e na ficha. Falhas em vermelho quando houver. */
function Resultado({ f }: { f: FichaDisparo }) {
  if (!f.resultado) return <span className="text-xs text-[var(--fg-3)]">—</span>;
  const r = f.resultado;
  const tx = taxasResultado(r);
  return (
    <span
      className="block truncate text-xs tabular text-[var(--fg-2)]"
      title={`${r.entregues.toLocaleString('pt-BR')} entregues · ${r.lidas.toLocaleString('pt-BR')} lidas · ${r.respostas.toLocaleString('pt-BR')} respostas · ${r.falhas.toLocaleString('pt-BR')} falhas (${pct(tx.falha)})`}
    >
      {pct(tx.leitura)} lidas · {pct(tx.resposta)} resp.
      {r.falhas > 0 && <span className="text-[var(--red)]"> · {r.falhas.toLocaleString('pt-BR')} falhas</span>}
    </span>
  );
}

/** Quantos recebem de fato (lista − supressões), com o cálculo no title. */
function Recebem({ f }: { f: FichaDisparo }) {
  const n = Math.max(0, f.quantidade - f.suprimidos);
  return (
    <span className="tabular" title={`${f.quantidade.toLocaleString('pt-BR')} na lista − ${f.suprimidos.toLocaleString('pt-BR')} suprimidos = ${n.toLocaleString('pt-BR')} recebem`}>
      {n.toLocaleString('pt-BR')}
    </span>
  );
}

function Conflito() {
  return (
    <span className="inline-flex items-center gap-1 text-[11px] font-medium text-[var(--yellow)]" title="Duas fichas do mesmo produto a menos de 48 h">
      <Icon name="alert" size={12} /> conflito 48 h
    </span>
  );
}

function AbaFichas({ fichas, templates, nomeDe, gestor, conflitos, onAbrir, acaoVazia }: {
  fichas: FichaDisparo[]; templates: Template[]; nomeDe: (id: string | null) => string; gestor: boolean;
  conflitos: Set<string>; onAbrir: (id: string) => void; acaoVazia?: React.ReactNode;
}) {
  // Aguardando aprovação sobe para o topo; o resto mantém a ordem do repositório (sort estável).
  const ordenadas = useMemo(
    () => [...fichas].sort((a, b) => Number(b.status === 'aguardando_aprovacao') - Number(a.status === 'aguardando_aprovacao')),
    [fichas],
  );
  if (!fichas.length) {
    return <Vazio titulo="Nenhuma ficha ainda" icone="send" hint="Toda ficha nova entra aqui como rascunho ou aguardando aprovação." acao={acaoVazia} />;
  }
  const decide = (f: FichaDisparo) => gestor && f.status === 'aguardando_aprovacao';
  return (
    // Sem tabela: em contêiner largo (≥ 768px) cada ficha é uma linha de 6 colunas que cabem; abaixo, cartão.
    <div className="@container">
      <div className={`hidden @3xl:grid ${COLUNAS_FICHA} items-center gap-x-3 px-3 pb-1.5 text-[11px] font-semibold uppercase tracking-wide text-[var(--fg-3)]`}>
        <span>Código</span>
        <span>Objetivo</span>
        <span>Agendado · operador</span>
        <span className="inline-flex items-center justify-end">Recebem<InfoIndicador texto={INFO_DISPARO.recebem} className="normal-case tracking-normal font-normal" /></span>
        <span>Status</span>
        <span className="inline-flex items-center">Resultado<InfoIndicador texto={INFO_DISPARO.resultado} className="normal-case tracking-normal font-normal" /></span>
      </div>
      <ul className="space-y-2 @3xl:space-y-0 @3xl:divide-y @3xl:divide-[var(--border-faint)] @3xl:rounded-[var(--r-md)] @3xl:border @3xl:border-[var(--border)] @3xl:bg-[var(--surface-2)]">
        {ordenadas.map((f) => {
          const t = templates.find((x) => x.id === f.templateId);
          const rotulo = `Abrir ficha ${f.codigo}${decide(f) ? ', aguardando sua decisão' : ''}`;
          return (
            <li key={f.id}>
              {/* Contêiner largo: linha. */}
              <button
                type="button"
                onClick={() => onAbrir(f.id)}
                aria-label={rotulo}
                className={`hidden @3xl:grid w-full ${COLUNAS_FICHA} items-center gap-x-3 px-3 py-2 text-left hover:bg-[var(--surface-3)]`}
              >
                <span className="min-w-0">
                  <span className="block text-xs font-semibold tabular text-[var(--fg)]">{f.codigo}</span>
                  {conflitos.has(f.id) && <span className="block mt-0.5"><Conflito /></span>}
                </span>
                <span className="min-w-0">
                  <span className="block text-sm text-[var(--fg)] truncate" title={f.objetivo}>{f.objetivo}</span>
                  <span className="block text-xs text-[var(--fg-3)] truncate">{produtoDe(f.produto).nome}{t ? ` · ${t.nome}` : ''}</span>
                </span>
                <span className="min-w-0">
                  <span className="block text-xs tabular text-[var(--fg-2)] truncate">{fmtDataHora(f.agendadoPara)}</span>
                  <span className="block text-xs text-[var(--fg-3)] truncate">{nomeDe(f.operadorId)}</span>
                </span>
                <span className="text-right text-sm"><Recebem f={f} /></span>
                <span><Badge tone={TOM_STATUS_FICHA[f.status]}>{ROTULO_STATUS_FICHA[f.status]}</Badge></span>
                <span className="min-w-0"><Resultado f={f} /></span>
              </button>
              {/* Contêiner estreito: cartão. */}
              <button
                type="button"
                onClick={() => onAbrir(f.id)}
                aria-label={rotulo}
                className="@3xl:hidden w-full text-left rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)] p-3 hover:bg-[var(--surface-3)]"
              >
                <span className="flex items-start justify-between gap-3">
                  <span className="min-w-0">
                    <span className="block text-sm text-[var(--fg)] truncate">{f.objetivo}</span>
                    <span className="block text-xs text-[var(--fg-3)] tabular">{f.codigo} · {fmtDataHora(f.agendadoPara)}</span>
                  </span>
                  <Badge tone={TOM_STATUS_FICHA[f.status]}>{ROTULO_STATUS_FICHA[f.status]}</Badge>
                </span>
                <span className="mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-[var(--fg-2)]">
                  <span>{nomeDe(f.operadorId)}</span>
                  <span><Recebem f={f} /> recebem</span>
                  {conflitos.has(f.id) && <Conflito />}
                </span>
                {f.resultado && <span className="mt-1 block"><Resultado f={f} /></span>}
              </button>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

const COLUNAS_FICHA = 'grid-cols-[88px_minmax(0,2fr)_minmax(0,1.1fr)_76px_auto_minmax(0,1.3fr)]';

const hora = (iso: string) => new Date(iso).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' });
const diaCurto = (d: Date) => d.toLocaleDateString('pt-BR', { weekday: 'short', day: '2-digit', month: '2-digit' }).replace('.', '');

function tituloDia(d: Date, agora: Date): string {
  const desloc = (n: number) => { const x = new Date(agora); x.setDate(x.getDate() + n); return x; };
  if (mesmoDia(d, agora)) return 'Hoje';
  if (mesmoDia(d, desloc(1))) return 'Amanhã';
  if (mesmoDia(d, desloc(-1))) return 'Ontem';
  return diaCurto(d);
}

function AbaAgenda({ fichas, agora, conflitos, nomeDe, onAbrir }: {
  fichas: FichaDisparo[]; agora: Date; conflitos: Set<string>; nomeDe: (id: string | null) => string; onAbrir: (id: string) => void;
}) {
  const inicioHoje = new Date(agora.getFullYear(), agora.getMonth(), agora.getDate()).getTime();
  // Dias com ficha viram seção; dias livres seguidos viram uma linha só.
  const blocos = useMemo(() => {
    const out: ({ tipo: 'dia'; d: Date; fichas: FichaDisparo[] } | { tipo: 'livre'; dias: Date[] })[] = [];
    for (const d of diasDaAgenda(agora)) {
      const doDia = fichas.filter((f) => mesmoDia(new Date(f.agendadoPara), d)).sort((a, b) => a.agendadoPara.localeCompare(b.agendadoPara));
      const ultimo = out[out.length - 1];
      if (doDia.length) out.push({ tipo: 'dia', d, fichas: doDia });
      else if (ultimo?.tipo === 'livre') ultimo.dias.push(d);
      else out.push({ tipo: 'livre', dias: [d] });
    }
    return out;
  }, [fichas, agora]);

  return (
    <div className="space-y-5">
      <p className="text-[11px] leading-relaxed text-[var(--fg-3)]">
        Últimos 7 e próximos 7 dias. Conflito 48 h = duas fichas do mesmo produto a menos de 48 h: a mesma pessoa não recebe
        disparo da casa em 48 h. Rascunho e reprovada aparecem riscados e não entram na conta.
      </p>
      {blocos.map((b) => {
        if (b.tipo === 'livre') {
          const [ini, fim] = [b.dias[0], b.dias[b.dias.length - 1]];
          return (
            <p key={ini.toISOString()} className="text-xs text-[var(--fg-3)]">
              <span className="font-medium text-[var(--fg-2)]">Livre</span> · {b.dias.length === 1 ? tituloDia(ini, agora) : `${tituloDia(ini, agora)} a ${tituloDia(fim, agora)}`}
            </p>
          );
        }
        const passado = b.d.getTime() < inicioHoje;
        return (
          <section key={b.d.toISOString()} aria-label={tituloDia(b.d, agora)}>
            <SectionTitle right={<span className="text-[11px] tabular text-[var(--fg-3)]">{b.fichas.length} {b.fichas.length === 1 ? 'ficha' : 'fichas'}</span>}>
              {tituloDia(b.d, agora)}{['Hoje', 'Amanhã', 'Ontem'].includes(tituloDia(b.d, agora)) ? ` · ${diaCurto(b.d)}` : ''}
            </SectionTitle>
            <ul className="divide-y divide-[var(--border-faint)] rounded-[var(--r-md)] border border-[var(--border)] bg-[var(--surface-2)]">
              {b.fichas.map((f) => {
                const conflito = conflitos.has(f.id);
                const conta = contaNaAgenda(f);
                return (
                  <li key={f.id} className={conflito ? 'border-l-2 border-l-[var(--yellow-border-forte)]' : ''}>
                    <button
                      type="button"
                      onClick={() => onAbrir(f.id)}
                      className={`grid w-full grid-cols-[48px_minmax(0,1fr)_auto] items-center gap-x-3 gap-y-0.5 px-3 py-2 text-left hover:bg-[var(--surface-3)] ${passado || !conta ? 'opacity-70' : ''}`}
                    >
                      <span className={`text-sm font-semibold tabular ${conta ? 'text-[var(--fg)]' : 'text-[var(--fg-3)] line-through'}`}>{hora(f.agendadoPara)}</span>
                      <span className="min-w-0">
                        <span className={`block truncate text-sm text-[var(--fg)] ${conta ? '' : 'line-through'}`}>{f.objetivo}</span>
                        <span className="block truncate text-xs text-[var(--fg-3)]">
                          <span className="tabular">{f.codigo}</span> · {produtoDe(f.produto).nome} · {nomeDe(f.operadorId)}
                          {!conta && ` · ${ROTULO_STATUS_FICHA[f.status].toLowerCase()}, não conta`}
                        </span>
                      </span>
                      <span className="text-right">{conflito ? <Conflito /> : null}</span>
                    </button>
                  </li>
                );
              })}
            </ul>
          </section>
        );
      })}
      <LimitesEnvio />
    </div>
  );
}

function AbaTemplates({ templates }: { templates: Template[] }) {
  return (
    <>
      <p className="mb-3 text-[11px] text-[var(--fg-3)]">
        Template novo é aprovado pela Mensageria (Jéssica). Fora da janela de 24 h só sai template aprovado.
      </p>
      {!templates.length ? <Vazio titulo="Nenhum template" icone="message" hint="Peça à Mensageria (Jéssica) o primeiro template aprovado." /> : (
        <div className="grid gap-3 md:grid-cols-2">
          {templates.map((t) => (
            <Card key={t.id} className="p-4">
              <div className="flex items-start justify-between gap-3">
                <div className="min-w-0">
                  <div className="text-sm font-semibold text-[var(--fg)] break-all">{t.nome}</div>
                  <div className="text-xs text-[var(--fg-3)]">{t.categoria === 'utility' ? 'utilidade' : 'marketing'}</div>
                </div>
                <Badge tone={t.aprovado ? 'success' : 'warning'}>{t.aprovado ? 'Aprovado' : 'Pendente'}</Badge>
              </div>
              <p className="mt-2 text-[13px] leading-relaxed text-[var(--fg-2)]"><TextoTemplate texto={t.texto} /></p>
            </Card>
          ))}
        </div>
      )}
    </>
  );
}

function LimitesEnvio() {
  return (
    <section className="border-t border-[var(--border-faint)] pt-4">
      <SectionTitle>Limites de envio</SectionTitle>
      <ul className="grid gap-2 sm:grid-cols-3 text-xs text-[var(--fg-2)]">
        <li><strong className="font-medium text-[var(--fg)]">Número oficial (API):</strong> limite diário da Meta de 250 conversas, 1.000 depois da verificação.</li>
        <li><strong className="font-medium text-[var(--fg)]">Fora da API:</strong> 30 a 50 conversas novas por dia por número, intervalo irregular.</li>
        <li><strong className="font-medium text-[var(--fg)]">Agenda e log:</strong> todo disparo entra na agenda antes e no log depois.</li>
      </ul>
    </section>
  );
}
