// Captura da live do Método Perfeito (timeholdingbrasil.com.br/metodo-perfeito), 07/10/2026.
//
// Duas ações, chamadas pela página:
//   - inscricao: nome, e-mail e WhatsApp (+ UTMs). Grava em metodo.pesquisa_respostas (origem "metodo-perfeito")
//     e manda ao ActiveCampaign do Dr. Marcio: contato, lista 613 "Black Friday 2026" e a tag [BF26] Live08 (882; ate 07/10/2026 era a [BF26] BL2, 873).
//     Devolve { ok, id, token }: o token liga a pesquisa a esta inscrição. Desde 12/10/2026 aceita a profissão
//     (opcional): grava, manda ao campo 192 e à tag da área, e devolve a área.
//   - parcial (07/10/2026): id + token + UMA resposta, mandada a cada clique. Grava no banco, no campo do Active e
//     na planilha: quem para no meio da pesquisa fica com as respostas até onde chegou.
//   - pesquisa: id + token + as respostas. Grava as respostas e manda ao Active os campos [BF26] e as tags da
//     área e de pesquisa concluída. Devolve { ok, area } para a página levar ao obrigado da profissão.
//
//   - consultoria (12/10/2026): a aplicação inteira da Consultoria ao Vivo (página meta/consultoria/, cópia do
//     Respondi JmSmjBBS). Grava em metodo.consultoria_aplicacoes (migração 0011) com UTMs, fbclid/_fbc/_fbp e gclid,
//     e manda ao Active: lista 613, campo 329 = página da consultoria, 192 = profissão e UTMs. Origem
//     'consultoria-ao-vivo' (default da coluna, migração 0012); profissão só Advogado(a), Contador(a), Outros. Tag própria só se
//     TAG.consultoria for preenchida. Desde 13/10/2026 vai também à planilha da consultoria (enviaPlanilhaConsultoria).
//
//   - reuniao (13/10/2026): página /dp4 (Black THB Vencidos). Nome, e-mail e WhatsApp; origem "dp4-thb-vencidos" em
//     pesquisa_respostas; Active na lista e tag de DP4 (sem a 613 e sem planilha).
//
// Nada novo no Active: lista, campos e tags são os de servicos-internos/black-friday-2026 (activecampaign.md).
// A chave do Active fica em metodo.segredos, lida só aqui (service_role). Se o Active falhar, a pessoa segue do
// mesmo jeito (o lead está no banco) e a falha fica em active_status/active_erro para reenviar.
//
// Planilha (07/10/2026): cada inscrição e cada pesquisa também vão para o webhook do Apps Script (planilha_url em
// metodo.segredos), com a chave planilha_chave. Sem planilha_url, não envia. Uma linha por pessoa: o Apps Script
// acha a linha pelo id e completa com a pesquisa. Status em planilha_status.
import { createClient } from "npm:@supabase/supabase-js@2";

const ORIGENS = ["https://timeholdingbrasil.com.br", "https://www.timeholdingbrasil.com.br", "http://localhost:3062", "http://localhost:3061"];
const LISTA = "613";
const TAG = { Live08: "882", Advogado: "874", Contador: "875", Outros: "876", pesquisa_concluida: "877" };
const CAMPO = {
  utm_source: "193", utm_medium: "194", utm_campaign: "195", utm_content: "196", utm_term: "197",
  pagina_origem: "329", profissao: "192", faixa_etaria: "937", renda_mensal: "938", funil: "940",
  atuacao: "941", aluno: "942", holding: "943",
};
// as opções têm que ser IGUAIS às de src/app/metodoperfeito/perguntas.ts
const OPCOES: Record<string, string[]> = {
  profissao: ["Advogado(a)", "Contador(a)", "Outros"],
  atuacao: ["Autônomo(a)", "Sócio(a) de escritório", "Empregado(a) (CLT ou concurso)", "Ainda estudando"],
  faixa_etaria: ["Menos de 18 anos", "De 18 a 24 anos", "De 25 a 34 anos", "De 35 a 44 anos", "De 45 a 55 anos", "Acima de 55 anos"],
  renda_mensal: ["Menos de R$ 5 mil", "De R$ 5 mil a R$ 10 mil", "De R$ 10 mil a R$ 20 mil", "De R$ 20 mil a R$ 30 mil", "Acima de R$ 30 mil"],
  aluno: ["Não", "Sim"],
  holding: ["Ainda não, quero começar", "Já estudei, mas nunca fiz uma", "Já fiz de 1 a 5", "Já fiz mais de 5"],
};
const PROGRAMAS = ["Time Holding Brasil", "Aurum"];
// Consultoria ao Vivo: opções IGUAIS às do Respondi e às de meta/consultoria/index.html
const CONSULTORIA = {
  // só as 3 da captação (lista final do Victor, 12/10/2026, 18h), não as 5 do Respondi
  profissao: ["Advogado(a)", "Contador(a)", "Outros"],
  cursos: ["Holding Total", "Curso Prático de Holding Familiar", "Acelera Holding", "Holding Masters", "Aurum", "Outro", "Ainda não fiz nenhum"],
  momento: ["Ainda não trabalho com holding", "Estou estudando, mas ainda não fechei nenhuma", "Já fechei de 1 a 5", "Já fechei mais de 5"],
  camera: ["Ciente, posso participar ao vivo com câmera.", "Não posso participar ao vivo"],
};
// Tag do Active para a consultoria: vazia = não aplica (pedir ao Maestro o id antes de preencher)
const TAG_CONSULTORIA = "";
// 13/10/2026: /dp4 (Black THB Vencidos, Reunião Direto ao Ponto 14/10). Lista e tag próprias (Vulcano criou).
const DP4 = { lista: "622", tag: "899" }; // [BLACK THB VENCIDOS] REUNIÃO 14/10 e [BF26] THB Vencidos Reunião 14/10
// 14/10/2026: página que manda a ação "reuniao" -> origem em pesquisa_respostas. Sem entrada: "dp4-thb-vencidos".
// A chave é a página sem protocolo, sem www, sem ?query/#âncora e sem barra final, em minúsculas.
const ORIGEM_POR_PAGINA: Record<string, string> = { "timeholdingbrasil.com.br/renovacao": "renovacao-thb-vencidos" };
const chavePagina = (v: string) =>
  v.trim().toLowerCase().replace(/^https?:\/\//, "").replace(/^www\./, "").replace(/[?#].*$/, "").replace(/\/+$/, "");
const AREA: Record<string, "advogados" | "contadores" | "outros"> = { "Advogado(a)": "advogados", "Contador(a)": "contadores", Outros: "outros" };

const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { db: { schema: "metodo" } });

function cors(origem: string | null) {
  return {
    "Access-Control-Allow-Origin": origem && ORIGENS.includes(origem) ? origem : ORIGENS[0],
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Content-Type": "application/json",
  };
}
const txt = (v: unknown, max = 200) => (typeof v === "string" ? v.trim().slice(0, max) : "");

let segredos: { url: string; chave: string; planilhaUrl: string; planilhaChave: string; consultoriaUrl: string; consultoriaChave: string } | null = null;
let lidoEm = 0;
/* relê a cada minuto: quando o planilha_url entra no banco, a função já passa a usar sem novo deploy */
async function carregaSegredos() {
  if (!segredos || Date.now() - lidoEm > 60000) {
    lidoEm = Date.now();
    const { data } = await db.from("segredos").select("nome, valor");
    const m = Object.fromEntries((data ?? []).map((r: { nome: string; valor: string }) => [r.nome, r.valor]));
    segredos = { url: m.ac_api_url, chave: m.ac_api_key, planilhaUrl: m.planilha_url ?? "", planilhaChave: m.planilha_chave ?? "",
      consultoriaUrl: m.consultoria_planilha_url ?? "", consultoriaChave: m.consultoria_planilha_chave ?? "" };
  }
  return segredos;
}
/** manda a linha para a planilha (Apps Script). Nunca derruba a inscrição: só anota o resultado. */
async function enviaPlanilha(id: string, evento: "inscricao" | "pesquisa") {
  const sg = await carregaSegredos();
  if (!sg.planilhaUrl) return;
  const { data: r } = await db.from("pesquisa_respostas")
    .select("id, criado_em, pesquisa_em, nome, email, whatsapp, origem, profissao, atuacao, faixa_etaria, renda_mensal, aluno, aluno_programa, holding, utm_source, utm_medium, utm_campaign, utm_content, utm_term")
    .eq("id", id).maybeSingle();
  if (!r) return;
  let status = "ok";
  try {
    const resp = await fetch(sg.planilhaUrl, {
      method: "POST",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify({ chave: sg.planilhaChave, evento, ...r }),
      redirect: "follow",
      signal: AbortSignal.timeout(10000),
    });
    const texto = await resp.text();
    if (!resp.ok || !texto.includes('"ok":true')) status = `falhou_${resp.status}`;
  } catch (e) {
    status = `falhou_${String(e).slice(0, 80)}`;
  }
  await db.from("pesquisa_respostas").update({ planilha_status: status, planilha_em: new Date().toISOString() }).eq("id", id);
}
/** 13/10/2026: cada aplicação da consultoria vai para a aba da live na planilha "[BLACK FRIDAY/26] APLICAÇÃO
 * CONSULTORIA" (Apps Script em supabase/apps-script/consultoria-planilha.gs). Sem consultoria_planilha_url, não envia.
 * Nunca derruba a aplicação: falha só vai ao log da função (a tabela não tem coluna de status da planilha). */
async function enviaPlanilhaConsultoria(id: string) {
  const sg = await carregaSegredos();
  if (!sg.consultoriaUrl) return;
  const { data: r } = await db.from("consultoria_aplicacoes").select("*").eq("id", id).maybeSingle();
  if (!r) return;
  const data = new Date(r.criado_em).toLocaleString("sv-SE", { timeZone: "America/Sao_Paulo" });
  let status = "ok";
  try {
    const resp = await fetch(sg.consultoriaUrl, {
      method: "POST",
      headers: { "Content-Type": "text/plain;charset=utf-8" },
      body: JSON.stringify({ chave: sg.consultoriaChave, ...r, data }),
      redirect: "follow",
      signal: AbortSignal.timeout(10000),
    });
    const texto = await resp.text();
    if (!resp.ok || !texto.includes('"ok":true')) status = `falhou_${resp.status}`;
  } catch (e) {
    status = `falhou_${String(e).slice(0, 80)}`;
  }
  if (status !== "ok") console.error("planilha_consultoria", id, status);
}
async function active(caminho: string, corpo: unknown) {
  await carregaSegredos();
  if (!segredos) throw new Error("sem_segredos");
  const r = await fetch(`${segredos.url}/api/3/${caminho}`, {
    method: "POST",
    headers: { "Api-Token": segredos.chave, "Content-Type": "application/json" },
    body: JSON.stringify(corpo),
    signal: AbortSignal.timeout(12000),
  });
  return { ok: r.ok, status: r.status, j: await r.json().catch(() => ({})) };
}
/** contato (pelo e-mail) com os campos, lista 613 e as tags. Campo vazio não vai: uma etapa não apaga a outra. */
async function enviaActive(c: { email: string; nome?: string; telefone?: string }, campos: Record<string, string>, tags: string[], lista = LISTA) {
  const contato: Record<string, unknown> = {
    email: c.email,
    fieldValues: Object.entries(campos).filter(([, v]) => v).map(([field, value]) => ({ field, value })),
  };
  if (c.nome) contato.firstName = c.nome;
  if (c.telefone) contato.phone = c.telefone;
  const s = await active("contact/sync", { contact: contato });
  const id = s.j?.contact?.id;
  if (!s.ok || !id) throw new Error(`contato_${s.status}`);
  const l = await active("contactLists", { contactList: { list: lista, contact: id, status: "1" } });
  if (!l.ok) throw new Error(`lista_${l.status}`);
  const falhas: string[] = [];
  for (const tag of tags) {
    const t = await active("contactTags", { contactTag: { contact: id, tag } }).catch(() => ({ ok: false, status: 0 }));
    if (!t.ok && t.status !== 422) falhas.push(`tag${tag}_${t.status}`);
  }
  return falhas.length ? `ok_sem_${falhas.join("_")}` : "ok";
}
async function registraActive(id: string, fn: () => Promise<string>) {
  try {
    const status = await fn();
    await db.from("pesquisa_respostas").update({ active_status: status, active_erro: null, active_em: new Date().toISOString() }).eq("id", id);
  } catch (e) {
    await db.from("pesquisa_respostas").update({ active_status: "falhou", active_erro: String(e).slice(0, 300), active_em: new Date().toISOString() }).eq("id", id);
  }
}

async function registraActiveConsultoria(id: string, fn: () => Promise<string>) {
  try {
    const status = await fn();
    await db.from("consultoria_aplicacoes").update({ active_status: status, active_erro: null, active_em: new Date().toISOString() }).eq("id", id);
  } catch (e) {
    await db.from("consultoria_aplicacoes").update({ active_status: "falhou", active_erro: String(e).slice(0, 300), active_em: new Date().toISOString() }).eq("id", id);
  }
}

Deno.serve(async (req) => {
  const h = cors(req.headers.get("origin"));
  if (req.method === "OPTIONS") return new Response(null, { headers: h });
  if (req.method !== "POST") return new Response(JSON.stringify({ ok: false }), { status: 405, headers: h });
  const resposta = (dados: unknown, status = 200) => new Response(JSON.stringify(dados), { status, headers: h });

  let p: Record<string, unknown>;
  try { p = await req.json(); } catch { return resposta({ ok: false, erro: "json" }, 400); }

  if (p.acao === "inscricao") {
    if (txt(p.website)) return resposta({ ok: true, id: "", token: "" }); // robô
    const nome = txt(p.nome, 120).replace(/\s+/g, " ");
    const email = txt(p.email, 160).toLowerCase();
    // 08/10/2026: com "+" na frente o número já vem com o DDI (o campo tem a bandeira do país); sem "+", vale o Brasil
    const zapBruto = txt(p.whatsapp, 30);
    let zap = zapBruto.replace(/\D/g, "");
    if (!zapBruto.startsWith("+") && zap.length === 11) zap = "55" + zap;
    // 11/10/2026: a página nova (meta/) pede só o nome; a antiga segue pedindo sobrenome do lado dela
    if (nome.length < 2) return resposta({ ok: false, erro: "nome" }, 422);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return resposta({ ok: false, erro: "email" }, 422);
    const zapValido = /^55[1-9][0-9]9[0-9]{8}$/.test(zap) || (!zap.startsWith("55") && /^[1-9][0-9]{7,14}$/.test(zap));
    if (!zapValido) return resposta({ ok: false, erro: "whatsapp" }, 422);
    // Profissão OBRIGATÓRIA desde 12/10/2026, 18h (lista final do Victor): os 15 leads sem profissão de 08 a 11/10
    // vieram de formulários que não pediam o campo (pesquisa antiga abandonada e /meta antes de 12/10).
    const profissao = txt(p.profissao);
    if (!OPCOES.profissao.includes(profissao)) return resposta({ ok: false, erro: "profissao" }, 422);
    const utm: Record<string, string | null> = {};
    for (const k of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"]) utm[k] = txt(p[k]) || null;
    const token = crypto.randomUUID().replace(/-/g, "");
    const pagina = txt(p.pagina, 200) || "timeholdingbrasil.com.br/metodo-perfeito";
    // origem própria do Fluxograma (12/10/2026): separa no banco quem veio de cada página
    const origem = pagina.includes("fluxograma-holding-familiar") ? "fluxograma-holding-familiar" : "metodo-perfeito";
    const { data, error } = await db.from("pesquisa_respostas")
      .insert({ nome, email, whatsapp: zap, origem, token, profissao, ...utm })
      .select("id").single();
    if (error || !data) return resposta({ ok: false, erro: "banco" }, 500);
    await registraActive(data.id, () =>
      enviaActive({ email, nome, telefone: zap },
        { [CAMPO.funil]: "Live08", [CAMPO.pagina_origem]: pagina,
          [CAMPO.profissao]: profissao === "Outros" ? "Outra" : profissao,
          ...Object.fromEntries(Object.entries(utm).map(([k, v]) => [CAMPO[k as keyof typeof CAMPO], v ?? ""])) },
        [TAG.Live08, { "Advogado(a)": TAG.Advogado, "Contador(a)": TAG.Contador, Outros: TAG.Outros }[profissao]!]));
    await enviaPlanilha(data.id, "inscricao");
    return resposta({ ok: true, id: data.id, token, area: AREA[profissao] });
  }

  if (p.acao === "parcial") {
    const id = txt(p.id, 60), token = txt(p.token, 60), campo = txt(p.campo, 40), valor = txt(p.valor);
    const { data: lead } = await db.from("pesquisa_respostas").select("id, email, token").eq("id", id).maybeSingle();
    if (!lead || !token || lead.token !== token) return resposta({ ok: false, erro: "inscricao" }, 403);
    const valido = campo === "aluno_programa" ? PROGRAMAS.includes(valor) : (OPCOES[campo] ?? []).includes(valor);
    if (!valido) return resposta({ ok: false, erro: campo || "campo" }, 422);
    const mudanca: Record<string, string | null> = { [campo]: valor, atualizado_em: new Date().toISOString() };
    if (campo === "aluno" && valor === "Não") mudanca.aluno_programa = null;
    const { error } = await db.from("pesquisa_respostas").update(mudanca).eq("id", id);
    if (error) return resposta({ ok: false, erro: "banco" }, 500);
    // no Active só o campo (sem lista nem tag: isso fica para o fim)
    const campoActive: Record<string, string> = { profissao: CAMPO.profissao, atuacao: CAMPO.atuacao, faixa_etaria: CAMPO.faixa_etaria, renda_mensal: CAMPO.renda_mensal, holding: CAMPO.holding };
    try {
      if (campoActive[campo]) {
        await active("contact/sync", { contact: { email: lead.email, fieldValues: [{ field: campoActive[campo], value: campo === "profissao" && valor === "Outros" ? "Outra" : valor }] } });
      } else if (campo === "aluno_programa" || (campo === "aluno" && valor === "Não")) {
        await active("contact/sync", { contact: { email: lead.email, fieldValues: [{ field: CAMPO.aluno, value: campo === "aluno" ? "Não" : `Sim, ${valor}` }] } });
      }
    } catch { /* o banco já tem; o fim da pesquisa manda tudo de novo */ }
    await enviaPlanilha(id, "inscricao");
    return resposta({ ok: true });
  }

  if (p.acao === "pesquisa") {
    const id = txt(p.id, 60), token = txt(p.token, 60);
    const { data: lead } = await db.from("pesquisa_respostas").select("id, email, nome, whatsapp, token").eq("id", id).maybeSingle();
    if (!lead || !token || lead.token !== token) return resposta({ ok: false, erro: "inscricao" }, 403);
    const r: Record<string, string> = {};
    for (const [campo, opcoes] of Object.entries(OPCOES)) {
      const v = txt(p[campo]);
      if (!opcoes.includes(v)) return resposta({ ok: false, erro: campo }, 422);
      r[campo] = v;
    }
    const programa = r.aluno === "Sim" ? txt(p.aluno_programa) : "";
    if (r.aluno === "Sim" && !PROGRAMAS.includes(programa)) return resposta({ ok: false, erro: "aluno_programa" }, 422);
    const { error } = await db.from("pesquisa_respostas")
      .update({ ...r, aluno_programa: programa || null, pesquisa_em: new Date().toISOString(), atualizado_em: new Date().toISOString() })
      .eq("id", id);
    if (error) return resposta({ ok: false, erro: "banco" }, 500);
    const tagArea = { "Advogado(a)": TAG.Advogado, "Contador(a)": TAG.Contador, Outros: TAG.Outros }[r.profissao]!;
    await registraActive(id, () =>
      enviaActive({ email: lead.email },
        {
          [CAMPO.profissao]: r.profissao === "Outros" ? "Outra" : r.profissao,
          [CAMPO.atuacao]: r.atuacao, [CAMPO.faixa_etaria]: r.faixa_etaria, [CAMPO.renda_mensal]: r.renda_mensal,
          [CAMPO.aluno]: r.aluno === "Sim" ? `Sim, ${programa}` : "Não", [CAMPO.holding]: r.holding,
        },
        [tagArea, TAG.pesquisa_concluida]));
    await enviaPlanilha(id, "pesquisa");
    return resposta({ ok: true, area: AREA[r.profissao] });
  }

  if (p.acao === "consultoria") {
    if (txt(p.website)) return resposta({ ok: true }); // robô
    const nome = txt(p.nome, 200).replace(/\s+/g, " ");
    const email = txt(p.email, 160).toLowerCase();
    const zapBruto = txt(p.whatsapp, 30);
    let zap = zapBruto.replace(/\D/g, "");
    if (!zapBruto.startsWith("+") && zap.length === 11) zap = "55" + zap;
    if (nome.length < 2) return resposta({ ok: false, erro: "nome" }, 422);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return resposta({ ok: false, erro: "email" }, 422);
    const zapValido = /^55[1-9][0-9]9[0-9]{8}$/.test(zap) || /^55[1-9][0-9][2-5][0-9]{7}$/.test(zap) || (!zap.startsWith("55") && /^[1-9][0-9]{7,14}$/.test(zap));
    if (!zapValido) return resposta({ ok: false, erro: "whatsapp" }, 422);
    const profissao = txt(p.profissao);
    if (!CONSULTORIA.profissao.includes(profissao)) return resposta({ ok: false, erro: "profissao" }, 422);
    const cursos = Array.isArray(p.cursos) ? [...new Set(p.cursos.map((c) => txt(c)))] : [];
    if (cursos.length === 0 || !cursos.every((c) => CONSULTORIA.cursos.includes(c))) return resposta({ ok: false, erro: "cursos" }, 422);
    // a nota só existe para quem já fez algum curso, e é opcional (como no Respondi: "contém Ainda não fiz nenhum" pula)
    const fezCurso = !cursos.includes("Ainda não fiz nenhum");
    let nota: number | null = null;
    if (fezCurso && p.nota_indicacao !== null && p.nota_indicacao !== undefined && p.nota_indicacao !== "") {
      nota = Number(p.nota_indicacao);
      if (!Number.isInteger(nota) || nota < 0 || nota > 10) return resposta({ ok: false, erro: "nota" }, 422);
    }
    const momento = txt(p.momento);
    if (!CONSULTORIA.momento.includes(momento)) return resposta({ ok: false, erro: "momento" }, 422);
    const dificuldade = txt(p.dificuldade, 2000);
    if (!dificuldade) return resposta({ ok: false, erro: "dificuldade" }, 422);
    const querCaso = p.quer_levar_caso === true;
    if (p.quer_levar_caso !== true && p.quer_levar_caso !== false) return resposta({ ok: false, erro: "quer_levar_caso" }, 422);
    let caso: string | null = null, camera: string | null = null, autoriza: boolean | null = null;
    if (querCaso) {
      caso = txt(p.caso, 10000);
      camera = txt(p.participa_camera);
      if (!caso) return resposta({ ok: false, erro: "caso" }, 422);
      if (!CONSULTORIA.camera.includes(camera)) return resposta({ ok: false, erro: "participa_camera" }, 422);
      if (p.autoriza_comentar !== true) return resposta({ ok: false, erro: "autoriza_comentar" }, 422);
      autoriza = true;
    }
    if (p.aceita_mensagens !== true) return resposta({ ok: false, erro: "aceita_mensagens" }, 422);
    const rastreio: Record<string, string | null> = {};
    for (const k of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term", "fbclid", "fbc", "fbp", "gclid"]) rastreio[k] = txt(p[k], 500) || null;
    const pagina = txt(p.pagina, 200) || "timeholdingbrasil.com.br/metodo-perfeito/consultoria";
    const { data, error } = await db.from("consultoria_aplicacoes").insert({
      nome, email, whatsapp: zap, profissao, cursos, nota_indicacao: nota, momento, dificuldade,
      quer_levar_caso: querCaso, caso, participa_camera: camera, autoriza_comentar: autoriza, aceita_mensagens: true,
      ...rastreio, pagina, user_agent: (req.headers.get("user-agent") ?? "").slice(0, 300),
    }).select("id").single();
    if (error || !data) return resposta({ ok: false, erro: "banco" }, 500);
    await registraActiveConsultoria(data.id, () =>
      enviaActive({ email, nome, telefone: zap },
        { [CAMPO.pagina_origem]: pagina,
          [CAMPO.profissao]: profissao === "Outros" ? "Outra" : profissao,
          ...Object.fromEntries(["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"].map((k) => [CAMPO[k as keyof typeof CAMPO], rastreio[k] ?? ""])) },
        TAG_CONSULTORIA ? [TAG_CONSULTORIA] : []));
    await enviaPlanilhaConsultoria(data.id);
    return resposta({ ok: true, id: data.id });
  }

  // 13/10/2026: painel público /metodo-perfeito/consultoria/resultados. Só números agregados, nenhum dado pessoal
  // nem texto livre (dificuldade e caso ficam na planilha). Ignora testes pelo nome, e-mail ou utm_source.
  if (p.acao === "consultoria_resultados") {
    const { data, error } = await db.from("consultoria_aplicacoes")
      .select("criado_em, nome, email, profissao, cursos, nota_indicacao, momento, quer_levar_caso, participa_camera, utm_source, utm_campaign, active_status")
      .order("criado_em", { ascending: true }).limit(20000);
    if (error || !data) return resposta({ ok: false, erro: "banco" }, 500);
    const teste = (r: Record<string, unknown>) => /teste|test@/i.test(`${r.nome} ${r.email}`) || /teste/i.test(String(r.utm_source ?? ""));
    const reais = data.filter((r) => !teste(r));
    const conta = (vals: (string | null | undefined)[]) => {
      const m: Record<string, number> = {};
      for (const v of vals) { const k = v || "(sem)"; m[k] = (m[k] ?? 0) + 1; }
      return Object.entries(m).sort((a, b) => b[1] - a[1]);
    };
    const dia = (iso: string) => new Date(iso).toLocaleDateString("sv-SE", { timeZone: "America/Sao_Paulo" });
    const notas = reais.map((r) => r.nota_indicacao).filter((n): n is number => typeof n === "number");
    return resposta({
      ok: true,
      atualizado: new Date().toISOString(),
      total: reais.length,
      ultima: reais.length ? reais[reais.length - 1].criado_em : null,
      por_dia: conta(reais.map((r) => dia(r.criado_em))).sort((a, b) => a[0].localeCompare(b[0])),
      profissao: conta(reais.map((r) => r.profissao)),
      cursos: conta(reais.flatMap((r) => r.cursos ?? [])),
      momento: conta(reais.map((r) => r.momento)),
      quer_caso: reais.filter((r) => r.quer_levar_caso).length,
      camera: conta(reais.filter((r) => r.quer_levar_caso).map((r) => r.participa_camera)),
      nota: { respostas: notas.length, media: notas.length ? notas.reduce((a, b) => a + b, 0) / notas.length : null,
        promotores: notas.filter((n) => n >= 9).length, neutros: notas.filter((n) => n >= 7 && n <= 8).length, detratores: notas.filter((n) => n <= 6).length },
      origem: conta(reais.map((r) => r.utm_source)),
      campanha: conta(reais.map((r) => r.utm_campaign)),
      active_falhas: reais.filter((r) => r.active_status === "falhou").length,
    });
  }

  // 13/10/2026: página timeholdingbrasil.com.br/dp4 (Black THB Vencidos). Nome, e-mail e WhatsApp com DDI.
  // Grava em pesquisa_respostas com origem própria e manda ao Active na lista e tag da dp4 (sem planilha da Black).
  if (p.acao === "reuniao") {
    if (txt(p.website)) return resposta({ ok: true }); // robô
    const nome = txt(p.nome, 120).replace(/\s+/g, " ");
    const email = txt(p.email, 160).toLowerCase();
    const zapBruto = txt(p.whatsapp, 30);
    let zap = zapBruto.replace(/\D/g, "");
    if (!zapBruto.startsWith("+") && zap.length === 11) zap = "55" + zap;
    if (nome.length < 2) return resposta({ ok: false, erro: "nome" }, 422);
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(email)) return resposta({ ok: false, erro: "email" }, 422);
    const zapValido = /^55[1-9][0-9]9[0-9]{8}$/.test(zap) || (!zap.startsWith("55") && /^[1-9][0-9]{7,14}$/.test(zap));
    if (!zapValido) return resposta({ ok: false, erro: "whatsapp" }, 422);
    const utm: Record<string, string | null> = {};
    for (const k of ["utm_source", "utm_medium", "utm_campaign", "utm_content", "utm_term"]) utm[k] = txt(p[k]) || null;
    const pagina = txt(p.pagina, 200) || "timeholdingbrasil.com.br/dp4";
    // 14/10/2026: a /renovacao (cópia da dp4 para a reunião de 16/10) grava com origem própria, separada da /dp4.
    // A etiqueta do projeto vem do banco (metodo.origem_etiqueta, migration 20261014200000).
    const origem = ORIGEM_POR_PAGINA[chavePagina(pagina)] ?? "dp4-thb-vencidos";
    const { data, error } = await db.from("pesquisa_respostas")
      .insert({ nome, email, whatsapp: zap, origem, token: crypto.randomUUID().replace(/-/g, ""), ...utm })
      .select("id").single();
    if (error || !data) return resposta({ ok: false, erro: "banco" }, 500);
    await registraActive(data.id, () =>
      enviaActive({ email, nome, telefone: zap },
        { [CAMPO.pagina_origem]: pagina,
          ...Object.fromEntries(Object.entries(utm).map(([k, v]) => [CAMPO[k as keyof typeof CAMPO], v ?? ""])) },
        [DP4.tag], DP4.lista));
    return resposta({ ok: true });
  }

  return resposta({ ok: false, erro: "acao" }, 400);
});
