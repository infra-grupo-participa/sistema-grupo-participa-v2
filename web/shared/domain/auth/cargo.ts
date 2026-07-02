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
}

/**
 * Normaliza o cargo bruto para o canônico v2.
 * Desde a migration `unifica_modelo_cargos_fase_a`, `perfis.cargo` é a ÚNICA fonte de verdade
 * (nivel_hierarquia/eh_dev foram absorvidos e estão deprecated). Os aliases legados ficam
 * mapeados por defesa — o CHECK do banco já não os permite em linhas novas.
 */
export function normalizeCargo(data: CargoSource): Cargo {
  const raw = String(data.cargo || '').toLowerCase().trim();
  if (raw === 'dev') return 'dev';
  if (raw === 'admin') return 'admin';
  if (raw === 'gestor') return 'gestor';
  if (raw === 'operador' || raw === 'ativacao' || raw === 'ativador') return 'operador';
  return 'visualizador'; // inclui 'visualizador', 'leitura' e qualquer valor desconhecido
}
