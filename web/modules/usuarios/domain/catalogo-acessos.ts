// Catálogo de Acessos (numerado) — camada de apresentação sobre o modelo real
// (cargo + áreas + funções + LGPD). A tela de liberação vira "marque os códigos";
// aqui traduzimos para os campos gravados em `perfis` e de volta.
//
//   1  Técnico          1.1 Dev
//   2  Geral            2.1 Acesso geral (Admin) · 2.2 Visualização geral
//   3  Módulos          3.x módulo · 3.x.1 ver · 3.x.2+ ações
//   4  LGPD             4.1 Ver CPF/documento completo
import { type Cargo, normalizeCargo } from '@/shared/domain/auth';

/** Nível de acesso "base" — determina o cargo. Módulos só valem para `modulos`. */
export type NivelBase = 'dev' | 'geral' | 'visualizador' | 'modulos';

export interface AcaoModulo {
  codigo: string; // ex.: '3.2.2'
  funcao: string; // ex.: 'placas.operar'
  label: string;
}
export interface ModuloAcesso {
  codigo: string; // ex.: '3.2'
  setor: string;
  label: string;
  verCodigo: string; // ex.: '3.2.1'
  verLabel: string;
  acoes: AcaoModulo[];
}
export interface NivelBaseMeta {
  valor: NivelBase;
  codigo: string;
  label: string;
  descricao: string;
  cargo: Cargo;
}

export const NIVEIS_BASE: NivelBaseMeta[] = [
  { valor: 'dev', codigo: '1.1', label: 'Dev', descricao: 'Acesso total, incluindo painel técnico. Só outro dev atribui.', cargo: 'dev' },
  { valor: 'geral', codigo: '2.1', label: 'Acesso geral (Admin)', descricao: 'Vê e edita tudo dos dados operacionais. Gerencia usuários.', cargo: 'admin' },
  { valor: 'visualizador', codigo: '2.2', label: 'Visualização geral', descricao: 'Vê todas as páginas em leitura. CPF mascarado.', cargo: 'visualizador' },
  { valor: 'modulos', codigo: '3', label: 'Acesso por módulo', descricao: 'Libera módulos e ações específicas, um a um.', cargo: 'operador' },
];

// Só entram no catálogo os módulos com tela/uso no v2. Setores/funções fora desta
// lista (ex.: ativacao, social_media) são preservados no perfil, não zerados.
export const MODULOS: ModuloAcesso[] = [
  {
    codigo: '3.1', setor: 'centro_controle', label: 'Centro de Controle',
    verCodigo: '3.1.1', verLabel: 'Visualizar base de alunos',
    acoes: [{ codigo: '3.1.2', funcao: 'centro_controle.operar', label: 'Editar dados de alunos' }],
  },
  {
    codigo: '3.2', setor: 'placas', label: 'Relatório de Placas',
    verCodigo: '3.2.1', verLabel: 'Visualizar dash + tabela',
    acoes: [
      { codigo: '3.2.2', funcao: 'placas.operar', label: 'Operar fluxo de placas' },
      { codigo: '3.2.3', funcao: 'placas.hm_liberar', label: 'Manipular / liberar Acesso HM' },
    ],
  },
  {
    codigo: '3.3', setor: 'depoimentos', label: 'Depoimentos',
    verCodigo: '3.3.1', verLabel: 'Visualizar',
    acoes: [{ codigo: '3.3.2', funcao: 'depoimentos.moderador', label: 'Moderar depoimentos' }],
  },
];

export const LGPD_ACESSO = { codigo: '4.1', label: 'Ver CPF/documento completo (LGPD)' };

const SETORES_GERENCIADOS = MODULOS.map((m) => m.setor);
const FUNCOES_GERENCIADAS = MODULOS.flatMap((m) => m.acoes.map((a) => a.funcao));

/** Estado da tela de acesso. `areas`/`funcoes` guardam só o que o catálogo gerencia. */
export interface EstadoAcesso {
  base: NivelBase;
  areas: string[];
  funcoes: string[];
  lgpd: boolean;
}
export interface CamposPerfil {
  cargo: Cargo;
  areas: string[];
  funcoes: string[];
  pode_ver_cpf_completo: boolean;
}

interface PerfilAcesso {
  cargo?: string | null;
  areas?: string[] | null;
  funcoes?: string[] | null;
  pode_ver_cpf_completo?: boolean | null;
}

/** Deriva o estado inicial da tela a partir do perfil salvo. */
export function estadoDoPerfil(p: PerfilAcesso): EstadoAcesso {
  const cargo = normalizeCargo({ cargo: p.cargo ?? null });
  const areas = (p.areas ?? []).filter((a) => SETORES_GERENCIADOS.includes(a));
  let funcoes = (p.funcoes ?? []).filter((f) => FUNCOES_GERENCIADAS.includes(f));

  let base: NivelBase;
  if (cargo === 'dev') base = 'dev';
  else if (cargo === 'admin') base = 'geral';
  else if (cargo === 'visualizador') base = 'visualizador';
  else base = 'modulos'; // operador e gestor

  // Gestor = módulo completo: marca todas as ações dos setores que ele tem.
  if (cargo === 'gestor') {
    funcoes = MODULOS.filter((m) => areas.includes(m.setor)).flatMap((m) => m.acoes.map((a) => a.funcao));
  }
  return { base, areas, funcoes, lgpd: p.pode_ver_cpf_completo === true };
}

/** Traduz o estado da tela nos campos de `perfis`, preservando setores/funções não gerenciados. */
export function perfilDoEstado(e: EstadoAcesso, origem: PerfilAcesso): CamposPerfil {
  const cargo = (NIVEIS_BASE.find((n) => n.valor === e.base) ?? NIVEIS_BASE[3]).cargo;
  const preservAreas = (origem.areas ?? []).filter((a) => !SETORES_GERENCIADOS.includes(a));
  const preservFuncoes = (origem.funcoes ?? []).filter((f) => !FUNCOES_GERENCIADAS.includes(f));

  if (e.base !== 'modulos') {
    return { cargo, areas: preservAreas, funcoes: preservFuncoes, pode_ver_cpf_completo: e.lgpd };
  }
  // Área presente se "ver" marcado OU alguma ação do setor marcada (operar implica ver).
  const funcoesSel = e.funcoes.filter((f) => FUNCOES_GERENCIADAS.includes(f));
  const setoresComAcao = MODULOS.filter((m) => m.acoes.some((a) => funcoesSel.includes(a.funcao))).map((m) => m.setor);
  const areasSel = e.areas.filter((a) => SETORES_GERENCIADOS.includes(a));
  return {
    cargo,
    areas: Array.from(new Set([...preservAreas, ...areasSel, ...setoresComAcao])),
    funcoes: Array.from(new Set([...preservFuncoes, ...funcoesSel])),
    pode_ver_cpf_completo: e.lgpd,
  };
}

/** Níveis-base que um usuário com estes cargos concedíveis pode atribuir. */
export function niveisBaseGrantaveis(grantaveis: Cargo[]): NivelBaseMeta[] {
  return NIVEIS_BASE.filter((n) => grantaveis.includes(n.cargo));
}
