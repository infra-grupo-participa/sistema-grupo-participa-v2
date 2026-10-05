// Configuração de navegação — porta de app/assets/js/config.js, sem itens fora de escopo.
// REMOVIDOS: PROJECTS (Ativação HT/HM), SOCIAL_MEDIA_NAV, Jarvis, Serviços Especializados.

export interface NavChild {
  key: string;
  label: string;
  href: string;
  path: string;
  hash?: string;
  icon?: string;
  ico?: string;
  adminOnly?: boolean;
  /** Título de seção mostrado acima deste item na sidebar (opcional — só o grupo Financeiro usa hoje). */
  secao?: string;
}

export interface ReportGroup {
  key: string;
  label: string;
  path: string;
  defaultHref: string;
  icon?: string;
  ico?: string;
  setor: string;
  adminOnly?: boolean;
  children: NavChild[];
}

export interface SystemNavItem {
  key: string;
  label: string;
  path: string;
  activePrefixes?: string[];
  icon?: string;
  ico?: string;
  adminOnly?: boolean;
  devOnly?: boolean;
}

const IMG = '/assets/images';

export const REPORTS: ReportGroup[] = [
  {
    key: 'alunos',
    label: 'Base de Alunos',
    path: '/educacional/alunos',
    defaultHref: '/educacional/alunos',
    icon: `${IMG}/ICONE - USUARIOS.svg`,
    ico: 'users',
    setor: 'centro_controle',
    adminOnly: true,
    children: [],
  },
  {
    key: 'placas',
    label: 'Relatório de Placas',
    path: '/educacional/placas',
    defaultHref: '/educacional/placas#solicitacoes',
    icon: `${IMG}/ICONE -  RELATORIO DE PLACAS.svg`,
    ico: 'trophy',
    setor: 'placas',
    children: [
      { key: 'solicitacoes', label: 'Solicitações', path: '/educacional/placas', hash: '#solicitacoes', href: '/educacional/placas#solicitacoes', ico: 'mail' },
      { key: 'agenda-horarios', label: 'Agenda de Horários', path: '/educacional/placas', hash: '#agenda-horarios', href: '/educacional/placas#agenda-horarios', ico: 'calendar', adminOnly: true },
    ],
  },
  {
    key: 'depoimentos',
    label: 'Depoimentos',
    path: '/educacional/depoimentos',
    defaultHref: '/educacional/depoimentos#biblioteca',
    icon: `${IMG}/ICONE - DEPOIMENTOS.svg`,
    ico: 'depoimentos',
    setor: 'depoimentos',
    adminOnly: true,
    children: [
      { key: 'biblioteca', label: 'Biblioteca', path: '/educacional/depoimentos', hash: '#biblioteca', href: '/educacional/depoimentos#biblioteca', ico: 'biblioteca', adminOnly: true },
      { key: 'para-copy', label: 'Para Copy', path: '/educacional/depoimentos/biblioteca', href: '/educacional/depoimentos/biblioteca', ico: 'pen', adminOnly: true },
      { key: 'cursos', label: 'Cursos', path: '/educacional/depoimentos', hash: '#cursos', href: '/educacional/depoimentos#cursos', ico: 'cursos', adminOnly: true },
      { key: 'tags', label: 'Tags', path: '/educacional/depoimentos', hash: '#tags', href: '/educacional/depoimentos#tags', ico: 'tags', adminOnly: true },
    ],
  },
  // Sem adminOnly: o gate é por setor. Quem vê é dev/admin ou quem tem a área
  // 'financeiro' — ver podeVerFinanceiro(), que espelha gp_pode_ver_financeiro() no banco.
  {
    key: 'financeiro',
    label: 'Financeiro',
    path: '/educacional/financeiro',
    defaultHref: '/educacional/financeiro#board',
    ico: 'wallet',
    setor: 'financeiro',
    children: [
      // "Contas a Receber" é o título de seção (secao?), não o rótulo de item. A Visão geral (#visao, F4) é o 1º item da
      // seção; o defaultHref do grupo continua #board (a página inicial só muda depois que o Marcio vir a Visão geral).
      { key: 'visao', label: 'Visão geral', path: '/educacional/financeiro', hash: '#visao', href: '/educacional/financeiro#visao', ico: 'eye', secao: 'Contas a Receber' },
      // Mesma seção: o título aparece uma vez só (a sidebar desenha quando a seção MUDA). O hash continua #receber.
      { key: 'receber', label: 'Previsão de caixa', path: '/educacional/financeiro', hash: '#receber', href: '/educacional/financeiro#receber', ico: 'receipt', secao: 'Contas a Receber' },
      { key: 'faturamento', label: 'Faturamento', path: '/educacional/financeiro', hash: '#faturamento', href: '/educacional/financeiro#faturamento', ico: 'trending-up' },
      { key: 'board', label: 'Board', path: '/educacional/financeiro', hash: '#board', href: '/educacional/financeiro#board', ico: 'dashboard' },
      { key: 'funis', label: 'Funis', path: '/educacional/financeiro', hash: '#funis', href: '/educacional/financeiro#funis', ico: 'trending-up' },
      { key: 'escritorio', label: 'Escritório', path: '/educacional/financeiro', hash: '#escritorio', href: '/educacional/financeiro#escritorio', ico: 'trending-up' },
      { key: 'ofertas', label: 'Ofertas', path: '/educacional/financeiro', hash: '#ofertas', href: '/educacional/financeiro#ofertas', ico: 'banknote' },
      { key: 'relatorios', label: 'Relatórios', path: '/educacional/financeiro', hash: '#relatorios', href: '/educacional/financeiro#relatorios', ico: 'file' },
    ],
  },
  // Gate por setor, como o financeiro: ver podeVerRemocao(), espelho de ra_pode_ver().
  {
    key: 'remocoes',
    label: 'Remoção de Acessos',
    path: '/educacional/remocoes',
    defaultHref: '/educacional/remocoes',
    ico: 'user-x',
    setor: 'remocao_acessos',
    children: [],
  },
  // Gate por setor: ver podePedirAlteracao(), espelho de pa_pode_pedir(). Quem pede não vê a Central.
  {
    key: 'pedidos-alteracao',
    label: 'Pedidos de alteração',
    path: '/educacional/pedidos-alteracao',
    defaultHref: '/educacional/pedidos-alteracao',
    ico: 'clipboard',
    setor: 'pedidos_alteracao',
    children: [],
  },
];

export const SYSTEM_NAV: SystemNavItem[] = [
  { key: 'admin-dev', label: 'Admin Dev', path: '/sistema/admin-dev', activePrefixes: ['/sistema/admin-dev'], ico: 'wrench', devOnly: true },
  { key: 'usuarios', label: 'Usuários', path: '/usuarios', ico: 'user', adminOnly: true },
  { key: 'configuracoes', label: 'Configurações', path: '/sistema/configuracoes', activePrefixes: ['/sistema/configuracoes'], ico: 'settings' },
];

export const SIDEBAR_GROUPS = ['home', 'reports', 'system'] as const;
