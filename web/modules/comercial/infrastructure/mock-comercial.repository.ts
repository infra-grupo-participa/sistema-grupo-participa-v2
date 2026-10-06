// Repositório de DEMONSTRAÇÃO: cumpre o contrato `ComercialRepository` em memória, sem banco.
// O estado vive enquanto a aba estiver aberta (recarregar a página volta à base inicial).
// Aplica as mesmas regras de domínio que o backend vai aplicar, para a tela se comportar como a real.
import type { ComercialRepository, NovaAtividade, NovaFicha, Resultado } from '../application/ports';
import { produto as produtoDe, ROTULO_CAMPO } from '../domain/catalogo';
import { bloqueioMoverNoFunil, camposFaltandoNoFunil, etapaDoFunil, etapaInicial, validarFunil } from '../domain/funis';
import { escolherDono, montarSck, somaPercentuais } from '../domain/regras';
import type {
  CampoKey, Conversa, EtapaFunil, EventoTimeline, Funil, MotivoPerda, Negocio, ProdutoKey, SessaoComercial, StatusFila,
  Vendedor,
} from '../domain/types';
import { funisDoProjeto } from '../domain/modelos';
import { situacaoSla } from '../domain/regras';
import type {
  MotivoPerdaConfig, Notificacao, PainelPessoa, PontoJornada, PreferenciasNotificacao, TipoPontoJornada, TipoProjeto,
} from '../domain/types';
import { gerarBaseDemo, painelPadrao, preferenciasPadrao, type BaseDemo } from './mock-dados';

const LATENCIA_MS = 120;
const espera = <T,>(v: T): Promise<T> => new Promise((ok) => setTimeout(() => ok(structuredClone(v)), LATENCIA_MS));
const agoraIso = () => new Date().toISOString();

export class MockComercialRepository implements ComercialRepository {
  private db: BaseDemo;
  private eu: SessaoComercial = { vendedorId: 'v-jonathan', papel: 'gestor' };
  private seq = 0;

  constructor() {
    this.db = gerarBaseDemo();
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
  negocios() { return espera(this.db.negocios); }
  atividades() { return espera(this.db.atividades); }
  eventos(contatoId?: string) {
    const lista = contatoId ? this.db.eventos.filter((e) => e.contatoId === contatoId) : this.db.eventos;
    return espera([...lista].sort((a, b) => b.em.localeCompare(a.em)));
  }
  templates() { return espera(this.db.templates); }
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
    this.aplicarEtapa(n, e);
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
      return espera({ ok: true, msg: 'Funil atualizado.', funilId: f.id });
    }
    const id = this.novoId('f');
    const comIds: Funil = {
      ...structuredClone(f), id, criadoEm: agoraIso(), ativo: true,
      etapas: f.etapas.map((e) => ({ ...e, id: e.id || this.novoId('et') })),
      campanhas: f.campanhas.map((c) => ({ ...c, id: c.id || this.novoId('cp'), criadoEm: c.criadoEm || agoraIso() })),
    };
    this.db.funis.push(comIds);
    return espera({ ok: true, msg: 'Funil criado.', funilId: id });
  }

  async arquivarFunil(funilId: string): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor arquiva funis.' });
    const f = this.db.funis.find((x) => x.id === funilId);
    if (!f) return espera({ ok: false, msg: 'Funil não encontrado.' });
    if (this.db.negocios.some((n) => n.funilId === funilId && n.status === 'aberto')) return espera({ ok: false, msg: 'Funil com negócio aberto não pode ser arquivado.' });
    f.ativo = false;
    return espera({ ok: true, msg: 'Funil arquivado.' });
  }

  async criarAgrupador(nome: string, produto: ProdutoKey | null): Promise<Resultado & { agrupadorId?: string }> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor cria agrupadores.' });
    if (!nome.trim()) return espera({ ok: false, msg: 'Dê um nome ao agrupador.' });
    if (this.db.agrupadores.some((a) => a.nome.trim().toLowerCase() === nome.trim().toLowerCase())) return espera({ ok: false, msg: 'Já existe um agrupador com esse nome.' });
    const id = this.novoId('ag');
    this.db.agrupadores.push({ id, nome: nome.trim(), produto, ordem: this.db.agrupadores.length + 1 });
    return espera({ ok: true, agrupadorId: id });
  }

  async salvarCampos(negocioId: string, campos: Partial<Record<CampoKey, string>>): Promise<Resultado> {
    const n = this.negocio(negocioId);
    if (!n) return espera({ ok: false, msg: 'Negócio não encontrado.' });
    n.campos = { ...n.campos, ...campos };
    return espera({ ok: true });
  }

  async marcarPerdido(negocioId: string, motivo: MotivoPerda, nota: string): Promise<Resultado> {
    const n = this.negocio(negocioId);
    if (!n || n.status !== 'aberto') return espera({ ok: false, msg: 'Só negócio aberto pode ser perdido.' });
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
    return espera({ ok: true });
  }

  async criarAtividade(a: NovaAtividade): Promise<Resultado> {
    const dono = (a.negocioId && this.negocio(a.negocioId)?.donoId) || this.eu.vendedorId;
    this.db.atividades.push({ id: this.novoId('a'), ...a, donoId: dono, concluidaEm: null, resultado: null, cadenciaDia: null });
    this.atualizarProxima(a.negocioId);
    return espera({ ok: true });
  }

  async concluirAtividade(atividadeId: string, resultado: string): Promise<Resultado> {
    const a = this.db.atividades.find((x) => x.id === atividadeId);
    if (!a || a.concluidaEm) return espera({ ok: false, msg: 'Atividade não encontrada ou já concluída.' });
    a.concluidaEm = agoraIso();
    a.resultado = resultado || 'Feito';
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
    this.evento({ contatoId, negocioId, tipo: 'nota', titulo: 'Nota interna', detalhe: texto.trim() });
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
    return espera({ ok: true });
  }

  async marcarConversaLida(contatoId: string): Promise<Resultado> {
    this.db.mensagens.filter((m) => m.contatoId === contatoId && m.direcao === 'entrada' && !m.status).forEach((m) => { m.status = 'lida'; });
    return espera({ ok: true });
  }

  async atualizarItemFila(filaId: string, itemId: string, status: StatusFila): Promise<Resultado> {
    const it = this.db.filas.find((f) => f.id === filaId)?.itens.find((i) => i.id === itemId);
    if (!it) return espera({ ok: false, msg: 'Item não encontrado.' });
    it.status = status;
    it.alteradoPor = this.eu.vendedorId;
    it.alteradoEm = agoraIso();
    return espera({ ok: true });
  }

  async salvarFicha(f: NovaFicha, enviarParaAprovacao: boolean): Promise<Resultado> {
    const v = this.db.vendedores.find((x) => x.id === this.eu.vendedorId);
    if (!v?.disparaApi) return espera({ ok: false, msg: 'Seu usuário não opera disparo por API.' });
    const ymd = new Date().toISOString().slice(0, 10).replace(/-/g, '');
    const n = this.db.fichas.filter((x) => x.codigo.includes(ymd)).length + 1;
    const codigo = `${f.produto.toUpperCase()}-${ymd}-${String(n).padStart(2, '0')}`;
    // O gestor dispara com a ficha registrada; o vendedor precisa do ok do gestor.
    const status = !enviarParaAprovacao ? 'rascunho' : this.eu.papel === 'gestor' ? 'aprovada' : 'aguardando_aprovacao';
    this.db.fichas.push({
      id: this.novoId('d'), codigo, ...f, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'],
      operadorId: this.eu.vendedorId, status, aprovadoPor: status === 'aprovada' ? this.eu.vendedorId : null, criadoEm: agoraIso(), resultado: null,
    });
    return espera({ ok: true, msg: status === 'aguardando_aprovacao' ? 'Ficha enviada para aprovação do gestor.' : status === 'aprovada' ? 'Ficha registrada e aprovada.' : 'Rascunho salvo.' });
  }

  async decidirFicha(fichaId: string, aprovar: boolean): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor aprova ficha de disparo.' });
    const f = this.db.fichas.find((x) => x.id === fichaId);
    if (!f || f.status !== 'aguardando_aprovacao') return espera({ ok: false, msg: 'Ficha não está aguardando aprovação.' });
    f.status = aprovar ? 'aprovada' : 'reprovada';
    f.aprovadoPor = this.eu.vendedorId;
    return espera({ ok: true });
  }

  async salvarDistribuicao(percentuais: Record<string, { percentual: number; ativo: boolean }>): Promise<Resultado> {
    if (this.eu.papel !== 'gestor') return espera({ ok: false, msg: 'Só o gestor define a distribuição.' });
    const novo = this.db.vendedores.map((v) => ({ ...v, ...(percentuais[v.id] ?? {}) }));
    if (somaPercentuais(novo) !== 100) return espera({ ok: false, msg: 'A soma dos percentuais dos ativos precisa dar 100%.' });
    this.db.vendedores = novo;
    return espera({ ok: true });
  }

  async criarLink(vendedorId: string, produto: ProdutoKey, acao: string, canal: string): Promise<Resultado> {
    const v = this.db.vendedores.find((x) => x.id === vendedorId);
    if (!v || !acao.trim()) return espera({ ok: false, msg: 'Informe vendedor e ação.' });
    if (this.eu.papel !== 'gestor' && vendedorId !== this.eu.vendedorId) return espera({ ok: false, msg: 'Vendedor só cria link para si mesmo.' });
    const sck = montarSck(produto, acao, new Date(), canal, v.sigla);
    if (this.db.links.some((l) => l.sck === sck)) return espera({ ok: false, msg: 'Este link já existe.' });
    this.db.links.push({ id: this.novoId('l'), vendedorId, produto, acao: acao.trim(), sck, url: `https://pay.hotmart.com/EXEMPLO?sck=${sck}` });
    return espera({ ok: true });
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
      return espera({ ok: true, msg: 'Motivo atualizado.' });
    }
    if (!atual && this.db.motivos.some((x) => x.label.trim().toLowerCase() === m.label.trim().toLowerCase())) {
      return espera({ ok: false, msg: 'Já existe um motivo com esse nome.' });
    }
    if (atual) Object.assign(atual, { ...m, sistema: false });
    else this.db.motivos.push({ ...m, label: m.label.trim(), sistema: false });
    return espera({ ok: true, msg: atual ? 'Motivo atualizado.' : 'Motivo criado.' });
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
    return espera({ ok: true, msg: `${ids.length} funis criados para ${nome.trim()}.`, funilIds: ids });
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

  async verComo(vendedorId: string) {
    const v = this.db.vendedores.find((x) => x.id === vendedorId);
    if (v) this.eu = { vendedorId: v.id, papel: v.papel };
  }
}
