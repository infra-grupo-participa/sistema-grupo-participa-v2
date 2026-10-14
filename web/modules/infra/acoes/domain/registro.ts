export type EstadoAcaoBlack = 'ativa' | 'em breve';

export type RegistroAcaoBlack = {
  id: string;
  nome: string;
  estado: EstadoAcaoBlack;
  /** Identificador do evento no banco. Mantido nulo enquanto o Victor não fornecer a etiqueta. */
  etiqueta: string | null;
  origem: string | null;
  ofertaHotmart: string | null;
};

/** Uma linha por ação. A tela e a etiqueta de leitura são dirigidas por este registro. */
export const registroAcoesBlack: RegistroAcaoBlack[] = [
  {
    id: 'thb-vencidos',
    nome: 'THB vencidos',
    estado: 'ativa',
    etiqueta: 'black-thb-2026-10',
    origem: 'renovacao-thb-vencidos',
    ofertaHotmart: null,
  },
  { id: 'thb-a-vencer', nome: 'THB a vencer', estado: 'em breve', etiqueta: null, origem: null, ofertaHotmart: null },
  { id: 'aurum', nome: 'Aurum', estado: 'em breve', etiqueta: null, origem: null, ofertaHotmart: null },
];

export const buscarAcaoBlack = (id: string) => registroAcoesBlack.find((acao) => acao.id === id);
