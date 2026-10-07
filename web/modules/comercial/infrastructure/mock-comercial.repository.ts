// Repositório de DEMONSTRAÇÃO: cumpre o contrato `ComercialRepository` em memória, sem banco.
// O estado vive enquanto a aba estiver aberta (recarregar a página volta à base inicial).
// Aplica as mesmas regras de domínio que o backend vai aplicar, para a tela se comportar como a real.
import type {
  ComercialRepository, FiltroNegocios, NovaAtividade, NovaFicha, Resultado, ResultadoFicha, ResultadoLink, ResultadoTokenMcp,
} from '../application/ports';
import { linhasContatos, mapaDuplicados, paginarContatos, resumirContatos, type FiltroContatos } from '../domain/contatos';
import { produto as produtoDe, ROTULO_CAMPO } from '../domain/catalogo';
import { bloqueioMoverNoFunil, camposFaltandoNoFunil, etapaDoFunil, etapaInicial, validarFunil } from '../domain/funis';
import { escolherDono, montarSck, somaPercentuais } from '../domain/regras';
import { podeMexerNoNegocio } from '../domain/travas';
import type {
  CampoKey, Contato, Conversa, EscopoMcp, EtapaFunil, EventoTimeline, Funil, MotivoPerda, Negocio, PainelHotmart, ProdutoKey,
  SessaoComercial, StatusFila, StatusWhatsapp, TokenMcp, Vendedor,
} from '../domain/types';
import { funisDoProjeto } from '../domain/modelos';
import { situacaoSla } from '../domain/regras';
import type {
  MotivoPerdaConfig, Notificacao, PainelPessoa, PontoJornada, PreferenciasNotificacao, TipoPontoJornada, TipoProjeto,
} from '../domain/types';
import { extrairCodigoOferta } from '../domain/hotmart';
import type {
  AcaoLog, Dashboard, EntidadeLog, FiltroLog, LogCrm, OfertaHotmart, OfertaOrfa, ProdutoHotmart,
} from '../domain/types';
import { OFERTAS_DEMO, ORFAS_DEMO, PRODUTOS_DEMO } from './mock-catalogo';
import { gerarBaseDemo, painelPadrao, preferenciasPadrao, type BaseDemo } from './mock-dados';
import { validarAtivacao, type EdicaoAtivacao, type PainelAtivacao } from '../domain/ativacao';
import { modeloFunil } from '../domain/modelos';
import { evidenciaDemo, origemDemo, painelDemo, regrasDemo, resumoDeOrigem, type EstadoOrigemDemo } from './mock-catalogacao';
import { CHAVE_PROJETO, type OrigemDetalhada, type PainelCatalogo, type RegraCatalogo } from '../domain/catalogacao';
import { cadastroVazio, ehFunilAtivacao, painelAtivacaoDemo, SUFIXO_ATIVACAO, toquesDoNegocio, type CadastroAtivacao } from './mock-ativacao';

const LATENCIA_MS = 120;
const espera = <T,>(v: T): Promise<T> => new Promise((ok) => setTimeout(() => ok(structuredClone(v)), LATENCIA_MS));
const agoraIso = () => new Date().toISOString();

export class MockComercialRepository implements ComercialRepository {
  private db: BaseDemo;
  private eu: SessaoComercial = { vendedorId: 'v-jonathan', papel: 'gestor' };
  private seq = 0;

  constructor() {
    this.db = gerarBaseDemo();
    this.semearAtivacao();
    this.db.contatos.forEach((c, i) => this.origensCat.set(c.id, { evidencia: evidenciaDemo(c, i), manual: null }));
    this.catalogarDemo();
    // Registro inicial a partir do histórico da demonstração (o que o backend teria gravado).
    const acao: Partial<Record<EventoTimeline['tipo'], AcaoLog>> = { criado: 'criou', etapa: 'moveu_etapa', dono: 'trocou_dono', perdido: 'marcou_perdido', ganho: 'marcou_ganho', nota: 'criou' };
    this.logDb = this.db.eventos.filter((e) => acao[e.tipo] && e.negocioId).map((e) => ({
      id: `log-${e.id}`, em: e.em, autorId: e.tipo === 'ganho' ? null : e.autorId, acao: acao[e.tipo]!, entidade: 'negocio' as const,
      entidadeId: e.negocioId!, contatoId: e.contatoId, resumo: `${e.titulo} · ${this.db.contatos.find((c) => c.id === e.contatoId)?.nome ?? ''}`, mudancas: [],
    }));
  }

  private produtos: ProdutoHotmart[] = structuredClone(PRODUTOS_DEMO);
  private ofertasDb: OfertaHotmart[] = structuredClone(OFERTAS_DEMO);
  private dashboardsDb: Dashboard[] = [];
  private logDb: LogCrm[] = [];

  /** Toda manipulação vira uma linha no registro do CRM (no backend: trigger grava, a tela só lê). */
  private registrar(acao: AcaoLog, entidade: EntidadeLog, entidadeId: string, resumo: string, contatoId: string | null = null, mudancas: LogCrm['mudancas'] = []) {
    this.logDb.push({ id: this.novoId('log'), em: agoraIso(), autorId: this.eu.vendedorId, acao, entidade, entidadeId, contatoId, resumo, mudancas });
  }

  private nomeContato(id: string | null | undefined) {
    return this.db.contatos.find((c) => c.id === id)?.nome ?? 'contato';
  }

  private nomeVendedor(id: string | null | undefined) {
    return id ? this.db.vendedores.find((v) => v.id === id)?.nome ?? id : 'sem dono';
  }

  private novoId(p: string) {
    return `${p}-novo-${++this.seq}`;
  }

  private evento(e: Omit<EventoTimeline, 'id' | 'em' | 'autorId'> & { autorId?: string | null }) {
    this.db.eventos.push({ id: this.novoId('e'), em: agoraIso(), autorId: this.eu.vendedorId, ...e });
  }

  private negocio(id: string): Negocio | undefined {
    return this.db.negocios.find((n) => n.id === id);
  }

  /** Recalcula a próxima atividade aberta (a de vencimento mais próximo). */
  private atualizarProxima(negocioId: string | null) {
    if (!negocioId) return;
    const n = this.negocio(negocioId);
    if (!n) return;
    const abertas = this.db.atividades
      .filter((a) => a.negocioId === negocioId && !a.concluidaEm)
      .sort((a, b) => a.venceEm.localeCompare(b.venceEm));
    const a = abertas[0];
    n.proximaAtividade = a ? { id: a.id, tipo: a.tipo, titulo: a.titulo, venceEm: a.venceEm } : null;
  }

  // ── Leitura ──
  sessao() { return espera(this.eu); }
  vendedores() { return espera(this.db.vendedores); }
  config() { return espera(this.db.config); }
  contatos() { return espera(this.db.contatos); }
  /** Demonstração: a lista já tem todo mundo; a busca filtra por nome, e-mail ou dígitos do telefone. */
  buscarContatos(texto: string) {
    const q = texto.trim().toLowerCase();
    if (q.length < 3) return espera([] as Contato[]);
    const dig = q.replace(/\D/g, '');
    return espera(this.db.contatos.filter((c) => `${c.nome} ${c.email ?? ''}`.toLowerCase().includes(q)
      || (dig.length >= 4 && String(c.telefone ?? '').replace(/\D/g, '').includes(dig))).slice(0, 50));
  }
  /** Mesmas regras de crm_contatos_pagina (filtro, ordem, página), em memória. Lançamentos saem da jornada demo. */
  contatosPagina(f: FiltroContatos) {
    const linhas = linhasContatos(this.db.contatos, this.db.negocios, this.db.jornada);
    return espera(paginarContatos(linhas, f, (id) => (id ? this.nomeVendedor(id) : '')));
  }
  contatosResumo() { return espera(resumirContatos(this.db.contatos)); }
  contatosPorIds(ids: string[]) {
    const pedidos = new Set(ids);
    return espera(this.db.contatos.filter((c) => pedidos.has(c.id)));
  }
  duplicadosDe(contatoId: string) {
    const ids = mapaDuplicados(this.db.contatos).get(contatoId) ?? [];
    return espera(this.db.contatos.filter((c) => ids.includes(c.id)));
  }
  negocios(filtro: FiltroNegocios = {}) {
    return espera(this.db.negocios.filter((n) => (!filtro.contatoId || n.contatoId === filtro.contatoId)
      && (!filtro.funilId || n.funilId === filtro.funilId) && (!filtro.status || n.status === filtro.status)));
  }
  atividades() { return espera(this.db.atividades); }
  eventos(contatoId?: string) {
    const lista = contatoId ? this.db.eventos.filter((e) => e.contatoId === contatoId) : this.db.eventos;
    return espera([...lista].sort((a, b) => b.em.localeCompare(a.em)));
  }
  templates() { return espera(this.db.templates); }
  /** Demonstração: tudo ligado, número fictício. */
  whatsappStatus(): Promise<StatusWhatsapp> {
    return espera({
      whatsappLigado: true, envioLigado: true, escritaLigada: true,
      numero: { id: 'n-demo', nome: 'Comercial oficial (API)', final: '0000', ativo: true },
      templatesAprovados: this.db.templates.filter((t) => t.aprovado).length,
      naFila: 0, falhasHoje: 0, janelaHoras: 24, maxDestinatarios: 5000,
    });
  }
  filas() { return espera(this.db.filas); }
  fichas() { return espera([...this.db.fichas].sort((a, b) => b.criadoEm.localeCompare(a.criadoEm))); }
  links() { return espera(this.db.links); }

  mensagens(contatoId: string) {
    return espera(this.db.mensagens.filter((m) => m.contatoId === contatoId).sort((a, b) => a.em.localeCompare(b.em)));
  }

  conversas() {
    const porContato = new Map<string, Conversa>();
    const msgs = [...this.db.mensagens].sort((a, b) => a.em.localeCompare(b.em));
    for (const m of msgs) {
      if (m.canal !== 'whatsapp') continue;
      const atual = porContato.get(m.contatoId);
      const dono = this.db.contatos.find((c) => c.id === m.contatoId)?.donoId ?? null;
      const naoLidas = m.direcao === 'entrada' && !m.status ? (atual?.naoLidas ?? 0) + 1 : m.direcao === 'saida' ? 0 : atual?.naoLidas ?? 0;
      const janela = m.direcao === 'entrada' ? new Date(new Date(m.em).getTime() + 24 * 3600_000).toISOString() : atual?.janelaAteEm ?? null;
      porContato.set(m.contatoId, { contatoId: m.contatoId, ultimaMensagem: m, naoLidas, janelaAteEm: janela, atribuidaA: dono });
    }
    const agora = Date.now();
    const lista = [...porContato.values()].map((c) => ({ ...c, janelaAteEm: c.janelaAteEm && new Date(c.janelaAteEm).getTime() > agora ? c.janelaAteEm : null }));
    return espera(lista.sort((a, b) => b.ultimaMensagem.em.localeCompare(a.ultimaMensagem.em)));
  }

  // ── Escrita ──
  /** Copia para o negócio o que vem da etapa (nome, papel, alerta). */
  private aplicarEtapa(n: Negocio, e: EtapaFunil) {
    n.etapaId = e.id;
    n.etapaNome = e.nome;
    n.etapa = e.papel;
    n.sla = e.slaAtencaoMin != null && e.slaCriticoMin != null ? { atencaoMin: e.slaAtencaoMin, criticoMin: e.slaCriticoMin } : null;
    n.etapaDesde = agoraIso();
  }

  async moverEtapa(negocioId: string, etapaId: string): Promise<Resultado> {
    const n = this.negocio(negocioId);
    if (!n) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    if (!podeMexerNoNegocio(n, this.eu)) return espera({ ok: false, msg: 'Este negócio não é seu.' });
    const f = this.db.funis.find((x) => x.id === n.funilId);
    if (!f) return espera({ ok: false, msg: 'Funil do negócio não encontrado.' });
    if (n.etapaId === etapaId) return espera({ ok: true });
    const b = bloqueioMoverNoFunil(n, f, etapaId);
    if (b === 'ganho_so_com_pagamento') return espera({ ok: false, msg: 'Ganho é pagamento aprovado: o negócio fecha sozinho quando a Hotmart aprova.' });
    if (b === 'negocio_encerrado') return espera({ ok: false, msg: 'Negócio encerrado não muda de etapa.' });
    if (b === 'etapa_inexistente') return espera({ ok: false, msg: 'Etapa não existe neste funil.' });
    if (b === 'campos_faltando') {
      const faltam = camposFaltandoNoFunil(n, f, etapaId).map((c) => ROTULO_CAMPO[c]).join(', ');
      return espera({ ok: false, msg: `Preencha antes: ${faltam}.` });
    }
    const e = etapaDoFunil(f, etapaId)!;
    const de = n.etapaNome;
    this.aplicarEtapa(n, e);
    this.registrar('moveu_etapa', 'negocio', n.id, `Moveu ${this.nomeContato(n.contatoId)} de ${de} para ${e.nome}`, n.contatoId, [{ campo: 'etapa', antes: de, depois: e.nome }]);
    n.ultimaInteracaoEm = agoraIso();
    this.evento({ contatoId: n.contatoId, negocioId, tipo: 'etapa', titulo: `Moveu para ${e.nome}`, detalhe: e.papel });
    return espera({ ok: true });
  }

  // ── Construtor de funis ──
  agrupadores() { return espera([...this.db.agrupadores].sort((a, b) => a.ordem - b.ordem)); }
  funis() { return espera(this.db.funis.filter((f) => f.ativo)); }

  async salvarFunil(f: Funil): Promise<Resultado & { funilId?: string }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor cria ou edita funis.' });
    const problemas = validarFunil(f, this.db.vendedores);
    if (problemas.length) return espera({ ok: false, msg: problemas[0].msg });
    const atual = f.id ? this.db.funis.find((x) => x.id === f.id) : undefined;
    if (atual) {
      // Etapa removida não pode ter negócio aberto.
      const removidas = atual.etapas.filter((e) => !f.etapas.some((x) => x.id === e.id)).map((e) => e.id);
      if (this.db.negocios.some((n) => n.funilId === f.id && n.status === 'aberto' && removidas.includes(n.etapaId))) {
        return espera({ ok: false, msg: 'Há negócio aberto numa etapa removida. Mova os negócios antes.' });
      }
      Object.assign(atual, structuredClone(f));
      // Negócios do funil herdam nome, papel e alerta atualizados da etapa.
      for (const n of this.db.negocios.filter((x) => x.funilId === f.id)) {
        const e = etapaDoFunil(atual, n.etapaId);
        if (e) { const desde = n.etapaDesde; this.aplicarEtapa(n, e); n.etapaDesde = desde; }
      }
      this.registrar('editou', 'funil', f.id, `Editou o funil ${f.nome}`);
      return espera({ ok: true, msg: 'Funil atualizado.', funilId: f.id });
    }
    const id = this.novoId('f');
    const comIds: Funil = {
      ...structuredClone(f), id, criadoEm: agoraIso(), ativo: true,
      etapas: f.etapas.map((e) => ({ ...e, id: e.id || this.novoId('et') })),
      campanhas: f.campanhas.map((c) => ({ ...c, id: c.id || this.novoId('cp'), criadoEm: c.criadoEm || agoraIso() })),
    };
    this.db.funis.push(comIds);
    this.registrar('criou', 'funil', id, `Criou o funil ${f.nome} (${f.etapas.length} etapas)`);
    return espera({ ok: true, msg: 'Funil criado.', funilId: id });
  }

  async arquivarFunil(funilId: string, comAbertos = false): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor arquiva funis.' });
    const f = this.db.funis.find((x) => x.id === funilId);
    if (!f) return espera({ ok: false, msg: 'Funil não encontrado.' });
    if (!comAbertos && this.db.negocios.some((n) => n.funilId === funilId && n.status === 'aberto')) return espera({ ok: false, msg: 'Funil com negócio aberto: confirme para arquivar mesmo assim.' });
    f.ativo = false;
    this.registrar('arquivou', 'funil', funilId, `Arquivou o funil ${f.nome}`);
    return espera({ ok: true, msg: 'Funil arquivado.' });
  }

  async criarAgrupador(nome: string, produto: ProdutoKey | null): Promise<Resultado & { agrupadorId?: string }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor cria agrupadores.' });
    if (!nome.trim()) return espera({ ok: false, msg: 'Dê um nome ao agrupador.' });
    if (this.db.agrupadores.some((a) => a.nome.trim().toLowerCase() === nome.trim().toLowerCase())) return espera({ ok: false, msg: 'Já existe um agrupador com esse nome.' });
    const id = this.novoId('ag');
    this.db.agrupadores.push({ id, nome: nome.trim(), produto, ordem: this.db.agrupadores.length + 1 });
    this.registrar('criou', 'agrupador', id, `Criou o agrupador ${nome.trim()}`);
    return espera({ ok: true, agrupadorId: id });
  }

  async salvarCampos(negocioId: string, campos: Partial<Record<CampoKey, string>>): Promise<Resultado> {
    const n = this.negocio(negocioId);
    if (!n) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    if (!podeMexerNoNegocio(n, this.eu)) return espera({ ok: false, msg: 'Este negócio não é seu.' });
    const mudancas = Object.entries(campos)
      .filter(([k, v]) => (n.campos[k as CampoKey] ?? '') !== (v ?? ''))
      .map(([k, v]) => ({ campo: ROTULO_CAMPO[k as CampoKey] ?? k, antes: n.campos[k as CampoKey] ?? null, depois: v ?? null }));
    n.campos = { ...n.campos, ...campos };
    if (mudancas.length) this.registrar('editou', 'negocio', n.id, `Editou ${mudancas.length} campo(s) de ${this.nomeContato(n.contatoId)}`, n.contatoId, mudancas);
    return espera({ ok: true });
  }

  async marcarPerdido(negocioId: string, motivo: MotivoPerda, nota: string): Promise<Resultado> {
    const n = this.negocio(negocioId);
    if (!n) return espera({ ok: false, msg: 'Só negócio aberto pode ser perdido.' });
    if (!podeMexerNoNegocio(n, this.eu)) return espera({ ok: false, msg: 'Este negócio não é seu.' });
    if (n.status !== 'aberto') return espera({ ok: false, msg: 'Só negócio aberto pode ser perdido.' });
    const cfg = this.db.motivos.find((m) => m.key === motivo && m.ativo);
    if (!cfg) return espera({ ok: false, msg: 'Motivo fora do cadastro não existe.' });
    n.status = 'perdido';
    n.motivoPerda = motivo;
    n.fechadoEm = agoraIso();
    n.proximaAtividade = null;
    this.db.atividades.filter((a) => a.negocioId === negocioId && !a.concluidaEm).forEach((a) => { a.concluidaEm = agoraIso(); a.resultado = 'Cancelada: negócio perdido'; });
    if (cfg.bloqueia) {
      const c = this.db.contatos.find((x) => x.id === n.contatoId);
      if (c) c.optOut = true;
    }
    this.evento({ contatoId: n.contatoId, negocioId, tipo: 'perdido', titulo: 'Marcado como perdido', detalhe: nota ? `${motivo} · ${nota}` : motivo });
    this.registrar('marcou_perdido', 'negocio', n.id, `Marcou ${this.nomeContato(n.contatoId)} como perdido: ${cfg.label}`, n.contatoId, [{ campo: 'status', antes: 'aberto', depois: 'perdido' }, { campo: 'motivo', antes: null, depois: cfg.label }]);
    return espera({ ok: true });
  }

  async transferirDono(negocioId: string, novoDonoId: string, motivo: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Troca de dono só pelo gestor do Comercial.' });
    if (!motivo.trim()) return espera({ ok: false, msg: 'Escreva o motivo da troca.' });
    const n = this.negocio(negocioId);
    if (!n) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    const de = this.db.vendedores.find((v) => v.id === n.donoId)?.nome ?? 'sem dono';
    const para = this.db.vendedores.find((v) => v.id === novoDonoId)?.nome ?? novoDonoId;
    n.donoId = novoDonoId;
    const c = this.db.contatos.find((x) => x.id === n.contatoId);
    if (c) c.donoId = novoDonoId;
    this.db.atividades.filter((a) => a.negocioId === negocioId && !a.concluidaEm).forEach((a) => { a.donoId = novoDonoId; });
    this.evento({ contatoId: n.contatoId, negocioId, tipo: 'dono', titulo: `Dono: ${de} → ${para}`, detalhe: motivo });
    this.registrar('trocou_dono', 'negocio', n.id, `Trocou o dono de ${this.nomeContato(n.contatoId)}: ${de} → ${para}`, n.contatoId, [{ campo: 'dono', antes: de, depois: para }, { campo: 'motivo', antes: null, depois: motivo }]);
    return espera({ ok: true });
  }

  async criarNegocio(contatoId: string, funilId: string, campanhaId?: string | null): Promise<Resultado & { negocioId?: string; donoId?: string | null }> {
    const c = this.db.contatos.find((x) => x.id === contatoId);
    if (!c) return espera({ ok: false, msg: 'Contato não encontrado.' });
    if (c.optOut) return espera({ ok: false, msg: 'Este contato pediu para não receber contato.' });
    const f = this.db.funis.find((x) => x.id === funilId && x.ativo);
    if (!f) return espera({ ok: false, msg: 'Funil não encontrado.' });
    if (this.db.negocios.some((n) => n.contatoId === contatoId && n.funilId === funilId && n.status === 'aberto')) {
      return espera({ ok: false, msg: 'Este contato já tem negócio aberto neste funil.' });
    }
    // Distribuição do funil quando ele tem uma própria; senão, a geral.
    const time: Vendedor[] = f.distribuicao
      ? this.db.vendedores.map((v) => ({ ...v, percentual: f.distribuicao!.find((d) => d.vendedorId === v.id)?.percentual ?? 0 }))
      : this.db.vendedores;
    const recebidos: Record<string, number> = {};
    this.db.negocios.filter((n) => n.funilId === funilId).forEach((n) => { if (n.donoId) recebidos[n.donoId] = (recebidos[n.donoId] ?? 0) + 1; });
    const dono = escolherDono(c, time, recebidos);
    const id = this.novoId('n');
    const e = etapaInicial(f);
    const n: Negocio = {
      id, contatoId, produto: f.produto, origem: 'venda_ativa', funilId, campanhaId: campanhaId ?? null,
      etapaId: e.id, etapaNome: e.nome, etapa: e.papel, sla: null, status: 'aberto', donoId: dono,
      valor: produtoDe(f.produto).ticket, campos: { origem: `${c.utm.source ?? 'direto'} / ${c.utm.campaign ?? '—'}` }, motivoPerda: null,
      criadoEm: agoraIso(), etapaDesde: agoraIso(), fechadoEm: null, proximaAtividade: null, ultimaInteracaoEm: null,
    };
    this.aplicarEtapa(n, e);
    this.db.negocios.push(n);
    if (dono && !c.donoId) c.donoId = dono;
    this.evento({ contatoId, negocioId: id, tipo: 'criado', titulo: `Negócio criado em ${f.nome}`, detalhe: null });
    this.registrar('criou', 'negocio', id, `Criou negócio de ${c.nome} em ${f.nome} (dono: ${this.nomeVendedor(dono)})`, contatoId);
    return espera({ ok: true, negocioId: id, donoId: dono });
  }

  async atribuirContato(contatoId: string, donoId: string, motivo: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor define dono.' });
    const c = this.db.contatos.find((x) => x.id === contatoId);
    if (!c) return espera({ ok: false, msg: 'Contato não encontrado.' });
    if (!motivo.trim()) return espera({ ok: false, msg: 'Escreva o motivo.' });
    c.donoId = donoId;
    this.db.negocios.filter((n) => n.contatoId === contatoId && n.status === 'aberto' && !n.donoId).forEach((n) => { n.donoId = donoId; });
    const para = this.db.vendedores.find((v) => v.id === donoId)?.nome ?? donoId;
    this.evento({ contatoId, negocioId: null, tipo: 'dono', titulo: `Dono definido: ${para}`, detalhe: motivo });
    this.registrar('atribuiu', 'contato', contatoId, `Definiu ${para} como dono de ${c.nome}`, contatoId, [{ campo: 'dono', antes: null, depois: para }]);
    return espera({ ok: true });
  }

  async criarAtividade(a: NovaAtividade): Promise<Resultado> {
    const alvo = a.negocioId ? this.negocio(a.negocioId) : undefined;
    if (a.negocioId && !alvo) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    if (alvo && !podeMexerNoNegocio(alvo, this.eu)) return espera({ ok: false, msg: 'Este negócio não é seu.' });
    const dono = (a.negocioId && this.negocio(a.negocioId)?.donoId) || this.eu.vendedorId;
    const aid = this.novoId('a');
    this.db.atividades.push({ id: aid, ...a, donoId: dono, concluidaEm: null, resultado: null, cadenciaDia: null });
    this.registrar('agendou', 'atividade', aid, `Agendou "${a.titulo}" para ${this.nomeContato(a.contatoId)}`, a.contatoId);
    this.atualizarProxima(a.negocioId);
    return espera({ ok: true });
  }

  async concluirAtividade(atividadeId: string, resultado: string): Promise<Resultado> {
    const a = this.db.atividades.find((x) => x.id === atividadeId);
    if (!a || a.concluidaEm) return espera({ ok: false, msg: 'Atividade não encontrada ou já concluída.' });
    a.concluidaEm = agoraIso();
    a.resultado = resultado || 'Feito';
    this.registrar('concluiu', 'atividade', a.id, `Concluiu "${a.titulo}" (${a.resultado}) de ${this.nomeContato(a.contatoId)}`, a.contatoId);
    this.atualizarProxima(a.negocioId);
    const n = a.negocioId ? this.negocio(a.negocioId) : undefined;
    if (n) n.ultimaInteracaoEm = agoraIso();
    this.evento({
      contatoId: a.contatoId, negocioId: a.negocioId, tipo: a.tipo === 'ligacao' ? 'ligacao' : 'nota',
      titulo: `${a.titulo} · concluída`, detalhe: a.resultado,
    });
    return espera({ ok: true });
  }

  async adicionarNota(contatoId: string, negocioId: string | null, texto: string): Promise<Resultado> {
    if (!texto.trim()) return espera({ ok: false, msg: 'Nota vazia.' });
    const alvo = negocioId ? this.negocio(negocioId) : undefined;
    if (negocioId && !alvo) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    if (alvo && !podeMexerNoNegocio(alvo, this.eu)) return espera({ ok: false, msg: 'Este negócio não é seu.' });
    this.evento({ contatoId, negocioId, tipo: 'nota', titulo: 'Nota interna', detalhe: texto.trim() });
    this.registrar('criou', 'nota', negocioId ?? contatoId, `Registrou nota em ${this.nomeContato(contatoId)}`, contatoId);
    return espera({ ok: true });
  }

  async enviarMensagem(contatoId: string, texto: string, templateId?: string | null): Promise<Resultado> {
    if (!texto.trim()) return espera({ ok: false, msg: 'Mensagem vazia.' });
    const c = this.db.contatos.find((x) => x.id === contatoId);
    if (c?.optOut) return espera({ ok: false, msg: 'Contato pediu para não receber mensagens.' });
    const ultimaEntrada = this.db.mensagens.filter((m) => m.contatoId === contatoId && m.direcao === 'entrada').sort((a, b) => b.em.localeCompare(a.em))[0];
    const janelaAberta = !!ultimaEntrada && Date.now() - new Date(ultimaEntrada.em).getTime() < 24 * 3600_000;
    if (!janelaAberta && !templateId) return espera({ ok: false, msg: 'Janela de 24 h fechada: só sai template aprovado.' });
    this.db.mensagens.push({ id: this.novoId('m'), contatoId, canal: 'whatsapp', direcao: 'saida', texto: texto.trim(), em: agoraIso(), status: 'enviada', autorId: this.eu.vendedorId, templateId: templateId ?? null });
    this.db.mensagens.filter((m) => m.contatoId === contatoId && m.direcao === 'entrada' && !m.status).forEach((m) => { m.status = 'lida'; });
    const n = this.db.negocios.find((x) => x.contatoId === contatoId && x.status === 'aberto');
    this.evento({ contatoId, negocioId: n?.id ?? null, tipo: 'mensagem', titulo: 'Mensagem enviada no WhatsApp', detalhe: texto.trim().slice(0, 140) });
    this.registrar('enviou', 'mensagem', contatoId, `Enviou ${templateId ? 'template' : 'mensagem'} para ${this.nomeContato(contatoId)}`, contatoId);
    return espera({ ok: true });
  }

  async enviarAnexo(): Promise<Resultado> {
    return espera({ ok: false, msg: 'Anexo só funciona com o banco real (modo demonstração).' });
  }

  async enviarAudio(): Promise<Resultado> {
    return espera({ ok: false, msg: 'Áudio só funciona com o banco real (modo demonstração).' });
  }

  async urlMidia(): Promise<string | null> {
    return null;
  }

  async marcarConversaLida(contatoId: string): Promise<Resultado> {
    this.db.mensagens.filter((m) => m.contatoId === contatoId && m.direcao === 'entrada' && !m.status).forEach((m) => { m.status = 'lida'; });
    return espera({ ok: true });
  }

  async atualizarItemFila(filaId: string, itemId: string, status: StatusFila): Promise<Resultado> {
    const it = this.db.filas.find((f) => f.id === filaId)?.itens.find((i) => i.id === itemId);
    if (!it) return espera({ ok: false, msg: 'Item não encontrado.' });
    const antes = it.status;
    it.status = status;
    this.registrar('editou', 'fila', it.id, `Mudou ${this.nomeContato(it.contatoId)} na fila: ${antes} → ${status}`, it.contatoId, [{ campo: 'status', antes, depois: status }]);
    it.alteradoPor = this.eu.vendedorId;
    it.alteradoEm = agoraIso();
    return espera({ ok: true });
  }

  async salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<ResultadoFicha> {
    const v = this.db.vendedores.find((x) => x.id === this.eu.vendedorId);
    if (!v?.disparaApi) return espera({ ok: false, msg: 'Seu usuário não opera disparo por API.' });
    const ymd = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    const n = this.db.fichas.filter((x) => x.codigo.includes(ymd)).length + 1;
    const codigo = `${f.produto.toUpperCase()}-${ymd}-${String(n).padStart(2, '0')}`;
    // O gestor dispara com a ficha registrada; o vendedor precisa do ok do gestor.
    const destinatarios = [...new Set(f.destinatarios)];
    // Como no banco: sem lista, a ficha só fica como rascunho.
    if (enviarParaAprovacao && !destinatarios.length) {
      return espera({ ok: false, msg: 'Ficha sem destinatários: monte a lista antes de enviar para aprovação.' });
    }
    const status = !enviarParaAprovacao ? 'rascunho' : this.eu.papel === 'gestor' ? 'aprovada' : 'aguardando_aprovacao';
    const id = this.novoId('d');
    const { destinatarios: _lista, ...resto } = f;
    void _lista;
    const quantidade = destinatarios.length;
    const suprimidos = Math.min(f.suprimidos, quantidade);
    this.db.fichas.push({
      id, codigo, ...resto, quantidade, suprimidos, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'],
      operadorId: this.eu.vendedorId, status, aprovadoPor: status === 'aprovada' ? this.eu.vendedorId : null, criadoEm: agoraIso(), resultado: null,
    });
    this.registrar('criou', 'ficha', codigo, `Criou a ficha de disparo ${codigo} (${status})`);
    return espera({
      ok: true, msg: status === 'aguardando_aprovacao' ? 'Ficha enviada para aprovação do gestor.' : status === 'aprovada' ? 'Ficha registrada e aprovada.' : 'Rascunho salvo.',
      fichaId: id, codigo, quantidade, suprimidos,
    });
  }

  async decidirFicha(fichaId: string, aprovar: boolean): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor aprova ficha de disparo.' });
    const f = this.db.fichas.find((x) => x.id === fichaId);
    if (!f || f.status !== 'aguardando_aprovacao') return espera({ ok: false, msg: 'Ficha não está aguardando aprovação.' });
    f.status = aprovar ? 'aprovada' : 'reprovada';
    this.registrar(aprovar ? 'aprovou' : 'reprovou', 'ficha', f.id, `${aprovar ? 'Aprovou' : 'Reprovou'} a ficha ${f.codigo}`);
    f.aprovadoPor = this.eu.vendedorId;
    return espera({ ok: true });
  }

  async salvarDistribuicao(percentuais: Record<string, { percentual: number; ativo: boolean }>): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor define a distribuição.' });
    const novo = this.db.vendedores.map((v) => ({ ...v, ...(percentuais[v.id] ?? {}) }));
    if (somaPercentuais(novo) !== 100) return espera({ ok: false, msg: 'A soma dos percentuais dos ativos precisa dar 100%.' });
    const mudancas = novo.filter((v) => { const a = this.db.vendedores.find((x) => x.id === v.id)!; return a.percentual !== v.percentual || a.ativo !== v.ativo; })
      .map((v) => { const a = this.db.vendedores.find((x) => x.id === v.id)!; return { campo: v.nome, antes: `${a.ativo ? '' : 'inativo · '}${a.percentual}%`, depois: `${v.ativo ? '' : 'inativo · '}${v.percentual}%` }; });
    this.db.vendedores = novo;
    this.registrar('editou', 'distribuicao', 'geral', 'Alterou a distribuição de leads', null, mudancas);
    return espera({ ok: true });
  }

  async criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<ResultadoLink> {
    const v = this.db.vendedores.find((x) => x.id === vendedorId);
    if (!v || !acao.trim()) return espera({ ok: false, msg: 'Informe vendedor e ação.' });
    if (this.eu.papel !== 'gestor' && vendedorId !== this.eu.vendedorId) return espera({ ok: false, msg: 'Vendedor só cria link para si mesmo.' });
    const sck = montarSck(produto, acao, new Date(), canal, v.sigla);
    if (this.db.links.some((l) => l.sck === sck)) return espera({ ok: false, msg: 'Este link já existe.' });
    const id = this.novoId('l');
    const url = `https://pay.hotmart.com/EXEMPLO?sck=${sck}`;
    this.db.links.push({ id, vendedorId, produto, acao: acao.trim(), sck, url, canal, criadoEm: agoraIso() });
    this.registrar('criou', 'link', sck, `Criou link rastreável ${sck}`);
    return espera({ ok: true, linkId: id, sck, url });
  }

  // ── Motivos de perda ──
  motivosPerda() { return espera(this.db.motivos); }

  async salvarMotivoPerda(m: MotivoPerdaConfig): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor edita motivos de perda.' });
    if (!m.label.trim() || !m.key) return espera({ ok: false, msg: 'Dê um nome ao motivo.' });
    const atual = this.db.motivos.find((x) => x.key === m.key);
    if (atual?.sistema) {
      // De fábrica: só nota e ativo mudam (a regra do playbook não se reescreve pela tela).
      atual.nota = m.nota;
      atual.ativo = m.ativo;
      this.registrar('editou', 'motivo', m.key, `Editou o motivo de perda "${atual.label}"`);
      return espera({ ok: true, msg: 'Motivo atualizado.' });
    }
    if (!atual && this.db.motivos.some((x) => x.label.trim().toLowerCase() === m.label.trim().toLowerCase())) {
      return espera({ ok: false, msg: 'Já existe um motivo com esse nome.' });
    }
    if (atual) Object.assign(atual, { ...m, sistema: false });
    else this.db.motivos.push({ ...m, label: m.label.trim(), sistema: false });
    this.registrar(atual ? 'editou' : 'criou', 'motivo', m.key, `${atual ? 'Editou' : 'Criou'} o motivo de perda "${m.label.trim()}"`);
    return espera({ ok: true, msg: atual ? 'Motivo atualizado.' : 'Motivo criado.' });
  }

  // ── Catalogação de origem (20261007141044) ──
  private regrasCat: RegraCatalogo[] = regrasDemo();
  private origensCat = new Map<string, EstadoOrigemDemo>();

  /** Recalcula a origem de todo contato demo com as regras atuais (no banco: crm.origem_catalogar). */
  private catalogarDemo() {
    for (const c of this.db.contatos) {
      const e = this.origensCat.get(c.id);
      c.origem = e ? resumoDeOrigem(origemDemo(e, this.regrasCat)) : null;
    }
  }

  catalogo(): Promise<PainelCatalogo> {
    const estados = this.db.contatos.map((c) => this.origensCat.get(c.id)).filter((e): e is EstadoOrigemDemo => !!e);
    const origens = estados.map((e) => origemDemo(e, this.regrasCat));
    return espera(painelDemo(origens, estados, this.regrasCat, this.eu.papel === 'gestor'));
  }

  async salvarRegraCatalogo(r: RegraCatalogo): Promise<Resultado & { id?: number }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor edita as regras de catalogação.' });
    if (!r.padrao.trim()) return espera({ ok: false, msg: 'Escreva o valor ou o pedaço do nome.' });
    if (r.projeto && !CHAVE_PROJETO.test(r.projeto)) return espera({ ok: false, msg: 'Chave do projeto inválida.' });
    const igual = this.regrasCat.find((x) => x.ativo && r.ativo && x.id !== r.id && (x.tipo ?? 'projeto') === (r.tipo ?? 'projeto') && x.campo === r.campo && x.operador === r.operador
      && x.padrao.trim().toLowerCase() === r.padrao.trim().toLowerCase() && (x.valeDe ?? '') === (r.valeDe ?? '') && (x.valeAte ?? '') === (r.valeAte ?? ''));
    if (igual) return espera({ ok: false, msg: 'Já existe uma regra ativa igual (campo, operador, valor e datas).' });
    const atual = r.id != null ? this.regrasCat.find((x) => x.id === r.id) : undefined;
    if (r.id != null && !atual) return espera({ ok: false, msg: 'Regra não encontrada.' });
    const id = atual?.id ?? Math.max(0, ...this.regrasCat.map((x) => x.id ?? 0)) + 1;
    if (atual) Object.assign(atual, { ...r, id });
    else this.regrasCat.push({ ...r, id, padrao: r.padrao.trim() });
    this.catalogarDemo();
    return espera({ ok: true, msg: atual ? 'Regra atualizada.' : 'Regra criada.', id });
  }

  async salvarListaAc(id: string, nome: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor edita as listas.' });
    if (!/^[0-9]{1,10}$/.test(id.trim())) return espera({ ok: false, msg: 'Id da lista inválido (só números).' });
    if (!nome.trim()) return espera({ ok: false, msg: 'Escreva o nome da lista (até 200 letras).' });
    return espera({ ok: true, msg: 'Lista salva. (Demonstração: os nomes de exemplo não mudam.)' });
  }

  async reaplicarCatalogo(todos = false): Promise<Resultado & { catalogados?: number }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor reaplica as regras.' });
    const antes = this.db.contatos.filter((c) => c.origem?.projeto).length;
    const n = this.db.contatos.filter((c) => todos || !c.origem?.projeto).length;
    this.catalogarDemo();
    const depois = this.db.contatos.filter((c) => c.origem?.projeto).length;
    return espera({ ok: true, msg: `${n} contatos recatalogados; com projeto: ${antes} → ${depois}.`, catalogados: n });
  }

  async origemContato(contatoId: string): Promise<OrigemDetalhada | null> {
    const e = this.origensCat.get(contatoId);
    if (!e) return espera(null);
    return espera({ ...origemDemo(e, this.regrasCat), podeDefinir: this.eu.papel === 'gestor' });
  }

  async definirProjetoContato(contatoId: string, projeto: string | null): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor define o projeto do contato.' });
    const e = this.origensCat.get(contatoId);
    if (!e) return espera({ ok: false, msg: 'Contato sem origem registrada.' });
    const p = projeto?.trim().toLowerCase() || null;
    if (p && !CHAVE_PROJETO.test(p)) return espera({ ok: false, msg: 'Chave do projeto inválida.' });
    e.manual = p;
    this.catalogarDemo();
    return espera({ ok: true, msg: p ? 'Projeto do contato definido.' : 'Projeto volta a seguir as regras.' });
  }

  // ── Jornada ──
  async jornada(contatoId: string): Promise<PontoJornada[]> {
    const c = this.db.contatos.find((x) => x.id === contatoId);
    const externos = this.db.jornada.filter((p) => p.contatoId === contatoId);
    const tipoDe: Partial<Record<EventoTimeline['tipo'], TipoPontoJornada>> = {
      criado: 'negocio', etapa: 'negocio', dono: 'negocio', ganho: 'negocio', perdido: 'negocio', mensagem: 'conversa',
      ligacao: 'conversa', nota: 'nota', checkout: 'checkout', pesquisa: 'pesquisa', grupo: 'grupo', disparo: 'disparo', compra: 'compra',
    };
    const doCrm: PontoJornada[] = this.db.eventos.filter((e) => e.contatoId === contatoId).map((e) => {
      const n = e.negocioId ? this.negocio(e.negocioId) : undefined;
      const f = n ? this.db.funis.find((x) => x.id === n.funilId) : undefined;
      const quem = e.autorId ? this.db.vendedores.find((v) => v.id === e.autorId)?.nome : null;
      return {
        id: `crm-${e.id}`, contatoId, tipo: tipoDe[e.tipo] ?? 'nota', em: e.em,
        titulo: n && (e.tipo === 'criado' || e.tipo === 'etapa' || e.tipo === 'ganho' || e.tipo === 'perdido') ? `${e.titulo} · ${f?.nome ?? ''}` : e.titulo,
        detalhe: [e.tipo === 'etapa' ? null : e.detalhe, quem ? `por ${quem}` : null].filter(Boolean).join(' · ') || null,
        fonte: 'crm', lancamento: f?.projeto ?? null, produto: n?.produto ?? null,
        utm: e.tipo === 'criado' && c ? c.utm : null, valor: e.tipo === 'ganho' ? n?.valor ?? null : null, negocioId: e.negocioId,
      };
    });
    return espera([...externos, ...doCrm].sort((a, b) => b.em.localeCompare(a.em)));
  }

  // ── Projetos ──
  async criarProjeto(tipo: TipoProjeto, nome: string, agrupadorId: string, produto: ProdutoKey): Promise<Resultado & { funilIds?: string[] }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor cria projetos.' });
    if (!nome.trim()) return espera({ ok: false, msg: 'Dê um nome ao projeto.' });
    const ag = this.db.agrupadores.find((a) => a.id === agrupadorId);
    if (!ag) return espera({ ok: false, msg: 'Escolha o agrupador.' });
    const novos = funisDoProjeto(tipo, nome.trim(), ag, produto);
    if (!novos.length) return espera({ ok: false, msg: 'Tipo de projeto desconhecido.' });
    if (novos.some((f) => this.db.funis.some((x) => x.ativo && x.nome === f.nome))) return espera({ ok: false, msg: 'Já existe projeto com esse nome.' });
    const ids: string[] = [];
    for (const f of novos) {
      const fid = this.novoId('f');
      ids.push(fid);
      this.db.funis.push({ ...f, id: fid, criadoEm: agoraIso(), campanhas: f.campanhas.map((c) => ({ ...c, criadoEm: agoraIso() })) });
    }
    this.registrar('criou', 'projeto', ids[0], `Começou o projeto ${nome.trim()} (${ids.length} funis)`);
    return espera({ ok: true, msg: `${ids.length} funis criados para ${nome.trim()}.`, funilIds: ids });
  }

  // ── Ativação padrão (20261007135415) ──
  private cadastrosAtivacao = new Map<string, CadastroAtivacao>();

  /** Demonstração: o projeto ATM da base ganha datas e três negócios de ativação com os toques agendados. */
  private semearAtivacao() {
    const f = this.db.funis.find((x) => ehFunilAtivacao(x));
    if (!f?.projeto) return;
    const ini = new Date(Date.now() + 9 * 86400000).toISOString().slice(0, 10);
    const fim = new Date(Date.now() + 11 * 86400000).toISOString().slice(0, 10);
    const c: CadastroAtivacao = { ...cadastroVazio(), eventoInicio: ini, eventoFim: fim, eventoHora: '19:00', carrinhoFim: new Date(Date.now() + 13 * 86400000).toISOString().slice(0, 10), hotmartOferta: ['5064314'] };
    this.cadastrosAtivacao.set(f.projeto, c);
    const vendedores = this.db.vendedores.filter((v) => v.ativo && v.papel === 'vendedor');
    const e0 = f.etapas[0];
    const contatos = this.db.contatos.filter((ct) => !ct.optOut).slice(0, 3);
    contatos.forEach((ct, i) => {
      const agora = new Date(Date.now() - i * 40 * 60000);
      const n: Negocio = {
        id: `n-ativ-demo-${i + 1}`, contatoId: ct.id, produto: f.produto, origem: 'venda_ativa', funilId: f.id, campanhaId: f.campanhas[0]?.id ?? null,
        etapaId: e0.id, etapaNome: e0.nome, etapa: e0.papel, sla: { atencaoMin: e0.slaAtencaoMin!, criticoMin: e0.slaCriticoMin! },
        status: 'aberto', donoId: vendedores[i % Math.max(1, vendedores.length)]?.id ?? null, valor: 0,
        campos: { origem: i === 2 ? 'Ativação · ingresso comprado na Hotmart' : 'Ativação · inscrição no ActiveCampaign' },
        motivoPerda: null, criadoEm: agora.toISOString(), etapaDesde: agora.toISOString(), fechadoEm: null, proximaAtividade: null, ultimaInteracaoEm: null,
      };
      this.db.negocios.push(n);
      this.db.atividades.push(...toquesDoNegocio(n, c, agora, () => this.novoId('a')));
      this.atualizarProxima(n.id);
    });
  }

  ativacao(): Promise<PainelAtivacao> {
    return espera(painelAtivacaoDemo({
      funis: this.db.funis, negocios: this.db.negocios, atividades: this.db.atividades, cadastros: this.cadastrosAtivacao,
      eu: this.eu, agora: new Date(),
    }));
  }

  async salvarAtivacao(e: EdicaoAtivacao): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor configura a ativação.' });
    const f = this.db.funis.find((x) => x.ativo && x.projeto === e.projeto && ehFunilAtivacao(x));
    if (!f) return espera({ ok: false, msg: 'Projeto sem ativação.' });
    const atual = this.cadastrosAtivacao.get(e.projeto) ?? cadastroVazio();
    if (atual.encerradoEm) return espera({ ok: false, msg: 'Ativação encerrada não muda.' });
    const erro = validarAtivacao(e);
    if (erro) return espera({ ok: false, msg: erro });
    const c: CadastroAtivacao = { ...atual, eventoInicio: e.eventoInicio, eventoFim: e.eventoFim, eventoHora: e.eventoHora, carrinhoFim: e.carrinhoFim, hotmartOferta: [...e.hotmartOferta], ligado: e.ligado };
    this.cadastrosAtivacao.set(e.projeto, c);
    // reagenda os toques 2/3 abertos (o toque 1 e o que já foi feito ficam)
    const abertos = this.db.negocios.filter((n) => n.funilId === f.id && n.status === 'aberto' && n.donoId);
    for (const n of abertos) {
      this.db.atividades = this.db.atividades.filter((a) => !(a.negocioId === n.id && !a.concluidaEm && /^Toque [23]/.test(a.titulo)));
      const novos = toquesDoNegocio(n, c, new Date(), () => this.novoId('a')).filter((a) => !a.titulo.startsWith('Toque 1:'))
        .filter((a) => !this.db.atividades.some((x) => x.negocioId === n.id && x.titulo === a.titulo));
      this.db.atividades.push(...novos);
      this.atualizarProxima(n.id);
    }
    const nome = f.nome.slice(0, -SUFIXO_ATIVACAO.length);
    this.registrar('editou', 'projeto', f.id, `Configurou a ativação de ${nome}`);
    return espera({ ok: true, msg: `Ativação de ${nome} salva.${abertos.length ? ` Toques de ${abertos.length} negócio(s) reagendados.` : ''}` });
  }

  async garantirAtivacao(projeto: string): Promise<Resultado & { funilId?: string }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor acrescenta a ativação.' });
    const ja = this.db.funis.find((x) => x.ativo && x.projeto === projeto && ehFunilAtivacao(x));
    if (ja) return espera({ ok: true, msg: 'Este projeto já tem a Ativação.', funilId: ja.id });
    const base = this.db.funis.filter((x) => x.ativo && x.projeto === projeto).sort((a, b) => a.criadoEm.localeCompare(b.criadoEm))[0];
    if (!base) return espera({ ok: false, msg: 'Projeto não encontrado.' });
    const m = modeloFunil('ativacao')!;
    const nome = base.nome.split(' · ')[0].trim();
    const id = this.novoId('f');
    this.db.funis.push({
      id, nome: `${nome}${SUFIXO_ATIVACAO}`, icone: m.icone, projeto, agrupadorId: base.agrupadorId, produto: base.produto, tipo: m.tipo,
      eventosHotmart: [], etapas: m.etapas.map((e, i) => ({ ...e, camposObrigatorios: [...e.camposObrigatorios], id: `${id}-e${i + 1}` })),
      campanhas: m.campanhas.map((c, i) => ({ ...c, nome: c.nome.replaceAll('{chave}', projeto), regra: c.regra.replaceAll('{chave}', projeto), id: `${id}-c${i + 1}`, criadoEm: agoraIso() })),
      distribuicao: null, ativo: true, criadoEm: agoraIso(),
    });
    this.registrar('criou', 'funil', id, `Acrescentou a Ativação ao projeto ${nome}`);
    return espera({ ok: true, msg: `Funil de Ativação criado para ${nome}.`, funilId: id });
  }

  async encerrarAtivacao(projeto: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor encerra a ativação.' });
    const f = this.db.funis.find((x) => x.projeto === projeto && ehFunilAtivacao(x));
    if (!f) return espera({ ok: false, msg: 'Projeto sem ativação.' });
    const c = this.cadastrosAtivacao.get(projeto) ?? cadastroVazio();
    if (c.encerradoEm) return espera({ ok: false, msg: 'Esta ativação já foi encerrada.' });
    const nome = f.nome.slice(0, -SUFIXO_ATIVACAO.length);
    const abertos = this.db.negocios.filter((n) => n.funilId === f.id && n.status === 'aberto');
    const filaId = this.novoId('fila');
    // a fila de recuperação do projeto, com o MESMO dono como responsável de cada contato
    this.db.filas.push({
      id: filaId, nome: `Recuperação · ${nome}`, produto: f.produto, ofertaVigente: null, ofertaCodigo: null, projeto, criadaEm: agoraIso(), encerradaEm: null,
      itens: abertos.filter((n) => !this.db.contatos.find((ct) => ct.id === n.contatoId)?.optOut).map((n, i) => ({
        id: `${filaId}-i${i + 1}`, contatoId: n.contatoId, score: 0, faixa: 'D' as const, sinais: [], status: 'a_abordar' as const,
        responsavelId: n.donoId, alteradoPor: null, alteradoEm: null,
      })),
    });
    for (const n of abertos) {
      n.status = 'perdido';
      n.motivoPerda = 'evento_sem_compra';
      n.fechadoEm = agoraIso();
      this.db.atividades.filter((a) => a.negocioId === n.id && !a.concluidaEm).forEach((a) => { a.concluidaEm = agoraIso(); a.resultado = 'Encerrada: carrinho fechou'; });
      n.proximaAtividade = null;
    }
    this.cadastrosAtivacao.set(projeto, { ...c, encerradoEm: agoraIso(), filaId });
    this.registrar('editou', 'projeto', f.id, `Encerrou a ativação de ${nome}`);
    return espera({ ok: true, msg: `Ativação encerrada: ${abertos.length} sem compra, ${abertos.length} na fila de recuperação com o mesmo dono.` });
  }

  // ── Painel ──
  painel(vendedorId: string) {
    const v = this.db.vendedores.find((x) => x.id === vendedorId);
    return espera(this.db.paineis.find((p) => p.vendedorId === vendedorId) ?? painelPadrao(vendedorId, v?.papel === 'gestor'));
  }

  async salvarPainel(p: PainelPessoa): Promise<Resultado> {
    // Cada um personaliza o próprio painel; o gestor também pode montar o de um vendedor.
    if (p.vendedorId !== this.eu.vendedorId && this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Você só edita o seu painel.' });
    this.db.paineis = [...this.db.paineis.filter((x) => x.vendedorId !== p.vendedorId), structuredClone(p)];
    this.registrar('editou', 'painel', p.vendedorId, `Personalizou o painel de ${this.nomeVendedor(p.vendedorId)} (${p.widgets.length} widgets)`);
    return espera({ ok: true, msg: 'Painel salvo.' });
  }

  // ── Notificações ──
  private lidas = new Set<string>();

  /** Na demonstração, as notificações nascem do estado atual (prazo crítico, mensagem sem resposta, ficha para aprovar). */
  async notificacoes(): Promise<Notificacao[]> {
    const eu = this.eu.vendedorId;
    const agora = new Date();
    const lista: Notificacao[] = [];
    const nome = (contatoId: string) => this.db.contatos.find((c) => c.id === contatoId)?.nome ?? 'Lead';
    for (const n of this.db.negocios) {
      if (n.status !== 'aberto' || n.donoId !== eu) continue;
      if (situacaoSla(n, agora) === 'critico') {
        lista.push({ id: `sla-${n.id}`, vendedorId: eu, gatilho: 'prazo_estourado', titulo: `Prazo estourado: ${nome(n.contatoId)}`, corpo: `${n.etapaNome} · aja agora ou escale.`, href: `/comercial/funil?negocio=${n.id}`, em: n.etapaDesde, lida: false });
      }
      if (n.etapa === 'primeiro_contato' && Date.now() - new Date(n.criadoEm).getTime() < 2 * 3600_000) {
        lista.push({ id: `novo-${n.id}`, vendedorId: eu, gatilho: 'lead_novo', titulo: `Lead novo: ${nome(n.contatoId)}`, corpo: `${n.etapaNome} · primeiro contato em até 5 minutos.`, href: `/comercial/funil?negocio=${n.id}`, em: n.criadoEm, lida: false });
      }
      if (n.status === 'aberto' && n.proximaAtividade && new Date(n.proximaAtividade.venceEm).getTime() - Date.now() < 30 * 60_000 && new Date(n.proximaAtividade.venceEm).getTime() > Date.now()) {
        lista.push({ id: `atv-${n.proximaAtividade.id}`, vendedorId: eu, gatilho: 'atividade_vencendo', titulo: `Em 30 min: ${n.proximaAtividade.titulo}`, corpo: nome(n.contatoId), href: '/comercial/atividades', em: agoraIso(), lida: false });
      }
    }
    const entradas = this.db.mensagens.filter((m) => m.direcao === 'entrada' && !m.status);
    for (const m of entradas) {
      if (this.db.contatos.find((c) => c.id === m.contatoId)?.donoId !== eu) continue;
      lista.push({ id: `msg-${m.id}`, vendedorId: eu, gatilho: 'lead_respondeu', titulo: `${nome(m.contatoId)} respondeu`, corpo: m.texto.slice(0, 90), href: `/comercial/conversas?contato=${m.contatoId}`, em: m.em, lida: false });
    }
    for (const n of this.db.negocios.filter((x) => x.status === 'ganho' && x.donoId === eu && x.fechadoEm && Date.now() - new Date(x.fechadoEm).getTime() < 24 * 3600_000)) {
      lista.push({ id: `venda-${n.id}`, vendedorId: eu, gatilho: 'venda_aprovada', titulo: `Venda aprovada: ${nome(n.contatoId)}`, corpo: `${produtoDe(n.produto).nome} · pagamento aprovado na Hotmart.`, href: `/comercial/funil?negocio=${n.id}`, em: n.fechadoEm!, lida: false });
    }
    if (this.eu.papel === 'gestor') {
      for (const f of this.db.fichas.filter((x) => x.status === 'aguardando_aprovacao')) {
        lista.push({ id: `ficha-${f.id}`, vendedorId: eu, gatilho: 'ficha_para_aprovar', titulo: `Ficha para aprovar: ${f.codigo}`, corpo: f.objetivo, href: '/comercial/disparos#fichas', em: f.criadoEm, lida: false });
      }
    }
    return espera(lista.map((x) => ({ ...x, lida: this.lidas.has(x.id) })).sort((a, b) => b.em.localeCompare(a.em)));
  }

  async marcarNotificacoesLidas(ids?: string[]): Promise<Resultado> {
    if (ids) ids.forEach((i) => this.lidas.add(i));
    else (await this.notificacoes()).forEach((n) => this.lidas.add(n.id));
    return espera({ ok: true });
  }

  preferenciasNotificacao() {
    return espera(this.db.preferencias.find((p) => p.vendedorId === this.eu.vendedorId) ?? preferenciasPadrao(this.eu.vendedorId));
  }

  async salvarPreferenciasNotificacao(p: PreferenciasNotificacao): Promise<Resultado> {
    if (p.vendedorId !== this.eu.vendedorId) return espera({ ok: false, msg: 'Você só edita as suas notificações.' });
    this.db.preferencias = [...this.db.preferencias.filter((x) => x.vendedorId !== p.vendedorId), structuredClone(p)];
    return espera({ ok: true, msg: 'Preferências salvas.' });
  }

  // ── Produtos e ofertas (espelho da Hotmart) ──
  produtosHotmart() { return espera([...this.produtos].sort((a, b) => Number(b.noComercial) - Number(a.noComercial) || a.nomeHotmart.localeCompare(b.nomeHotmart))); }

  ofertas(produtoId?: string) {
    return espera(this.ofertasDb.filter((o) => !produtoId || o.produtoId === produtoId).sort((a, b) => Number(b.vigente) - Number(a.vigente) || b.transacoes - a.transacoes));
  }

  ofertasOrfas(): Promise<OfertaOrfa[]> { return espera(ORFAS_DEMO); }

  async buscarPorLinkHotmart(linkOuCodigo: string) {
    const codigo = extrairCodigoOferta(linkOuCodigo);
    const oferta = codigo ? this.ofertasDb.find((o) => o.codigo === codigo) ?? null : null;
    const produto = oferta ? this.produtos.find((p) => p.produtoId === oferta.produtoId) ?? null : null;
    return espera({ produto, oferta, codigo });
  }

  async vincularProduto(p: Pick<ProdutoHotmart, 'produtoId' | 'noComercial' | 'nomeComercial' | 'produtoKey' | 'agrupadorId' | 'escada'>): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor vincula produtos.' });
    const atual = this.produtos.find((x) => x.produtoId === p.produtoId);
    if (!atual) return espera({ ok: false, msg: 'Produto não veio da Hotmart. Crie o produto na Hotmart; ele aparece aqui depois da sincronização.' });
    if (p.noComercial && (!p.nomeComercial?.trim() || !p.escada)) return espera({ ok: false, msg: 'Para vincular, dê o nome comercial e a escada (A ou B).' });
    const antes = atual.noComercial;
    Object.assign(atual, { ...p, nomeComercial: p.nomeComercial?.trim() || null });
    this.registrar(p.noComercial ? (antes ? 'editou' : 'vinculou') : 'desvinculou', 'produto', p.produtoId, `${p.noComercial ? (antes ? 'Editou' : 'Vinculou ao comercial') : 'Desvinculou'} o produto ${atual.nomeHotmart}`);
    return espera({ ok: true, msg: p.noComercial ? 'Produto vinculado ao comercial.' : 'Produto desvinculado.' });
  }

  async salvarOferta(o: Pick<OfertaHotmart, 'codigo' | 'vigente' | 'condicao' | 'validaAte' | 'uso'>): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor define a oferta vigente.' });
    const atual = this.ofertasDb.find((x) => x.codigo === o.codigo);
    if (!atual) return espera({ ok: false, msg: 'Oferta não está no catálogo da Hotmart.' });
    if (o.vigente && !this.produtos.find((p) => p.produtoId === atual.produtoId)?.noComercial) return espera({ ok: false, msg: 'Vincule o produto ao comercial antes de marcar oferta vigente.' });
    const mudancas = (['vigente', 'condicao', 'validaAte', 'uso'] as const)
      .filter((k) => String(atual[k] ?? '') !== String(o[k] ?? ''))
      .map((k) => ({ campo: k, antes: atual[k] == null ? null : String(atual[k]), depois: o[k] == null ? null : String(o[k]) }));
    Object.assign(atual, o);
    this.registrar('editou', 'oferta', o.codigo, `Editou a oferta ${o.codigo}${o.vigente ? ' (vigente)' : ''}`, null, mudancas);
    return espera({ ok: true, msg: 'Oferta salva.' });
  }

  // ── Dashboards ──
  dashboards() {
    return espera(this.dashboardsDb.filter((d) => d.donoId === this.eu.vendedorId || d.compartilhado).sort((a, b) => b.atualizadoEm.localeCompare(a.atualizadoEm)));
  }

  async salvarDashboard(d: Dashboard): Promise<Resultado & { dashboardId?: string }> {
    if (!d.nome.trim()) return espera({ ok: false, msg: 'Dê um nome ao dashboard.' });
    const atual = d.id ? this.dashboardsDb.find((x) => x.id === d.id) : undefined;
    if (atual && atual.donoId !== this.eu.vendedorId && this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o dono e o gestor editam este dashboard.' });
    if (atual) {
      Object.assign(atual, structuredClone(d), { atualizadoEm: agoraIso() });
      this.registrar('editou', 'dashboard', d.id, `Editou o dashboard ${d.nome}`);
      return espera({ ok: true, msg: 'Dashboard salvo.', dashboardId: d.id });
    }
    const id = this.novoId('dash');
    this.dashboardsDb.push({ ...structuredClone(d), id, donoId: this.eu.vendedorId, criadoEm: agoraIso(), atualizadoEm: agoraIso() });
    this.registrar('criou', 'dashboard', id, `Criou o dashboard ${d.nome}`);
    return espera({ ok: true, msg: 'Dashboard criado.', dashboardId: id });
  }

  async excluirDashboard(id: string): Promise<Resultado> {
    const d = this.dashboardsDb.find((x) => x.id === id);
    if (!d) return espera({ ok: false, msg: 'Dashboard não encontrado.' });
    if (d.donoId !== this.eu.vendedorId && this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o dono e o gestor excluem.' });
    this.dashboardsDb = this.dashboardsDb.filter((x) => x.id !== id);
    this.registrar('excluiu', 'dashboard', id, `Excluiu o dashboard ${d.nome}`);
    return espera({ ok: true, msg: 'Dashboard excluído.' });
  }

  // ── Registro do CRM ──
  log(filtro: FiltroLog = {}): Promise<LogCrm[]> {
    const l = this.logDb.filter((x) =>
      (filtro.autorId === undefined || x.autorId === filtro.autorId)
      && (!filtro.entidade || x.entidade === filtro.entidade)
      && (!filtro.entidadeId || x.entidadeId === filtro.entidadeId)
      && (!filtro.contatoId || x.contatoId === filtro.contatoId)
      && (!filtro.desde || x.em >= filtro.desde)
      && (!filtro.ate || x.em <= filtro.ate));
    return espera([...l].sort((a, b) => b.em.localeCompare(a.em)).slice(0, filtro.limite ?? 500));
  }

  async verComo(vendedorId: string) {
    const v = this.db.vendedores.find((x) => x.id === vendedorId);
    if (v) this.eu = { vendedorId: v.id, papel: v.papel };
  }

  // ── Integração Hotmart (F3): painel de demonstração ──
  private hotmartErros: PainelHotmart['erros'] = [
    { chave: 'demo-ev-1042', classe: 'cartao_recusado', resultado: 'erro: telefone e e-mail não casam com nenhum contato', em: new Date(Date.now() - 3 * 3600_000).toISOString(), tentativas: 1 },
    { chave: 'demo-ev-1017', classe: 'carrinho_abandonado', resultado: 'erro: oferta sem produto vinculado', em: new Date(Date.now() - 26 * 3600_000).toISOString(), tentativas: 2 },
  ];

  async hotmartPainel(dias: number): Promise<PainelHotmart> {
    if (this.eu.papel !== 'gestor') throw new Error('Só o gestor do Comercial vê a integração.');
    const d = Math.min(Math.max(Math.round(dias) || 7, 1), 90);
    const k = d / 7;
    return espera({
      hotmartLigado: true, slackLigado: false, desde: '2026-10-06T09:00:00.000Z',
      ultimoProcessadoEm: new Date(Date.now() - 12 * 60_000).toISOString(),
      porResultado: [
        { fonte: 'webhook', classe: 'compra_aprovada', resultado: 'ganho', n: Math.round(18 * k) },
        { fonte: 'webhook', classe: 'carrinho_abandonado', resultado: 'negocio_criado', n: Math.round(41 * k) },
        { fonte: 'webhook', classe: 'cartao_recusado', resultado: 'negocio_criado', n: Math.round(9 * k) },
        { fonte: 'sync', classe: 'compra_aprovada', resultado: 'duplicado', n: Math.round(16 * k) },
        { fonte: 'webhook', classe: 'carrinho_abandonado', resultado: 'jornada', n: Math.round(7 * k) },
        { fonte: 'webhook', classe: 'cartao_recusado', resultado: 'erro', n: this.hotmartErros.length },
      ].filter((x) => x.n > 0),
      erros: this.hotmartErros,
      ofertasOrfas: ['demo1x2y'],
      slack: { pendentes: 0, enviados: 0, descartados: 0 },
    });
  }

  async reprocessarHotmart(chave: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor do Comercial reprocessa.' });
    const i = this.hotmartErros.findIndex((e) => e.chave === chave);
    if (i < 0) return espera({ ok: false, msg: 'Evento não encontrado.' });
    this.hotmartErros.splice(i, 1);
    return espera({ ok: true, msg: 'negocio_criado' });
  }

  // ── MCP (F7): tokens de demonstração (nenhum funciona fora desta tela) ──
  private tokensDb: TokenMcp[] = [];

  tokensMcp(): Promise<TokenMcp[]> {
    const agora = Date.now();
    const vistos = this.tokensDb
      .filter((t) => this.eu.papel === 'gestor' || t.perfilId === this.eu.vendedorId)
      .map((t) => ({ ...t, ativo: !t.revogadoEm && new Date(t.expiraEm).getTime() > agora }));
    return espera([...vistos].sort((a, b) => b.criadoEm.localeCompare(a.criadoEm)));
  }

  async criarTokenMcp(nome: string, escopos: EscopoMcp[], dias: number): Promise<ResultadoTokenMcp> {
    if (this.db.config.mcpLigado === false) return espera({ ok: false, msg: 'MCP do Comercial desligado.' });
    const n = nome.trim();
    if (n.length < 1 || n.length > 60) return espera({ ok: false, msg: 'Dê um nome ao token (até 60 caracteres).' });
    if (!escopos.length || escopos.some((e) => e !== 'ler' && e !== 'operar')) return espera({ ok: false, msg: 'Escopo inválido: use ler e/ou operar.' });
    if (!Number.isInteger(dias) || dias < 1 || dias > 180) return espera({ ok: false, msg: 'Validade entre 1 e 180 dias.' });
    const agora = Date.now();
    const ativos = this.tokensDb.filter((t) => t.perfilId === this.eu.vendedorId && !t.revogadoEm && new Date(t.expiraEm).getTime() > agora);
    if (ativos.length >= 5) return espera({ ok: false, msg: 'Limite de 5 tokens ativos: revogue um antes.' });
    const bytes = new Uint8Array(32);
    crypto.getRandomValues(bytes);
    const token = `gpc_${Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')}`;
    const esc: EscopoMcp[] = escopos.includes('operar') ? ['ler', 'operar'] : ['ler'];
    const t: TokenMcp = {
      id: this.novoId('tok'), nome: n, prefixo: token.slice(0, 12), escopos: esc, perfilId: this.eu.vendedorId,
      perfilNome: this.nomeVendedor(this.eu.vendedorId), criadoEm: agoraIso(),
      expiraEm: new Date(agora + dias * 86400_000).toISOString(), revogadoEm: null, ultimoUsoEm: null, ativo: true,
    };
    this.tokensDb.push(t);
    return espera({ ok: true, id: t.id, token, prefixo: t.prefixo, escopos: esc, expiraEm: t.expiraEm, msg: 'Copie agora: o token não aparece de novo.' });
  }

  async revogarTokenMcp(id: string): Promise<Resultado> {
    const t = this.tokensDb.find((x) => x.id === id);
    if (!t) return espera({ ok: false, msg: 'Token não encontrado.' });
    if (t.perfilId !== this.eu.vendedorId && this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Este token não é seu.' });
    if (t.revogadoEm) return espera({ ok: true, msg: 'Já estava revogado.' });
    t.revogadoEm = agoraIso();
    return espera({ ok: true });
  }
}
