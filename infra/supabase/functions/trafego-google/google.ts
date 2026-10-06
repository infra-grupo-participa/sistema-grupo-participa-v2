// trafego-google: ESQUELETO da leitura do Google Ads (migration 20261006i). NÃO FUNCIONA AINDA e não tem index.ts:
// falta credencial e decisão (docs/central-de-dados.md, seção Tráfego, "Google Ads: desenho"). O que está aqui é a
// parte pura, testada no vitest com resposta simulada: a consulta GAQL e a conversão para o formato das funções de
// entrada da 20261006g (trafego_campanhas_receber e trafego_desempenho_receber).
//
// O que vai precisar (nada disso existe ainda):
//   - developer token da API do Google Ads (pedido na conta administradora, aprovado pelo Google);
//   - conta administradora (MCC) com acesso às contas dos projetos; o id dela vai no header login-customer-id;
//   - OAuth 2.0: client id e client secret de um projeto do Google Cloud e um refresh token de um usuário com acesso à
//     MCC (tudo no Vault: google_ads_developer_token, google_ads_client_id, google_ads_client_secret,
//     google_ads_refresh_token). A Edge troca o refresh token por um access token a cada rodada.
//   POST https://googleads.googleapis.com/<versão>/customers/<conta>/googleAds:searchStream  {query: GAQL}
//   headers: Authorization: Bearer <access token>, developer-token, login-customer-id (MCC, só dígitos)

export const PLATAFORMA = 'google';

/** GAQL: uma linha por campanha e dia. Custo vem em micros (1 real = 1.000.000). */
export function consultaGaql(de: string, ate: string): string {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(de) || !/^\d{4}-\d{2}-\d{2}$/.test(ate)) throw new Error('datas');
  return [
    'SELECT campaign.id, campaign.name, campaign.status, segments.date,',
    '       metrics.cost_micros, metrics.impressions, metrics.clicks',
    'FROM campaign',
    `WHERE segments.date BETWEEN '${de}' AND '${ate}'`,
  ].join('\n');
}

export function urlSearchStream(versao: string, conta: string): string {
  return `https://googleads.googleapis.com/${versao}/customers/${conta.replace(/\D/g, '')}/googleAds:searchStream`;
}

interface LinhaGaql {
  campaign?: { id?: string; name?: string; status?: string };
  segments?: { date?: string };
  metrics?: { costMicros?: string; impressions?: string; clicks?: string };
}

/**
 * Converte a resposta do searchStream (lista de lotes {results: [...]}) para o formato dos dois "receber".
 * Decisão pendente (Victor): no Google "cliques no link" = metrics.clicks (clique no anúncio). cliques_total e leads
 * ficam nulos (conversão do Google não é o lead da Central).
 */
export function paraEntrada(conta: string, lotes: { results?: LinhaGaql[] }[]) {
  const campanhas = new Map<string, { plataforma: string; conta: string; id: string; nome: string; status: string | null }>();
  const desempenho: { plataforma: string; campanha: string; dia: string; gasto: number; impressoes: number; cliques_link: number; cliques_total: null; leads: null }[] = [];
  for (const l of lotes.flatMap((x) => x.results ?? [])) {
    const id = l.campaign?.id;
    const dia = l.segments?.date;
    if (!id || !l.campaign?.name || !dia) continue;
    campanhas.set(id, { plataforma: PLATAFORMA, conta, id, nome: l.campaign.name, status: l.campaign.status ?? null });
    desempenho.push({
      plataforma: PLATAFORMA, campanha: id, dia,
      gasto: Math.round(Number(l.metrics?.costMicros ?? 0) / 10_000) / 100,
      impressoes: Number(l.metrics?.impressions ?? 0),
      cliques_link: Number(l.metrics?.clicks ?? 0),
      cliques_total: null, leads: null,
    });
  }
  return { campanhas: [...campanhas.values()], desempenho };
}
