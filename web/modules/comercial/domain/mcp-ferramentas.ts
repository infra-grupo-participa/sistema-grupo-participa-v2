// Ferramentas do MCP do Comercial (F7). Domínio puro: sem Next, sem Supabase.
//
// Cada ferramenta = validação dos argumentos + PLANO (quais RPCs public.crm_* chamar, com quais parâmetros) +
// montagem do resultado. Quem executa o plano é a aplicação (`application/mcp-servidor.ts`), sempre com o JWT do
// PRÓPRIO dono do token: RLS, guardas e crm.config.escrita_ligada do banco decidem o que passa. Nada aqui decide
// permissão de dado; o único corte local é o escopo do token ('ler' × 'operar').
//
// Fora de propósito (backend-arquitetura.md §5.9): transferir dono, marcar ganho/perdido, disparo/envio de WhatsApp,
// funil/motivo, produto/oferta, exportar lista. Para incluir uma ferramenta: definir aqui + teste em
// mcp-ferramentas.test.ts + a RPC na lista fechada de public.crm_mcp_rpc (migration nova).

export type EscopoMcp = 'ler' | 'operar';

export interface ChamadaRpc {
  rpc: string;
  params: Record<string, unknown>;
}

export type Validado<T> = { ok: true; valor: T } | { ok: false; msg: string };

type Args = Record<string, unknown>;

/** Quem está conectado (para filtros "só os meus"; a permissão de dado continua no banco). */
export interface ContextoMcp {
  perfilId: string;
  papel: 'gestor' | 'vendedor';
}

export interface DefFerramenta {
  name: string;
  title: string;
  description: string;
  escopo: EscopoMcp;
  inputSchema: Record<string, unknown>;
  annotations: { readOnlyHint: boolean; destructiveHint: boolean; idempotentHint: boolean; openWorldHint: boolean };
  validar(args: Args): Validado<Args>;
  plano(args: Args, agora: Date): ChamadaRpc[];
  /** Respostas das RPCs na ordem do plano → objeto devolvido ao Claude. */
  resultado(respostas: unknown[], args: Args, agora: Date, ctx: ContextoMcp): Record<string, unknown>;
  /** Escrita: a RPC devolve {ok, msg}; ok=false vira erro da ferramenta (mensagem do banco, igual à tela). */
  escrita?: boolean;
}

// ─── Validação ──────────────────────────────────────────────────────────────────────────────────────────────────────
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATA = /^\d{4}-\d{2}-\d{2}$/;
/** ISO 8601 com hora; sem fuso = horário de Brasília. */
const DATA_HORA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})?$/;
export const TIPOS_ATIVIDADE = ['whatsapp', 'ligacao', 'email', 'tarefa', 'reuniao'] as const;
const STATUS_NEGOCIO = ['aberto', 'ganho', 'perdido'] as const;
/** Brasil sem horário de verão desde 2019: São Paulo = UTC−3 fixo. */
const OFFSET_SP = '-03:00';

class ErroArg extends Error {}

function uuid(a: Args, campo: string, obrigatorio: true): string;
function uuid(a: Args, campo: string, obrigatorio: false): string | null;
function uuid(a: Args, campo: string, obrigatorio: boolean): string | null {
  const v = a[campo];
  if (v === undefined || v === null || v === '') {
    if (obrigatorio) throw new ErroArg(`Informe ${campo}.`);
    return null;
  }
  if (typeof v !== 'string' || !UUID.test(v.trim())) throw new ErroArg(`${campo} precisa ser um UUID.`);
  return v.trim().toLowerCase();
}

function texto(a: Args, campo: string, min: number, max: number, obrigatorio = true): string | null {
  const v = a[campo];
  if (v === undefined || v === null) {
    if (obrigatorio) throw new ErroArg(`Informe ${campo}.`);
    return null;
  }
  if (typeof v !== 'string') throw new ErroArg(`${campo} precisa ser texto.`);
  const t = v.trim();
  if (t.length < min || t.length > max) throw new ErroArg(`${campo} precisa ter de ${min} a ${max} caracteres.`);
  return t;
}

function inteiro(a: Args, campo: string, min: number, max: number, padrao: number): number {
  const v = a[campo];
  if (v === undefined || v === null) return padrao;
  if (typeof v !== 'number' || !Number.isInteger(v) || v < min || v > max) {
    throw new ErroArg(`${campo} precisa ser inteiro entre ${min} e ${max}.`);
  }
  return v;
}

function booleano(a: Args, campo: string, padrao: boolean): boolean {
  const v = a[campo];
  if (v === undefined || v === null) return padrao;
  if (typeof v !== 'boolean') throw new ErroArg(`${campo} precisa ser true ou false.`);
  return v;
}

function umDe<T extends string>(a: Args, campo: string, opcoes: readonly T[], padrao: T | null): T | null {
  const v = a[campo];
  if (v === undefined || v === null || v === '') return padrao;
  if (typeof v !== 'string' || !opcoes.includes(v as T)) throw new ErroArg(`${campo} precisa ser um de: ${opcoes.join(', ')}.`);
  return v as T;
}

/** Data (YYYY-MM-DD, dia em São Paulo) ou data-hora ISO → instante ISO UTC. `fimDoDia` para limite superior de data. */
/** Dia de calendário que existe (o Date do JS "rola" 31/02 para março em silêncio). */
function diaExiste(s: string): boolean {
  const [y, m, d] = s.slice(0, 10).split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d));
  return t.getUTCFullYear() === y && t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
}

export function instante(v: string, fimDoDia = false): string | null {
  const s = v.trim();
  if (!/^\d{4}-\d{2}-\d{2}/.test(s) || !diaExiste(s)) return null;
  let d: Date;
  if (DATA.test(s)) {
    d = new Date(`${s}T00:00:00${OFFSET_SP}`);
    if (fimDoDia) d = new Date(d.getTime() + 86_400_000);
  } else if (DATA_HORA.test(s)) {
    d = new Date(/(Z|[+-]\d{2}:\d{2})$/.test(s) ? s : `${s}${OFFSET_SP}`);
  } else {
    return null;
  }
  return Number.isNaN(d.getTime()) ? null : d.toISOString();
}

function instanteArg(a: Args, campo: string, obrigatorio: boolean, fimDoDia = false): string | null {
  const v = a[campo];
  if (v === undefined || v === null || v === '') {
    if (obrigatorio) throw new ErroArg(`Informe ${campo}.`);
    return null;
  }
  const i = typeof v === 'string' ? instante(v, fimDoDia) : null;
  if (!i) throw new ErroArg(`${campo} precisa ser data (AAAA-MM-DD) ou data-hora ISO.`);
  return i;
}

/** Dia (YYYY-MM-DD) de um instante no fuso de São Paulo. */
export function diaSp(agora: Date): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Sao_Paulo', year: 'numeric', month: '2-digit', day: '2-digit' }).format(agora);
}

/** Início e fim (exclusivo) do dia em São Paulo, em ISO UTC. */
export function limitesDoDia(dia: string): { inicio: string; fim: string } {
  const inicio = new Date(`${dia}T00:00:00${OFFSET_SP}`);
  return { inicio: inicio.toISOString(), fim: new Date(inicio.getTime() + 86_400_000).toISOString() };
}

function validarCom(fn: (a: Args) => Args): (args: Args) => Validado<Args> {
  return (args) => {
    try {
      return { ok: true, valor: fn(args ?? {}) };
    } catch (e) {
      if (e instanceof ErroArg) return { ok: false, msg: e.message };
      throw e;
    }
  };
}

// ─── Formatação compacta (só o que ajuda o Claude a responder; nada de PII além do que a RPC já devolve) ─────────────
type Obj = Record<string, unknown>;
const lista = (v: unknown): Obj[] => (Array.isArray(v) ? (v as Obj[]) : []);

function negocioCompacto(n: Obj): Obj {
  const pa = n.proximaAtividade as Obj | null | undefined;
  return {
    id: n.id, contatoId: n.contatoId, funilId: n.funilId, etapaId: n.etapaId, etapaNome: n.etapaNome, status: n.status,
    donoId: n.donoId, valor: n.valor, origem: n.origem, criadoEm: n.criadoEm, etapaDesde: n.etapaDesde,
    ultimaInteracaoEm: n.ultimaInteracaoEm ?? null,
    proximaAtividade: pa ? { id: pa.id, tipo: pa.tipo, titulo: pa.titulo, venceEm: pa.venceEm } : null,
  };
}

const SCHEMA_UUID = { type: 'string', format: 'uuid' };
const ANOT_LER = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };

// ─── Ferramentas ────────────────────────────────────────────────────────────────────────────────────────────────────
export const FERRAMENTAS: DefFerramenta[] = [
  {
    name: 'comercial_listar_funis',
    title: 'Listar funis do CRM',
    description: 'Lista os funis ativos do CRM Comercial com as etapas (id, nome, papel). Use para descobrir funil_id e etapa_id.',
    escopo: 'ler',
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: ANOT_LER,
    validar: validarCom(() => ({})),
    plano: () => [{ rpc: 'crm_funis', params: {} }],
    resultado: ([funis]) => ({
      funis: lista(funis).map((f) => ({
        id: f.id, nome: f.nome, produto: f.produto, tipo: f.tipo,
        etapas: lista(f.etapas).map((e) => ({ id: e.id, nome: e.nome, papel: e.papel })),
      })),
    }),
  },
  {
    name: 'comercial_resumo_funil',
    title: 'Resumo de um funil',
    description: 'Negócios abertos por etapa (quantidade, valor, sem dono, estourados no SLA) e ganhos/perdidos dos últimos 30 dias. '
      + 'Vendedor vê só os seus + os sem dono; gestor vê o time.',
    escopo: 'ler',
    inputSchema: { type: 'object', properties: { funil_id: SCHEMA_UUID }, required: ['funil_id'], additionalProperties: false },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ funil_id: uuid(a, 'funil_id', true) })),
    plano: (a) => [{ rpc: 'crm_funil_resumo', params: { p_funil: a.funil_id } }],
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
  {
    name: 'comercial_negocios_por_etapa',
    title: 'Negócios (por funil e etapa)',
    description: 'Lista negócios com a próxima atividade, opcionalmente de UM funil e de UMA etapa. Padrão: só abertos, até 50. '
      + 'apenas_meus=true traz só os negócios de que a pessoa conectada é dona ("meus negócios").',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: {
        funil_id: SCHEMA_UUID,
        etapa_id: SCHEMA_UUID,
        status: { type: 'string', enum: [...STATUS_NEGOCIO], default: 'aberto' },
        apenas_meus: { type: 'boolean', default: false },
        limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
      },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({
      funil_id: uuid(a, 'funil_id', false),
      etapa_id: uuid(a, 'etapa_id', false),
      status: umDe(a, 'status', STATUS_NEGOCIO, 'aberto'),
      apenas_meus: booleano(a, 'apenas_meus', false),
      limite: inteiro(a, 'limite', 1, 200, 50),
    })),
    // Sem filtro local: a própria RPC limita. Com etapa/apenas_meus: a RPC não filtra por isso, então traz até 1.000
    // (lista já cortada pela RLS) e o filtro é feito aqui. Para contagens use comercial_resumo_funil (agregado no banco).
    plano: (a) => [{
      rpc: 'crm_negocios',
      params: { p_funil: a.funil_id, p_status: a.status, p_limite: a.etapa_id || a.apenas_meus ? 1000 : a.limite },
    }],
    resultado: ([ns], a, _agora, ctx) => {
      const todos = lista(ns)
        .filter((n) => !a.etapa_id || n.etapaId === a.etapa_id)
        .filter((n) => !a.apenas_meus || n.donoId === ctx.perfilId);
      const limite = a.limite as number;
      return { total: todos.length, temMais: todos.length > limite, negocios: todos.slice(0, limite).map(negocioCompacto) };
    },
  },
  {
    name: 'comercial_buscar_pessoa',
    title: 'Buscar pessoa no CRM',
    description: 'Busca contatos do Comercial por e-mail, telefone ou nome (mínimo 3 caracteres, até 20 resultados). '
      + 'E-mail/telefone completos só para o dono do contato ou gestor; o resto vem mascarado. Nunca CPF.',
    escopo: 'ler',
    inputSchema: { type: 'object', properties: { busca: { type: 'string', minLength: 3, maxLength: 120 } }, required: ['busca'], additionalProperties: false },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ busca: texto(a, 'busca', 3, 120) })),
    plano: (a) => [{ rpc: 'crm_contatos', params: { p_busca: a.busca, p_limite: 20 } }],
    resultado: ([r]) => {
      const o = (r && typeof r === 'object' ? r : {}) as Obj;
      return { temMais: o.temMais === true, pessoas: lista(o.itens) };
    },
  },
  {
    name: 'comercial_pessoa_jornada',
    title: 'Pessoa: jornada, negócios e atividades',
    description: 'Tudo o que a pessoa fez com a empresa (compras, grupos, pesquisas, etapas, notas) + negócios e atividades dela. '
      + 'Só para quem pode ver a pessoa (dono, sem dono ou gestor).',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: { pessoa_id: SCHEMA_UUID, limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 } },
      required: ['pessoa_id'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ pessoa_id: uuid(a, 'pessoa_id', true), limite: inteiro(a, 'limite', 1, 200, 50) })),
    plano: (a) => [
      { rpc: 'crm_jornada', params: { p_pessoa: a.pessoa_id, p_limite: a.limite } },
      { rpc: 'crm_negocios', params: { p_pessoa: a.pessoa_id, p_limite: 50 } },
      { rpc: 'crm_atividades', params: { p_pessoa: a.pessoa_id, p_limite: 100 } },
    ],
    resultado: ([j, ns, ats], a) => ({
      pessoaId: a.pessoa_id,
      jornada: lista(j),
      negocios: lista(ns).map(negocioCompacto),
      atividades: lista(ats),
    }),
  },
  {
    name: 'comercial_atividades_do_dia',
    title: 'Atividades do dia',
    description: 'Agenda de um dia (padrão: hoje, horário de Brasília): atividades que vencem no dia, atrasadas e concluídas no dia. '
      + 'Vendedor vê as suas; gestor vê as do time.',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: {
        data: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$', description: 'AAAA-MM-DD (padrão: hoje)' },
        incluir_atrasadas: { type: 'boolean', default: true },
      },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => {
      const d = a.data;
      if (d !== undefined && d !== null && (typeof d !== 'string' || !DATA.test(d) || !instante(d))) {
        throw new ErroArg('data precisa ser AAAA-MM-DD.');
      }
      return { data: (d as string | undefined) ?? null, incluir_atrasadas: booleano(a, 'incluir_atrasadas', true) };
    }),
    plano: (a, agora) => {
      const { inicio } = limitesDoDia((a.data as string | null) ?? diaSp(agora));
      // crm_atividades devolve TODAS as abertas + as concluídas desde p_desde (limite 2.000, por vencimento)
      return [{ rpc: 'crm_atividades', params: { p_desde: inicio, p_limite: 2000 } }];
    },
    resultado: ([ats], a, agora) => {
      const dia = (a.data as string | null) ?? diaSp(agora);
      const { inicio, fim } = limitesDoDia(dia);
      const t = (v: unknown) => (typeof v === 'string' ? Date.parse(v) : NaN);
      const ini = Date.parse(inicio);
      const fi = Date.parse(fim);
      const todas = lista(ats);
      const abertas = todas.filter((x) => !x.concluidaEm);
      return {
        data: dia,
        doDia: abertas.filter((x) => t(x.venceEm) >= ini && t(x.venceEm) < fi),
        atrasadas: a.incluir_atrasadas ? abertas.filter((x) => t(x.venceEm) < ini) : [],
        concluidas: todas.filter((x) => x.concluidaEm && t(x.concluidaEm) >= ini && t(x.concluidaEm) < fi),
      };
    },
  },
  {
    name: 'comercial_sem_proximo_passo',
    title: 'Negócios sem próximo passo',
    description: 'Negócios ABERTOS sem nenhuma atividade agendada (sem próximo passo), do mais parado para o mais recente. '
      + 'Padrão: vendedor vê só os seus; gestor vê o time (apenas_meus=true restringe aos dele). Opcional: um funil.',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: {
        funil_id: SCHEMA_UUID,
        apenas_meus: { type: 'boolean', description: 'Padrão: true para vendedor, false para gestor' },
        limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
      },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => {
      const m = a.apenas_meus;
      if (m !== undefined && m !== null && typeof m !== 'boolean') throw new ErroArg('apenas_meus precisa ser true ou false.');
      return { funil_id: uuid(a, 'funil_id', false), apenas_meus: m ?? null, limite: inteiro(a, 'limite', 1, 200, 50) };
    }),
    plano: (a) => [{ rpc: 'crm_negocios', params: { p_funil: a.funil_id, p_status: 'aberto', p_limite: 1000 } }],
    resultado: ([ns], a, _agora, ctx) => {
      const meus = (a.apenas_meus as boolean | null) ?? ctx.papel === 'vendedor';
      const parado = (n: Obj) => Date.parse(String(n.ultimaInteracaoEm ?? n.etapaDesde ?? n.criadoEm ?? '')) || 0;
      const sem = lista(ns)
        .filter((n) => !n.proximaAtividade)
        .filter((n) => !meus || n.donoId === ctx.perfilId)
        .sort((x, y) => parado(x) - parado(y));
      const limite = a.limite as number;
      return { apenasMeus: meus, total: sem.length, temMais: sem.length > limite, negocios: sem.slice(0, limite).map(negocioCompacto) };
    },
  },
  {
    name: 'comercial_conversa_whatsapp',
    title: 'Conversa de WhatsApp da pessoa',
    description: 'Mensagens de WhatsApp trocadas com a pessoa (mais antigas primeiro; padrão: as últimas 100), para resumir a '
      + 'conversa ou preparar o próximo contato. Só leitura: NÃO envia mensagem. Só para quem pode ver a pessoa.',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: { pessoa_id: SCHEMA_UUID, limite: { type: 'integer', minimum: 1, maximum: 300, default: 100 } },
      required: ['pessoa_id'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ pessoa_id: uuid(a, 'pessoa_id', true), limite: inteiro(a, 'limite', 1, 300, 100) })),
    plano: (a) => [{ rpc: 'crm_mensagens', params: { p_pessoa: a.pessoa_id, p_limite: a.limite } }],
    resultado: ([ms], a) => {
      const msgs = lista(ms).map((m) => ({
        em: m.em, de: m.direcao === 'entrada' ? 'cliente' : 'equipe', tipo: m.tipo, texto: m.texto ?? null,
        ...(m.status ? { status: m.status } : {}), ...(m.erro ? { falhou: true } : {}),
      }));
      return { pessoaId: a.pessoa_id, total: msgs.length, mensagens: msgs };
    },
  },
  {
    name: 'comercial_desempenho',
    title: 'Desempenho comercial',
    description: 'Por dono no período: abertos, criados, ganhos (e valor), perdidos, taxa de conversão, atividades concluídas e atrasadas. '
      + 'Padrão: hoje. Vendedor vê só a própria linha (+ sem dono); gestor vê o time. Período máximo de 366 dias.',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: {
        desde: { type: 'string', description: 'AAAA-MM-DD ou data-hora ISO (padrão: início de hoje)' },
        ate: { type: 'string', description: 'AAAA-MM-DD (inclusive) ou data-hora ISO (padrão: agora)' },
      },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ desde: instanteArg(a, 'desde', false), ate: instanteArg(a, 'ate', false, true) })),
    plano: (a) => {
      const params: Record<string, unknown> = {};
      if (a.desde) params.p_desde = a.desde;
      if (a.ate) params.p_ate = a.ate;
      return [{ rpc: 'crm_desempenho', params }];
    },
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
  {
    name: 'comercial_criar_atividade',
    title: 'Criar atividade',
    description: 'Agenda uma atividade (whatsapp, ligacao, email, tarefa, reuniao) para uma pessoa, opcionalmente ligada a um negócio. '
      + 'Só nas pessoas/negócios que são seus (gestor: todos). Fica no registro do CRM como feita via MCP.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        pessoa_id: SCHEMA_UUID,
        negocio_id: SCHEMA_UUID,
        tipo: { type: 'string', enum: [...TIPOS_ATIVIDADE] },
        titulo: { type: 'string', minLength: 1, maxLength: 200 },
        vence_em: { type: 'string', description: 'Data-hora ISO; sem fuso = horário de Brasília' },
      },
      required: ['pessoa_id', 'tipo', 'titulo', 'vence_em'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    validar: validarCom((a) => ({
      pessoa_id: uuid(a, 'pessoa_id', true),
      negocio_id: uuid(a, 'negocio_id', false),
      tipo: umDe(a, 'tipo', TIPOS_ATIVIDADE, null) ?? (() => { throw new ErroArg('Informe tipo.'); })(),
      titulo: texto(a, 'titulo', 1, 200),
      vence_em: instanteArg(a, 'vence_em', true),
    })),
    plano: (a) => [{
      rpc: 'crm_criar_atividade',
      params: { p_negocio: a.negocio_id, p_pessoa: a.pessoa_id, p_tipo: a.tipo, p_titulo: a.titulo, p_vence_em: a.vence_em },
    }],
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
  {
    name: 'comercial_adicionar_nota',
    title: 'Adicionar nota',
    description: 'Registra uma nota interna na pessoa (e no negócio, se informado). Só nas pessoas/negócios que são seus (gestor: todos).',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: { pessoa_id: SCHEMA_UUID, negocio_id: SCHEMA_UUID, texto: { type: 'string', minLength: 1, maxLength: 5000 } },
      required: ['pessoa_id', 'texto'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false },
    validar: validarCom((a) => ({
      pessoa_id: uuid(a, 'pessoa_id', true),
      negocio_id: uuid(a, 'negocio_id', false),
      texto: texto(a, 'texto', 1, 5000),
    })),
    plano: (a) => [{ rpc: 'crm_adicionar_nota', params: { p_pessoa: a.pessoa_id, p_negocio: a.negocio_id, p_texto: a.texto } }],
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
  {
    name: 'comercial_concluir_atividade',
    title: 'Concluir atividade',
    description: 'Marca uma atividade SUA (gestor: qualquer) como feita, com o resultado opcional (ex.: "Atendeu, pediu proposta"). '
      + 'Use o id que aparece em comercial_atividades_do_dia ou comercial_pessoa_jornada.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: { atividade_id: SCHEMA_UUID, resultado: { type: 'string', maxLength: 1000 } },
      required: ['atividade_id'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    validar: validarCom((a) => ({ atividade_id: uuid(a, 'atividade_id', true), resultado: texto(a, 'resultado', 0, 1000, false) })),
    plano: (a) => [{ rpc: 'crm_concluir_atividade', params: { p_atividade: a.atividade_id, p_resultado: a.resultado } }],
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
  {
    name: 'comercial_mover_etapa',
    title: 'Mover negócio de etapa',
    description: 'Move um negócio SEU (gestor: qualquer) para outra etapa do mesmo funil. Etapa de Ganho é recusada (ganho só por '
      + 'pagamento aprovado); campos obrigatórios da etapa são exigidos.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: { negocio_id: SCHEMA_UUID, etapa_id: SCHEMA_UUID },
      required: ['negocio_id', 'etapa_id'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false },
    validar: validarCom((a) => ({ negocio_id: uuid(a, 'negocio_id', true), etapa_id: uuid(a, 'etapa_id', true) })),
    plano: (a) => [{ rpc: 'crm_mover_etapa', params: { p_negocio: a.negocio_id, p_etapa: a.etapa_id } }],
    resultado: ([r]) => (r && typeof r === 'object' ? (r as Obj) : {}),
  },
];

export function acharFerramenta(nome: unknown): DefFerramenta | undefined {
  return typeof nome === 'string' ? FERRAMENTAS.find((f) => f.name === nome) : undefined;
}

/** Ferramentas visíveis para os escopos do token ('operar' sem 'ler' não existe: o banco garante 'ler'). */
export function ferramentasDoEscopo(escopos: readonly string[]): DefFerramenta[] {
  return FERRAMENTAS.filter((f) => escopos.includes(f.escopo));
}

/** Formato do tools/list do MCP. */
export function descreverFerramenta(f: DefFerramenta) {
  return { name: f.name, title: f.title, description: f.description, inputSchema: f.inputSchema, annotations: f.annotations };
}
