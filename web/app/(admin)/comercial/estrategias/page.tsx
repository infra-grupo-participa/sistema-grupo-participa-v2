import { redirect } from 'next/navigation';
import { getCurrentUser } from '@/shared/composition/server-container';
import { acessoComercial, podeSolicitarEstrategia } from '@/shared/domain/departamentos';
import { ACESSO_DEPARTAMENTOS } from '@/shared/composition/acesso-departamentos';
import { EstrategiasClient } from '@/modules/comercial/ui/estrategias/EstrategiasClient';

export const dynamic = 'force-dynamic';

/**
 * Estratégias (ex-Recuperação). Abre para quem vê o CRM e para quem só pede estratégia (função
 * `comercial.solicitar_estrategia`): este vê os próprios pedidos e o placar, sem as filas e sem o resto do CRM.
 * Quem executa (gestor comercial) e o que cada um vê vêm do banco (`crm_estrategia_acesso` + guarda das RPCs).
 */
export default async function Page() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');
  const acesso = acessoComercial(user, ACESSO_DEPARTAMENTOS);
  if (!acesso) redirect('/');
  return <EstrategiasClient doComercial={acesso === 'completo'} podeSolicitar={podeSolicitarEstrategia(user)} />;
}
