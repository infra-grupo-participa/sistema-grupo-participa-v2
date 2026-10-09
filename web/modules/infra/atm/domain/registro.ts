export type RegistroAtm = {
  chave: string;
  rotulo: string;
  dataLive: string;
  /** Família no histórico de edições (`dados_historico_edicoes(p_familia)`), aba Histórico. */
  familia: string;
};

/** Registros dos ATMs; as leituras de dados usam sempre `chave`, nunca nome de planilha. */
export const registroAtm: RegistroAtm[] = [
  { chave: 'atm-elaine-1-2026-10', rotulo: 'ATM 1 · Dra. Elaine · 13/10 às 19h30', dataLive: '2026-10-13T19:30:00-03:00', familia: 'seminario-atm' },
];

export const buscarAtm = (chave: string) => registroAtm.find((item) => item.chave === chave);
