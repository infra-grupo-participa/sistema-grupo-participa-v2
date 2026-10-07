import type { LeadPresencial } from '../domain/presencial';
import { ModalPessoas } from './ModalPessoas';
export function ModalPreCheckout(props: { linhas: LeadPresencial[] | null; erro: string | null; carregando: boolean; onClose: () => void; isMaster: boolean; onToggleTeste: (pessoaId: string, teste: boolean) => Promise<string | null> }) {
  return <ModalPessoas {...props} tipo="leads" />;
}
