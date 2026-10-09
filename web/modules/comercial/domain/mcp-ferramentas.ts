// Ferramentas do MCP do Comercial (F7). Domínio puro: sem Next, sem Supabase.
import { MAX_TAGS_CONTATO, normalizarTag } from './tags';
import { normalizarValorCampo, sugerirCampos, type TextoLead } from './campos-negocio';
import { lerLinkCrm } from './link-crm';
import { LIMITE_PAGINA, PARTES_PLAYBOOK, buscarPlaybook, indicePlaybook, lerSecao } from './playbook/mcp-playbook';
//
// Cada ferramenta = validação dos argumentos + PLANO (quais RPCs public.crm_* chamar, com quais parâmetros) +
// montagem do resultado. Quem executa o plano é a aplicação (`application/mcp-servidor.ts`), sempre com o JWT do
// PRÓPRIO dono do token: RLS, guardas e crm.config.escrita_ligada do banco decidem o que passa. Nada aqui decide
// permissão de dado; o único corte local é o escopo do token ('ler' × 'operar').
//
// Fora de propósito (backend-arquitetura.md §5.9): transferir dono, marcar ganho/perdido, disparo em massa, funil/motivo,
// produto/oferta, exportar lista, apagar contato (exclusão aguarda decisão do Arthur). Envio de WhatsApp 1:1 entrou em
// 08/10/2026 (decisão do Arthur, migration 20261008233100): as travas moram no banco (crm_mcp_enviar_whatsapp).
// Para incluir uma ferramenta: definir aqui + teste em mcp-ferramentas.test.ts + a RPC na lista fechada de
// public.crm_mcp_rpc (migration nova).
// Exceção: ferramenta `local` (playbook, 09/10/2026) não toca o banco além da autenticação do token (que valida,
// aplica kill-switch e limite e registra a chamada em crm.mcp_chamada): plano vazio, resposta montada aqui com o
// conteúdo do próprio app (domain/playbook). Não precisa de migration.

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
  /** A RPC devolve {ok, msg}; ok=false vira erro da ferramenta (mensagem do banco, igual à tela). Toda escrita e as
   *  consultas do WhatsApp (que também respondem {ok, msg}). */
  escrita?: boolean;
  /** Só servidor: plano vazio, nenhuma RPC além da autenticação do token. Só leitura de conteúdo do app. */
  local?: boolean;
}

// ─── Validação ──────────────────────────────────────────────────────────────────────────────────────────────────────
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATA = /^\d{4}-\d{2}-\d{2}$/;
/** ISO 8601 com hora; sem fuso = horário de Brasília. */
const DATA_HORA = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d{1,6})?)?(Z|[+-]\d{2}:\d{2})?$/;
export const TIPOS_ATIVIDADE = ['whatsapp', 'ligacao', 'email', 'tarefa', 'reuniao'] as const;
const STATUS_NEGOCIO = ['aberto', 'ganho', 'perdido'] as const;
const PERFIS = ['advogado', 'contador', 'outro'] as const;
const HOLDING = ['sim', 'nao', 'comecando'] as const;
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

/** Lista de tags: 1 a 30 textos; cada um precisa sobrar letra/número depois de normalizar (crm.tag_normalizar). */
function listaTags(a: Args, campo: string): string[] {
  const v = a[campo];
  if (!Array.isArray(v) || v.length < 1 || v.length > MAX_TAGS_CONTATO) throw new ErroArg(`${campo} precisa ser lista de 1 a ${MAX_TAGS_CONTATO} tags.`);
  const out: string[] = [];
  for (const t of v) {
    if (typeof t !== 'string' || t.trim().length < 1 || t.trim().length > 60) throw new ErroArg(`Cada tag precisa ser texto de 1 a 60 caracteres.`);
    if (!normalizarTag(t)) throw new ErroArg(`Tag inválida: "${t.trim()}" (use letras ou números).`);
    out.push(t.trim());
  }
  return out;
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

function mensagemCompacta(m: Obj): Obj {
  return {
    em: m.em, de: m.direcao === 'entrada' ? 'cliente' : 'equipe', tipo: m.tipo, texto: m.texto ?? null,
    ...(m.status ? { status: m.status } : {}), ...(m.erro ? { falhou: true } : {}),
  };
}

const SCHEMA_UUID = { type: 'string', format: 'uuid' };
const ANOT_LER = { readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const ANOT_ESCREVE = { readOnlyHint: false, destructiveHint: false, idempotentHint: false, openWorldHint: false };
const ANOT_ESCREVE_IDEMP = { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: false };
const SCHEMA_TAGS = { type: 'array', items: { type: 'string', minLength: 1, maxLength: 60 }, minItems: 1, maxItems: MAX_TAGS_CONTATO };
const resultadoRpc = ([r]: unknown[]) => (r && typeof r === 'object' ? (r as Obj) : {});

/** Campos editáveis do contato (MCP → chave de p_dados de crm_editar_contato) e limites (os mesmos do banco). */
const CAMPOS_EDICAO: { arg: string; chave: string; min: number; max: number }[] = [
  { arg: 'nome', chave: 'nome', min: 2, max: 160 },
  { arg: 'telefone', chave: 'telefone', min: 0, max: 30 },
  { arg: 'email', chave: 'email', min: 0, max: 200 },
  { arg: 'cidade', chave: 'cidade', min: 0, max: 120 },
  { arg: 'uf', chave: 'uf', min: 0, max: 2 },
  { arg: 'empresa', chave: 'empresa', min: 0, max: 160 },
  { arg: 'observacao', chave: 'observacao', min: 0, max: 1000 },
];

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
      const msgs = lista(ms).map(mensagemCompacta);
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
  {
    name: 'comercial_criar_contato',
    title: 'Criar contato',
    description: 'Cadastra um contato (nome + telefone e/ou e-mail). Antes, confere duplicidade como a tela: se o e-mail ou o '
      + 'telefone já estiver no CRM, NÃO cria outro e devolve o contato existente (nova=false, contatoId) sem trocar o dono. '
      + 'Vendedor vira dono do que cadastra. Busque antes com comercial_buscar_pessoa.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        nome: { type: 'string', minLength: 2, maxLength: 160 },
        telefone: { type: 'string', maxLength: 30, description: 'DDD + número (celular com 9)' },
        email: { type: 'string', maxLength: 200 },
      },
      required: ['nome'],
      additionalProperties: false,
    },
    annotations: ANOT_ESCREVE_IDEMP,
    validar: validarCom((a) => {
      const nome = texto(a, 'nome', 2, 160);
      const telefone = texto(a, 'telefone', 0, 30, false) || null;
      const email = texto(a, 'email', 0, 200, false) || null;
      if (!telefone && !email) throw new ErroArg('Informe telefone ou e-mail.');
      if (telefone && !/^\+?[\d\s().-]{8,30}$/.test(telefone)) throw new ErroArg('telefone inválido: use DDD + número.');
      if (email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new ErroArg('email inválido.');
      return { nome, telefone, email };
    }),
    plano: (a) => {
      const dados: Record<string, unknown> = { nome: a.nome };
      if (a.telefone) dados.telefone = a.telefone;
      if (a.email) dados.email = a.email;
      return [{ rpc: 'crm_criar_contato', params: { p_dados: dados } }];
    },
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_editar_contato',
    title: 'Editar contato',
    description: 'Corrige a ficha de um contato SEU (gestor: qualquer): nome, telefone, e-mail, cidade, UF, perfil '
      + '(advogado, contador, outro), atua_com_holding (sim, nao, comecando), empresa e observação. Só os campos enviados mudam. '
      + 'Telefone/e-mail novo vira o principal e o antigo fica guardado (nada é apagado); recusa se já for de outro contato. '
      + 'Texto vazio ("") volta o campo ao dado da base.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        pessoa_id: SCHEMA_UUID,
        nome: { type: 'string', minLength: 2, maxLength: 160 },
        telefone: { type: 'string', maxLength: 30 },
        email: { type: 'string', maxLength: 200 },
        cidade: { type: 'string', maxLength: 120 },
        uf: { type: 'string', maxLength: 2 },
        perfil: { type: 'string', enum: [...PERFIS, ''] },
        atua_com_holding: { type: 'string', enum: [...HOLDING, ''] },
        empresa: { type: 'string', maxLength: 160 },
        observacao: { type: 'string', maxLength: 1000 },
      },
      required: ['pessoa_id'],
      additionalProperties: false,
    },
    annotations: ANOT_ESCREVE_IDEMP,
    validar: validarCom((a) => {
      const dados: Record<string, string> = {};
      for (const c of CAMPOS_EDICAO) {
        const v = texto(a, c.arg, c.min, c.max, false);
        if (v !== null) dados[c.chave] = v;
      }
      if (dados.uf && !/^[A-Za-z]{2}$/.test(dados.uf)) throw new ErroArg('uf precisa ser a sigla (ex.: SP).');
      const perfil = umDe(a, 'perfil', PERFIS, null);
      if (perfil || a.perfil === '') dados.perfil = perfil ?? '';
      const holding = umDe(a, 'atua_com_holding', HOLDING, null);
      if (holding || a.atua_com_holding === '') dados.atuaComHolding = holding ?? '';
      if (Object.keys(dados).length === 0) throw new ErroArg('Informe ao menos um campo para mudar.');
      return { pessoa_id: uuid(a, 'pessoa_id', true), dados };
    }),
    plano: (a) => [{ rpc: 'crm_editar_contato', params: { p_contato: a.pessoa_id, p_dados: a.dados } }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_tag_adicionar',
    title: 'Adicionar tags ao contato',
    description: 'Adiciona tags a um contato SEU (gestor: qualquer). A tag é normalizada (minúsculo, sem acento, hífen no lugar '
      + 'de espaço, até 40 caracteres: "Quente Ágora" vira "quente-agora"); a que já existe não repete. Máximo de 30 tags por contato.',
    escopo: 'operar',
    escrita: true,
    inputSchema: { type: 'object', properties: { pessoa_id: SCHEMA_UUID, tags: SCHEMA_TAGS }, required: ['pessoa_id', 'tags'], additionalProperties: false },
    annotations: ANOT_ESCREVE_IDEMP,
    validar: validarCom((a) => ({ pessoa_id: uuid(a, 'pessoa_id', true), tags: listaTags(a, 'tags') })),
    plano: (a) => [{ rpc: 'crm_tags_contato', params: { p_pessoa: a.pessoa_id, p_adicionar: a.tags } }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_tag_remover',
    title: 'Remover tags do contato',
    description: 'Remove tags de um contato SEU (gestor: qualquer). Compara pela forma normalizada: "ht alunos" tira "[HT] ALUNOS".',
    escopo: 'operar',
    escrita: true,
    inputSchema: { type: 'object', properties: { pessoa_id: SCHEMA_UUID, tags: SCHEMA_TAGS }, required: ['pessoa_id', 'tags'], additionalProperties: false },
    annotations: ANOT_ESCREVE_IDEMP,
    validar: validarCom((a) => ({ pessoa_id: uuid(a, 'pessoa_id', true), tags: listaTags(a, 'tags') })),
    plano: (a) => [{ rpc: 'crm_tags_contato', params: { p_pessoa: a.pessoa_id, p_remover: a.tags } }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_reabrir_atividade',
    title: 'Reabrir atividade',
    description: 'Desfaz a conclusão de uma atividade SUA (gestor: qualquer): ela volta para a agenda, sem resultado. '
      + 'Use quando marcou como feita por engano.',
    escopo: 'operar',
    escrita: true,
    inputSchema: { type: 'object', properties: { atividade_id: SCHEMA_UUID }, required: ['atividade_id'], additionalProperties: false },
    annotations: ANOT_ESCREVE,
    validar: validarCom((a) => ({ atividade_id: uuid(a, 'atividade_id', true) })),
    plano: (a) => [{ rpc: 'crm_reabrir_atividade', params: { p_atividade: a.atividade_id } }],
    resultado: resultadoRpc,
  },
  // ─── WhatsApp pelo Claude (migration 20261008233100). As regras moram no banco; aqui só valida o formato. ────────
  {
    name: 'comercial_numeros_whatsapp',
    title: 'Números de WhatsApp para enviar',
    description: 'Lista os números de WhatsApp que você pode usar para enviar: nome, tipo (Oficial = API Infobip; QR = WhatsApp '
      + 'comum conectado por QR), status, 4 últimos dígitos e se envia agora. No Oficial, texto livre só com a janela de 24 h '
      + 'aberta (senão template); no QR, texto livre sempre (sem template). Traz também os limites de envio.',
    escopo: 'operar',
    escrita: true,
    inputSchema: { type: 'object', properties: {}, additionalProperties: false },
    annotations: ANOT_LER,
    validar: validarCom(() => ({})),
    plano: () => [{ rpc: 'crm_mcp_numeros', params: {} }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_templates_whatsapp',
    title: 'Templates aprovados do WhatsApp oficial',
    description: 'Templates aprovados do número oficial: nome, idioma, categoria, número de variáveis e prévia do texto. '
      + 'Filtre com busca (no nome ou no texto). {{1}} é sempre o primeiro nome do contato, preenchido pelo CRM. '
      + 'usavel=false (2+ variáveis, ex.: link) só sai por ficha de disparo, não por aqui.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        busca: { type: 'string', maxLength: 80, description: 'Parte do nome ou do texto (ex.: "aula", "ht")' },
        limite: { type: 'integer', minimum: 1, maximum: 200, default: 50 },
      },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ busca: texto(a, 'busca', 0, 80, false) || null, limite: inteiro(a, 'limite', 1, 200, 50) })),
    plano: (a) => [{ rpc: 'crm_mcp_templates', params: { p_busca: a.busca, p_limite: a.limite } }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_situacao_conversa',
    title: 'Situação da conversa (texto livre ou template?)',
    description: 'Para um contato e um número: se pode mandar texto livre (QR sempre; Oficial só com a janela de 24 h aberta, '
      + 'contada naquele número) ou se precisa template, quando a janela fecha, o destinatário (nome + 4 últimos dígitos) e '
      + 'bloqueios (opt-out, número desconectado, envio desligado). Com template, devolve a prévia já com o nome do contato. '
      + 'Use antes de comercial_enviar_whatsapp para montar a confirmação. Sem numero_id: o da conversa mais recente, senão o oficial.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        contato_id: { ...SCHEMA_UUID, description: 'pessoa_id de comercial_buscar_pessoa' },
        numero_id: { ...SCHEMA_UUID, description: 'id de comercial_numeros_whatsapp (opcional)' },
        template: { type: 'string', minLength: 1, maxLength: 200, description: 'Nome ou id do template (opcional, para a prévia)' },
      },
      required: ['contato_id'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({
      contato_id: uuid(a, 'contato_id', true),
      numero_id: uuid(a, 'numero_id', false),
      template: texto(a, 'template', 1, 200, false),
    })),
    plano: (a) => {
      const params: Record<string, unknown> = { p_contato: a.contato_id };
      if (a.numero_id) params.p_canal = a.numero_id;
      if (a.template) params.p_template = a.template;
      return [{ rpc: 'crm_mcp_situacao_conversa', params }];
    },
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_enviar_whatsapp',
    title: 'Enviar WhatsApp',
    description: 'IMPORTANTE: antes de chamar, mostre ao usuário o texto final (ou a prévia do template), o número e o '
      + 'destinatário e peça confirmação explícita. Sem um "pode enviar" do usuário para ESTA mensagem, não chame. '
      + 'Envia UMA mensagem de WhatsApp a UM contato seu (gestor: do time), no seu nome, marcada "via Claude". '
      + 'Mande texto OU template (nome ou id de comercial_templates_whatsapp; {{1}} = primeiro nome, preenchido pelo CRM). '
      + 'Número Oficial: texto livre só com a janela de 24 h aberta; fora dela, template (veja comercial_situacao_conversa). '
      + 'Número QR: só texto. chave_idempotencia: gere um UUID novo para cada mensagem e reuse o MESMO só se for repetir a '
      + 'chamada por erro de rede (não duplica). Recusa: opt-out, contato de outro dono, mais de 30 por hora, menos de 20 s '
      + 'para o mesmo contato, limites anti-ban do QR. Nunca use para envio em massa.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        contato_id: { ...SCHEMA_UUID, description: 'pessoa_id de comercial_buscar_pessoa' },
        numero_id: { ...SCHEMA_UUID, description: 'id de comercial_numeros_whatsapp. Padrão: o da conversa mais recente, senão o oficial' },
        texto: { type: 'string', minLength: 1, maxLength: 4096 },
        template: { type: 'string', minLength: 1, maxLength: 200, description: 'Nome ou id de template aprovado (só número Oficial)' },
        chave_idempotencia: { ...SCHEMA_UUID, description: 'UUID novo por mensagem; o mesmo só para repetir a chamada' },
      },
      required: ['contato_id', 'chave_idempotencia'],
      additionalProperties: false,
    },
    annotations: { readOnlyHint: false, destructiveHint: false, idempotentHint: true, openWorldHint: true },
    validar: validarCom((a) => {
      const msg = texto(a, 'texto', 1, 4096, false);
      const template = texto(a, 'template', 1, 200, false);
      if (!msg === !template) throw new ErroArg('Informe texto OU template (um dos dois).');
      return {
        contato_id: uuid(a, 'contato_id', true),
        numero_id: uuid(a, 'numero_id', false),
        texto: msg,
        template,
        chave_idempotencia: uuid(a, 'chave_idempotencia', true),
      };
    }),
    plano: (a) => {
      const params: Record<string, unknown> = { p_contato: a.contato_id, p_chave: a.chave_idempotencia };
      if (a.numero_id) params.p_canal = a.numero_id;
      if (a.texto) params.p_texto = a.texto;
      if (a.template) params.p_template = a.template;
      return [{ rpc: 'crm_mcp_enviar_whatsapp', params }];
    },
    resultado: resultadoRpc,
  },
  // ─── Campos do negócio, sugestão pela conversa e link do sistema (migration 20261009153128) ─────────────────────
  {
    name: 'comercial_campos_negocio',
    title: 'Campos do negócio',
    description: 'Campos de qualificação de UM negócio: perfil profissional (advogado, contador, outro), se já atua com holding '
      + '(sim, comecando, nao), produto de interesse, origem, objeção principal e forma de pagamento — com rótulo, opções '
      + 'válidas e valor atual. Traz também a próxima etapa do funil e quais campos ela exige (faltando). Use antes de '
      + 'comercial_preencher_campos.',
    escopo: 'ler',
    inputSchema: { type: 'object', properties: { negocio_id: SCHEMA_UUID }, required: ['negocio_id'], additionalProperties: false },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ negocio_id: uuid(a, 'negocio_id', true) })),
    plano: (a) => [{ rpc: 'crm_mcp_negocio_campos', params: { p_negocio: a.negocio_id } }],
    resultado: resultadoRpc,
  },
  {
    name: 'comercial_preencher_campos',
    title: 'Preencher campos do negócio',
    description: 'Grava campos de qualificação de um negócio SEU (gestor: qualquer), pela mesma regra da tela. Pode ser usada '
      + 'quando o vendedor pedir, inclusive por voz ("marca como contador começando em holding"). Quando você identificar o '
      + 'perfil numa conversa que leu, PROPONHA o preenchimento e confirme com o usuário antes de gravar. campos = '
      + '{chave: valor}; aceita linguagem natural, que é normalizada (contadora → contador; começando → comecando; '
      + 'Holding Total → ht; Clínica Miami → clinica_miami; "no pix" → pix). Valor vazio ("") limpa o campo. O banco valida '
      + 'contra as opções de comercial_campos_negocio e devolve o que mudou.',
    escopo: 'operar',
    escrita: true,
    inputSchema: {
      type: 'object',
      properties: {
        negocio_id: SCHEMA_UUID,
        campos: {
          type: 'object',
          description: 'Ex.: {"perfil_profissional": "contador", "atua_com_holding": "começando", "produto_interesse": "Holding Total"}',
          additionalProperties: { type: ['string', 'null'], maxLength: 200 },
          minProperties: 1,
          maxProperties: 10,
        },
      },
      required: ['negocio_id', 'campos'],
      additionalProperties: false,
    },
    annotations: ANOT_ESCREVE_IDEMP,
    validar: validarCom((a) => {
      const c = a.campos;
      if (!c || typeof c !== 'object' || Array.isArray(c)) throw new ErroArg('campos precisa ser objeto {chave: valor}.');
      const entradas = Object.entries(c as Record<string, unknown>);
      if (entradas.length < 1 || entradas.length > 10) throw new ErroArg('Informe de 1 a 10 campos.');
      const campos: Record<string, string> = {};
      for (const [k, v] of entradas) {
        if (!/^[a-z][a-z_]{1,39}$/.test(k)) throw new ErroArg(`Campo inválido: "${k.slice(0, 40)}". Veja comercial_campos_negocio.`);
        if (v !== null && typeof v !== 'string') throw new ErroArg(`${k} precisa ser texto.`);
        if (typeof v === 'string' && v.length > 200) throw new ErroArg(`${k}: até 200 caracteres.`);
        campos[k] = normalizarValorCampo(k, v as string | null);
      }
      return { negocio_id: uuid(a, 'negocio_id', true), campos };
    }),
    plano: (a) => [{ rpc: 'crm_mcp_preencher_campos', params: { p_negocio: a.negocio_id, p_campos: a.campos } }],
    resultado: ([r], a) => {
      const o = resultadoRpc([r]);
      return o.ok === true ? { ...o, interpretado: a.campos } : o;
    },
  },
  {
    name: 'comercial_sugerir_campos',
    title: 'Sugerir campos pela conversa',
    description: 'Lê as últimas mensagens do cliente e as notas do lead e SUGERE campos (perfil, se atua com holding, produto, '
      + 'objeção, forma de pagamento), cada um com o trecho que justifica. Heurística por palavras-chave: confira o trecho. '
      + 'NÃO grava nada: mostre as sugestões ao usuário e, com o "sim" dele, grave com comercial_preencher_campos. '
      + 'Informe contato_id OU negocio_id. Só para quem pode ver o lead.',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: { contato_id: { ...SCHEMA_UUID, description: 'pessoa_id' }, negocio_id: SCHEMA_UUID },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => {
      const contato = uuid(a, 'contato_id', false);
      const negocio = uuid(a, 'negocio_id', false);
      if (!contato === !negocio) throw new ErroArg('Informe contato_id OU negocio_id (um dos dois).');
      return { contato_id: contato, negocio_id: negocio };
    }),
    plano: (a) => [{ rpc: 'crm_mcp_lead', params: { p_contato: a.contato_id, p_negocio: a.negocio_id, p_mensagens: 100 } }],
    resultado: ([r]) => {
      const o = resultadoRpc([r]);
      if (o.ok !== true) return { ok: false, msg: typeof o.msg === 'string' ? o.msg : 'Você não tem acesso a este lead.' };
      const textos: TextoLead[] = [
        ...lista(o.mensagens).map((m) => ({ fonte: 'mensagem' as const, de: m.direcao === 'entrada' ? 'cliente' as const : 'equipe' as const, texto: m.texto as string, em: m.em as string })),
        ...lista(o.notas).map((n) => ({ fonte: 'nota' as const, texto: n.texto as string, em: n.em as string })),
      ];
      const contato = (o.contato ?? {}) as Obj;
      return {
        ok: true,
        contatoId: contato.id ?? null,
        nome: contato.nome ?? null,
        lidas: { mensagens: lista(o.mensagens).length, notas: lista(o.notas).length },
        sugestoes: sugerirCampos(textos),
        negociosAbertos: lista(o.negocios).filter((n) => n.status === 'aberto')
          .map((n) => ({ id: n.id, etapaNome: n.etapaNome, produto: n.produto, campos: n.campos ?? {} })),
        aviso: 'Nada foi gravado. Proponha ao usuário e só grave com comercial_preencher_campos depois do sim dele.',
      };
    },
  },
  {
    name: 'comercial_abrir_link',
    title: 'Abrir link do CRM',
    description: 'Recebe um link do sistema colado pelo usuário (conversa: /comercial/conversas?contato=…; negócio: '
      + '/comercial/funil?negocio=…) e devolve o lead para analisar ou resumir: contato, negócios (com os campos), próximas '
      + 'atividades, últimas notas e últimas mensagens. Só links de grupoparticipa.app.br. Sem acesso: "Você não tem acesso a '
      + 'este lead."',
    escopo: 'ler',
    inputSchema: {
      type: 'object',
      properties: {
        link: { type: 'string', minLength: 10, maxLength: 500 },
        mensagens: { type: 'integer', minimum: 1, maximum: 200, default: 50, description: 'Quantas mensagens recentes trazer' },
      },
      required: ['link'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => {
      const l = lerLinkCrm(a.link);
      if (!l.ok) throw new ErroArg(l.msg);
      return { tipo: l.tipo, id: l.id, mensagens: inteiro(a, 'mensagens', 1, 200, 50) };
    }),
    plano: (a) => [{
      rpc: 'crm_mcp_lead',
      params: a.tipo === 'negocio' ? { p_negocio: a.id, p_mensagens: a.mensagens } : { p_contato: a.id, p_mensagens: a.mensagens },
    }],
    resultado: ([r], a) => {
      const o = resultadoRpc([r]);
      if (o.ok !== true) return { ok: false, msg: typeof o.msg === 'string' ? o.msg : 'Você não tem acesso a este lead.' };
      const msgs = lista(o.mensagens).map(mensagemCompacta);
      return {
        ok: true,
        link: { tipo: a.tipo, id: a.id },
        contato: o.contato ?? null,
        negocios: lista(o.negocios).map((n) => ({ ...negocioCompacto(n), produto: n.produto ?? null, campos: n.campos ?? {} })),
        proximasAtividades: lista(o.proximasAtividades)
          .map((x) => ({ id: x.id, negocioId: x.negocioId, tipo: x.tipo, titulo: x.titulo, venceEm: x.venceEm, donoId: x.donoId })),
        notas: lista(o.notas),
        mensagens: { total: msgs.length, itens: msgs },
      };
    },
  },
  // ─── Playbook e central de ajuda (conteúdo do app, sem banco: domain/playbook) ────────────────────────────────────
  {
    name: 'comercial_playbook_indice',
    title: 'Índice do playbook',
    description: 'Lista as seções e subseções do playbook de vendas do Comercial e da central de ajuda do CRM (id, título, '
      + 'resumo de 1 linha). Consulte o playbook antes de sugerir abordagem, roteiro de etapa, resposta a objeção, script ou '
      + 'regra comercial, e cite a seção (id e título) na resposta. Depois leia com comercial_playbook_ler. Para um assunto '
      + 'específico, comercial_playbook_buscar costuma ser mais rápido. parte filtra: comece, sistema, modulos, playbook, faq, glossario.',
    escopo: 'ler',
    local: true,
    inputSchema: {
      type: 'object',
      properties: { parte: { type: 'string', enum: [...PARTES_PLAYBOOK], description: 'Só uma parte (padrão: todas)' } },
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ parte: umDe(a, 'parte', PARTES_PLAYBOOK, null) })),
    plano: () => [],
    resultado: (_r, a) => {
      const secoes = indicePlaybook(a.parte as (typeof PARTES_PLAYBOOK)[number] | null);
      return {
        total: secoes.length,
        secoes,
        uso: 'Leia com comercial_playbook_ler {id} (seção ou subseção "secao/subsecao"). Cite a seção ao usar o conteúdo.',
      };
    },
  },
  {
    name: 'comercial_playbook_ler',
    title: 'Ler seção do playbook',
    description: 'Devolve o texto de uma seção (ou subseção "secao/subsecao") do playbook ou da central de ajuda, em markdown: '
      + 'regras, roteiros, scripts prontos, tabelas e trechos "a definir"/"a validar" (que ainda não valem como regra). '
      + 'Seção grande vem em páginas: use pagina=proximaPagina. Consulte antes de sugerir abordagem, resposta a objeção ou '
      + 'regra comercial e cite a seção. Preço: o playbook não é fonte de preço; não invente valor.',
    escopo: 'ler',
    local: true,
    inputSchema: {
      type: 'object',
      properties: {
        id: { type: 'string', minLength: 2, maxLength: 140, description: 'Id do índice ou da busca (ex.: "conversa", "funil/as-etapas")' },
        pagina: { type: 'integer', minimum: 1, maximum: 50, default: 1 },
      },
      required: ['id'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => {
      const id = texto(a, 'id', 2, 140) as string;
      if (!/^[a-z0-9-]+(\/[a-z0-9-]+)?$/i.test(id)) throw new ErroArg('id inválido: use o id do índice (ex.: "conversa" ou "funil/as-etapas").');
      return { id: id.toLowerCase(), pagina: inteiro(a, 'pagina', 1, 50, 1) };
    }),
    plano: () => [],
    resultado: (_r, a) => lerSecao(a.id as string, a.pagina as number, LIMITE_PAGINA),
  },
  {
    name: 'comercial_playbook_buscar',
    title: 'Buscar no playbook',
    description: 'Busca no playbook de vendas e na central de ajuda (sem acento e sem caixa; todas as palavras precisam '
      + 'aparecer na seção). Ex.: "objeção caro", "garantia", "Miami", "template", "janela de 24 horas". Devolve as seções '
      + 'mais relevantes com o trecho e o id (e a subseção onde mais aparece) para ler com comercial_playbook_ler. Consulte o '
      + 'playbook antes de sugerir abordagem, resposta a objeção ou regra comercial; cite a seção.',
    escopo: 'ler',
    local: true,
    inputSchema: {
      type: 'object',
      properties: {
        termo: { type: 'string', minLength: 2, maxLength: 120 },
        limite: { type: 'integer', minimum: 1, maximum: 20, default: 8 },
      },
      required: ['termo'],
      additionalProperties: false,
    },
    annotations: ANOT_LER,
    validar: validarCom((a) => ({ termo: texto(a, 'termo', 2, 120), limite: inteiro(a, 'limite', 1, 20, 8) })),
    plano: () => [],
    resultado: (_r, a) => {
      const achados = buscarPlaybook(a.termo as string, a.limite as number);
      return {
        termo: a.termo,
        total: achados.length,
        resultados: achados,
        ...(achados.length ? {} : { dica: 'Nada encontrado. Tente menos palavras ou um sinônimo, ou veja comercial_playbook_indice.' }),
      };
    },
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
