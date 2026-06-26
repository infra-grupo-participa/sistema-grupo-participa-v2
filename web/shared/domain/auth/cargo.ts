// Domínio puro — modelo canônico de cargos LGPD v2 (espelha auth.js). Sem deps externas.

export type Cargo = 'dev' | 'admin' | 'gestor' | 'operador' | 'visualizador';

// Setores canônicos. 'ativacao'/'social_media' permanecem por fidelidade ao modelo,
// embora não tenham telas no sistema refatorado.
export type Setor =
  | 'ativacao'
  | 'social_media'
  | 'placas'
  | 'depoimentos'
  | 'centro_controle';

/** Dados brutos de cargo vindos da tabela `perfis`. */
export interface CargoSource {
  cargo?: string | null;
  nivel_hierarquia?: string | null;
  eh_dev?: boolean | null;
}

/**
 * Normaliza um perfil bruto (com possíveis cargos legados) para o cargo canônico v2.
 * Porta fiel de _gpNormalizeCargo() em auth.js.
 */
export function normalizeCargo(data: CargoSource): Cargo {
  const raw = String(data.cargo || '').toLowerCase().trim();
  const nivel = String(data.nivel_hierarquia || '').toLowerCase().trim();
  const ehDevFlag = data.eh_dev === true;

  if (raw === 'dev' || nivel === 'dev' || ehDevFlag) return 'dev';
  if (raw === 'admin' || nivel === 'admin_principal') return 'admin';
  if (raw === 'gestor') return 'gestor';
  if (raw === 'operador') return 'operador';
  if (raw === 'visualizador' || raw === 'leitura' || nivel === 'visualizador') return 'visualizador';
  if (raw === 'ativacao' || raw === 'ativador') return 'operador';
  return 'visualizador'; // fallback conservador
}
