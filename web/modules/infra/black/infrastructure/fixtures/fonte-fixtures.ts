// Fonte do modo demonstração: lê a base FICTÍCIA do gerador, em memória. Sem Supabase, sem rede.
// Só é carregada (import dinâmico) quando a flag NEXT_PUBLIC_BLACK_DEMO=1 está ligada fora de produção.
import type { FonteDadosBlack } from '../../application/ports';
import { LEADS_POR_PAGINA } from '../../application/ports';
import { diaDe } from '../../domain/recorte';
import { CANAIS_DISPARO } from '../../domain/tipos';
import type { CanalMensageria, MensageriaBlack, MetricasDisparo, Periodo, Resultado, TotalPeriodo } from '../../domain/tipos';
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

export function criarFonteFixtures(relogio?: string | null): FonteDadosBlack {
  const agora = relogioDemo(relogio);
  const hoje = diaDe(agora.toISOString());
  const corte = (p: Periodo) => ({ de: p.de, ate: p.ate < hoje ? p.ate : hoje });
  const chaveErrada = <T,>(chave: string, vazio: T): Resultado<T> | null =>
    chave === CHAVE_BLACK ? null : { data: vazio, semDado: true, erro: `Projeto ${chave} não existe no modo demonstração.` };

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
    async perfil(chave, p) {
      const erro = chaveErrada(chave, []);
      if (erro) return erro;
      const { de, ate } = corte(p);
      const limite = agora.getTime();
      // O gerador grava criadoEm com -03:00: os 10 primeiros caracteres já são o dia de São Paulo.
      return ok(baseFicticia().linhas.filter((l) => {
        const dia = l.criadoEm.slice(0, 10);
        return dia >= de && dia <= ate && Date.parse(l.criadoEm) <= limite;
      }).map((l) => (l.entrouGrupoEm && Date.parse(l.entrouGrupoEm) > limite ? { ...l, entrouGrupoEm: null } : l)));
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
