// Respostas CRUAS (snake_case, como o PostgREST devolve) das RPCs dados_black_*, para os testes dos mapeadores de
// fonte-supabase.ts. Nomes, e-mails e telefones são FICTÍCIOS (domínio .invalid, telefone de zeros); os nomes de
// campanha seguem o padrão do tráfego, mas os ids são inventados para o teste. Não é importado por código de tela.
// Contrato de cada campo: docs/dashboard-black/README.md.

/** dados_black_trafego (migration 20261012231649). Valores em centavos; métricas que o Meta não mandou vêm null. */
export const RESPOSTA_TRAFEGO = {
  periodo_de: '2026-10-04',
  periodo_ate: '2026-10-12',
  moeda: 'BRL',
  coletado_em: '2026-10-12T22:00:00+00:00',
  anuncio_desde: '2026-10-08',
  campanhas: [
    { id: '101', nome: 'CF | BF26 | C2 | META | ISCA | ABO | LEAD', plataforma: 'meta', status: 'ACTIVE', objetivo: 'LEADS', conta: 'conta-teste', projeto_id: 1, etapa: 'C2', subtipo: 'ISCA', conflito: false },
    { id: '102', nome: 'CF | BF26 | TEASER', plataforma: 'meta', status: 'ACTIVE', objetivo: 'VIDEO', conta: 'conta-teste', projeto_id: 1, etapa: null, subtipo: null, conflito: false },
    { id: '103', nome: 'CF | BF26 | C1 | META | DISTRIBUICAO', plataforma: 'meta', status: 'PAUSED', objetivo: 'VIDEO', conta: 'conta-teste', projeto_id: 1, etapa: 'C1', subtipo: null, conflito: false },
  ],
  conjuntos: [
    { id: '201', campanha_id: '101', nome: 'CJ ISCA 01', status: 'ACTIVE', meta_otimizacao: 'LEAD' },
  ],
  anuncios: [
    { id: '301', conjunto_id: '201', nome: 'AD ISCA 01', status: 'ACTIVE', anuncio_externa: '990001', video_id: null },
    { id: '302', conjunto_id: '201', nome: 'AD ISCA 02', status: 'ACTIVE', anuncio_externa: null, video_id: null },
  ],
  dias_campanha: [
    { campanha_id: '101', dia: '2026-10-10', gasto_centavos: 12345 },
    { campanha_id: '101', dia: '2026-10-11', gasto_centavos: 655 },
    { campanha_id: '102', dia: '2026-10-11', gasto_centavos: 100000 },
  ],
  dias_anuncio: [
    {
      anuncio_id: '301', dia: '2026-10-10', gasto_centavos: 12345, impressoes: 1000, alcance: 800, frequencia: 1.25,
      cliques_link: 40, cliques_total: 55, cliques_saida: null, landing_page_views: 30, leads_plataforma: 3, engajamento: 70,
      video_plays: null, video_thruplay: null, video_p25: null, video_p50: null, video_p75: null, video_p100: null,
    },
    // Sem impressões: não é desempenho medido, fica de fora.
    { anuncio_id: '302', dia: '2026-10-10', gasto_centavos: 100, impressoes: null },
  ],
};

/** dados_black_perfil (migration 20261012234606). pessoa_id muda a cada chamada: só agrupa dentro da resposta. */
export const RESPOSTA_PERFIL = [
  {
    lead_id: 'captacao:1', pessoa_id: 'p-a', criado_em: '2026-10-10T13:00:00+00:00', primeira_porta: true,
    pagina: 'captacao', porta: 'inscricao_direta', isca: null,
    campanha_id: '880001', conjunto_id: '770001', anuncio_id: '990001', canal: 'meta',
    utm_source: 'facebook', utm_medium: 'CJ|770001', utm_campaign: 'CF|880001', utm_content: 'AD|990001', utm_term: 'Facebook_Mobile_Feed',
    profissao: 'advogado', profissao_bruta: 'Advogado(a)', mql: true, uf: 'RJ',
    entrou_grupo_em: '2026-10-10T14:00:00+00:00', entrada_grupo_aproximada: false, teste: false, parece_teste: false,
    a_corrigir: [], campos: { origem: 'formulario' },
  },
  {
    lead_id: 'checkup:2', pessoa_id: 'p-a', criado_em: '2026-10-11T13:00:00+00:00', primeira_porta: false,
    pagina: 'checkup', porta: 'isca', isca: 'Checkup',
    campanha_id: null, conjunto_id: null, anuncio_id: null, canal: null,
    utm_source: null, utm_medium: null, utm_campaign: 'disparo', utm_content: null, utm_term: null,
    profissao: null, profissao_bruta: null, mql: null, uf: 'Outros',
    entrou_grupo_em: null, entrada_grupo_aproximada: null, teste: false, parece_teste: true,
    a_corrigir: ['profissao_vazia', 'utm_campaign_fora_do_padrao'], campos: null,
  },
  // Linha sem lead_id não é cadastro: fica de fora.
  { lead_id: null, pessoa_id: 'p-b', criado_em: '2026-10-11T13:00:00+00:00' },
];

/** dados_black_leads: único lugar com dado pessoal. Aqui, só fictício. */
export const RESPOSTA_LEADS = [
  { lead_id: 'captacao:1', nome: 'Pessoa Ficticia', email: 'ficticia@exemplo.invalid', telefone: '5500000000000' },
];

/** dados_black_grupo sem recorte. Contagens no formato da resposta de 12/10 (04 a 12/10, sem teste). */
export const RESPOSTA_GRUPO = {
  periodo: { de: '2026-10-04', ate: '2026-10-12' },
  recorte: null,
  incluir_teste: false,
  grupos: [
    { campanha: 'BF26 - Live 03/11 - Advogados', segmento: 'advogado', unicos: 0, unicos_webhook: 0, unicos_so_foto: 0, unicos_cruzados: 0 },
    { campanha: 'BF26 - Live 03/11 - Contadores', segmento: 'contador', unicos: 0, unicos_webhook: 0, unicos_so_foto: 0, unicos_cruzados: 0 },
    { campanha: 'BF26 - Live 03/11 - Outros', segmento: 'outros', unicos: 0, unicos_webhook: 0, unicos_so_foto: 0, unicos_cruzados: 0 },
  ],
  unicos_grupos_mql: 0,
  unicos_grupos_total: 0,
  unicos_cruzados_mql: 0,
  leads: {
    unicos: 159, mql: 106, advogado: 79, estudante_direito: 0, advogado_mais_estudante: 79, contador: 27,
    outros: 40, sem_profissao: 13, nao_mql: 53,
  },
  atualizado: { ultimo_evento_webhook: null, ultima_foto: null },
};
