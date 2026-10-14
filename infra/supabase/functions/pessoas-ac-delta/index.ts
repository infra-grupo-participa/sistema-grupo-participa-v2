// pessoas-ac-delta: delta diário do ActiveCampaign para a pessoa única (migrations 20261014150034 e 20261014210300).
//
// Chamada: 1×/dia pelo job pg_cron 'pessoas-ac-delta' (05:40 UTC = 02:40 em Brasília), POST com o header
// x-webhook-secret = Vault cron_webhook_secret (o mesmo dos outros crons de ingestão). O job NASCE DESLIGADO e a chave
// pessoas.carga_chave 'activecampaign_delta' também (com data de fim 31/12/2026): rotina externa só com ok do Victor.
//
// O que faz, em série e com teto:
//   1. confere o segredo, a chave 'activecampaign_delta' (ligada e dentro da data de fim) e a chave 'activecampaign';
//   2. lê as listas do AC (2 chamadas) e grava no catálogo (lista nova de Sessão de Viabilidade vira pré-checkout sozinha);
//   3. lê os contatos atualizados desde o último delta (filters[updated_after], paginado por id), até TETO_PAGINAS páginas
//      de 100, e grava no estágio por pessoas.carga_ac_estagio (lote como parâmetro ligado, nunca no texto do SQL);
//   4. passa o estágio pendente para pessoas por pessoas.carga_ac_pessoas, até o orçamento de tempo.
// Teto: 2 + TETO_PAGINAS = 42 chamadas ao AC por dia, no máximo. Dia comum (medido em 14/10/2026): 2,4 a 3,8 mil contatos
// atualizados = 25 a 38 páginas. Se o teto bater, a execução fica 'parada' e o dia seguinte continua do cursor.
// Chave do AC: Vault activecampaign_api_key (nunca impressa). Erro sai só com o código.
import postgres from "npm:postgres@3.4.4";

const TETO_PAGINAS = 40;          // teto de chamadas de contatos por execução (regra do Victor: teto no código)
const ORCAMENTO_MS = 110_000;     // a Edge tem 150 s; não começa trabalho novo depois disto
const PAUSA_AC_MS = 500;          // entre páginas do AC (< 2 req/s)
const LOTE_ESTAGIO = 500;         // contatos por chamada a carga_ac_estagio
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 20 });
const espera = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
type Obj = Record<string, any>;

function igual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

// Regra do descadastro (censo-capacidade-ac.md): saiu pela pessoa = link do e-mail (campaign/message) ou motivo.
function saiuPelaPessoa(cl: Obj) {
  const z = (v: unknown) => v === null || v === undefined || v === "" || v === "0";
  return cl.status === "2" && (!z(cl.campaign) || !z(cl.message) || String(cl.unsubreason ?? "").trim() !== "");
}

// mesma montagem do infra/scripts/pessoa-unica/carga_ac.py (montar_lote)
function montarLote(p: Obj, campos: Map<string, string>) {
  const listas = new Map<string, unknown[][]>(), tags = new Map<string, number[]>(), valores = new Map<string, Obj>();
  for (const cl of p.contactLists ?? []) {
    const l = listas.get(cl.contact) ?? [];
    l.push([Number(cl.list), Number(cl.status), (cl.sdate ?? "").slice(0, 10) || null, saiuPelaPessoa(cl)]);
    listas.set(cl.contact, l);
  }
  for (const ct of p.contactTags ?? []) tags.set(ct.contact, [...(tags.get(ct.contact) ?? []), Number(ct.tag)]);
  for (const fv of p.fieldValues ?? []) {
    const pt = campos.get(String(fv.field));
    const v = String(fv.value ?? "").trim();
    if (pt && v) valores.set(fv.contact, { ...(valores.get(fv.contact) ?? {}), [pt]: v.slice(0, 500) });
  }
  return (p.contacts ?? []).map((c: Obj) => ({
    id: Number(c.id), email: c.email || null, telefone: c.phone || null,
    nome: [c.firstName, c.lastName].map((x: unknown) => String(x ?? "").trim()).filter(Boolean).join(" ") || null,
    cdate: c.cdate || null, udate: c.udate || null,
    bounced_hard: /^\d+$/.test(String(c.bounced_hard ?? "")) ? Number(c.bounced_hard) : null,
    listas: listas.get(c.id) ?? [], tags: [...new Set(tags.get(c.id) ?? [])].sort((a, b) => a - b),
    campos: valores.get(c.id) ?? {},
  }));
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  let eid: number | null = null;
  try {
    const [seg] = await sql`select decrypted_secret s from vault.decrypted_secrets where name = 'cron_webhook_secret'`;
    if (!seg?.s || !igual(req.headers.get("x-webhook-secret") ?? "", seg.s)) return json({ erro: "não autorizado" }, 401);
    const [ch] = await sql`select pessoas.carga_ligada('activecampaign_delta') d, pessoas.carga_ligada('activecampaign') a`;
    if (!ch.d || !ch.a) return json({ ok: true, desligada: true });
    // só depois da carga inicial do AC terminar, e nunca em cima de uma carga aberta pelo script
    const [ini] = await sql`select
        exists (select 1 from pessoas.carga_execucao where fonte = 'activecampaign' and fase = 'pessoas' and status = 'ok'
                  and coalesce(por, '') not in ('delta', 'ensaio')) feita,
        exists (select 1 from pessoas.carga_execucao where fonte = 'activecampaign' and status in ('rodando', 'parada')
                  and coalesce(por, '') <> 'delta') aberta`;
    if (!ini.feita || ini.aberta) return json({ ok: true, aguardando: ini.aberta ? "carga do script aberta" : "sem carga inicial" });

    const [k] = await sql`select (select decrypted_secret from vault.decrypted_secrets where name = 'activecampaign_api_key') k,
                                 (select description from vault.secrets where name = 'activecampaign_api_key') d`;
    const base = String(k?.d ?? "").match(/https:\/\/[a-z0-9]+\.api-us1\.com/)?.[0];
    if (!k?.k || !base) return json({ erro: "sem chave do AC no Vault" }, 500);
    let chamadas = 0;
    const ac = async (caminho: string) => {
      for (let t = 0; t < 3; t++) {
        const r = await fetch(`${base}/api/3/${caminho}`, { headers: { "Api-Token": k.k, Accept: "application/json" },
                                                           signal: AbortSignal.timeout(30_000) });
        chamadas++;
        if (r.ok) return await r.json();
        await r.body?.cancel();
        if (r.status !== 429 && r.status < 500) throw new Error(`AC HTTP ${r.status}`);
        await espera(3000 * (t + 1));
      }
      throw new Error("AC sem resposta");
    };

    // 2. listas (catálogo)
    const listas: Obj[] = [];
    for (let off = 0; off < 1000; off += 100) {
      const j = await ac(`lists?limit=100&offset=${off}`);
      listas.push(...(j.lists ?? []).map((l: Obj) => ({ tipo: "lista", id: Number(l.id), nome: l.name })));
      await espera(PAUSA_AC_MS);
      if (off + 100 >= Number(j.meta?.total ?? 0)) break;
    }
    await sql`select pessoas.carga_ac_catalogo(${sql.json(listas)}::jsonb)`;

    // 3. estágio: cursor "aaaa-mm-dd|ultimo_id" da execução aberta (retomada) ou do último delta ok
    const campos = new Map<string, string>(
      (await sql`select field_id, perstag from pessoas.ac_campo_carga`).map((r: Obj) => [String(r.field_id), r.perstag]));
    const [ab] = await sql`select pessoas.carga_abrir('activecampaign', 'estagio', 'delta') v`;
    eid = ab.v.execucao;
    let cursor: string = ab.v.cursor ??
      (await sql`select cursor from pessoas.carga_execucao where fonte = 'activecampaign' and fase = 'estagio'
                   and por = 'delta' and status = 'ok' order by id desc limit 1`)[0]?.cursor ??
      `${new Date(Date.now() - 2 * 86400_000).toISOString().slice(0, 10)}|0`;
    let [desde, ultimo] = cursor.split("|");
    const hoje = new Date().toISOString().slice(0, 10);
    let lote: Obj[] = [], paginas = 0, fim = false;
    while (paginas < TETO_PAGINAS && Date.now() - t0 < ORCAMENTO_MS * 0.7) {
      const pg = await ac(`contacts?limit=100&orders[id]=ASC&id_greater=${ultimo}&filters[updated_after]=${desde}` +
                          `&include=contactLists,contactTags,fieldValues`);
      paginas++;
      const novos = montarLote(pg, campos);
      if (novos.length === 0) { fim = true; break; }
      lote.push(...novos);
      ultimo = String(Math.max(...novos.map((c: Obj) => c.id)));
      if (lote.length >= LOTE_ESTAGIO) {
        await sql`select pessoas.carga_ac_estagio(${eid}, ${sql.json(lote)}::jsonb, ${`${desde}|${ultimo}`})`;
        lote = [];
      }
      await espera(PAUSA_AC_MS);
    }
    if (lote.length) await sql`select pessoas.carga_ac_estagio(${eid}, ${sql.json(lote)}::jsonb, ${`${desde}|${ultimo}`})`;
    // terminou o dia: o próximo delta começa da data de hoje (sobreposição de 1 dia; o estágio é idempotente)
    if (fim) {
      await sql`update pessoas.carga_execucao set cursor = ${`${hoje}|0`} where id = ${eid}`;
      await sql`select pessoas.carga_fechar(${eid}, 'ok')`;
    } else {
      await sql`select pessoas.carga_fechar(${eid}, 'parada', 'teto de páginas ou tempo; continua no próximo delta')`;
    }
    eid = null;

    // 4. estágio -> pessoas, até o orçamento
    const [pa] = await sql`select pessoas.carga_abrir('activecampaign', 'pessoas', 'delta') v`;
    eid = pa.v.execucao;
    let restam = 1;
    while (restam > 0 && Date.now() - t0 < ORCAMENTO_MS) {
      const [r] = await sql`select pessoas.carga_ac_pessoas(${eid}, 1000) v`;
      restam = Number(r.v.restam);
      if (Number(r.v.lidas) === 0) break;
    }
    await sql`select pessoas.carga_fechar(${eid}, ${restam > 0 ? "parada" : "ok"})`;
    eid = null;
    return json({ ok: true, chamadas_ac: chamadas, paginas, fim_do_dia: fim, restam, ms: Date.now() - t0 });
  } catch (e) {
    // só o código: nunca a mensagem do banco (pode trazer DETAIL com dado) nem a do AC
    const codigo = String((e as Obj)?.code ?? (e as Error)?.message ?? "erro").slice(0, 40);
    if (eid !== null) {
      try { await sql`select pessoas.carga_fechar(${eid}, 'erro', ${"delta: " + codigo})`; } catch { /* segue */ }
    }
    return json({ erro: codigo }, 500);
  }
});
