// Gerador determinístico do modo demonstração (semente 20261103, PRNG mulberry32). Tudo FICTÍCIO:
// nomes "Lead Teste 00001", e-mails @exemplo.test, telefones impossíveis (o número começa com 0; celular no
// Brasil começa com 9) com DDD real coerente com a UF, para o mapa "estado pelo DDD" ter o que mostrar.
// Não importa cliente Supabase nem faz rede: roda em memória, uma vez, na primeira chamada.
import { deslocarDia } from '@/modules/infra/atm/domain/periodo';
import { DDD_UF, ufDoTelefone } from '../../domain/ddd-uf';
import type {
  Anuncio, Campanha, CanalDisparo, Conjunto, DesempenhoDia, EnvioMensageria, Funil, LeadDetalhe, LinhaPerfil, OrigemLead, Porta, Profissao,
} from '../../domain/tipos';
import { BASES_PUBLICOS, CAMPANHAS, PAGINAS, PESO_UF, PLANOS } from './catalogo';

export const SEMENTE = 20261103;
export const PRIMEIRO_DIA = '2026-10-04';
export const ULTIMO_DIA = '2026-11-03';
/** Relógio padrão do demo: 03/11, 18h, uma hora e meia antes da live. */
export const RELOGIO_PADRAO = '2026-11-03T18:00:00-03:00';
/** No último dia, nada nasce depois das 17h59 (o relógio padrão vê o dia inteiro gerado). */
const HORA_MAX_ULTIMO_DIA = 17;

export function mulberry32(semente: number): () => number {
  let a = semente >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export interface DiaMensageria { dia: string; envios: EnvioMensageria[]; regua: { janela: '2h' | '12h' | '24h'; enviados: number; ingressos: number }[] }

/** Modelos FICTÍCIOS de envio (título, objetivo e copy de demonstração; {nome} e {link} são marcadores). */
interface ModeloEnvio { titulo: string; objetivo: string; copy: string }
const MODELOS: Record<'email' | 'grupoManha' | 'grupoTarde' | 'apiBoasVindas' | 'apiLembrete' | 'sms' | 'ligacao', ModeloEnvio> = {
  email: { titulo: 'E-mail de conteúdo do dia', objetivo: 'Levar o lead para a página da live',
    copy: 'Assunto: o erro que mais custa caro no planejamento patrimonial.\n\nOi, {nome}. Separei um conteúdo curto para você ver antes da live: {link}' },
  grupoManha: { titulo: 'Aquecimento da manhã no grupo', objetivo: 'Engajar o grupo antes da live',
    copy: 'Bom dia! Hoje tem conteúdo novo sobre holding familiar aqui no grupo. Fique de olho: {link}' },
  grupoTarde: { titulo: 'Lembrete da tarde no grupo', objetivo: 'Lembrar a live do grupo',
    copy: 'Passando para lembrar: a live da Black vem aí. Ative o lembrete: {link}' },
  apiBoasVindas: { titulo: 'Boas-vindas ao inscrito', objetivo: 'Levar o inscrito para o grupo da live',
    copy: 'Oi, {nome}! Sua inscrição está confirmada. Entre no grupo para receber o link da live: {link}' },
  apiLembrete: { titulo: 'Convite para quem não entrou no grupo', objetivo: 'Levar o inscrito para o grupo da live',
    copy: '{nome}, vi que você ainda não entrou no grupo da live. O link é este: {link}' },
  sms: { titulo: 'SMS para quem não entrou no grupo', objetivo: 'Levar o inscrito para o grupo da live',
    copy: 'Black HT: sua vaga esta garantida. Entre no grupo da live: {link}' },
  ligacao: { titulo: 'Ligação para inscrito fora do grupo', objetivo: 'Levar o inscrito para o grupo da live',
    copy: 'Roteiro: confirmar a inscrição, explicar a live e enviar o link do grupo por mensagem.' },
};

export interface BaseFicticia {
  campanhas: Campanha[]; conjuntos: Conjunto[]; anuncios: Anuncio[];
  dias: DesempenhoDia[];
  linhas: LinhaPerfil[];
  detalhes: Map<string, LeadDetalhe>;
  mensageria: DiaMensageria[];
}

const pad = (n: number, k: number) => String(n).padStart(k, '0');

function sortearPeso<T extends string>(r: () => number, pesos: Readonly<Record<T, number>>): T {
  const chaves = Object.keys(pesos) as T[];
  const total = chaves.reduce((s, k) => s + pesos[k], 0);
  let x = r() * total;
  for (const k of chaves) { x -= pesos[k]; if (x <= 0) return k; }
  return chaves[chaves.length - 1];
}

/** Arredondamento estocástico: 2,3 vira 2 em 70% das vezes e 3 em 30%. Mantém a média sem viés. */
const inteiro = (r: () => number, x: number) => Math.floor(x) + (r() < x - Math.floor(x) ? 1 : 0);

const DDDS_POR_UF: Record<string, string[]> = {};
for (const [ddd, uf] of Object.entries(DDD_UF)) (DDDS_POR_UF[uf] ??= []).push(ddd);

function gerar(): BaseFicticia {
  const r = mulberry32(SEMENTE);
  const campanhas = CAMPANHAS.map((c) => ({ ...c }));
  const conjuntos = PLANOS.map((p) => ({ ...p.conjunto }));
  const anuncios: Anuncio[] = [];
  const anunciosDoPlano = PLANOS.map((p, ip) => p.anuncios.map((a, ia) => {
    const an: Anuncio = {
      id: `ad-${pad(ip + 1, 2)}-${ia + 1}`, conjuntoId: p.conjunto.id, nome: a.nome, formato: a.formato,
      paginaId: p.paginaId, miniaturaUrl: null, linkPrevia: null, linkGerenciador: null,
    };
    anuncios.push(an);
    return an;
  }));
  const campanhaPorId = new Map(campanhas.map((c) => [c.id, c]));
  const paginaPorId = new Map(PAGINAS.map((p) => [p.id, p]));

  const dias: DesempenhoDia[] = [];
  const linhas: LinhaPerfil[] = [];
  const detalhes = new Map<string, LeadDetalhe>();
  const mensageria: DiaMensageria[] = [];
  // Sorteio próprio da mensageria: o fluxo principal (r) continua com as mesmas 3 chamadas por dia de antes,
  // para os totais de tráfego e de leads não mudarem.
  const rm = mulberry32(SEMENTE + 7);
  let n = 0;
  const pessoasAnteriores: { pessoaId: string; funil: Funil | null }[] = [];

  const novoLead = (dia: string, base: Omit<LinhaPerfil, 'leadId' | 'pessoaId' | 'criadoEm' | 'primeiraPorta' | 'profissao' | 'profissaoBruta' | 'uf' | 'ufOrigem' | 'entrouGrupoEm' | 'teste'>) => {
    n += 1;
    const leadId = `ld-${pad(n, 5)}`;
    const horaMax = dia === ULTIMO_DIA ? HORA_MAX_ULTIMO_DIA : 23;
    const hora = 7 + Math.floor(r() * (horaMax - 7 + 1));
    const criadoEm = `${dia}T${pad(hora, 2)}:${pad(Math.floor(r() * 60), 2)}:${pad(Math.floor(r() * 60), 2)}-03:00`;
    // ~3% chega por uma segunda porta: reaproveita a pessoa de um cadastro de dia anterior em outro funil
    // (sorteio de 8,5% porque só vale quando o funil sorteado é outro; medido: ~3% dos cadastros).
    let pessoaId = `ps-${pad(n, 5)}`; let primeiraPorta = true;
    if (r() < 0.085 && pessoasAnteriores.length > 50) {
      const alvo = pessoasAnteriores[Math.floor(r() * pessoasAnteriores.length)];
      if (alvo.funil !== base.funil) { pessoaId = alvo.pessoaId; primeiraPorta = false; }
    }
    const prof = r();
    const profissao: Profissao | null = prof < 0.55 ? 'advogado' : prof < 0.8 ? 'contador' : prof < 0.95 ? 'outros' : null;
    const uf = sortearPeso(r, PESO_UF);
    const ddds = DDDS_POR_UF[uf];
    const ddd = ddds[Math.floor(r() * ddds.length)];
    const numero = pad(n, 9); // 9 dígitos começando com 0: número impossível
    // Casos de borda do telefone (caem em "Não informado" quando não há DDD legível).
    let telefone: string | null = `(${ddd}) ${numero.slice(0, 5)}-${numero.slice(5)}`;
    if (n % 173 === 0) telefone = '';
    else if (n % 251 === 0) telefone = 'FICTÍCIO sem número';
    else if (n % 389 === 0) telefone = null;
    else if (n % 97 === 0) telefone = `+55 ${telefone}`;
    else if (n % 131 === 0) telefone = `${ddd}${numero}`; // sem 55 e sem máscara
    const ufLida = ufDoTelefone(telefone);
    // Grupo: C3 (inscrição direta) ~75% em até 48h, C2 ~50%.
    const chance = base.porta === 'inscricao_direta' ? 0.75 : base.porta ? 0.5 : 0;
    let entrouGrupoEm: string | null = null;
    if (r() < chance) {
      const q = r();
      const horas = q < 0.55 ? r() * 2 : q < 0.75 ? 2 + r() * 10 : q < 0.9 ? 12 + r() * 12 : 24 + r() * 24;
      entrouGrupoEm = new Date(Date.parse(criadoEm) + horas * 3_600_000).toISOString();
    }
    const linha: LinhaPerfil = {
      ...base, leadId, pessoaId, criadoEm, primeiraPorta, profissao, profissaoBruta: null,
      uf: ufLida, ufOrigem: ufLida === null ? null : 'ddd', entrouGrupoEm, teste: false,
    };
    linhas.push(linha);
    detalhes.set(leadId, { leadId, nome: `Lead Teste ${pad(n, 5)}`, email: `lead${pad(n, 5)}@exemplo.test`, telefone: telefone === '' ? null : telefone });
    return linha;
  };

  const baseDoC3 = () => {
    const pesos: Record<string, number> = {};
    for (const b of BASES_PUBLICOS) pesos[b.codigo] = Math.sqrt(b.pessoas);
    const cod = sortearPeso(r, pesos);
    return BASES_PUBLICOS.find((b) => b.codigo === cod)!;
  };

  const novosDoDia: { pessoaId: string; funil: Funil | null }[] = [];
  for (let dia = PRIMEIRO_DIA; dia <= ULTIMO_DIA; dia = deslocarDia(dia, 1)) {
    pessoasAnteriores.push(...novosDoDia.splice(0));
    let pagosDoDia = 0;
    PLANOS.forEach((p, ip) => {
      if (dia < p.de || dia > p.ate) return;
      const camp = campanhaPorId.get(p.conjunto.campanhaId)!;
      const ehC1 = camp.funil === 'c1' || camp.fase === 'antecipacao';
      const captacao = camp.funil !== null && camp.funil !== 'c1';
      const progresso = (Date.parse(dia) - Date.parse(p.de)) / (Date.parse(p.ate) - Date.parse(p.de) || 1);
      const rampa = camp.funil === 'iscas' ? 0.7 + 0.6 * progresso : 1; // a verba das iscas sobe com o público do C1
      for (const an of anunciosDoPlano[ip]) {
        const gasto = Math.round((p.gastoDia / p.anuncios.length) * rampa * (0.75 + r() * 0.5) * 100) / 100;
        const cpmBase = camp.canal === 'google' ? 60 : ehC1 ? 18 : p.conjunto.conjuntoC3 === 'base' || p.conjunto.conjuntoC3 === 'quente' ? 45 : 32;
        const impressoes = Math.round((gasto / (cpmBase * (0.85 + r() * 0.3))) * 1000);
        const cliques = ehC1 ? null : Math.round(impressoes * (camp.canal === 'google' ? 0.045 : 0.011) * (0.8 + r() * 0.4));
        const lpv = captacao && camp.canal === 'meta' && cliques !== null ? Math.round(cliques * (0.68 + r() * 0.18)) : null;
        const freqDia = 1.05 + r() * 0.25;
        const video = an.formato === 'video';
        dias.push({
          anuncioId: an.id, dia, gasto, impressoes, cliquesLink: cliques, landingPageViews: lpv,
          alcance: Math.round(impressoes / freqDia), frequencia: Math.round(freqDia * 100) / 100,
          videoP50: video ? Math.round(impressoes * (0.07 + r() * 0.03)) : null,
          videoP75: video ? Math.round(impressoes * (0.04 + r() * 0.02)) : null,
          thruplay: video ? Math.round(impressoes * (0.03 + r() * 0.015)) : null,
        });
        if (p.cplAlvo === null || camp.funil === null || camp.funil === 'c1') continue;
        const qtd = inteiro(r, (gasto / p.cplAlvo) * (0.85 + r() * 0.3));
        const pagina = an.paginaId ? paginaPorId.get(an.paginaId) ?? null : null;
        const porta: Porta | null = pagina?.porta ?? null;
        for (let i = 0; i < qtd; i++) {
          const base = p.conjunto.conjuntoC3 === 'base' ? baseDoC3() : null;
          const l = novoLead(dia, {
            porta, funil: camp.funil, isca: p.conjunto.isca, conjuntoC3: p.conjunto.conjuntoC3,
            campanhaId: camp.id, conjuntoId: p.conjunto.id, anuncioId: an.id, paginaId: an.paginaId,
            origem: 'pago', canal: camp.canal,
            utmSource: camp.canal === 'google' ? 'zz-google' : 'zz-meta', utmMedium: 'zz-pago',
            utmCampaign: camp.nome, utmContent: an.nome, utmTerm: p.conjunto.nome,
            listaOrigem: base?.base ?? null, temperaturaBase: base?.temperatura ?? null, jaNaBase: base ? true : false,
          });
          novosDoDia.push({ pessoaId: l.pessoaId, funil: l.funil });
          pagosDoDia += 1;
        }
      }
    });
    // Não pagos (~10% do total): orgânico, base por API e grupo legado. Entram na lista, ficam fora do CPL.
    const naoPagos = inteiro(r, pagosDoDia * 0.11);
    for (let i = 0; i < naoPagos; i++) {
      const q = r();
      const origem: OrigemLead = q < 0.5 ? 'organico' : q < 0.85 ? 'base_api' : 'grupo_legado';
      const base = origem === 'base_api' ? baseDoC3() : null;
      const l = novoLead(dia, {
        porta: 'inscricao_direta', funil: 'c3', isca: null, conjuntoC3: null,
        campanhaId: null, conjuntoId: null, anuncioId: null, paginaId: 'pg-metodo', origem, canal: null,
        utmSource: origem === 'organico' ? 'zz-organico' : origem === 'base_api' ? 'zz-api' : 'zz-grupo',
        utmMedium: null, utmCampaign: null, utmContent: null, utmTerm: null,
        listaOrigem: base?.base ?? null, temperaturaBase: base?.temperatura ?? null, jaNaBase: base ? true : null,
      });
      novosDoDia.push({ pessoaId: l.pessoaId, funil: l.funil });
    }
    // Mensageria fictícia, a partir de 12/10: uma lista de envios por canal, cada um com título, objetivo e copy.
    if (dia >= '2026-10-12') {
      const fApi = 0.85 + r() * 0.3; const fSms = 0.85 + r() * 0.3; const fLig = 0.85 + r() * 0.3;
      const entre = (a: number, b: number) => a + rm() * (b - a);
      const envios: EnvioMensageria[] = [];
      const envio = (canal: CanalDisparo, hora: string, modelo: ModeloEnvio, base: number) => {
        const env = base;
        const m: Pick<EnvioMensageria, 'enviados' | 'entregues' | 'lidas' | 'cliques' | 'falhas' | 'custo'> = (() => {
          if (canal === 'api') {
            const falhas = Math.round(env * entre(0.02, 0.05)); const ent = env - falhas;
            return { enviados: env, entregues: ent, lidas: Math.round(ent * entre(0.6, 0.78)), cliques: Math.round(ent * entre(0.06, 0.12)), falhas, custo: Math.round(env * 0.05 * 100) / 100 };
          }
          if (canal === 'sms') {
            const falhas = Math.round(env * entre(0.06, 0.11)); const ent = env - falhas;
            return { enviados: env, entregues: ent, lidas: null, cliques: Math.round(ent * entre(0.02, 0.04)), falhas, custo: Math.round(env * 0.09 * 100) / 100 };
          }
          if (canal === 'ligacao') {
            const atendidas = Math.round(env * entre(0.28, 0.4));
            return { enviados: env, entregues: null, lidas: atendidas, cliques: null, falhas: env - atendidas, custo: Math.round(env * 0.6 * 100) / 100 };
          }
          if (canal === 'grupo') return { enviados: env, entregues: null, lidas: null, cliques: Math.round(env * entre(0.03, 0.08)), falhas: null, custo: null };
          const falhas = Math.round(env * entre(0.01, 0.03)); const ent = env - falhas;
          return { enviados: env, entregues: ent, lidas: Math.round(ent * entre(0.17, 0.28)), cliques: Math.round(ent * entre(0.015, 0.03)), falhas, custo: null };
        })();
        envios.push({ id: `env-${dia}-${canal}-${hora.replace(':', '')}`, canal, enviadoEm: `${dia}T${hora}`, base, ...modelo, ...m });
      };
      const api = Math.round(2400 * fApi);
      const membros = Math.round(linhas.length * 0.72);
      envio('email', '07:00', MODELOS.email, Math.round(9000 * entre(0.9, 1.1)));
      envio('grupo', '08:30', MODELOS.grupoManha, membros);
      envio('api', '09:30', MODELOS.apiBoasVindas, Math.round(api * 0.6));
      envio('sms', '11:00', MODELOS.sms, Math.round(800 * fSms));
      envio('ligacao', '14:00', MODELOS.ligacao, Math.round(150 * fLig));
      envio('api', '16:00', MODELOS.apiLembrete, api - Math.round(api * 0.6));
      envio('grupo', '17:30', MODELOS.grupoTarde, membros);
      const reg = (j: '2h' | '12h' | '24h', env: number, tx: number) => ({ janela: j, enviados: env, ingressos: Math.round(env * tx) });
      mensageria.push({
        dia,
        envios,
        regua: [reg('2h', Math.round(pagosDoDia * 0.5), 0.22), reg('12h', Math.round(pagosDoDia * 0.35), 0.14), reg('24h', Math.round(pagosDoDia * 0.25), 0.09)],
      });
    }
  }
  return { campanhas, conjuntos, anuncios, dias, linhas, detalhes, mensageria };
}

let memo: BaseFicticia | null = null;
/** Gera uma vez e guarda em memória. */
export function baseFicticia(): BaseFicticia {
  memo ??= gerar();
  return memo;
}
