// Dados de DEMONSTRAÇÃO do CRM. Pessoas fictícias (nomes gerados), nenhum dado real.
// Datas relativas a "agora" para os alertas de tempo aparecerem como na operação.
// Gerador determinístico: a mesma semente produz a mesma base em toda carga.
import { MOTIVOS_PADRAO } from '../domain/catalogo';
import { etapasPadrao } from '../domain/funis';
import { funisDoProjeto } from '../domain/modelos';
import { calcularScore, faixaDoScore } from '../domain/regras';
import type {
  Agrupador, Atividade, ConfigComercial, EtapaFunil, Funil, MotivoPerdaConfig, PainelPessoa, PontoJornada,
  PreferenciasNotificacao, WidgetPainel, Contato, EtapaKey, EventoTimeline, FichaDisparo, FilaRecuperacao, ItemFila,
  LinkRastreavel, Mensagem, MotivoPerda, Negocio, OrigemTipo, ProdutoKey, SinalRecuperacao, StatusFila, Template,
  TipoAtividade, Vendedor,
} from '../domain/types';

export interface BaseDemo {
  vendedores: Vendedor[];
  agrupadores: Agrupador[];
  funis: Funil[];
  contatos: Contato[];
  negocios: Negocio[];
  atividades: Atividade[];
  eventos: EventoTimeline[];
  mensagens: Mensagem[];
  templates: Template[];
  filas: FilaRecuperacao[];
  fichas: FichaDisparo[];
  links: LinkRastreavel[];
  config: ConfigComercial;
  motivos: MotivoPerdaConfig[];
  /** Pontos de jornada vindos das fontes externas (AC, Hotmart, Respondi, SendFlow…). Os do CRM são derivados. */
  jornada: PontoJornada[];
  paineis: PainelPessoa[];
  preferencias: PreferenciasNotificacao[];
}

/** Painel inicial de quem nunca personalizou. */
export function painelPadrao(vendedorId: string, gestor: boolean): PainelPessoa {
  const w = (id: string, titulo: string, metrica: WidgetPainel['metrica'], visual: WidgetPainel['visual'], periodo: WidgetPainel['periodo'], agrupar: WidgetPainel['agrupar'], largura: WidgetPainel['largura']): WidgetPainel =>
    ({ id: `${vendedorId}-${id}`, titulo, metrica, visual, periodo, agrupar, largura, funilId: null });
  return {
    vendedorId,
    widgets: gestor
      ? [
        w('w1', 'Vendas da semana por vendedor', 'vendas', 'barras', '7d', 'vendedor', 2),
        w('w2', 'Receita do mês', 'receita', 'numero', 'mes', 'nenhum', 1),
        w('w3', 'Prazo crítico agora', 'criticos', 'numero', 'hoje', 'nenhum', 1),
        w('w4', 'Abordados por dia', 'abordados', 'linha', '7d', 'dia', 2),
        w('w5', 'Perdidos por motivo', 'perdidos', 'pizza', '30d', 'motivo', 2),
      ]
      : [
        w('w1', 'Minhas vendas no mês', 'vendas', 'numero', 'mes', 'nenhum', 1),
        w('w2', 'Em negociação', 'em_negociacao', 'numero', 'hoje', 'nenhum', 1),
        w('w3', 'Atividades atrasadas', 'atrasadas', 'numero', 'hoje', 'nenhum', 1),
        w('w4', 'Sem próximo passo', 'sem_proximo', 'numero', 'hoje', 'nenhum', 1),
        w('w5', 'Meus abordados por dia', 'abordados', 'barras', '7d', 'dia', 4),
      ],
  };
}

export function preferenciasPadrao(vendedorId: string): PreferenciasNotificacao {
  return {
    vendedorId, desktop: false,
    gatilhos: { lead_novo: true, lead_respondeu: true, prazo_estourado: true, venda_aprovada: true, ficha_para_aprovar: true, atividade_vencendo: true },
    silencioInicio: '20:00', silencioFim: '08:00',
  };
}

function prng(seed: number) {
  let s = seed >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const NOMES = ['Ana', 'Bruno', 'Carla', 'Diego', 'Elisa', 'Fábio', 'Gabriela', 'Henrique', 'Isadora', 'João', 'Karina', 'Leonardo',
  'Mariana', 'Nícolas', 'Olívia', 'Paulo', 'Renata', 'Sérgio', 'Tatiana', 'Vinícius', 'Yasmin', 'Rafael', 'Luana', 'Otávio',
  'Patrícia', 'Gustavo', 'Débora', 'Marcelo', 'Fernanda', 'Rodrigo', 'Camila', 'André'];
const SOBRENOMES = ['Albuquerque', 'Barros', 'Cardoso', 'Duarte', 'Esteves', 'Figueira', 'Guimarães', 'Holanda', 'Lacerda',
  'Macedo', 'Nogueira', 'Pacheco', 'Quintela', 'Rezende', 'Siqueira', 'Teixeira', 'Valadares', 'Xavier', 'Moura', 'Brandão'];
const CIDADES: [string, string][] = [['São Paulo', 'SP'], ['Rio de Janeiro', 'RJ'], ['Belo Horizonte', 'MG'], ['Curitiba', 'PR'],
  ['Porto Alegre', 'RS'], ['Goiânia', 'GO'], ['Recife', 'PE'], ['Salvador', 'BA'], ['Campinas', 'SP'], ['Florianópolis', 'SC']];
const DDD = ['11', '21', '31', '41', '51', '62', '81', '71', '19', '48'];

export const VENDEDORES: Vendedor[] = [
  { id: 'v-jonathan', nome: 'Jonathan Mendes', sigla: 'JM', papel: 'gestor', ativo: true, percentual: 0, disparaApi: true },
  { id: 'v-marcos', nome: 'Marcos Paulo', sigla: 'MP', papel: 'vendedor', ativo: true, percentual: 50, disparaApi: true },
  { id: 'v-ronan', nome: 'Ronan', sigla: 'RO', papel: 'vendedor', ativo: true, percentual: 50, disparaApi: false },
];

const TEMPLATES: Template[] = [
  { id: 't-abordagem', nome: 'abordagem_inscrito_v2', categoria: 'marketing', aprovado: true,
    texto: 'Oi {{nome}}, tudo bem? Aqui é {{vendedor}}, do time do Professor Marcio. Vi que você se inscreveu no {{evento}}. O que motivou você a se inscrever?' },
  { id: 't-recuperacao', nome: 'recuperacao_assistiu_nao_comprou', categoria: 'marketing', aprovado: true,
    texto: 'Oi {{nome}}, tudo bem? Aqui é {{vendedor}}, do time do Professor Marcio. Você acompanhou as aulas e não chegou a entrar. Não vim insistir em venda, vim entender o que te segurou. Foi a técnica ou a captação de cliente? Ou foi outra coisa?' },
  { id: 't-boleto', nome: 'lembrete_boleto_vencendo', categoria: 'utility', aprovado: true,
    texto: 'Oi {{nome}}, seu boleto do {{produto}} vence amanhã. Se preferir Pix ou cartão, me avisa aqui que eu te mando o link.' },
  { id: 't-retomada', nome: 'retomada_conversa', categoria: 'marketing', aprovado: false,
    texto: '{{nome}}, só pra não deixar em aberto: prefere que eu te explique por aqui ou prefere que eu não insista? Qualquer uma das duas tá ok.' },
];

const AGRUPADORES: Agrupador[] = [
  { id: 'ag-hm', nome: 'Holding Masters', produto: 'hm', ordem: 1 },
  { id: 'ag-ht', nome: 'Holding Total', produto: 'ht', ordem: 2 },
  { id: 'ag-aurum', nome: 'Aurum', produto: 'aurum', ordem: 3 },
  { id: 'ag-acelera', nome: 'Acelera Holding', produto: 'acelera', ordem: 4 },
  { id: 'ag-escritorio', nome: 'Escritório (Escada A)', produto: 'sv', ordem: 5 },
];

const etapa = (id: string, nome: string, papel: EtapaFunil['papel'], cor: EtapaFunil['cor'], atencao: number | null, critico: number | null, campos: EtapaFunil['camposObrigatorios'] = [], criterio = ''): EtapaFunil =>
  ({ id, nome, papel, cor, slaAtencaoMin: atencao, slaCriticoMin: critico, camposObrigatorios: campos, criterio });

function montarFunis(agoraIso: string): Funil[] {
  const vendaAtiva = (produto: ProdutoKey, agrupadorId: string, campanhas: Funil['campanhas']): Funil => ({
    id: `f-va-${produto}`, nome: 'Venda ativa', icone: 'kanban', projeto: null, agrupadorId, produto, tipo: 'manual', eventosHotmart: [],
    etapas: etapasPadrao(`va-${produto}`), campanhas, distribuicao: null, ativo: true, criadoEm: agoraIso,
  });
  const checkout = (produto: ProdutoKey, agrupadorId: string): Funil => ({
    id: `f-ck-${produto}`, nome: 'Checkout e recuperação', icone: 'zap', projeto: null, agrupadorId, produto, tipo: 'hotmart',
    eventosHotmart: ['carrinho_abandonado', 'cartao_recusado', 'compra_em_aberto', 'expirada', 'reembolso'],
    etapas: [
      etapa(`ck-${produto}-1`, 'Ligar em até 15 min', 'primeiro_contato', 'red', 10, 15, [], 'Lead atendeu ou respondeu'),
      etapa(`ck-${produto}-2`, 'Em conversa', 'qualificar', 'cyan', 4 * 60, 24 * 60, [], 'Entendeu o que travou'),
      etapa(`ck-${produto}-3`, 'Link novo enviado', 'negociar', 'accent', 12 * 60, 48 * 60, [], 'Escolheu a forma de pagamento'),
      etapa(`ck-${produto}-4`, 'Aguardar pagamento', 'aguardar_pagamento', 'yellow', 24 * 60, 48 * 60, ['forma_pagamento'], 'Pagamento aprovado'),
      etapa(`ck-${produto}-5`, 'Recuperado', 'fechado', 'green', null, null),
    ],
    campanhas: [{ id: `cp-ck-${produto}`, nome: 'Eventos de checkout da Hotmart', canal: 'hotmart', regra: 'Carrinho abandonado, cartão recusado, boleto/Pix em aberto, expirada, reembolso', ativa: true, criadoEm: agoraIso }],
    distribuicao: null, ativo: true, criadoEm: agoraIso,
  });
  const cp = (id: string, nome: string, canal: Funil['campanhas'][number]['canal'], regra: string, ativa = true) => ({ id, nome, canal, regra, ativa, criadoEm: agoraIso });
  return [
    vendaAtiva('hm', 'ag-hm', [
      cp('cp-hm-imersao', 'Imersão HT · SET26 (pitch HM)', 'utm', 'utm_campaign = imersao-ht-set26'),
      cp('cp-hm-ficha', 'Ficha de reserva HM', 'formulario', 'Formulário ficha-reserva preenchido'),
      cp('cp-hm-disparo', 'Disparo recuperação HM', 'disparo', 'Ficha de disparo HM-REC-*'),
    ]),
    checkout('hm', 'ag-hm'),
    vendaAtiva('ht', 'ag-ht', [
      cp('cp-ht-meteorico', 'HT33 Meteórico', 'utm', 'utm_campaign = ht33-meteorico'),
      cp('cp-ht-bf', 'Black Friday 26', 'utm', 'utm_campaign = black-friday-26', false),
    ]),
    checkout('ht', 'ag-ht'),
    vendaAtiva('aurum', 'ag-aurum', [cp('cp-ar-alunos', 'Alunos HM com faturamento', 'manual', 'Lista do gestor (faturamento declarado > R$ 150 mil)')]),
    vendaAtiva('acelera', 'ag-acelera', [cp('cp-ac-cnhf', 'CNHF ago/26', 'utm', 'utm_campaign = acelera-ago26')]),
    checkout('acelera', 'ag-acelera'),
    {
      id: 'f-sv-seminario', nome: 'Seminário · Sessão de Viabilidade', icone: 'calendar', projeto: 'seminario-elaine-set26', agrupadorId: 'ag-escritorio', produto: 'sv', tipo: 'manual', eventosHotmart: [],
      etapas: [
        etapa('sv-1', 'Agendar a sessão', 'primeiro_contato', 'info', 30, 120, [], 'Sessão marcada na agenda'),
        etapa('sv-2', 'Sessão marcada', 'qualificar', 'cyan', 3 * 24 * 60, 5 * 24 * 60, ['perfil_profissional', 'atua_com_holding', 'produto_interesse'], 'Sessão realizada'),
        etapa('sv-3', 'Sessão realizada', 'apresentar_oferta', 'purple', 24 * 60, 72 * 60, [], 'Croqui proposto'),
        etapa('sv-4', 'Proposta do croqui', 'negociar', 'accent', 72 * 60, 7 * 24 * 60, ['objecao_principal'], 'Família decidiu a forma de pagamento'),
        etapa('sv-5', 'Aguardar pagamento', 'aguardar_pagamento', 'yellow', 24 * 60, 48 * 60, ['forma_pagamento'], 'Pagamento aprovado'),
        etapa('sv-6', 'Sessão paga', 'fechado', 'green', null, null),
      ],
      campanhas: [
        cp('cp-sv-set26', 'Seminário Dra. Elaine · SET26', 'utm', 'utm_campaign = seminario-elaine-set26'),
        cp('cp-sv-mql', 'Pesquisa MQL do Seminário', 'formulario', 'Pesquisa respondida com patrimônio acima de R$ 1 mi'),
        cp('cp-sv-webinar', 'Webinar perpétuo', 'webhook', 'Webhook da página webijama (inscrição)'),
      ],
      distribuicao: [{ vendedorId: 'v-jonathan', percentual: 40 }, { vendedorId: 'v-marcos', percentual: 60 }],
      ativo: true, criadoEm: agoraIso,
    },
    // Projeto ATM (aula ao vivo de entrada) do HT, criado por "Comecei um novo projeto". Fica depois dos funis
    // fixos do HT: o encaixe dos negócios de exemplo continua indo para Venda ativa e Checkout.
    ...funisDoProjeto('atm', 'ATM HT out26', AGRUPADORES[1], 'ht').map((f, i) => ({
      ...f, id: `f-atm-ht-${i + 1}`, criadoEm: agoraIso, campanhas: f.campanhas.map((c) => ({ ...c, criadoEm: agoraIso })),
    })),
  ];
}

/** Coloca o negócio no funil e na etapa certos: Hotmart → funil de checkout; resto → Venda ativa (ou Seminário, na SV). */
function encaixarNoFunil(n: Negocio, funis: Funil[]): void {
  const doProduto = funis.filter((f) => f.produto === n.produto);
  const auto = n.origem !== 'venda_ativa' && n.origem !== 'compra_aprovada' ? doProduto.find((f) => f.tipo === 'hotmart') : undefined;
  const f = auto ?? doProduto.find((x) => x.tipo === 'manual') ?? funis[0];
  const ordem: EtapaFunil['papel'][] = ['primeiro_contato', 'qualificar', 'apresentar_oferta', 'negociar', 'aguardar_pagamento', 'fechado'];
  // Primeira etapa com o mesmo papel; se o funil não tem esse papel, a etapa anterior mais próxima.
  let e = f.etapas.find((x) => x.papel === n.etapa);
  for (let i = ordem.indexOf(n.etapa); !e && i >= 0; i--) e = f.etapas.find((x) => x.papel === ordem[i]);
  e ??= f.etapas[0];
  n.funilId = f.id;
  n.campanhaId = f.campanhas.find((c) => c.ativa)?.id ?? null;
  n.etapaId = e.id;
  n.etapaNome = e.nome;
  n.etapa = e.papel;
  n.sla = e.slaAtencaoMin != null && e.slaCriticoMin != null ? { atencaoMin: e.slaAtencaoMin, criticoMin: e.slaCriticoMin } : null;
}

export function gerarBaseDemo(agora = new Date()): BaseDemo {
  const r = prng(20261005);
  const pick = <T,>(a: readonly T[]): T => a[Math.floor(r() * a.length)];
  const minAtras = (m: number) => new Date(agora.getTime() - m * 60000).toISOString();
  const minDepois = (m: number) => new Date(agora.getTime() + m * 60000).toISOString();
  const H = 60;
  const D = 24 * H;

  let seq = 0;
  const id = (p: string) => `${p}-${++seq}`;
  const vendedorAtivo = () => (r() < 0.5 ? 'v-marcos' : 'v-ronan');

  // ── Contatos ──
  const contatos: Contato[] = Array.from({ length: 64 }, (_, i) => {
    const nome = `${NOMES[i % NOMES.length]} ${pick(SOBRENOMES)}`;
    const [cidade, uf] = pick(CIDADES);
    const perfil = r() < 0.48 ? 'advogado' : r() < 0.8 ? 'contador' : 'outro';
    const slug = nome.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/\s+/g, '.');
    const campanha = pick(['ht33-meteorico', 'imersao-ht-set26', 'seminario-elaine-set26', 'acelera-ago26', 'black-friday-26']);
    return {
      id: `c-${i + 1}`,
      nome,
      email: `${slug}@exemplo.com.br`,
      telefone: `55${DDD[i % DDD.length]}9${String(10000000 + Math.floor(r() * 89999999))}`,
      cidade, uf,
      perfil: r() < 0.85 ? perfil : null,
      atuaComHolding: r() < 0.7 ? pick(['sim', 'nao', 'comecando'] as const) : null,
      donoId: r() < 0.9 ? (i % 11 === 0 ? 'v-jonathan' : vendedorAtivo()) : null,
      tags: [pick(['HT33', 'Imersão SET26', 'Seminário SET26', 'Acelera AGO26']), ...(r() < 0.3 ? ['Grupo WhatsApp'] : [])],
      utm: { source: pick(['metaads', 'ActiveCampaign', 'sendflow', 'infobip', 'organico']), medium: pick(['cpc', 'email', 'grupo', 'api']), campaign: campanha, content: null, sck: null },
      score: null,
      ehAluno: r() < 0.12,
      optOut: r() < 0.05,
      criadoEm: minAtras(Math.floor(r() * 40 * D) + 60),
    };
  });

  // ── Negócios ──
  const plano: { etapa: EtapaKey; origem: OrigemTipo; produto: ProdutoKey; desdeMin: number; status?: Negocio['status']; motivo?: MotivoPerda }[] = [];
  const push = (n: number, etapa: EtapaKey, origem: OrigemTipo, produtos: ProdutoKey[], desde: [number, number], status?: Negocio['status'], motivo?: MotivoPerda) => {
    for (let i = 0; i < n; i++) plano.push({ etapa, origem, produto: pick(produtos), desdeMin: desde[0] + Math.floor(r() * (desde[1] - desde[0])), status, motivo });
  };
  push(3, 'primeiro_contato', 'venda_ativa', ['hm', 'ht'], [1, 4]);
  push(2, 'primeiro_contato', 'venda_ativa', ['hm', 'sv'], [6, 14]);
  push(2, 'primeiro_contato', 'venda_ativa', ['ht', 'acelera'], [20, 90]);
  push(4, 'primeiro_contato', 'carrinho_abandonado', ['hm', 'ht', 'acelera'], [2, 40]);
  push(2, 'primeiro_contato', 'cartao_recusado', ['hm'], [5, 30]);
  push(6, 'qualificar', 'venda_ativa', ['hm', 'ht', 'sv', 'aurum'], [2 * H, 30 * H]);
  push(2, 'qualificar', 'venda_ativa', ['hm'], [50 * H, 70 * H]);
  push(5, 'apresentar_oferta', 'venda_ativa', ['hm', 'aurum', 'sv'], [10 * H, 80 * H]);
  push(5, 'negociar', 'venda_ativa', ['hm', 'aurum', 'acelera'], [12 * H, 8 * D]);
  push(3, 'aguardar_pagamento', 'compra_em_aberto', ['hm', 'ht'], [6 * H, 50 * H]);
  push(2, 'aguardar_pagamento', 'venda_ativa', ['hm', 'aurum'], [4 * H, 30 * H]);
  push(4, 'fechado', 'venda_ativa', ['hm', 'ht', 'sv', 'aurum'], [1 * H, 9 * H], 'ganho');
  push(3, 'fechado', 'compra_aprovada', ['ht', 'acelera'], [2 * D, 6 * D], 'ganho');
  push(2, 'qualificar', 'venda_ativa', ['hm'], [2 * H, 6 * H], 'perdido', 'sem_interesse');
  push(1, 'negociar', 'venda_ativa', ['aurum'], [3 * H, 5 * H], 'perdido', 'sem_condicao_financeira');
  push(1, 'primeiro_contato', 'venda_ativa', ['ht'], [3 * D, 4 * D], 'perdido', 'tentativas_esgotadas');
  push(1, 'qualificar', 'venda_ativa', ['hm'], [1 * H, 2 * H], 'perdido', 'ja_atendido_outro_vendedor');
  push(1, 'primeiro_contato', 'expirada', ['hm'], [2 * D, 3 * D], 'perdido', 'contato_invalido');
  push(1, 'primeiro_contato', 'reembolso', ['ht'], [30, 120]);

  const PRECO: Record<ProdutoKey, number> = { ht: 297, acelera: 2997, hm: 30000, aurum: 100000, ethb: 997, sv: 1200 };
  const camposAte = (etapa: EtapaKey, c: Contato, produto: ProdutoKey): Negocio['campos'] => {
    const ordem: EtapaKey[] = ['primeiro_contato', 'qualificar', 'apresentar_oferta', 'negociar', 'aguardar_pagamento', 'fechado'];
    const i = ordem.indexOf(etapa);
    const campos: Negocio['campos'] = { origem: `${c.utm.source ?? 'direto'} / ${c.utm.campaign ?? '—'}` };
    if (i >= 1) Object.assign(campos, { perfil_profissional: c.perfil ?? 'advogado', atua_com_holding: c.atuaComHolding ?? 'comecando', produto_interesse: produto });
    if (i >= 3) campos.objecao_principal = pick(['preco', 'pensar', 'socio_conjuge', 'sem_cliente']);
    if (i >= 4) campos.forma_pagamento = pick(['cartao', 'pix', 'boleto']);
    return campos;
  };

  const negocios: Negocio[] = [];
  const atividades: Atividade[] = [];
  const eventos: EventoTimeline[] = [];
  const titulos: Record<TipoAtividade, string[]> = {
    whatsapp: ['WhatsApp de abordagem', 'WhatsApp curto de retomada', 'Enviar link de pagamento', 'Mandar depoimento de aluno'],
    ligacao: ['Ligação de diagnóstico', 'Ligar para apresentar a oferta', 'Retornar ligação combinada', 'Ligar sobre o boleto'],
    email: ['Enviar proposta por e-mail'],
    tarefa: ['Conferir pagamento na Hotmart', 'Preparar condição da oferta vigente'],
    reuniao: ['Reunião com sócio do lead'],
  };

  plano.forEach((p, i) => {
    const c = contatos[i % contatos.length];
    const dono = p.origem === 'compra_aprovada' ? (r() < 0.5 ? vendedorAtivo() : null) : i === 5 || i === 17 ? null : c.donoId ?? vendedorAtivo();
    const status = p.status ?? 'aberto';
    const desde = minAtras(p.desdeMin);
    const criado = minAtras(p.desdeMin + Math.floor(r() * 3 * D));
    const nid = `n-${i + 1}`;
    const tipoProx: TipoAtividade = pick(['whatsapp', 'ligacao', 'ligacao', 'whatsapp', 'tarefa']);
    const semProximo = status === 'aberto' && (i % 9 === 4);
    const proxVence = r() < 0.25 ? minAtras(30 + Math.floor(r() * 300)) : minDepois(30 + Math.floor(r() * 2 * D));
    const n: Negocio = {
      id: nid, contatoId: c.id, produto: p.produto, origem: p.origem, etapa: p.etapa, status, donoId: dono,
      funilId: '', campanhaId: null, etapaId: '', etapaNome: '', sla: null,
      valor: PRECO[p.produto], campos: camposAte(p.etapa, c, p.produto), motivoPerda: p.motivo ?? null,
      criadoEm: criado, etapaDesde: desde, fechadoEm: status === 'aberto' ? null : desde,
      proximaAtividade: null, ultimaInteracaoEm: minAtras(p.desdeMin / 2),
    };
    if (status === 'aberto' && !semProximo && dono) {
      const aid = id('a');
      const titulo = pick(titulos[tipoProx]);
      atividades.push({ id: aid, negocioId: nid, contatoId: c.id, donoId: dono, tipo: tipoProx, titulo, venceEm: proxVence, concluidaEm: null, resultado: null, cadenciaDia: p.etapa === 'primeiro_contato' ? 1 + Math.floor(r() * 4) : null });
      n.proximaAtividade = { id: aid, tipo: tipoProx, titulo, venceEm: proxVence };
    }
    negocios.push(n);

    // Histórico concluído (alimenta o fechamento do dia e a linha do tempo).
    if (dono) {
      const nConcl = 1 + Math.floor(r() * 3);
      for (let k = 0; k < nConcl; k++) {
        const t: TipoAtividade = pick(['whatsapp', 'ligacao']);
        const quando = r() < 0.55 ? minAtras(Math.floor(r() * 9 * H)) : minAtras(D + Math.floor(r() * 6 * D));
        atividades.push({
          id: id('a'), negocioId: nid, contatoId: c.id, donoId: dono, tipo: t, titulo: pick(titulos[t]),
          venceEm: quando, concluidaEm: quando, resultado: pick(['Respondeu', 'Não atendeu', 'Pediu retorno amanhã', 'Conversa boa, mandou dúvida', 'Caixa postal']), cadenciaDia: null,
        });
      }
    }

    const ev = (tipo: EventoTimeline['tipo'], titulo: string, em: string, detalhe: string | null = null, autor: string | null = dono) =>
      eventos.push({ id: id('e'), contatoId: c.id, negocioId: nid, tipo, titulo, detalhe, em, autorId: autor });
    ev('criado', `Negócio criado em ${p.origem === 'venda_ativa' ? 'Venda ativa' : 'origem automática da Hotmart'}`, criado, null, null);
    if (p.origem === 'carrinho_abandonado') ev('checkout', 'Abandonou o checkout na Hotmart', criado, null, null);
    if (p.origem === 'cartao_recusado') ev('checkout', 'Cartão recusado na Hotmart (restrição no cartão)', criado, null, null);
    if (['qualificar', 'apresentar_oferta', 'negociar', 'aguardar_pagamento'].includes(p.etapa) || (status !== 'aberto' && p.etapa !== 'primeiro_contato')) {
      ev('mensagem', 'Lead escreveu no WhatsApp', minAtras(p.desdeMin + 30));
      ev('etapa', 'Moveu para Qualificar', minAtras(p.desdeMin + 20), 'qualificar');
    }
    if (p.etapa === 'negociar' || p.etapa === 'aguardar_pagamento') ev('etapa', 'Moveu para Negociar', p.etapa === 'negociar' ? desde : minAtras(p.desdeMin + 10), 'negociar');
    if (status === 'ganho') ev('ganho', `Pagamento aprovado na Hotmart · ${p.produto.toUpperCase()}`, desde, null, null);
    if (status === 'perdido') ev('perdido', 'Marcado como perdido', desde, p.motivo ?? null);
  });

  const funis = montarFunis(minAtras(30 * D));
  negocios.forEach((n) => encaixarNoFunil(n, funis));

  // Eventos extras de hoje: entradas espontâneas e respostas (alimentam o fechamento).
  contatos.slice(40, 46).forEach((c) => eventos.push({ id: id('e'), contatoId: c.id, negocioId: null, tipo: 'mensagem', titulo: 'Lead escreveu no WhatsApp', detalhe: null, em: minAtras(Math.floor(r() * 6 * H)), autorId: null }));
  contatos.slice(0, 20).forEach((c) => {
    if (r() < 0.4) eventos.push({ id: id('e'), contatoId: c.id, negocioId: null, tipo: 'pesquisa', titulo: 'Respondeu a pesquisa de qualificação', detalhe: 'Patrimônio: até R$ 1 mi · Advogado', em: minAtras(5 * D + Math.floor(r() * 10 * D)), autorId: null });
    if (r() < 0.3) eventos.push({ id: id('e'), contatoId: c.id, negocioId: null, tipo: 'grupo', titulo: 'Entrou no grupo de WhatsApp do evento', detalhe: null, em: minAtras(6 * D + Math.floor(r() * 10 * D)), autorId: null });
  });

  // ── Conversas (WhatsApp) ──
  const mensagens: Mensagem[] = [];
  const roteiros: { lead: string; vendedor: string }[] = [
    { lead: 'Oi! Vi o anúncio do Holding Masters. Como funciona a parte do pagamento?', vendedor: 'Oi, {nome}! Tudo bem? Antes de falar de valor: você já atua com holding ou está começando?' },
    { lead: 'Gostei muito da imersão, mas fiquei com dúvida se consigo aplicar sem ter cliente ainda.', vendedor: 'Faz sentido, é a dúvida mais comum. Hoje, quando alguém te procura e a família tem patrimônio, você chega a levantar o tema de holding?' },
    { lead: 'Meu boleto venceu, consigo pagar no Pix?', vendedor: 'Consegue sim. Te mando o link do Pix agora. Prefere à vista ou parcelado no cartão?' },
    { lead: 'Preciso conversar com minha sócia antes de fechar.', vendedor: 'Claro. De 0 a 5, qual a chance real de vocês seguirem? E o que falta para ser 5? Posso fazer uma ligação com as duas amanhã às 10h ou às 15h?' },
    { lead: 'Quanto custa a Sessão de Viabilidade?', vendedor: 'São R$ 1.200, e esse valor é abatido no croqui se vocês seguirem. Antes de te mandar o link: o patrimônio da família hoje está em nome das pessoas físicas?' },
    { lead: 'Tentei pagar no cartão e deu recusado.', vendedor: 'Isso costuma ser limite ou dado digitado. Te mando um link novo; se preferir, dá para fazer no Pix ou parcelar em mais vezes.' },
  ];
  const comConversa = negocios.filter((n) => n.status === 'aberto' && n.donoId).slice(0, 14);
  comConversa.forEach((n, i) => {
    const c = contatos.find((x) => x.id === n.contatoId)!;
    const rot = roteiros[i % roteiros.length];
    const base = i < 5 ? 3 + i * 7 : 2 * H + i * 97;
    const primeiroNome = c.nome.split(' ')[0];
    const ms: Omit<Mensagem, 'id'>[] = [
      { contatoId: c.id, canal: 'whatsapp', direcao: 'saida', texto: TEMPLATES[0].texto.replace('{{nome}}', primeiroNome).replace('{{vendedor}}', VENDEDORES.find((v) => v.id === n.donoId)!.nome.split(' ')[0]).replace('{{evento}}', 'Holding Total'), em: minAtras(base + 3 * D), status: 'lida', autorId: n.donoId, templateId: 't-abordagem' },
      { contatoId: c.id, canal: 'whatsapp', direcao: 'entrada', texto: rot.lead, em: minAtras(base + 40), status: null, autorId: null, templateId: null },
      { contatoId: c.id, canal: 'whatsapp', direcao: 'saida', texto: rot.vendedor.replace('{nome}', primeiroNome), em: minAtras(base + 25), status: i % 3 === 0 ? 'entregue' : 'lida', autorId: n.donoId, templateId: null },
    ];
    if (i < 6) ms.push({ contatoId: c.id, canal: 'whatsapp', direcao: 'entrada', texto: pick(['Entendi. Me manda mais detalhes?', 'Pode ser amanhã às 10h.', 'Faz sentido, quero entender melhor.', 'Ainda não, mas quero começar este ano.']), em: minAtras(base), status: null, autorId: null, templateId: null });
    ms.forEach((m) => mensagens.push({ id: id('m'), ...m }));
  });

  // ── Fila de recuperação (pós-lançamento, modelo Sala de Guerra) ──
  const sinaisPossiveis: SinalRecuperacao[] = ['boleto_aberto', 'carrinho', 'cartao_recusado', 'ficha_completa', 'senhas', 'chat', 'workbook', 'pesquisa', 'comunidade', 'grupo', 'advogado_contador', 'quer_parceria', 'respondeu_sem_retorno'];
  const statusPossiveis: StatusFila[] = ['a_abordar', 'a_abordar', 'a_abordar', 'tentando_contato', 'em_conversa', 'vai_comprar', 'ganho', 'sem_resposta', 'declinou', 'numero_invalido'];
  const itensFila: ItemFila[] = contatos.slice(8, 56).map((c, i) => {
    const sinais = sinaisPossiveis.filter(() => r() < 0.28);
    if (i < 6) sinais.push('respondeu_sem_retorno');
    const score = calcularScore(sinais);
    const status = i < 12 ? 'a_abordar' : pick(statusPossiveis);
    return {
      id: `fi-${i + 1}`, contatoId: c.id, score, faixa: faixaDoScore(score), sinais, status,
      responsavelId: c.donoId ?? vendedorAtivo(),
      alteradoPor: status === 'a_abordar' ? null : c.donoId ?? 'v-marcos',
      alteradoEm: status === 'a_abordar' ? null : minAtras(Math.floor(r() * 2 * D)),
    };
  });
  const filas: FilaRecuperacao[] = [
    { id: 'f-imersao', nome: 'Imersão Holding Total · SET26', produto: 'hm', criadaEm: minAtras(9 * D), ofertaVigente: 'HM R$ 30.000 · 1ª metade R$ 15 mil (12× R$ 1.461) · reserva R$ 300', itens: itensFila },
    { id: 'f-seminario', nome: 'Seminário Dra. Elaine · SET26', produto: 'sv', criadaEm: minAtras(14 * D), ofertaVigente: null, itens: itensFila.slice(0, 14).map((it, i) => ({ ...it, id: `fs-${i + 1}`, status: 'a_abordar', alteradoEm: null, alteradoPor: null })) },
  ];

  // ── Fichas de disparo ──
  const fichas: FichaDisparo[] = [
    { id: 'd-1', codigo: 'HM-REC-20261003-01', objetivo: 'Recuperar quem assistiu a Imersão e não comprou o HM', produto: 'hm', filtro: 'Fila Imersão SET26 · faixas A e B · status A abordar', quantidade: 212, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'], suprimidos: 37, templateId: 't-recuperacao', numeroEnvio: 'Comercial oficial (API)', agendadoPara: minAtras(2 * D), operadorId: 'v-marcos', link: 'https://o.holdingmasters.com.br/rec?sck=hm-rec-20261003-whatsapp-mp', status: 'enviada', aprovadoPor: 'v-jonathan', criadoEm: minAtras(3 * D), resultado: { entregues: 168, lidas: 121, respostas: 34, falhas: 7 } },
    { id: 'd-2', codigo: 'HT-ABD-20261006-01', objetivo: 'Abordagem de inscritos do HT33 sem pedido de contato', produto: 'ht', filtro: 'Inscritos HT33 · advogado ou contador · sem dono', quantidade: 480, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'], suprimidos: 62, templateId: 't-abordagem', numeroEnvio: 'Comercial oficial (API)', agendadoPara: minDepois(18 * H), operadorId: 'v-marcos', link: 'https://o.holdingtotal.com.br/ht33?sck=ht-abordagem-20261006-whatsapp-mp', status: 'aguardando_aprovacao', aprovadoPor: null, criadoEm: minAtras(3 * H), resultado: null },
    { id: 'd-3', codigo: 'HM-BOL-20261005-01', objetivo: 'Lembrete de boleto vencendo (HM)', produto: 'hm', filtro: 'Aguardar pagamento · boleto · vence em 24 h', quantidade: 17, supressoes: ['opt_out', 'ja_comprou'], suprimidos: 2, templateId: 't-boleto', numeroEnvio: 'Comercial oficial (API)', agendadoPara: minDepois(2 * H), operadorId: 'v-jonathan', link: 'https://o.holdingmasters.com.br/pix?sck=hm-boleto-20261005-whatsapp-jm', status: 'aprovada', aprovadoPor: 'v-jonathan', criadoEm: minAtras(5 * H), resultado: null },
    { id: 'd-4', codigo: 'SV-REC-20261007-01', objetivo: 'Recuperar interessados em Sessão de Viabilidade', produto: 'sv', filtro: 'Seminário SET26 · MQL · não agendou', quantidade: 96, supressoes: ['em_negociacao', 'opt_out'], suprimidos: 11, templateId: 't-retomada', numeroEnvio: 'Comercial oficial (API)', agendadoPara: minDepois(2 * D), operadorId: 'v-marcos', link: '', status: 'rascunho', aprovadoPor: null, criadoEm: minAtras(1 * H), resultado: null },
    { id: 'd-5', codigo: 'AR-ABD-20260929-01', objetivo: 'Convite Aurum para alunos HM com faturamento', produto: 'aurum', filtro: 'Alunos HM · faturamento declarado > R$ 150 mil', quantidade: 58, supressoes: ['em_negociacao', 'disparo_48h', 'opt_out', 'ja_comprou'], suprimidos: 9, templateId: 't-abordagem', numeroEnvio: 'Comercial oficial (API)', agendadoPara: minAtras(6 * D), operadorId: 'v-jonathan', link: 'https://o.aurum.com.br/convite?sck=aurum-abordagem-20260929-whatsapp-jm', status: 'reprovada', aprovadoPor: 'v-jonathan', criadoEm: minAtras(7 * D), resultado: null },
  ];

  const links: LinkRastreavel[] = [];
  for (const v of VENDEDORES) {
    for (const [p, acao] of [['hm', 'recuperacao'], ['ht', 'abordagem'], ['sv', 'agendamento']] as [ProdutoKey, string][]) {
      const sck = `${p}-${acao}-20261001-whatsapp-${v.sigla.toLowerCase()}`;
      links.push({ id: id('l'), vendedorId: v.id, produto: p, acao, sck, url: `https://pay.hotmart.com/EXEMPLO?sck=${sck}` });
    }
  }

  // ── Jornada externa: cada pessoa passou por 1 a 3 lançamentos, cada um com a UTM daquela entrada ──
  const LANCAMENTOS: { chave: string; produto: ProdutoKey; nome: string; diasAtras: number; source: string; medium: string }[] = [
    { chave: 'ht30-classico-mar26', produto: 'ht', nome: 'Holding Total 30', diasAtras: 210, source: 'metaads', medium: 'cpc' },
    { chave: 'cnhf-ago26', produto: 'acelera', nome: 'CNHF / Acelera', diasAtras: 60, source: 'ActiveCampaign', medium: 'email' },
    { chave: 'seminario-elaine-set26', produto: 'sv', nome: 'Seminário Dra. Elaine', diasAtras: 35, source: 'metaads', medium: 'cpc' },
    { chave: 'imersao-ht-set26', produto: 'hm', nome: 'Imersão Holding Total', diasAtras: 25, source: 'sendflow', medium: 'grupo' },
    { chave: 'ht33-meteorico', produto: 'ht', nome: 'HT33 Meteórico', diasAtras: 8, source: 'infobip', medium: 'api' },
  ];
  const PRECO_J: Record<ProdutoKey, number> = { ht: 297, acelera: 2997, hm: 30000, aurum: 100000, ethb: 997, sv: 1200 };
  const jornada: PontoJornada[] = [];
  contatos.forEach((c, i) => {
    const qtd = 1 + (i % 3);
    const escolhidos = [...LANCAMENTOS].sort(() => r() - 0.5).slice(0, qtd).sort((a, b) => b.diasAtras - a.diasAtras);
    escolhidos.forEach((l, k) => {
      const base = l.diasAtras * D + Math.floor(r() * 3 * D);
      const ponto = (tipo: PontoJornada['tipo'], titulo: string, mins: number, extra: Partial<PontoJornada> = {}) =>
        jornada.push({ id: id('j'), contatoId: c.id, tipo, titulo, em: minAtras(Math.max(5, mins)), detalhe: null, fonte: 'crm', lancamento: l.chave, produto: l.produto, utm: null, valor: null, negocioId: null, ...extra });
      const utm = { source: l.source, medium: l.medium, campaign: l.chave, content: pick(['ad01-video-marcio', 'ad07-carrossel', 'email-convite-2', 'grupo-aviso-d1']), sck: null };
      ponto('inscricao', `Inscreveu-se em ${l.nome}`, base, { fonte: l.source === 'ActiveCampaign' ? 'activecampaign' : 'formulario', utm, detalhe: `Página de captação · ${utm.source} / ${utm.medium}` });
      ponto('lista', `Entrou na lista "${l.nome}"`, base - 2, { fonte: 'activecampaign' });
      if (r() < 0.6) ponto('pesquisa', 'Respondeu a pesquisa de qualificação', base - 3 * H, { fonte: 'respondi', detalhe: pick(['Advogado · já atua com holding', 'Contador · começando', 'Patrimônio até R$ 1 mi', 'Advogado · quer parceria']) });
      if (r() < 0.55) ponto('grupo', 'Entrou no grupo de WhatsApp do evento', base - 6 * H, { fonte: 'sendflow' });
      if (r() < 0.5) ponto('presenca', `Assistiu ${pick(['à aula 1', 'às aulas 1 e 2', 'às três aulas', 'ao pitch ao vivo'])}`, base - 3 * D, { fonte: 'youtube' });
      const quente = r();
      if (quente < 0.35) ponto('checkout', pick(['Abandonou o checkout', 'Gerou boleto', 'Cartão recusado (restrição no cartão)']), base - 4 * D, { fonte: 'hotmart', valor: PRECO_J[l.produto] });
      if (quente < 0.22 || (k === 0 && qtd > 1 && r() < 0.6)) {
        ponto('compra', `Comprou ${l.produto.toUpperCase()} · pagamento aprovado`, base - 4 * D - 30, { fonte: 'hotmart', valor: PRECO_J[l.produto], detalhe: pick(['Cartão 12x', 'Pix à vista', 'Boleto']) });
        if (r() < 0.12) ponto('reembolso', 'Pediu reembolso dentro dos 7 dias', base - 6 * D, { fonte: 'hotmart', valor: PRECO_J[l.produto], detalhe: 'Motivo informado: "não é o momento"' });
      }
    });
  });

  return {
    motivos: MOTIVOS_PADRAO.map((m) => ({ ...m })),
    jornada,
    paineis: [],
    preferencias: [],
    vendedores: VENDEDORES.map((v) => ({ ...v })),
    agrupadores: AGRUPADORES.map((a) => ({ ...a })),
    funis,
    contatos,
    negocios,
    atividades,
    eventos,
    mensagens,
    templates: TEMPLATES,
    filas,
    fichas,
    links,
    config: { horarioContato: 'Seg a sex, 8h às 20h · sáb, 9h às 13h (proposta, a definir)', limiteNegociosAbertos: null, mcpLigado: true },
  };
}
