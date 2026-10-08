export type RegistroAtm = {
  chave: string;
  rotulo: string;
  dataLive: string;
  notaSerie?: { dia: string; texto: string };
};

/** Registros dos ATMs; as leituras de dados usam sempre `chave`, nunca nome de planilha. */
export const registroAtm: RegistroAtm[] = [
  {
    chave: 'atm-elaine-1-2026-10',
    rotulo: 'ATM 1 · Dra. Elaine · 13/10 às 19h30',
    dataLive: '2026-10-13T19:30:00-03:00',
    notaSerie: { dia: '2026-10-08', texto: 'O pico de 41 entradas em 08/10 corresponde à primeira foto do SendFlow; a data é aproximada.' },
  },
];

export const buscarAtm = (chave: string) => registroAtm.find((item) => item.chave === chave);
