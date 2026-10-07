export type RegistroDashboard = { chave: string; titulo: string; modelo: 'presencial-base'; descricao: string };
export const registroDashboards: RegistroDashboard[] = [
  { chave: 'clinica-miami-2026-12', titulo: 'Clínica de Miami', modelo: 'presencial-base', descricao: 'Evento presencial para a base' },
];
export const buscarDashboard = (chave: string) => registroDashboards.find((item) => item.chave === chave);
