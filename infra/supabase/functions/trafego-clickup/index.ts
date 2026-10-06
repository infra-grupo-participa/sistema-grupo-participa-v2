// trafego-clickup: espelho mínimo das tarefas do ClickUp por etiqueta de projeto (migration 20261005r). NASCE
// DESLIGADA: nenhum cron chama esta Edge até o Victor decidir o token (como ligar: bloco LIGAR da migration e
// docs/central-de-dados.md, seção Tráfego). SÓ LEITURA no ClickUp.
// Quem chama: o cron trafego-clickup, pelo ops.cron_post, com o header x-sync-chave (= Vault trafego_coleta_chave).
// Entra no banco como postgres (SUPABASE_DB_URL): token (Vault clickup_api_token) e workspace
// (mkt_trafego.coleta_config clickup_team_id) por mkt_trafego.clickup_credenciais; etiquetas dos projetos ativos por
// mkt_trafego.clickup_etiquetas; grava por public.trafego_clickup_receber. Nunca registra o token.
import postgres from 'npm:postgres@3.4.4';
import { coletarClickup } from './clickup.ts';

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false, idle_timeout: 20 });

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ erro: 'método' }, 405);
  let chave: string | null;
  try {
    [{ chave }] = await sql`select mkt_trafego.coleta_chave() as chave`;
  } catch {
    return json({ erro: 'banco' }, 503);
  }
  const recebida = req.headers.get('x-sync-chave') ?? '';
  if (!chave || !igual(recebida, chave)) return json({ erro: 'chave' }, 401);

  const [cred] = await sql`select token, team_id from mkt_trafego.clickup_credenciais()`;
  if (!cred?.token || !cred?.team_id) {
    const erro = !cred?.token ? 'sem_token' : 'sem_workspace';
    await sql`select mkt_trafego.coleta_registrar('clickup', false, ${JSON.stringify({ etiquetas: [] })}::jsonb, ${erro})`;
    return json({ ok: false, erro });
  }
  const etiquetas = (await sql`select e from mkt_trafego.clickup_etiquetas() e`).map((r) => String(r.e));
  const res = await coletarClickup(etiquetas, {
    buscar: (url, init) => fetch(url, { ...init, signal: AbortSignal.timeout(20_000) }),
    token: String(cred.token),
    team: String(cred.team_id),
    receber: async (p) => (await sql`select public.trafego_clickup_receber(${JSON.stringify(p)}::jsonb) as r`)[0].r,
  });
  const ok = res.every((r) => r.ok);
  const erro = ok ? null : res.filter((r) => !r.ok).map((r) => `${r.etiqueta}: ${r.erro}`).join('; ').slice(0, 480);
  await sql`select mkt_trafego.coleta_registrar('clickup', ${ok}, ${JSON.stringify({ etiquetas: res })}::jsonb, ${erro})`;
  return json({ ok, etiquetas: res });
});
