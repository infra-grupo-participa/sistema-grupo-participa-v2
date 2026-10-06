// Substitui ui/mensageria-data.ts no harness de geometria (alias do Vite em ../mensageria-geometria.spec.ts).
// Mesmos nomes exportados, nenhum acesso a banco. Volume real de 05/10/2026: 30 disparos automáticos do
// ActiveCampaign (2 com projeto PB26, 28 sem projeto, custo estimado), 4 fontes ligadas + cs_disparos desligada, 7 preços.
import type { Projeto } from '@/modules/marketing/projetos/domain/projetos';
import type {
  Disparo, Ferramenta, FonteSaude, ItemHistorico, ListaDisparos, ListaPrecos, Numero, Preco, Resultado, ResultadoImportacao,
  SaudeIntegracoes, Totais,
} from '@/modules/marketing/mensageria/domain/mensageria';
import type { FiltroDisparos } from '@/modules/marketing/mensageria/ui/mensageria-data';

export type { FiltroDisparos, DisparoForm, Retorno, NumeroForm, FerramentaForm, PrecoForm } from '@/modules/marketing/mensageria/ui/mensageria-data';

const AGORA = '2026-10-05T22:00:00-03:00';
const ha = (min: number) => new Date(new Date(AGORA).getTime() - min * 60000).toISOString();

const LINHAS: Disparo[] = Array.from({ length: 30 }, (_, i) => {
  const comProjeto = i < 2;
  return {
    id: 1000 + i, enviado_em: ha(60 * (i * 5 + 1)), projeto_id: comProjeto ? 7 : null, projeto: comProjeto ? 'PB26' : null,
    canal: 'email', ferramenta_id: 1, ferramenta: 'ActiveCampaign', numero_id: null, numero: null, tipo: null,
    copy_texto: i % 3 === 0 ? 'Última chamada: as vagas da imersão fecham hoje às 23h59. Garanta a sua agora.' : null,
    copy_link: i % 4 === 0 ? 'https://exemplo.com.br/pagina-de-vendas?utm_source=ac' : null,
    publico_lista: `Lista AC ${i + 1}`, publico_origem: 'ActiveCampaign', tamanho_lista: 1200 + i * 37,
    entregues: 1100 + i * 30, lidas: i === 5 ? 0 : 300 + i * 9, cliques: 20 + i, falhas: 3, custo_centavos: null,
    disparado_por: 'Automação AC', retorno_em: ha(30), origem: 'api', origem_sistema: 'activecampaign', id_externo: `ac-${i}`,
    importacao_id: null, atualizado_em: ha(10),
    pendencias: comProjeto ? [] : i === 5 ? ['sem_projeto', 'conferir_zero_leitura'] : ['sem_projeto'],
    campanha: comProjeto ? `[PB26] Campanha de aquecimento ${i}` : `Newsletter semanal ${i}`,
    custo_estimado_centavos: 450 + i * 11, custo_fonte: 'estimado',
  };
});

const estimado = LINHAS.reduce((s, l) => s + (l.custo_estimado_centavos ?? 0), 0);
const TOTAIS: Totais = {
  qtd: 30, tamanho: LINHAS.reduce((s, l) => s + l.tamanho_lista, 0), entregues: 40000, lidas: 9000, cliques: 900, falhas: 90,
  custo_centavos: null, com_custo: 0, sem_custo: 0, sem_retorno: 0, conferir_zero_leitura: 1,
  custo_estimado_centavos: estimado, com_estimativa: 30, custo_total_centavos: estimado, sem_preco: 0, sem_projeto: 28,
};

const OK: Resultado = { ok: true, msg: 'ok' };
const ok = async (): Promise<Resultado> => OK;

export const listarProjetos = async (): Promise<Projeto[]> => [{
  id: 7, sigla: 'PB26', nome: 'Programa Base 2026', linha: 'x', edicao: null, ano: 2026, etiqueta_clickup: null,
  subarea_trafego: null, inicio: null, fim: null, ativo: true, obs: null, paginas: 0,
}];

const ferramenta = (id: number, nome: string, extra: Partial<Ferramenta> = {}): Ferramenta => ({
  id, nome, api: 'sim', custo_mensal_centavos: null, responsavel: null, ativa: true, obs: null, atualizado_em: AGORA, ...extra,
});
export const listarFerramentas = async (): Promise<Ferramenta[]> => [
  ferramenta(1, 'ActiveCampaign', { custo_mensal_centavos: 89000, responsavel: 'Jéssica' }),
  ferramenta(2, 'Infobip'),
  ferramenta(3, 'Unnichat', { custo_mensal_centavos: 29700 }),
  ferramenta(4, 'SendFlow', { custo_mensal_centavos: 19700 }),
  ferramenta(5, 'CS Disparos', { api: 'futura', ativa: false }),
];

export async function listarNumeros(): Promise<Numero[]> {
  return [{
    id: 1, numero: '+55 11 99999-0000', projeto_id: 7, projeto: 'PB26', frente: null, responsavel: 'Ana', finalidade: 'mensageria',
    ferramenta_id: 3, ferramenta: 'Unnichat', capacidade_dia: 50, status: 'ativo', status_desde: ha(9000), arquivado_em: null,
    consumo_hoje: 62, acima_da_capacidade: true, atualizado_em: AGORA,
  }];
}

export async function listarDisparos(f: FiltroDisparos): Promise<ListaDisparos> {
  return {
    ok: true, de: f.de, ate: f.ate, limite: 500, truncado: false,
    linhas: f.projeto ? LINHAS.filter((l) => l.projeto === f.projeto) : LINHAS, totais: TOTAIS,
    por_canal: [{
      canal: 'email', qtd: 30, tamanho: TOTAIS.tamanho, entregues: 40000, lidas: 9000, cliques: 900, falhas: 90, custo_centavos: null,
      sem_custo: 0, custo_estimado_centavos: estimado, custo_total_centavos: estimado,
    }],
  };
}

export const salvarDisparo = ok;
export const arquivarDisparo = ok;
export const lancarRetorno = ok;
export const salvarNumero = ok;
export const salvarFerramenta = ok;
export const salvarPreco = ok;
export const anularPreco = ok;
export async function importar(): Promise<ResultadoImportacao | null> { return null; }
export async function historico(): Promise<ItemHistorico[] | null> { return []; }

const preco = (id: number, ferramentaNome: string, canal: string, tipo: string | null, base: string, c: number, extra: Partial<Preco> = {}): Preco => ({
  id, ferramenta_id: 1, ferramenta: ferramentaNome, canal, tipo, base_cobranca: base, preco_centavos: c, vigente_desde: '2026-09-01',
  obs: null, criado_em: ha(50000), criado_por_nome: 'Jéssica', anulado_em: null, anulado_por_nome: null, anulado_motivo: null,
  vigente_hoje: true, ...extra,
});
export async function listarPrecos(): Promise<ListaPrecos> {
  return {
    ok: true, hoje: '2026-10-05', precos: [
      preco(1, 'ActiveCampaign', 'email', null, 'tamanho_lista', 0.36),
      preco(2, 'Infobip', 'whatsapp_api', 'marketing', 'entregues', 35),
      preco(3, 'Infobip', 'whatsapp_api', 'utilidade', 'entregues', 8),
      preco(4, 'Infobip', 'sms', null, 'entregues', 6.5),
      preco(5, 'Unnichat', 'whatsapp', null, 'mensalidade', 0),
      preco(6, 'SendFlow', 'grupos', null, 'mensalidade', 0, { vigente_hoje: false, vigente_desde: '2026-11-01' }),
      preco(7, 'Infobip', 'sms', null, 'entregues', 7, { vigente_hoje: false, anulado_em: ha(20000), anulado_por_nome: 'Jéssica', anulado_motivo: 'valor digitado errado' }),
    ],
  };
}

const fonte = (chave: string, nome: string, extra: Partial<FonteSaude> = {}): FonteSaude => ({
  chave, nome, ferramenta_id: 1, ferramenta: nome, ativa: true, ativa_desde: ha(90000), intervalo_minutos: 60,
  ultima_execucao_em: ha(25), ultima_execucao_status: 'ok', ultima_ok_em: ha(25), atraso_minutos: null, atrasada: false,
  execucoes_7d: 168, recusas_7d: 0, inconsistentes_7d: 0, negadas_7d: 0, chave_no_vault: true, vigia_jobname: chave,
  ultima_reconciliacao: { dia: '2026-10-04', contagem_fonte: 30, contagem_log: 30, faltantes_total: 0, em: ha(600) }, ...extra,
});
export async function saudeIntegracoes(): Promise<SaudeIntegracoes> {
  return {
    ok: true, agora: AGORA, fontes: [
      fonte('activecampaign', 'ActiveCampaign', { execucoes_7d: 1680, recusas_7d: 3 }),
      fonte('infobip', 'Infobip', { atrasada: true, atraso_minutos: 190, ultima_ok_em: ha(190), ultima_execucao_status: 'erro', inconsistentes_7d: 12 }),
      fonte('unichat', 'Unnichat'),
      fonte('sendflow', 'SendFlow'),
      fonte('cs_disparos', 'CS Disparos', { ativa: false, chave_no_vault: false, ultima_ok_em: null, ultima_execucao_em: null, execucoes_7d: 0, ultima_reconciliacao: null }),
    ],
  };
}
