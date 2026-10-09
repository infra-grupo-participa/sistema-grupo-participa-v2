// Caso de uso: atender uma mensagem MCP do Comercial (F7). Sem Next, sem Supabase: fala com o banco pela porta.
//
// Regras (docs/projetos/comercial/mcp.md):
//   1. Todo pedido autentica o token (hash sha-256) no banco: crm_mcp_autenticar recusa token inválido/revogado/
//      expirado, perfil fora do Comercial, crm.config.mcp_ligado = false e mais de 60 chamadas/min.
//   2. Ferramenta roda SEMPRE como o dono do token (JWT dele): RLS, guardas e escrita_ligada são as da tela.
//   3. O único corte local é o escopo: ferramenta de escrita exige 'operar'.
//   4. Playbook (ferramentas `local` e resources playbook://comercial/<id>): conteúdo do próprio app, sem RPC. O token
//      passa pela mesma autenticação (resources/read conta no limite como 'recurso_playbook').

import {
  ERRO, VERSAO_PADRAO, ehNotificacao, erroFerramenta, lerPedido, negociarVersao, respostaErro, respostaOk,
  resultadoFerramenta, type RespostaJsonRpc,
} from '../domain/mcp-protocolo';
import { acharFerramenta, descreverFerramenta, ferramentasDoEscopo } from '../domain/mcp-ferramentas';
import { lerRecursoPlaybook, recursosPlaybook, URI_PLAYBOOK } from '../domain/playbook/mcp-playbook';

/** Nome registrado em crm.mcp_chamada (e contado no limite) para resources/read. */
export const CHAMADA_RECURSO = 'recurso_playbook';
/** Código JSON-RPC do MCP para resource inexistente. */
const RECURSO_INEXISTENTE = -32002;

export interface SessaoMcp {
  tokenId: string;
  perfilId: string;
  email: string;
  papel: 'gestor' | 'vendedor';
  escopos: string[];
}

export type Autenticacao =
  | { ok: true; sessao: SessaoMcp }
  | { ok: false; codigo: 'desligado' | 'token' | 'perfil' | 'limite' | 'ferramenta' | 'falha'; msg: string };

export interface ErroRpc {
  message: string;
  code?: string;
}

export interface PortaMcp {
  /** `ferramenta` não nulo = chamada de ferramenta (conta no limite de 60/min e fica em crm.mcp_chamada). */
  autenticar(hashToken: string, ferramenta: string | null): Promise<Autenticacao>;
  /** Chama public.<rpc> com o JWT do dono do token. */
  rpc(sessao: SessaoMcp, rpc: string, params: Record<string, unknown>): Promise<{ data: unknown; error: ErroRpc | null }>;
}

export interface RespostaHttp {
  status: number;
  corpo?: RespostaJsonRpc | { error: string };
  /** Cabeçalho WWW-Authenticate (401). */
  autenticar?: boolean;
}

const INSTRUCOES =
  'CRM Comercial do Grupo Participa. Tudo roda como a pessoa conectada: vendedor vê os próprios leads e os sem dono; '
  + 'gestor vê o time. Use comercial_listar_funis para achar funil_id/etapa_id e comercial_buscar_pessoa para achar '
  + 'pessoa_id. Escritas (atividade, nota, concluir/reabrir atividade, mover etapa, criar/editar contato, tags, campos do negócio) ficam no '
  + 'registro do CRM como feitas via MCP; confirme com a pessoa antes de escrever. Antes de criar contato, busque: se já '
  + 'existir, o CRM devolve o existente. WhatsApp: ANTES de comercial_enviar_whatsapp mostre o texto final (ou a prévia do '
  + 'template), o número e o destinatário e só envie com a confirmação explícita da pessoa, uma mensagem por vez, nunca em '
  + 'massa; use comercial_situacao_conversa para saber se precisa template. Não existe exclusão de contato por aqui. '
  + 'Campos do negócio (perfil advogado/contador, se já atua com holding, produto, objeção, pagamento): veja com '
  + 'comercial_campos_negocio e grave com comercial_preencher_campos quando o usuário pedir (aceita fala natural, inclusive '
  + 'ditada por voz). Ao ler uma conversa, use comercial_sugerir_campos e PROPONHA o preenchimento com o trecho que '
  + 'justifica; só grave depois do sim. Link do sistema colado (…/comercial/conversas?contato=… ou /comercial/funil?negocio=…): '
  + 'use comercial_abrir_link para resumir ou analisar. '
  + 'Playbook de vendas e central de ajuda: consulte (comercial_playbook_buscar, comercial_playbook_indice, '
  + 'comercial_playbook_ler) antes de sugerir abordagem, roteiro de etapa, resposta a objeção ou regra comercial, e cite a '
  + 'seção. Trecho "a definir"/"a validar" ainda não vale como regra. O playbook não é fonte de preço: não invente valor. '
  + 'Dados de clientes são pessoais (LGPD): '
  + 'use só para o atendimento, não copie listas de contatos para fora. Horários sem fuso são de Brasília.';

/** Erro do banco → mensagem para o Claude, sem detalhe interno. */
export function mensagemDeErroRpc(e: ErroRpc): string {
  if (e.code === '42501') return e.message && !/permission denied/i.test(e.message) ? e.message : 'Sem acesso a este dado do Comercial.';
  if (e.code === '28000') return 'Token inválido, revogado ou expirado (ou MCP desligado). Conecte de novo.';
  if (e.code === 'PGRST202' || e.code === '42883') return 'Função do CRM indisponível (migration da fase ainda não aplicada).';
  if (e.code === '22023' || e.code === 'P0002' || e.code === '22P02') return e.message || 'Parâmetro inválido.';
  return 'Não foi possível consultar o CRM agora.';
}

export async function atenderMcp(corpo: unknown, hashToken: string, porta: PortaMcp, agora: Date = new Date()): Promise<RespostaHttp> {
  const lido = lerPedido(corpo);
  if (!lido.ok) return { status: 400, corpo: lido.erro };
  const pedido = lido.pedido;
  const id = pedido.id ?? null;

  // ferramenta conhecida conta no limite; desconhecida autentica sem contar e responde erro de parâmetro
  const nomeFerramenta = pedido.method === 'tools/call' ? pedido.params?.name : undefined;
  const ferramenta = pedido.method === 'tools/call' ? acharFerramenta(nomeFerramenta) : undefined;

  const contaComo = ferramenta ? ferramenta.name : pedido.method === 'resources/read' ? CHAMADA_RECURSO : null;
  const auth = await porta.autenticar(hashToken, contaComo);
  if (!auth.ok) {
    if (auth.codigo === 'token') return { status: 401, corpo: { error: auth.msg }, autenticar: true };
    if (auth.codigo === 'perfil') return { status: 403, corpo: { error: auth.msg } };
    if (auth.codigo === 'desligado') return { status: 503, corpo: { error: auth.msg } };
    if (auth.codigo === 'limite' && !ehNotificacao(pedido)) return { status: 200, corpo: respostaOk(id, erroFerramenta(auth.msg)) };
    if (auth.codigo === 'limite') return { status: 429, corpo: { error: auth.msg } };
    return { status: 502, corpo: { error: 'Não foi possível validar o token agora.' } };
  }
  const sessao = auth.sessao;

  if (ehNotificacao(pedido)) return { status: 202 };

  switch (pedido.method) {
    case 'initialize':
      return {
        status: 200,
        corpo: respostaOk(id, {
          protocolVersion: negociarVersao(pedido.params?.protocolVersion ?? VERSAO_PADRAO),
          capabilities: { tools: { listChanged: false }, resources: { listChanged: false } },
          serverInfo: { name: 'grupo-participa-comercial', title: 'CRM Comercial — Grupo Participa', version: '1.0.0' },
          instructions: INSTRUCOES,
        }),
      };
    case 'ping':
      return { status: 200, corpo: respostaOk(id, {}) };
    case 'tools/list':
      return { status: 200, corpo: respostaOk(id, { tools: ferramentasDoEscopo(sessao.escopos).map(descreverFerramenta) }) };
    case 'resources/list':
      return { status: 200, corpo: respostaOk(id, { resources: sessao.escopos.includes('ler') ? recursosPlaybook() : [] }) };
    case 'resources/templates/list':
      return {
        status: 200,
        corpo: respostaOk(id, {
          resourceTemplates: [{
            uriTemplate: `${URI_PLAYBOOK}{id}`,
            name: 'playbook',
            title: 'Playbook e central de ajuda do Comercial',
            description: 'Seção ("conversa") ou subseção ("funil/as-etapas") em markdown. Ids em comercial_playbook_indice.',
            mimeType: 'text/markdown',
          }],
        }),
      };
    case 'resources/read': {
      if (!sessao.escopos.includes('ler')) return { status: 200, corpo: respostaErro(id, ERRO.parametrosInvalidos, 'Este token não tem o escopo "ler".') };
      const r = lerRecursoPlaybook(pedido.params?.uri);
      if (!r) return { status: 200, corpo: respostaErro(id, RECURSO_INEXISTENTE, 'Resource não encontrado.') };
      return { status: 200, corpo: respostaOk(id, { contents: [r] }) };
    }
    case 'tools/call':
      break;
    default:
      return { status: 200, corpo: respostaErro(id, ERRO.metodoInexistente, `Método não suportado: ${pedido.method}`) };
  }

  if (!ferramenta) {
    return { status: 200, corpo: respostaErro(id, ERRO.parametrosInvalidos, `Ferramenta desconhecida: ${String(nomeFerramenta)}`) };
  }
  if (!sessao.escopos.includes(ferramenta.escopo)) {
    return { status: 200, corpo: respostaOk(id, erroFerramenta(`Este token não tem o escopo "${ferramenta.escopo}". Gere um token com esse escopo no CRM.`)) };
  }
  const brutos = pedido.params?.arguments;
  if (brutos !== undefined && (brutos === null || typeof brutos !== 'object' || Array.isArray(brutos))) {
    return { status: 200, corpo: respostaErro(id, ERRO.parametrosInvalidos, 'arguments precisa ser objeto.') };
  }
  const v = ferramenta.validar((brutos ?? {}) as Record<string, unknown>);
  if (!v.ok) return { status: 200, corpo: respostaOk(id, erroFerramenta(v.msg)) };

  const respostas: unknown[] = [];
  for (const c of ferramenta.plano(v.valor, agora)) {
    const { data, error } = await porta.rpc(sessao, c.rpc, c.params);
    if (error) return { status: 200, corpo: respostaOk(id, erroFerramenta(mensagemDeErroRpc(error))) };
    respostas.push(data);
  }
  const dados = ferramenta.resultado(respostas, v.valor, agora, { perfilId: sessao.perfilId, papel: sessao.papel });
  // escrita: só ok=true passa. Leitura que responde {ok, msg} (lead sem acesso, negócio de outro): ok=false vira erro.
  if ((ferramenta.escrita && dados.ok !== true) || dados.ok === false) {
    return { status: 200, corpo: respostaOk(id, erroFerramenta(typeof dados.msg === 'string' ? dados.msg : 'O CRM recusou a operação.')) };
  }
  return { status: 200, corpo: respostaOk(id, resultadoFerramenta(dados)) };
}
