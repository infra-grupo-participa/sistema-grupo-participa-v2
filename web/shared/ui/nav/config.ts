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
    path: '/sistema/alunos',
    defaultHref: '/sistema/alunos',
    icon: `${IMG}/ICONE - USUARIOS.svg`,
    ico: 'users',
    setor: 'centro_controle',
    adminOnly: true,
    children: [],
  },
  {
    key: 'placas',
    label: 'Relatório de Placas',
    path: '/relatorios/placas',
    defaultHref: '/relatorios/placas#solicitacoes',
    icon: `${IMG}/ICONE -  RELATORIO DE PLACAS.svg`,
    ico: 'trophy',
    setor: 'placas',
    children: [
      { key: 'solicitacoes', label: 'Solicitações', path: '/relatorios/placas', hash: '#solicitacoes', href: '/relatorios/placas#solicitacoes', ico: 'mail' },
      { key: 'agenda-horarios', label: 'Agenda de Horários', path: '/relatorios/placas', hash: '#agenda-horarios', href: '/relatorios/placas#agenda-horarios', ico: 'calendar', adminOnly: true },
    ],
  },
  {
    key: 'depoimentos',
    label: 'Depoimentos',
    path: '/depoimentos',
    defaultHref: '/depoimentos#biblioteca',
    icon: `${IMG}/ICONE - DEPOIMENTOS.svg`,
    ico: 'depoimentos',
    setor: 'depoimentos',
    adminOnly: true,
    children: [
      { key: 'biblioteca', label: 'Biblioteca', path: '/depoimentos', hash: '#biblioteca', href: '/depoimentos#biblioteca', ico: 'biblioteca', adminOnly: true },
      { key: 'para-copy', label: 'Para Copy', path: '/depoimentos/biblioteca', href: '/depoimentos/biblioteca', ico: 'pen', adminOnly: true },
      { key: 'cursos', label: 'Cursos', path: '/depoimentos', hash: '#cursos', href: '/depoimentos#cursos', ico: 'cursos', adminOnly: true },
      { key: 'tags', label: 'Tags', path: '/depoimentos', hash: '#tags', href: '/depoimentos#tags', ico: 'tags', adminOnly: true },
    ],
  },
  // Sem adminOnly: o gate é por setor. Quem vê é dev/admin ou quem tem a área
  // 'financeiro' — ver podeVerFinanceiro(), que espelha gp_pode_ver_financeiro() no banco.
  {
    key: 'financeiro',
    label: 'Financeiro',
    path: '/relatorios/financeiro',
    defaultHref: '/relatorios/financeiro#board',
    ico: 'wallet',
    setor: 'financeiro',
    children: [
      // "Contas a Receber" é o título de seção (secao?), não o rótulo de item. A Visão geral (#visao, F4) é o 1º item da
      // seção; o defaultHref do grupo continua #board (a página inicial só muda depois que o Marcio vir a Visão geral).
      { key: 'visao', label: 'Visão geral', path: '/relatorios/financeiro', hash: '#visao', href: '/relatorios/financeiro#visao', ico: 'eye', secao: 'Contas a Receber' },
      // Mesma seção: o título aparece uma vez só (a sidebar desenha quando a seção MUDA). O hash continua #receber.
      { key: 'receber', label: 'Previsão de caixa', path: '/relatorios/financeiro', hash: '#receber', href: '/relatorios/financeiro#receber', ico: 'receipt', secao: 'Contas a Receber' },
      { key: 'faturamento', label: 'Faturamento', path: '/relatorios/financeiro', hash: '#faturamento', href: '/relatorios/financeiro#faturamento', ico: 'trending-up' },
      { key: 'board', label: 'Board', path: '/relatorios/financeiro', hash: '#board', href: '/relatorios/financeiro#board', ico: 'dashboard' },
      { key: 'funis', label: 'Funis', path: '/relatorios/financeiro', hash: '#funis', href: '/relatorios/financeiro#funis', ico: 'trending-up' },
      { key: 'escritorio', label: 'Escritório', path: '/relatorios/financeiro', hash: '#escritorio', href: '/relatorios/financeiro#escritorio', ico: 'trending-up' },
      { key: 'ofertas', label: 'Ofertas', path: '/relatorios/financeiro', hash: '#ofertas', href: '/relatorios/financeiro#ofertas', ico: 'banknote' },
      { key: 'relatorios', label: 'Relatórios', path: '/relatorios/financeiro', hash: '#relatorios', href: '/relatorios/financeiro#relatorios', ico: 'file' },
    ],
  },
  // Gate por setor, como o financeiro: ver podeVerRemocao(), espelho de ra_pode_ver().
  {
    key: 'remocoes',
    label: 'Remoção de Acessos',
    path: '/relatorios/remocoes',
    defaultHref: '/relatorios/remocoes',
    ico: 'user-x',
    setor: 'remocao_acessos',
    children: [],
  },
  // Gate por setor: ver podePedirAlteracao(), espelho de pa_pode_pedir(). Quem pede não vê a Central.
  {
    key: 'pedidos-alteracao',
    label: 'Pedidos de alteração',
    path: '/sistema/pedidos-alteracao',
    defaultHref: '/sistema/pedidos-alteracao',
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
