// Domínio puro. Espelha gp_pode_ver_financeiro() / gp_pode_operar_financeiro() no banco.
//
// A regra mora em `shared/domain/acesso-financeiro.ts` desde 15/10/2026 (o módulo virou o departamento Financeiro e
// o gate do departamento, em shared/domain, precisa da mesma regra). Este arquivo só reexporta, para os consumidores
// do módulo não mudarem de import. Visualizador NÃO vê dinheiro (ver o arquivo de origem).
export { podeOperarFinanceiro, podeVerFinanceiro } from '@/shared/domain/acesso-financeiro';
