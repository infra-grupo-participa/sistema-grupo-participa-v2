import { publicEnv } from '@/shared/infrastructure/config/env';
import type { OpcoesAcessoDepartamento } from '@/shared/domain/departamentos';

/**
 * Opções de acesso aos departamentos vindas de flag (NEXT_PUBLIC_*: embutidas no build, valem no servidor e no
 * browser). Todo `podeVerDepartamento` de tela/layout/sidebar passa isto, para porta e menu concordarem.
 */
export const ACESSO_DEPARTAMENTOS: OpcoesAcessoDepartamento = {
  comercialVendedores: publicEnv.comercialVendedores,
  acessoV2: publicEnv.acessoV2,
};
