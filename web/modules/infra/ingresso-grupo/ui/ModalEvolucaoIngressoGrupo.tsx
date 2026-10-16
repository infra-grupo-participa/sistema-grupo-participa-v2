'use client';

import { Modal } from '@/shared/ui/components';
import { EvolucaoIngressoGrupo, type EstadoSerieIngresso } from './EvolucaoIngressoGrupo';

/**
 * Modal padrão do card "% ingresso no grupo": evolução diária (gráfico + tabela).
 * Qualquer dashboard com card de ingresso no grupo abre este modal (ou a aba equivalente, `EvolucaoIngressoGrupo`).
 */
export function ModalEvolucaoIngressoGrupo({ open, onClose, titulo, serie }: {
  open: boolean;
  onClose: () => void;
  titulo: string;
  serie: EstadoSerieIngresso;
}) {
  return <Modal open={open} onClose={onClose} title={titulo} width="max-w-6xl">
    <EvolucaoIngressoGrupo serie={serie} />
  </Modal>;
}
