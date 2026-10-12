export type ModeloDashboard = 'presencial-base' | 'jornada-captacao';
export type RegistroDashboard = { chave: string; titulo: string; modelo: ModeloDashboard; descricao: string };
export const registroDashboards: RegistroDashboard[] = [
  { chave: 'clinica-miami-2026-12', titulo: 'Clínica de Miami', modelo: 'presencial-base', descricao: 'Evento presencial para a base' },
  // Black Friday 2026: módulo web/modules/infra/black (docs/dashboard-black/README.md). Reversão = tirar esta linha.
  { chave: 'black-friday-2026-10', titulo: 'Black Friday 2026', modelo: 'jornada-captacao', descricao: 'Captação da live de 03/11: jornada, tráfego, criativos e mensageria' },
];
export const buscarDashboard = (chave: string) => registroDashboards.find((item) => item.chave === chave);
