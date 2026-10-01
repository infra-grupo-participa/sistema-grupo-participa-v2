// Normalização do Respondi — porte fiel de infra/scripts/respondi/fam.py, inv.py e carga.py (mesma saída para o
// mesmo respondente). Puro: sem rede, sem banco. Mudou aqui? Mude lá também (ou aposente o Python).
// Diferenças conhecidas do Python, sem caso real no acervo: número com ".0" (JS perde: "10.0" vira "10") e objeto
// com chave numérica (JS reordena) na serialização de val().
type Obj = Record<string, any>;

export const WS: Record<number, string> = {
  160: "Holding Masters", 161: "Diamante", 162: "Aurum", 3380: "Acelera Holding", 574: "Holding Total",
};

export function familia(nome: string): string | null {
  const n = nome.toLowerCase();
  if (/nps|vota[cç]|csat|teste|c[oó]pia|apostila|resumo|arquivo secreto|feedback|sorteio|desfazer|activecamp|patroc|rateio|leads|d[uú]vida|hot seat|tema|indica[cç][aã]o tema|me conta|coisa mais importante|refinamento|compartilhamento|artigos|monitores|oab/.test(n)) return null;
  if (/coleta de opini|pesquisa inicial|briefing|pesquisa com os alunos|dados dos alunos antes/.test(n)) return "questionario_inicial";
  if (/n[ií]ve(is|l)|galeria|ingressa no diamante|renova[cç]/.test(n)) return "nivel";
  if (/s[oó]cios/.test(n)) return "socios";
  if (/envio kit|escrit[oó]rio|cnpj|dados\(|dados \(|\] dados|dados dos participantes|camisa|voo/.test(n)) return "cadastro";
  if (/pesquisa de resultados|pesquisa final|debriefing|experi[eê]ncia|reuni[oõ]es de acelera|dificuldade|interesse/.test(n)) return "pesquisa";
  if (/inscri|encontro|cl[ií]nica|workshop|palestra|webn|reserva|residen|imers|aula|aplica|participa|congresso|oficina|treinamento|holding \+|ht|consultoria|sess[aã]o/.test(n)) return "evento";
  return "outros";
}

// \b do Python 3 é Unicode (letra acentuada é palavra); o do JS é ASCII. B(x) = \bx\b do Python.
const W = "[\\p{L}\\p{N}_]";
const B = (x: string, f = "u") => new RegExp(`(?<!${W})${x}(?!${W})`, f);
const corta = (s: string, n: number) => Array.from(s).slice(0, n).join(""); // s[:n] do Python (code points)
const semTag = (s: string) => s.replace(/<[^>]+>/g, "");
export const semAcento = (s: string) => s.normalize("NFD").replace(/\p{Mn}/gu, "").toLowerCase();
export const dig = (s: unknown) => String(s ?? "").replace(/\D/g, "");
const vazio = (v: unknown) => v == null || v === "" || v === 0 || v === false ||
  (Array.isArray(v) && !v.length) || (typeof v === "object" && !Array.isArray(v) && !Object.keys(v as Obj).length);

const R_ENDERECO = ["cep", "cidade", "bairro", "pais", "complemento", "numero", "endereco", "uf"];
const REGRAS: [RegExp, string][] = [
  [/espaco de instrucao/, "espaco"],
  [/em qual nivel|seu nivel|nivel voce/, "nivel"], [B("turma"), "turma"], [/profiss/, "profissao"], [/qual a area/, "area"],
  [/sua idade/, "idade"], [/seu sexo/, "sexo"], [/anos voce se formou/, "anos_formado"], [/forma autonoma/, "atuacao"],
  [/possui equipe/, "equipe"], [/redes sociais como ferramenta/, "redes_sociais"], [/por que voce ingressou/, "objetivo"],
  [/conhecimento juridico/, "conhecimento_juridico"], [/conhecimento de holding/, "conhecimento_hf"],
];
const REGRAS2: [RegExp, string][] = [
  [/facebook/, "facebook"], [/canal no youtube/, "youtube"], [/camisa/, "camisa"], [/razao social/, "razao_social"],
  [/seccional/, "seccional"], [/familias atendidas/, "familias_12m"], [/patrimonio somado/, "patrimonio_familias"],
  [/honorarios faturados/, "honorarios_12m"], [B("cep"), "*cep"], [B("cidade"), "*cidade"], [B("bairro"), "*bairro"],
  [B("pais"), "*pais"], [/complemento/, "*complemento"], [/^(informe o )?numero$/, "*numero"],
  [/logradouro|endereco completo|endereco/, "*endereco"], [/estado \(uf\)|seu estado|^estado$|informe o estado/, "*uf"],
];

export function chave(tipo: string | undefined, pergunta: string): string | null {
  const q = semAcento(String(pergunta || "").replace(/<[^>]+>|\s+/g, " ")).trim();
  const soc = q.includes("socio") && !/aluno|titular|voce vai trazer|quantos socios|comprove|documento/.test(q);
  if (/voce vai trazer um socio/.test(q)) return "traz_socio";
  if (/quantos socios/.test(q)) return "qtd_socios";
  const p = soc ? "socio_" : "";
  if (tipo === "email" || B("e-?mail").test(q)) return p + "email";
  if (tipo === "cpf" || B("cpf").test(q)) return p + "cpf";
  if (tipo === "cnpj" || q.includes("cnpj")) return "cnpj";
  if (tipo === "phone" || /telefone|whats/.test(q)) return p + "telefone";
  const k = (lista: [RegExp, string][]) => {
    for (const [re, c] of lista) if (re.test(q)) return c.startsWith("*") ? p + c.slice(1) : c;
    return null;
  };
  if (B("cracha").test(q)) return "cracha";
  if (tipo === "name" || /nome completo|seu nome|qual o nome/.test(q)) return p + "nome";
  const a = k(REGRAS);
  if (a) return a;
  if (/instagram/.test(q) && !/seguidores|palestra/.test(q)) return "instagram";
  return k(REGRAS2);
}

// json.dumps(v, ensure_ascii=False) do Python: separadores ", " e ": ".
function pyDumps(v: unknown): string {
  if (v === null || v === undefined) return "null";
  if (Array.isArray(v)) return "[" + v.map(pyDumps).join(", ") + "]";
  if (typeof v === "object") return "{" + Object.entries(v as Obj).map(([k, x]) => JSON.stringify(k) + ": " + pyDumps(x)).join(", ") + "}";
  return JSON.stringify(v);
}

export function val(v: unknown): string {
  if (v === null || v === undefined) return "";
  if (Array.isArray(v)) return v.map(val).join(", ");
  if (typeof v === "object") {
    const o = v as Obj;
    const r = !vazio(o.url) ? o.url : !vazio(o.name) ? o.name : pyDumps(o);
    return typeof r === "string" ? r : String(r);
  }
  const s = (typeof v === "boolean" ? (v ? "True" : "False") : String(v)).trim();
  if (s.startsWith("[") && s.endsWith("]")) {
    try {
      const l = JSON.parse(s);
      if (Array.isArray(l)) return l.map(val).join(", ");
    } catch { /* igual ao Python: fica a string */ }
  }
  return s;
}

const UFS: Record<string, string> = {
  acre: "AC", alagoas: "AL", amapa: "AP", amazonas: "AM", bahia: "BA", ceara: "CE", "distrito federal": "DF",
  "espirito santo": "ES", goias: "GO", maranhao: "MA", "mato grosso": "MT", "mato grosso do sul": "MS",
  "minas gerais": "MG", para: "PA", paraiba: "PB", parana: "PR", pernambuco: "PE", piaui: "PI",
  "rio de janeiro": "RJ", "rio grande do norte": "RN", "rio grande do sul": "RS", rondonia: "RO", roraima: "RR",
  "santa catarina": "SC", "sao paulo": "SP", sergipe: "SE", tocantins: "TO",
};
const SIGLAS = new Set(Object.values(UFS));
export function uf(s: string): string | null {
  const t = semAcento(s || "").trim();
  return SIGLAS.has(t.toUpperCase()) ? t.toUpperCase() : UFS[t] ?? null;
}
const NIVEIS = [["diamante vermelho", "diamante_vermelho"], ["diamante", "diamante"], ["platina", "platina"], ["ouro", "ouro"],
  ["profissional", "profissional"], ["em formacao", "em_formacao"], ["pessoal", "pessoal"], ["iniciante", "iniciante"]];
export function nivel(s: string): string | null {
  const t = semAcento(s || "").split(" - ")[0].replace(/\s+/g, " ").trim();
  for (const [k, c] of NIVEIS) if (t.includes("nivel " + k) || t.startsWith(k)) return c;
  return null;
}
const ESPACOS: [string, string | null][] = [["nao faco parte", null], ["implementa", "holding_masters_implementacao"],
  ["holding masters", "holding_masters"], ["aurum", "aurum"], ["platina", "platina"], ["mastermind", "mastermind_diamante"],
  ["vermelho", "diamante_vermelho"]];
export function espaco(s: string): string | null {
  const t = semAcento(s || "");
  for (const [k, c] of ESPACOS) if (t.includes(k)) return c;
  return null;
}
export function cpfOk(c: string): boolean {
  if (c.length !== 11 || c === c[0].repeat(11)) return false;
  for (const n of [9, 10]) {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(c[i]) * (n + 1 - i);
    if ((s * 10) % 11 % 10 !== Number(c[n])) return false;
  }
  return true;
}

// Formulário da API (GET form) → linha de respondi.formularios + campos indexados por slug (o que inv.py guardava).
export function formulario(f: Obj, time: number, fam: string, nRespostas: number) {
  const fields = (f.fields ?? []).map((x: Obj) => ({ slug: x.slug, type: x.type, q: corta(String(x.value || ""), 200) }));
  const m = String(f.name).match(new RegExp(`\\[(T\\d{2})(?:\\.\\d)?\\]|(?<!${W})(A\\d{1,2})(?!${W})`, "u"));
  const tc: string | null = m ? (m[1] ?? m[2]) : null;
  const linha = {
    slug: f.slug, form_id: f.id, workspace: WS[time], nome: f.name, familia: fam, turma_codigo: tc,
    criado_em: corta(String(f.created_at || ""), 10) || null, n_respostas: nRespostas,
    campos: fields.filter((x: Obj) => !["welcome", "message", "thankyou", "statement", "end"].includes(x.type))
      .map((x: Obj) => ({ slug: x.slug, tipo: x.type, pergunta: semTag(x.q) })),
  };
  return { linha, flds: new Map<string, Obj>(fields.map((x: Obj) => [x.slug, x])), tc };
}

// Respondente da API (answers/form) → linha de respondi.respostas, ou null (sem nenhuma resposta com valor).
export function resposta(r: Obj, slug: string, flds: Map<string, Obj>, fam: string, tc: string | null) {
  const dados: Obj = {};
  const arr: { p: string; v: string }[] = [];
  for (const a of r.answers ?? []) {
    const fl = flds.get(a.field_slug) ?? {};
    const t = a.field_type || fl.type;
    const q = a.field_title || (fl.q ?? "");
    const v = val(a.value);
    if (!v || ["welcome", "message", "thankyou", "statement"].includes(t)) continue;
    arr.push({ p: corta(semTag(q), 300), v: corta(v, 4000) });
    let k = chave(t, q);
    if (k && fam === "socios" && R_ENDERECO.includes(k)) k = "socio_" + k;
    if (k && !(k in dados)) dados[k] = corta(v, 1000);
  }
  if (!arr.length) return null;
  for (const p of ["", "socio_"]) if (p + "uf" in dados && uf(dados[p + "uf"])) dados[p + "uf_sigla"] = uf(dados[p + "uf"]);
  if ("nivel" in dados && nivel(dados.nivel)) dados.nivel_codigo = nivel(dados.nivel);
  if ("espaco" in dados && espaco(dados.espaco)) dados.espaco_codigo = espaco(dados.espaco);
  const tm = String(dados.turma || "").match(/^\s*(T\d{1,2}(?:\.2)?|A\d{1,2})\s*$/);
  if (tm) dados.turma_codigo = tm[1];
  else if (tc && ["questionario_inicial", "socios"].includes(fam)) dados.turma_codigo = tc;
  for (const k of ["cpf", "socio_cpf"]) if (k in dados) dados[k + "_valido"] = cpfOk(dig(dados[k]));
  const cpf = dig(dados.cpf);
  const tel = dig(dados.telefone);
  return {
    uuid: r.uuid, form_slug: slug, respondido_em: r.updated_at || r.created_at,
    email: String(dados.email || "").trim().toLowerCase(), cpf: cpfOk(cpf) ? cpf : "", telefone: tel.length >= 10 ? tel : "",
    dados, respostas: arr,
  };
}
