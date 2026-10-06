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
      area('marketing', 'web', 'Web', 'globe', 'Páginas e sites'),
      area('marketing', 'mensageria', 'Mensageria', 'message', 'Disparos e grupos'),
      area('marketing', 'trafego', 'Tráfego', 'trending-up', 'Mídia paga'),
      area('marketing', 'audiovisual', 'Audiovisual', 'video', 'Vídeo e foto'),
      area('marketing', 'social-media', 'Social Media', 'share', 'Redes sociais'),
    ],
  },
  {
    key: 'comercial',
    label: 'Comercial',
    path: '/comercial',
    descricao: 'CRM: ativação, vendas e recuperação',
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
      area('comercial', 'recuperacao', 'Recuperação', 'target', 'Filas pós-lançamento com score A a D', 'ativo'),
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
  { key: 'infra', label: 'Infra', path: '/infra', descricao: 'IA e Dados', ico: 'server', status: 'em_breve', areas: [] },
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
  marketing: 'marketing', // web/modules/marketing/<area>/
  comercial: 'comercial', // CRM: web/modules/comercial/
};

export function departamento(key: DepartamentoKey): Departamento {
  const d = DEPARTAMENTOS.find((x) => x.key === key);
  if (!d) throw new Error(`Departamento desconhecido: ${key}`);
  return d;
}

/**
 * Pode ENTRAR no departamento?
 * - Educacional: qualquer pessoa da equipe logada; cada tela dentro mantém o próprio gate (igual a antes).
 * - Marketing: só admin e dev, até os níveis de acesso por departamento serem desenhados (decisão de 05/10/2026).
 *   Bloqueia o visualizador geral, gestor e operador. Ainda não há dado de Marketing no banco, então não
 *   existe regra de RLS correspondente: quando houver, ela precisa negar o visualizador do mesmo jeito.
 * - Comercial: só admin e dev enquanto o CRM roda com dados de demonstração (05/10/2026). Quando o backend
 *   entrar, o acesso passa a ser por setor (gestor e vendedores do Comercial) e a RLS nega o visualizador.
 * - Financeiro, Infra: só mostram "Em breve"; qualquer pessoa da equipe vê o aviso.
 */
export function podeVerDepartamento(u: GpUser | null, key: DepartamentoKey): boolean {
  if (!u) return false;
  if (key === 'marketing' || key === 'comercial') return ehAdminOuAcima(u);
  return true;
}

/** Departamento dono de uma rota (`/educacional/placas` → educacional). Fora dos departamentos: null. */
export function departamentoDaRota(pathname: string): DepartamentoKey | null {
  const seg = (pathname || '/').split('/')[1] || '';
  return DEPARTAMENTOS.find((d) => d.key === seg)?.key ?? null;
}
