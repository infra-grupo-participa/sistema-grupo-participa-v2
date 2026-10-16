// dados-planilha-relatorio: guarda no banco uma cópia da aba `Relatório` da planilha "Dados [MIAMI 2026]" (migration
// 20261016240000). A tela do dashboard da Clínica Miami lê essa cópia pela função public.dados_miami_relatorio.
// Quem chama: o cron dados-relatorio-planilha-sync (a cada 5 min), pelo ops.cron_post, com o header x-sync-chave
// (= Vault dados_relatorio_planilha_chave). A Edge entra no banco como postgres (SUPABASE_DB_URL), pega as planilhas ativas
// (dados.relatorio_planilha_config), lê a aba no Google com a conta de serviço SHEETS_SA_B64 (só leitura, a mesma da
// mensageria-planilha), transforma com o leitor puro relatorio-miami.ts e entrega ao banco (dados.relatorio_planilha_gravar).
// Leitura que falha (Google, aba, título ou cabeçalho diferente) NUNCA apaga a cópia: o banco mantém a anterior e só grava o erro.
// Resposta: 200 quando todas fecharam ok; 502 se alguma falhou (o vigia de rotinas enxerga).
// Nunca registra token, chave nem conteúdo de célula.
import postgres from 'npm:postgres@3.4.4';
import { contaDoSegredo, lerAbas, tokenDeAcesso, type Aba } from '../mensageria-planilha/planilha.ts';
import { parseRelatorioMiami } from './relatorio-miami.ts';

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
    [{ chave }] = await sql`select dados.relatorio_planilha_chave() as chave`;
  } catch {
    return json({ erro: 'banco' }, 503);
  }
  const recebida = req.headers.get('x-sync-chave') ?? '';
  if (!chave || !igual(recebida, chave)) return json({ erro: 'chave' }, 401);

  const [{ c }] = await sql`select dados.relatorio_planilha_config() as c`;
  const planilhas = (c ?? []) as { chave: string; planilha_id: string; aba: string }[];
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
    let conteudo: unknown = null;
    let erro: string | null = null;
    if (!token) erro = erroToken ?? 'google_token';
    else {
      let abas: Aba[];
      try {
        abas = await lerAbas(p.planilha_id, [p.aba], token, buscar);
      } catch {
        abas = [{ aba: p.aba, erro: 'google_leitura' }];
      }
      const a = abas[0];
      if (!a || 'erro' in a) erro = a && 'erro' in a ? a.erro : 'aba_nao_veio';
      else {
        const r = parseRelatorioMiami(a.valores);
        if (r.ok) conteudo = r.conteudo;
        else erro = r.erro;
      }
    }
    // Com erro, o banco só registra a tentativa e mantém a cópia anterior. A mensagem do Postgres não sai na resposta.
    try {
      const [{ r }] = await sql`
        select dados.relatorio_planilha_gravar(${p.chave}, ${conteudo === null ? null : sql.json(conteudo as never)}::jsonb, ${erro}) as r`;
      resultados.push({ chave: p.chave, ...r, ...(erro ? { ok: false, erro } : {}) });
    } catch {
      resultados.push({ chave: p.chave, ok: false, erro: 'banco' });
    }
  }
  const ok = resultados.every((r) => r.ok === true);
  return json({ ok, resultados }, ok ? 200 : 502);
});
