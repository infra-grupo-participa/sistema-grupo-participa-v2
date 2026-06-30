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
];

export const SYSTEM_NAV: SystemNavItem[] = [
  { key: 'admin-dev', label: 'Admin Dev', path: '/sistema/admin-dev', activePrefixes: ['/sistema/admin-dev'], ico: 'wrench', devOnly: true },
  { key: 'usuarios', label: 'Usuários', path: '/usuarios', ico: 'user', adminOnly: true },
  { key: 'configuracoes', label: 'Configurações', path: '/sistema/configuracoes', activePrefixes: ['/sistema/configuracoes'], ico: 'settings' },
];

export const SIDEBAR_GROUPS = ['home', 'reports', 'system'] as const;
