import type { VendaPresencial } from '../domain/presencial';
import { ModalPessoas } from './ModalPessoas';
export function ModalVendas(props: { linhas: VendaPresencial[] | null; erro: string | null; carregando: boolean; onClose: () => void }) { return <ModalPessoas {...props} tipo="vendas" />; }
