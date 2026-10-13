// Fonte do modo demonstração: lê a base FICTÍCIA do gerador, em memória. Sem Supabase, sem rede.
// Só é carregada (import dinâmico) quando a flag NEXT_PUBLIC_BLACK_DEMO=1 está ligada fora de produção.
import type { FonteDadosBlack } from '../../application/ports';
import { LEADS_POR_PAGINA } from '../../application/ports';
import { grupoSemDado } from '../../domain/grupo';
import { diaDe } from '../../domain/recorte';
import { CANAIS_DISPARO } from '../../domain/tipos';
import type {
  CanalMensageria, GrupoBlack, GrupoResumoBlack, LinhaPerfil, MensageriaBlack, MetricasDisparo, Periodo, Profissao, RecorteGrupo,
  Resultado, ResultadoAcao, SegmentoGrupo, TotalPeriodo,
} from '../../domain/tipos';
import { CHAVE_BLACK, CONFIG_BLACK, PAGINAS } from './catalogo';
import { baseFicticia, PRIMEIRO_DIA, RELOGIO_PADRAO, ULTIMO_DIA } from './gerador';

const ok = <T,>(data: T): Resultado<T> => ({ data, semDado: false, erro: null });
const RE_DIA = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Relógio do demo. Padrão: 03/11 às 18h. `?relogio=AAAA-MM-DD` (dentro de 04/10 a 03/11) fixa o fim
 * daquele dia, 23h59 de São Paulo; valor fora disso cai no padrão.
 */
export function relogioDemo(relogio?: string | null): Date {
  if (relogio && RE_DIA.test(relogio) && relogio >= PRIMEIRO_DIA && relogio <= ULTIMO_DIA && !Number.isNaN(Date.parse(relogio))) {
    return new Date(`${relogio}T23:59:59-03:00`);
  }
  return new Date(RELOGIO_PADRAO);
}

/** Alcance do período FICTÍCIO: frequência acumulada cresce com os dias de veiculação (não soma alcance diário). */
function totalDoPeriodo(nivel: TotalPeriodo['nivel'], id: string, impressoes: number, diasComGasto: number): TotalPeriodo {
  if (impressoes === 0) return { nivel, id, alcance: null, frequencia: null };
  let h = 0;
  for (const ch of id) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  const frequencia = Math.round(Math.min(1 + 0.07 * diasComGasto * (0.8 + (h % 40) / 100), 4.5) * 100) / 100;
  return { nivel, id, alcance: Math.round(impressoes / frequencia), frequencia };
}

/** Grupos FICTÍCIOS do demo, um por segmento (o nome não é o da campanha real do SendFlow). */
export const GRUPOS_DEMO: { campanha: string; segmento: SegmentoGrupo }[] = [
  { campanha: 'Demo - Advogados', segmento: 'advogado' },
  { campanha: 'Demo - Contadores', segmento: 'contador' },
  { campanha: 'Demo - Outros', segmento: 'outros' },
];
const SEGMENTO_DA_CLASSE = (c: Profissao | null): SegmentoGrupo =>
  c === 'advogado' || c === 'estudante_direito' ? 'advogado' : c === 'contador' ? 'contador' : 'outros';

/** Lead dentro do recorte (mesma regra de dados.black_no_recorte). No demo, o id do Meta é o próprio id do fictício. */
function noRecorte(l: LinhaPerfil, r: RecorteGrupo | null): boolean {
  if (!r) return true;
  if (r.tipo === 'porta') return l.porta === r.valor;
  if (r.tipo === 'isca') return l.isca === r.valor;
  if (r.tipo === 'campanha') return (l.campanhaMeta ?? l.campanhaId) === r.valor;
  if (r.tipo === 'conjunto') return (l.conjuntoMeta ?? l.conjuntoId) === r.valor;
  return (l.anuncioMeta ?? l.anuncioId) === r.valor;
}

/**
 * Mesmas contas de dados_black_grupo sobre a base fictícia: pessoa única, classe do envio mais recente com
 * profissão, ingresso = entrada no grupo do segmento dentro do período, teste fora.
 */
export function grupoDemo(todas: LinhaPerfil[], p: Periodo, recorte: RecorteGrupo | null, limite: number): GrupoResumoBlack {
  const noPeriodo = (iso: string | null): iso is string =>
    !!iso && Date.parse(iso) <= limite && diaDe(iso) >= p.de && diaDe(iso) <= p.ate;
  const semTeste = todas.filter((l) => !l.teste);
  const classeDe = (ls: LinhaPerfil[]) => {
    const com = ls.filter((l) => l.profissao !== null).sort((a, b) => (a.criadoEm < b.criadoEm ? 1 : -1));
    return com.length ? com[0].profissao : null;
  };
  const agrupar = (ls: LinhaPerfil[]) => {
    const m = new Map<string, LinhaPerfil[]>();
    for (const l of ls) m.set(l.pessoaId, [...(m.get(l.pessoaId) ?? []), l]);
    return m;
  };
  // Ingresso: pessoa (de toda a base) cuja entrada no grupo caiu no período; o grupo é o da classe da pessoa.
  const entrou = new Map<string, SegmentoGrupo>();
  for (const [pessoa, ls] of agrupar(semTeste)) {
    if (ls.some((l) => noPeriodo(l.entrouGrupoEm))) entrou.set(pessoa, SEGMENTO_DA_CLASSE(classeDe(ls)));
  }
  // Leads do período e do recorte.
  const pessoas = agrupar(semTeste.filter((l) => noPeriodo(l.criadoEm) && noRecorte(l, recorte)));
  const classes = [...pessoas.values()].map(classeDe);
  const conta = (f: (c: Profissao | null) => boolean) => classes.filter(f).length;
  const cruzados = (seg: SegmentoGrupo[]) => [...pessoas.keys()].filter((ps) => {
    const s = entrou.get(ps);
    return s !== undefined && seg.includes(s);
  }).length;
  const mqlSeg: SegmentoGrupo[] = ['advogado', 'contador'];
  const grupos: GrupoBlack[] = GRUPOS_DEMO.map((g) => {
    const unicos = [...entrou.values()].filter((s) => s === g.segmento).length;
    return { ...g, unicos, unicosWebhook: unicos, unicosSoFoto: 0, unicosCruzados: recorte ? cruzados([g.segmento]) : null };
  });
  return {
    periodo: { de: p.de, ate: p.ate }, recorte, grupos,
    unicosGruposMql: [...entrou.values()].filter((s) => mqlSeg.includes(s)).length,
    unicosGruposTotal: entrou.size,
    unicosCruzadosMql: recorte ? cruzados(mqlSeg) : null,
    leads: {
      unicos: pessoas.size,
      mql: conta((c) => c === 'advogado' || c === 'contador' || c === 'estudante_direito'),
      advogado: conta((c) => c === 'advogado'), estudanteDireito: conta((c) => c === 'estudante_direito'),
      advogadoMaisEstudante: conta((c) => c === 'advogado' || c === 'estudante_direito'),
      contador: conta((c) => c === 'contador'), outros: conta((c) => c === 'outros'),
      semProfissao: conta((c) => c === null), naoMql: conta((c) => c === 'outros' || c === null),
    },
    atualizado: { ultimoEventoWebhook: null, ultimaFoto: null },
  };
}

export function criarFonteFixtures(relogio?: string | null): FonteDadosBlack {
  const agora = relogioDemo(relogio);
  const hoje = diaDe(agora.toISOString());
  const corte = (p: Periodo) => ({ de: p.de, ate: p.ate < hoje ? p.ate : hoje });
  const chaveErrada = <T,>(chave: string, vazio: T): Resultado<T> | null =>
    chave === CHAVE_BLACK ? null : { data: vazio, semDado: true, erro: `Projeto ${chave} não existe no modo demonstração.` };

  // Marcação de teste do demo, em memória e por pessoa (o banco marca pelo e-mail e pelo telefone, então todos os
  // envios da pessoa saem juntos). A base de baseFicticia() é compartilhada: nunca mutar, só marcar na leitura.
  const testes = new Set<string>();
  const comTeste = () => baseFicticia().linhas.map((l) => (testes.has(l.pessoaId) ? { ...l, teste: true } : l));
  const acao = (chave: string, leadId: string, marcar: boolean): ResultadoAcao => {
    if (chave !== CHAVE_BLACK) return { data: null, erro: 'Dashboard ou identificador não encontrado neste evento.' };
    const ps = baseFicticia().linhas.find((l) => l.leadId === leadId)?.pessoaId;
    if (!ps) return { data: null, erro: 'E-mail ou telefone não encontrado neste evento. Atualize os dados e tente novamente.' };
    const mudou = marcar ? !testes.has(ps) : testes.has(ps);
    if (marcar) testes.add(ps); else testes.delete(ps);
    return { data: mudou ? 1 : 0, erro: null };
  };

  return {
    modo: 'demonstracao',
    agora: () => new Date(agora),
    async config(chave) {
      return chaveErrada(chave, CONFIG_BLACK) ?? ok(CONFIG_BLACK);
    },
    async trafego(chave, p) {
      const b = baseFicticia();
      const vazio = { campanhas: [], conjuntos: [], anuncios: [], paginas: [], dias: [], totais: [], coletadoEm: null };
      const erro = chaveErrada(chave, vazio);
      if (erro) return erro;
      const { de, ate } = corte(p);
      const dias = b.dias.filter((d) => d.dia >= de && d.dia <= ate);
      const conjuntoDoAnuncio = new Map(b.anuncios.map((a) => [a.id, a.conjuntoId]));
      const campanhaDoConjunto = new Map(b.conjuntos.map((c) => [c.id, c.campanhaId]));
      const acc = new Map<string, { nivel: TotalPeriodo['nivel']; imp: number; dias: Set<string> }>();
      const somar = (nivel: TotalPeriodo['nivel'], id: string, imp: number, dia: string) => {
        const k = `${nivel}:${id}`;
        const a = acc.get(k) ?? { nivel, imp: 0, dias: new Set<string>() };
        a.imp += imp; a.dias.add(dia); acc.set(k, a);
      };
      for (const d of dias) {
        const cj = conjuntoDoAnuncio.get(d.anuncioId)!;
        somar('anuncio', d.anuncioId, d.impressoes, d.dia);
        somar('conjunto', cj, d.impressoes, d.dia);
        somar('campanha', campanhaDoConjunto.get(cj)!, d.impressoes, d.dia);
      }
      const totais = [...acc.entries()].map(([k, a]) => totalDoPeriodo(a.nivel, k.slice(k.indexOf(':') + 1), a.imp, a.dias.size));
      return ok({
        campanhas: b.campanhas, conjuntos: b.conjuntos, anuncios: b.anuncios, paginas: [...PAGINAS],
        dias, totais, coletadoEm: agora.toISOString(),
      });
    },
    async perfil(chave, p, opcoes) {
      const erro = chaveErrada(chave, []);
      if (erro) return erro;
      const { de, ate } = corte(p);
      const limite = agora.getTime();
      // O gerador grava criadoEm com -03:00: os 10 primeiros caracteres já são o dia de São Paulo.
      return ok(comTeste().filter((l) => {
        const dia = l.criadoEm.slice(0, 10);
        return dia >= de && dia <= ate && Date.parse(l.criadoEm) <= limite && (opcoes?.incluirTeste === true || !l.teste);
      }).map((l) => (l.entrouGrupoEm && Date.parse(l.entrouGrupoEm) > limite ? { ...l, entrouGrupoEm: null } : l)));
    },
    async grupo(chave, p, recorte) {
      const erro = chaveErrada(chave, grupoSemDado(recorte));
      if (erro) return erro;
      return ok(grupoDemo(comTeste(), corte(p), recorte, agora.getTime()));
    },
    async marcarTeste(chave, lead) {
      return acao(chave, lead.leadId, true);
    },
    async desmarcarTeste(chave, lead) {
      return acao(chave, lead.leadId, false);
    },
    async leads(chave, leadIds) {
      const erro = chaveErrada(chave, []);
      if (erro) return erro;
      const det = baseFicticia().detalhes;
      return ok(leadIds.slice(0, LEADS_POR_PAGINA).flatMap((id) => { const d = det.get(id); return d ? [d] : []; }));
    },
    async mensageria(chave, p) {
      const vazio: MensageriaBlack = { canais: [], envios: [], regua: [] };
      const erro = chaveErrada(chave, vazio);
      if (erro) return erro;
      const { de, ate } = corte(p);
      const doPeriodo = baseFicticia().mensageria.filter((m) => m.dia >= de && m.dia <= ate);
      if (doPeriodo.length === 0) return { data: vazio, semDado: true, erro: null };
      const envios = doPeriodo.flatMap((m) => m.envios).sort((x, y) => (x.enviadoEm < y.enviadoEm ? 1 : x.enviadoEm > y.enviadoEm ? -1 : 0));
      // Por canal = soma dos envios do período. Métrica que o canal não mede (todos null) continua null.
      const campos: (keyof MetricasDisparo)[] = ['enviados', 'entregues', 'lidas', 'cliques', 'falhas', 'custo'];
      const canais: CanalMensageria[] = CANAIS_DISPARO.flatMap((canal) => {
        const doCanal = envios.filter((e) => e.canal === canal);
        if (doCanal.length === 0) return [];
        const m = Object.fromEntries(campos.map((k) => {
          const vs = doCanal.map((e) => e[k]).filter((v): v is number => v !== null);
          return [k, vs.length ? Math.round(vs.reduce((t, v) => t + v, 0) * 100) / 100 : null];
        })) as unknown as MetricasDisparo;
        return [{ canal, envios: doCanal.length, ...m }];
      });
      const regua = (['2h', '12h', '24h'] as const).map((janela) => {
        const r = doPeriodo.flatMap((m) => m.regua.filter((x) => x.janela === janela));
        return { janela, enviados: r.reduce((t, x) => t + x.enviados, 0), ingressos: r.reduce((t, x) => t + x.ingressos, 0) };
      });
      return ok({ canais, envios, regua });
    },
    async marcos(chave) {
      // Presença na live e vendas: null de propósito (não existe nem no fictício).
      const vazio = { presencaLive: null, vendas: null };
      return chaveErrada(chave, vazio) ?? { data: vazio, semDado: true, erro: null };
    },
  };
}

/** Instância com o relógio padrão. */
export const fonteFixtures = criarFonteFixtures();
