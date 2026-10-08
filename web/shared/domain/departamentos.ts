// Registro de departamentos da Central (decisão do Victor, 05/10/2026). Domínio puro: sem Next, sem Supabase.
//
// Ao entrar, a pessoa vê os DEPARTAMENTOS. Dentro de cada um, as ÁREAS (só o Marketing tem por enquanto).
// Este arquivo é a fonte única de: quais departamentos existem, em que rota moram, quais estão prontos
// ("ativo") ou "Em breve", quem pode ver cada um, e a que departamento pertence cada módulo de `web/modules`.
// Usado pela home (cards), pela sidebar (seletor) e pelo gate do layout de cada departamento.
//
// Como acrescentar uma área: ver `docs/central-de-dados.md` ("Como adicionar uma área").

import { ehAdminOuAcima, type GpUser } from './auth';

export type DepartamentoKey = 'educacional' | 'marketing' | 'comercial' | 'financeiro' | 'infra';
export type Status = 'ativo' | 'em_breve';

export interface Area {
  key: string;
  label: string;
  /** Rota da área: `/<departamento>/<area>`. */
  path: string;
  descricao: string;
  ico: string;
  status: Status;
}

export interface Departamento {
  key: DepartamentoKey;
  label: string;
  path: string;
  descricao: string;
  ico: string;
  status: Status;
  areas: Area[];
}

const area = (dep: DepartamentoKey, key: string, label: string, ico: string, descricao: string, status: Status = 'em_breve'): Area => ({
  key, label, path: `/${dep}/${key}`, descricao, ico, status,
});

export const DEPARTAMENTOS: Departamento[] = [
  {
    key: 'educacional',
    label: 'Educacional',
    path: '/educacional',
    descricao: 'Central de Alunos, placas, depoimentos, Financeiro, remoção de acessos e pedidos de alteração',
    ico: 'graduation',
    status: 'ativo',
    areas: [], // Educacional não se divide em áreas: é o sistema que já existe, modularizado.
  },
  {
    key: 'marketing',
    label: 'Marketing',
    path: '/marketing',
    descricao: 'Web, Mensageria, Tráfego, Audiovisual e Social Media',
    ico: 'megaphone',
    status: 'ativo',
    areas: [
      { ...area('marketing', 'web', 'Web', 'globe', 'Páginas e sites'), status: 'ativo' }, // o Radar (20261006f)
      { ...area('marketing', 'mensageria', 'Mensageria', 'message', 'Disparos e grupos'), status: 'ativo' }, // migration 20261005n
      { ...area('marketing', 'trafego', 'Tráfego', 'trending-up', 'Mídia paga'), status: 'ativo' }, // Central do Tráfego (20261006g)
      area('marketing', 'audiovisual', 'Audiovisual', 'video', 'Vídeo e foto'),
      area('marketing', 'social-media', 'Social Media', 'share', 'Redes sociais'),
    ],
  },
  {
    key: 'comercial',
    label: 'Comercial',
    path: '/comercial',
    descricao: 'CRM: ativação, vendas e estratégias',
    ico: 'handshake',
    status: 'ativo',
    // As "áreas" do Comercial são as telas do CRM (o playbook divide o time em Atendimento, Prospecção e
    // Fechamento, mas todos trabalham no mesmo funil). Front pronto com dados de demonstração (05/10/2026);
    // o backend entra por trás de `modules/comercial/application/ports.ts`.
    areas: [
      area('comercial', 'funil', 'Funil de vendas', 'kanban', 'Venda ativa e origens da Hotmart, por produto', 'ativo'),
      area('comercial', 'conversas', 'Conversas', 'message', 'WhatsApp oficial, atribuído ao dono do lead', 'ativo'),
      area('comercial', 'atividades', 'Atividades', 'list-checks', 'Agenda do dia, cadência e atrasadas', 'ativo'),
      area('comercial', 'contatos', 'Contatos', 'contact', 'Pessoas, dono e histórico completo', 'ativo'),
      // Ex-"Recuperação" (07/10/2026): pedidos de estratégia + as filas de recuperação. /comercial/recuperacao → 308 aqui.
      area('comercial', 'estrategias', 'Estratégias', 'target', 'Pedidos de estratégia e filas de recuperação', 'ativo'),
      area('comercial', 'disparos', 'Disparos', 'send', 'Ficha, aprovação, supressões e log', 'ativo'),
      area('comercial', 'relatorios', 'Relatórios', 'chart', 'Fechamento do dia e indicadores', 'ativo'),
      area('comercial', 'produtos', 'Produtos e ofertas', 'wallet', 'Catálogo da Hotmart e oferta vigente', 'ativo'),
      area('comercial', 'registro', 'Registro', 'clipboard', 'Log de tudo que foi feito no CRM', 'ativo'),
      area('comercial', 'playbook', 'Playbook', 'notebook', 'O playbook completo do Comercial', 'ativo'),
      area('comercial', 'social-selling', 'Social selling', 'share', 'Comentários do Instagram viram lead', 'em_breve'),
      area('comercial', 'configuracoes', 'Configurações', 'sliders', 'Distribuição, etapas, motivos e links', 'ativo'),
    ],
  },
  // Departamento Financeiro (Em breve). NÃO confundir com o módulo "Financeiro" (Contas a Receber), que hoje
  // mora DENTRO do Educacional em /educacional/financeiro e mantém o nome por decisão do Victor (05/10/2026).
  { key: 'financeiro', label: 'Financeiro', path: '/financeiro', descricao: 'Departamento financeiro da empresa', ico: 'building', status: 'em_breve', areas: [] },
  { key: 'infra', label: 'Infra', path: '/infra', descricao: 'IA e Dados', ico: 'server', status: 'ativo', areas: [] },
];

/**
 * Base compartilhada do Marketing (fase 1 da central de dados, 05/10/2026): não é área, é o cadastro que as áreas
 * leem (tabela de projetos única e páginas). Banco: schema `mkt` (migration 20261005m). Código em
 * `web/modules/marketing/projetos/`. Mesmo gate do Marketing (admin/dev).
 */
export const BASE_MARKETING: Omit<Area, 'status'>[] = [
  { key: 'projetos', label: 'Projetos e páginas', path: '/marketing/projetos', ico: 'tags', descricao: 'Projetos (PB26, HT33…) e páginas de cada um' },
];

/**
 * A que departamento pertence cada módulo de `web/modules`. `sistema` = global (vale para a Central toda:
 * usuários, configurações). Módulo novo entra aqui; o teste `departamentos.test.ts` cobra.
 */
export const MODULO_DEPARTAMENTO: Record<string, DepartamentoKey | 'sistema'> = {
  alunos: 'educacional', // inclui Pedidos de alteração
  placas: 'educacional',
  depoimentos: 'educacional',
  financeiro: 'educacional', // o módulo Contas a Receber, não o departamento Financeiro
  'remocao-acessos': 'educacional',
  usuarios: 'sistema',
  calendario: 'sistema', // home (/): calendário da empresa, toda a equipe
  marketing: 'marketing', // web/modules/marketing/<area>/
  comercial: 'comercial', // CRM: web/modules/comercial/
  infra: 'infra',
};

export function departamento(key: DepartamentoKey): Departamento {
  const d = DEPARTAMENTOS.find((x) => x.key === key);
  if (!d) throw new Error(`Departamento desconhecido: ${key}`);
  return d;
}

/**
 * Opções de acesso que dependem de configuração (flag de env). O domínio não lê env: quem chama passa
 * (`shared/composition/acesso-departamentos.ts` monta a partir de `publicEnv`). Ausente = tudo desligado.
 */
export interface OpcoesAcessoDepartamento {
  /** NEXT_PUBLIC_COMERCIAL_VENDEDORES: libera o Comercial para gestor/vendedor do Comercial (não só admin/dev). */
  comercialVendedores?: boolean;
  acessoV2?: boolean;
}

/** A flag é explícita para testes e para manter servidor e browser na mesma regra. */
export function podeEditarArea(u: GpUser | null, key: DepartamentoKey, areaKey: string | null = null, opcoes: OpcoesAcessoDepartamento = {}): boolean {
  if (!u) return false;
  if (!opcoes.acessoV2) {
    if (key === 'marketing' || key === 'infra') return ehAdminOuAcima(u);
    if (key === 'comercial') return ehDoComercial(u);
    return ehAdminOuAcima(u) || (u.cargo === 'gestor' && u.setores.includes(key));
  }
  const acesso = u.acesso;
  if (!acesso?.equipe) return false;
  if (acesso.master) return true;
  if (key === 'financeiro') return acesso.capacidades.includes('financeiro.operar');
  const chave = areaKey ? `${key}/${areaKey}` : key;
  return acesso.editar.includes(chave) || (!!areaKey && acesso.editar.includes(key));
}

export function temCapacidade(u: GpUser | null, chave: string, opcoes: OpcoesAcessoDepartamento = {}): boolean {
  if (!u) return false;
  if (!opcoes.acessoV2) return ehAdminOuAcima(u);
  return u.acesso?.equipe === true && (u.acesso.master || u.acesso.capacidades.includes(chave));
}

/**
 * É do Comercial? Espelha `crm.eh_comercial()` do banco (= `crm.eh_gestor()` OU `crm.eh_vendedor()`, migration
 * 20261005r), sem a parte que só o banco sabe:
 * - gestor: aqui é só a PORTA (cargo dev/admin, ou cargo `gestor` com área `comercial`). Quem é gestor de fato é a lista
 *   `crm.config.gestores` (`crm.eh_gestor`, migration 20261008150041) e o papel chega à tela por `crm_sessao`; admin fora
 *   da lista entra aqui mas o banco devolve "Sem acesso ao Comercial." se também não for vendedor;
 * - vendedor: status ativo, área `comercial` e função `comercial.vender` (o banco exige também a linha ATIVA em
 *   `crm.vendedor`; quem passar aqui sem ela entra na tela, mas as RPCs devolvem "Sem acesso ao Comercial." — a
 *   fronteira de dado é a RLS, isto é só a porta).
 */
export function ehDoComercial(u: GpUser | null): boolean {
  if (!u || (u.status ?? 'ativo') !== 'ativo') return false;
  if (ehAdminOuAcima(u)) return true;
  const temArea = (u.setores || []).includes('comercial');
  if (u.cargo === 'gestor' && temArea) return true;
  return temArea && (u.funcoes || []).includes('comercial.vender');
}

/**
 * Pode ENTRAR no departamento?
 * - Educacional: qualquer pessoa da equipe logada; cada tela dentro mantém o próprio gate (igual a antes).
 * - Marketing: só admin e dev, até os níveis de acesso por departamento serem desenhados (decisão de 05/10/2026).
 *   Bloqueia o visualizador geral, gestor e operador. Ainda não há dado de Marketing no banco, então não
 *   existe regra de RLS correspondente: quando houver, ela precisa negar o visualizador do mesmo jeito.
 * - Comercial: só admin e dev por padrão. Com `opcoes.comercialVendedores` (flag NEXT_PUBLIC_COMERCIAL_VENDEDORES),
 *   também quem é do Comercial (`ehDoComercial`: gestor com área comercial, vendedor com área + `comercial.vender`).
 *   Visualizador e equipe fora do Comercial continuam fora (e a RLS do schema crm também os nega).
 * - Financeiro: só mostra "Em breve"; qualquer pessoa da equipe vê o aviso.
 * - Infra: qualquer pessoa da equipe; o dado dos dashboards é travado por `dados.pode_ver` e pela capacidade financeira.
 */
export function podeVerDepartamento(u: GpUser | null, key: DepartamentoKey, opcoes: OpcoesAcessoDepartamento = {}): boolean {
  if (!u) return false;
  if (opcoes.acessoV2) return u.acesso?.equipe === true && u.acesso.ver.includes(key) &&
    (key !== 'financeiro' || temCapacidade(u, 'financeiro.ver', opcoes));
  if (key === 'marketing') return ehAdminOuAcima(u);
  if (key === 'comercial') return ehAdminOuAcima(u) || (opcoes.comercialVendedores === true && ehDoComercial(u));
  return true;
}

/** Função que libera pedir estratégia ao Comercial (vale pela FUNÇÃO, não pelo cargo; espelho de `crm.pode_solicitar_estrategia()`). */
export const FUNCAO_SOLICITAR_ESTRATEGIA = 'comercial.solicitar_estrategia';

/**
 * Pode pedir estratégia ao Comercial? Status ativo e a função `comercial.solicitar_estrategia` em `funcoes`.
 * Dev/admin SEM a função não pedem (de propósito: a permissão é da função, para poder liberar a quem não é admin).
 */
export function podeSolicitarEstrategia(u: GpUser | null): boolean {
  if (!u || (u.status ?? 'ativo') !== 'ativo') return false;
  return (u.funcoes || []).includes(FUNCAO_SOLICITAR_ESTRATEGIA);
}

/**
 * O que a pessoa abre no Comercial:
 * - 'completo': o CRM inteiro (`podeVerDepartamento`);
 * - 'estrategias': só a tela de Estratégias (quem pede estratégia e não é do Comercial vê os próprios pedidos e o placar);
 * - null: nada.
 * Usado pelo layout de /comercial, pela página de Estratégias, pela sidebar e pelo cartão da home. As outras páginas do
 * Comercial continuam exigindo `podeVerDepartamento` (cada page repete a regra). A fronteira de dado é o banco.
 */
export type AcessoComercial = 'completo' | 'relatorios' | 'estrategias' | null;
export function acessoComercial(u: GpUser | null, opcoes: OpcoesAcessoDepartamento = {}): AcessoComercial {
  if (opcoes.acessoV2) {
    if (podeVerDepartamento(u, 'comercial', opcoes) && podeEditarArea(u, 'comercial', null, opcoes)) return 'completo';
    // Quem pede estratégia e não é do Comercial abre Estratégias (antes caía em 'relatorios' e perdia a tela).
    if (podeSolicitarEstrategia(u)) return 'estrategias';
    return podeVerDepartamento(u, 'comercial', opcoes) ? 'relatorios' : null;
  }
  if (podeVerDepartamento(u, 'comercial', opcoes)) return 'completo';
  return podeSolicitarEstrategia(u) ? 'estrategias' : null;
}

/** Departamento dono de uma rota (`/educacional/placas` → educacional). Fora dos departamentos: null. */
export function departamentoDaRota(pathname: string): DepartamentoKey | null {
  const seg = (pathname || '/').split('/')[1] || '';
  return DEPARTAMENTOS.find((d) => d.key === seg)?.key ?? null;
}
