// mensageria-planilha: sync das planilhas de mensageria para mkt_mensageria.disparos (migration 20261011120000).
// Quem chama: o cron mensageria-planilha-sync (a cada 10 min), pelo ops.cron_post, com o header x-sync-chave
// (= Vault mkt_msg_planilha_chave). A Edge entra no banco como postgres (SUPABASE_DB_URL), pega as planilhas ativas
// (mkt_mensageria.planilha_sync_config), lê as abas no Google com a conta de serviço SHEETS_SA_B64 (só leitura) e
// entrega os valores crus para mkt_mensageria.planilha_sync_receber, que confere o cabeçalho, filtra, valida e grava
// (upsert pela chave da linha: rodar de novo não duplica). Toda a regra mora no banco; aqui só se lê e se repassa.
// Resposta: 200 quando todas as planilhas fecharam ok; 502 se alguma falhou (o vigia de rotinas enxerga).
// Nunca registra token, chave nem conteúdo de célula.
import postgres from 'npm:postgres@3.4.4';
import { contaDoSegredo, lerAbas, tokenDeAcesso, type Aba } from './planilha.ts';

const sql = postgres(Deno.env.get('SUPABASE_DB_URL')!, { max: 2, prepare: false, idle_timeout: 20 });

const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { 'Content-Type': 'application/json' } });

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

const buscar = (url: string, init?: RequestInit) => fetch(url, { ...init, signal: AbortSignal.timeout(20_000) });

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ erro: 'método' }, 405);
  let chave: string | null;
  try {
    [{ chave }] = await sql`select mkt_mensageria.planilha_sync_chave() as chave`;
  } catch {
    return json({ erro: 'banco' }, 503);
  }
  const recebida = req.headers.get('x-sync-chave') ?? '';
  if (!chave || !igual(recebida, chave)) return json({ erro: 'chave' }, 401);

  const [{ c }] = await sql`select mkt_mensageria.planilha_sync_config() as c`;
  const planilhas = (c ?? []) as { id: number; planilha_id: string; nome: string; abas: string[] }[];
  if (planilhas.length === 0) return json({ ok: true, planilhas: 0 });

  const sa = contaDoSegredo(Deno.env.get('SHEETS_SA_B64') ?? '');
  let token: string | null = null;
  let erroToken: string | null = null;
  if (!sa) erroToken = 'sem_conta_de_servico';
  else {
    try {
      token = await tokenDeAcesso(sa, buscar);
    } catch (e) {
      erroToken = e instanceof Error ? e.message.slice(0, 60) : 'google_token';
    }
  }

  const resultados = [];
  for (const p of planilhas) {
    let abas: Aba[];
    if (!token) abas = p.abas.map((aba) => ({ aba, erro: erroToken ?? 'google_token' }));
    else {
      try {
        abas = await lerAbas(p.planilha_id, p.abas, token, buscar);
      } catch {
        abas = p.abas.map((aba) => ({ aba, erro: 'google_leitura' }));
      }
    }
    // Mesmo com erro de leitura o banco registra a rodada (planilha_execucoes) e não poda nada.
    // Erro do banco numa planilha não derruba as outras; a mensagem do Postgres não sai na resposta.
    try {
      const [{ r }] = await sql`select mkt_mensageria.planilha_sync_receber(${p.id}, ${sql.json(abas)}::jsonb) as r`;
      resultados.push({ planilha: p.nome, ...r });
    } catch {
      resultados.push({ planilha: p.nome, ok: false, erro: 'banco' });
    }
  }
  const ok = resultados.every((r) => r.ok === true);
  return json({ ok, resultados }, ok ? 200 : 502);
});
