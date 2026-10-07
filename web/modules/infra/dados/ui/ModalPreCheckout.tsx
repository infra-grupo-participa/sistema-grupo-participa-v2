import type { LeadPresencial } from '../domain/presencial';
import { ModalPessoas } from './ModalPessoas';
export function ModalPreCheckout(props: { linhas: LeadPresencial[] | null; erro: string | null; carregando: boolean; onClose: () => void }) { return <ModalPessoas {...props} tipo="leads" />; }
