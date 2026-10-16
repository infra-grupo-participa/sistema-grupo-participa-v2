// pessoas-ac-delta: delta diário do ActiveCampaign para a pessoa única (migrations 20261014150034 e 20261014152242).
//
// Chamada: 1×/dia pelo job pg_cron 'pessoas-ac-delta' (05:40 UTC = 02:40 em Brasília), POST com o header
// x-webhook-secret = Vault cron_webhook_secret (o mesmo dos outros crons de ingestão). Job e chave pessoas.carga_chave 'activecampaign_delta' foram
// LIGADOS em 16/10/2026 com o ok do Victor (data de fim 15/11/2026; ao religar, grava current_date + 30): rotina externa só com ok do Victor.
//
// O que faz, em série e com teto:
//   1. confere o segredo, a chave 'activecampaign_delta' (ligada e dentro da data de fim) e a chave 'activecampaign';
//   2. lê as listas do AC (2 chamadas) e grava no catálogo (lista nova de Sessão de Viabilidade vira pré-checkout sozinha);
//   3. lê os contatos atualizados desde o último delta (filters[updated_after], paginado por id), até TETO_PAGINAS páginas
//      de 100, e grava no estágio por pessoas.carga_ac_estagio (lote como parâmetro ligado, nunca no texto do SQL);
//   4. passa o estágio pendente para pessoas por pessoas.carga_ac_pessoas, até o orçamento de tempo.
// Teto: TETO_DIA = 42 requisições ao AC por dia UTC, somando execuções (manual, repetida ou do cron) e tentativas; cada
// requisição é gravada em pessoas.carga_lote (detalhe chamada_ac) ANTES de sair, no mesmo comando que confere o teto; uma só execução por vez
// (flag em memória do isolate + pg_try_advisory_lock do banco). Dia comum (medido em 14/10/2026): 2,4 a 3,8 mil contatos
// atualizados = 25 a 38 páginas. Se o teto bater, a execução fica 'parada' e o dia seguinte continua do cursor.
// Chave do AC: Vault activecampaign_api_key (nunca impressa). Erro sai só com o código.
// Revisão de 16/10/2026 (migration 20261016120000; pentester aprovou a 5ª revisão):
//   - HTTP 200 não é sucesso: execução PARCIAL (teto do dia, tempo, páginas ou estágio por passar) devolve ok:false, e o vigia
//     (ops.vigiar, regra "2xx com ok:false = falha_http") abre incidente em vez de ver "tudo certo";
//   - chave 'activecampaign_delta' ligada com data de fim vencida = 503 {ok:false, erro:'chave_vencida'} (a revisão de 30 dias não pode calar);
//   - segredo vazio é recusado ANTES de consultar o Vault; cursor é validado antes de ir para a URL do AC;
//   - estágio -> pessoas tem teto de chamadas (TETO_CHAMADAS_PESSOAS x 1.000 contatos), além do orçamento de tempo;
//   - primeiro delta nunca começa depois do fim da carga inicial (script): piso = data do fim da carga - 1 dia, para não abrir buraco.
// Correções do pentester (16/10/2026, 4ª revisão):
//   - no fim da leitura o cursor recebe o dia UTC de iniciada_em da PRÓPRIA execução (a retomada reaproveita a mesma execução), não "hoje":
//     um ciclo que atravessa a meia-noite não abre mais buraco para o contato atualizado depois da passagem do id;
//   - 'aguardando' (sem carga inicial, ou carga do script aberta) com a chave ligada sai ok:false (o vigia enxerga), não ok:true;
//   - uma execução por vez também dentro do isolate (a trava consultiva é de sessão e reentrante) e idle_timeout de 150 s (> orçamento).
import postgres from "npm:postgres@3.4.4";

const TETO_PAGINAS = 40;          // teto de páginas de contatos por execução
const TETO_DIA = 42;              // teto de REQUISIÇÕES ao AC POR DIA (UTC), somando todas as execuções e tentativas (regra do Victor;
                                  // achado A1 do pentester, 2ª revisão). Cada requisição vira uma linha em pessoas.carga_lote antes de sair.
const RQ_TIMEOUT_MS = 15_000;     // 3 tentativas de 15 s cabem nos 150 s da Edge
const ORCAMENTO_MS = 110_000;     // a Edge tem 150 s; não começa trabalho novo depois disto
const PAUSA_AC_MS = 500;          // entre páginas do AC (< 2 req/s)
const LOTE_ESTAGIO = 500;         // contatos por chamada a carga_ac_estagio
const TETO_CHAMADAS_PESSOAS = 6;  // chamadas a carga_ac_pessoas (1.000 contatos cada) por execução: 6.000. Medido em 15/10: lote de 500 leva 1,5 s em média (máx 4,5 s)
const RE_CURSOR = /^\d{4}-\d{2}-\d{2}\|\d{1,10}$/;   // aaaa-mm-dd|ultimo_id: é o que vai para a URL do AC
// idle_timeout acima dos 150 s da Edge: com 20 s, a espera entre tentativas (fetch de 15 s + 9 s) fechava a conexão e soltava a trava no meio
const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { max: 1, prepare: false, idle_timeout: 150 });
let emExecucao = false;           // flag do isolate: a trava consultiva é da sessão (reentrante), então dois POSTs aqui passariam juntos
const espera = (ms: number) => new Promise((ok) => setTimeout(ok, ms));
const json = (corpo: unknown, status = 200) =>
  new Response(JSON.stringify(corpo), { status, headers: { "Content-Type": "application/json" } });
type Obj = Record<string, any>;
class TetoAtingido extends Error {}
class TempoEsgotado extends Error {}   // orçamento de 110 s da Edge; não é o teto do dia
class CursorInvalido extends Error {}

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
  if (req.method !== "POST") return json({ erro: "método não permitido" }, 405);   // achado 3 do pentester
  const t0 = Date.now();
  let eid: number | null = null;
  let travado = false, marcado = false;
  try {
    const enviado = req.headers.get("x-webhook-secret") ?? "";
    if (!enviado) return json({ erro: "não autorizado" }, 401);   // fail-closed antes de gastar uma consulta
    const [seg] = await sql`select decrypted_secret s from vault.decrypted_secrets where name = 'cron_webhook_secret'`;
    if (!seg?.s || !igual(enviado, seg.s)) return json({ erro: "não autorizado" }, 401);
    const [ch] = await sql`select pessoas.carga_ligada('activecampaign_delta') d, pessoas.carga_ligada('activecampaign') a,
                                  coalesce((select ligada and ate is not null and current_date > ate
                                              from pessoas.carga_chave where fonte = 'activecampaign_delta'), false) vencida`;
    // ligada mas com a data de fim vencida: a revisão de 30 dias venceu. Falha visível (503), não "desligada" calada.
    if (ch.vencida) return json({ ok: false, erro: "chave_vencida" }, 503);
    if (!ch.d || !ch.a) return json({ ok: true, desligada: true });   // desligada de propósito: não é falha
    // só depois da carga inicial do AC terminar, e nunca em cima de uma carga aberta pelo script
    const [ini] = await sql`select
        exists (select 1 from pessoas.carga_execucao where fonte = 'activecampaign' and fase = 'pessoas' and status = 'ok'
                  and coalesce(por, '') not in ('delta', 'ensaio')) feita,
        exists (select 1 from pessoas.carga_execucao where fonte = 'activecampaign' and status in ('rodando', 'parada')
                  and coalesce(por, '') <> 'delta') aberta`;
    // chave ligada e o delta não pôde rodar: ok:false, para o vigia não ler "tudo certo" (a desligada de propósito é a de cima)
    if (!ini.feita || ini.aberta) return json({ ok: false, aguardando: ini.aberta ? "carga do script aberta" : "sem carga inicial" });

    // uma execução por vez (POST manual, repetido ou simultâneo ao cron): flag do isolate (síncrona, sem espera entre conferir e marcar)
    // e, entre isolates e conexões, a trava consultiva do banco
    if (emExecucao) return json({ ok: false, ocupado: true }, 409);
    emExecucao = true; marcado = true;
    const [lk] = await sql`select pg_try_advisory_lock(hashtext('pessoas-ac-delta')) ok`;
    if (!lk.ok) return json({ ok: false, ocupado: true }, 409);
    travado = true;

    const [k] = await sql`select (select decrypted_secret from vault.decrypted_secrets where name = 'activecampaign_api_key') k,
                                 (select description from vault.secrets where name = 'activecampaign_api_key') d`;
    const base = String(k?.d ?? "").match(/https:\/\/[a-z0-9]+\.api-us1\.com/)?.[0];
    if (!k?.k || !base) return json({ erro: "sem chave do AC no Vault" }, 500);
    // a execução do estágio abre ANTES da 1ª chamada: toda requisição fica gravada nela
    const [ab] = await sql`select pessoas.carga_abrir('activecampaign', 'estagio', 'delta') v`;
    eid = ab.v.execucao;
    let chamadas = 0;
    const ac = async (caminho: string) => {
      for (let t = 0; t < 3; t++) {
        if (Date.now() - t0 > ORCAMENTO_MS) throw new TempoEsgotado();
        // conferir o teto e gravar a chamada num comando só (achado B1 do pentester, 3ª revisão): com o pool de 1 conexão,
        // a trava consultiva não separa requisições do mesmo processo; sem linha devolvida = teto do dia atingido.
        // Soma todas as linhas 'chamada_ac' do dia UTC, de qualquer execução (achado B2: sem filtrar por quem abriu).
        const gravada = await sql`insert into pessoas.carga_lote (execucao_id, detalhe)
                                  select ${eid}, ${sql.json({ chamada_ac: 1 })}
                                   where (select count(*) from pessoas.carga_lote
                                           where detalhe ? 'chamada_ac'
                                             and em >= (date_trunc('day', now() at time zone 'utc') at time zone 'utc')) < ${TETO_DIA}
                                  returning id`;
        if (gravada.length === 0) throw new TetoAtingido();
        chamadas++;
        const r = await fetch(`${base}/api/3/${caminho}`, { headers: { "Api-Token": k.k, Accept: "application/json" },
                                                           signal: AbortSignal.timeout(RQ_TIMEOUT_MS) });
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
      let j: Obj;
      try { j = await ac(`lists?limit=100&offset=${off}`); } catch (e) {
        if (e instanceof TetoAtingido || e instanceof TempoEsgotado) {
          const teto = e instanceof TetoAtingido;
          await sql`select pessoas.carga_fechar(${eid}, 'parada', ${teto ? "teto diário de chamadas ao AC" : "orçamento de tempo da Edge"})`;
          eid = null;
          return json({ ok: false, parcial: true, ...(teto ? { teto_do_dia: true } : { tempo_esgotado: true }), chamadas_ac: chamadas });
        }
        throw e;
      }
      listas.push(...(j.lists ?? []).map((l: Obj) => ({ tipo: "lista", id: Number(l.id), nome: l.name })));
      await espera(PAUSA_AC_MS);
      if (off + 100 >= Number(j.meta?.total ?? 0)) break;
    }
    await sql`select pessoas.carga_ac_catalogo(${sql.json(listas)}::jsonb)`;

    // 3. estágio: cursor "aaaa-mm-dd|ultimo_id" da execução aberta (retomada) ou do último delta ok
    const campos = new Map<string, string>(
      (await sql`select field_id, perstag from pessoas.ac_campo_carga`).map((r: Obj) => [String(r.field_id), r.perstag]));
    // 1º delta: a partir do fim da carga inicial menos 1 dia (nunca "hoje - 2", que abriria buraco se o cron fosse ligado dias depois);
    // sem carga inicial registrada cai no "hoje - 2" (mas a Edge já saiu em "sem carga inicial" lá em cima).
    let cursor: string = ab.v.cursor ??
      (await sql`select cursor from pessoas.carga_execucao where fonte = 'activecampaign' and fase = 'estagio'
                   and por = 'delta' and status = 'ok' order by id desc limit 1`)[0]?.cursor ??
      `${(await sql`select ((terminada_em at time zone 'utc')::date - 1)::text d from pessoas.carga_execucao
                     where fonte = 'activecampaign' and fase = 'estagio' and status = 'ok' and coalesce(por, '') not in ('delta', 'ensaio')
                     order by id desc limit 1`)[0]?.d ??
          new Date(Date.now() - 2 * 86400_000).toISOString().slice(0, 10)}|0`;
    if (!RE_CURSOR.test(cursor)) throw new CursorInvalido();
    let [desde, ultimo] = cursor.split("|");
    let lote: Obj[] = [], paginas = 0, fim = false;
    while (paginas < TETO_PAGINAS && Date.now() - t0 < ORCAMENTO_MS * 0.7) {
      let pg: Obj;
      try {
        pg = await ac(`contacts?limit=100&orders[id]=ASC&id_greater=${ultimo}&filters[updated_after]=${desde}` +
                          `&include=contactLists,contactTags,fieldValues`);
      } catch (e) {
        if (e instanceof TetoAtingido || e instanceof TempoEsgotado) break;
        throw e;
      }
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
    // terminou o dia: o próximo delta começa no dia UTC em que ESTA execução começou (iniciada_em; a retomada de uma 'parada' reaproveita a
    // mesma execução e não muda esse campo), NUNCA em "hoje": se o ciclo atravessou a meia-noite, "hoje" deixaria de fora o contato de id já
    // percorrido que foi atualizado depois da passagem. Sobreposição de 1 dia ou mais; o estágio é idempotente.
    if (fim) {
      await sql`update pessoas.carga_execucao set cursor = to_char(iniciada_em at time zone 'utc', 'YYYY-MM-DD') || '|0' where id = ${eid}`;
      await sql`select pessoas.carga_fechar(${eid}, 'ok')`;
    } else {
      await sql`select pessoas.carga_fechar(${eid}, 'parada', 'teto de páginas ou tempo; continua no próximo delta')`;
    }
    eid = null;

    // 4. estágio -> pessoas, até o orçamento
    const [pa] = await sql`select pessoas.carga_abrir('activecampaign', 'pessoas', 'delta') v`;
    eid = pa.v.execucao;
    let restam = 1, chamadasPessoas = 0;
    while (restam > 0 && chamadasPessoas < TETO_CHAMADAS_PESSOAS && Date.now() - t0 < ORCAMENTO_MS) {
      const [r] = await sql`select pessoas.carga_ac_pessoas(${eid}, 1000) v`;
      chamadasPessoas++;
      restam = Number(r.v.restam);
      if (Number(r.v.lidas) === 0) break;
    }
    await sql`select pessoas.carga_fechar(${eid}, ${restam > 0 ? "parada" : "ok"})`;
    eid = null;
    // ok só quando o dia foi lido até o fim E o estágio foi todo passado para pessoas; parcial = ok:false (o vigia enxerga)
    const completo = fim && restam === 0;
    return json({ ok: completo, ...(completo ? {} : { parcial: true }), chamadas_ac: chamadas, paginas, fim_do_dia: fim, restam,
                  chamadas_pessoas: chamadasPessoas, ms: Date.now() - t0 });
  } catch (e) {
    // só o código: nunca a mensagem do banco (pode trazer DETAIL com dado) nem a do AC
    const sqlstate = String((e as Obj)?.code ?? "");
    const msg = String((e as Error)?.message ?? "");
    const codigo = e instanceof CursorInvalido ? "cursor invalido"
      : /^[0-9A-Z]{5}$/.test(sqlstate) ? `sql ${sqlstate}` : (/^AC HTTP \d{3}$/.test(msg) ? msg : "erro");
    if (eid !== null) {
      try { await sql`select pessoas.carga_fechar(${eid}, 'erro', ${"delta: " + codigo})`; } catch { /* segue */ }
    }
    return json({ erro: codigo }, 500);
  } finally {
    if (travado) { try { await sql`select pg_advisory_unlock(hashtext('pessoas-ac-delta'))`; } catch { /* a conexão fecha */ } }
    if (marcado) emExecucao = false;
  }
});
