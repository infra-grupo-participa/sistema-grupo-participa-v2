// Cards da seção "Comparecimento" do dashboard do ATM (uma sessão por vez, lida de dados_atm_comparecimento).
// Comparecimento = pico de audiência ÷ leads e pico ÷ grupo, a mesma conta da planilha do ATM (comparecimento = pico ÷ leads;
// comparecimento do grupo = pico ÷ grupo). O pico lançado já vem SEM as pessoas da equipe (pico = máximo da série do Zoom
// menos equipe na sala), então o percentual não inclui a equipe. Presença por pessoa (relatório do Zoom) entra quando
// dados.sessao_presencas for carregada; por isso presentes_* não aparecem aqui.

export type TipoCardComparecimento = 'inteiro' | 'percentual';
export interface CardComparecimento { rotulo: string; chave: string; tipo: TipoCardComparecimento; ajuda?: string }

export const AJUDA_EQUIPE =
  'O pico de audiência já está sem as pessoas da equipe na sala: é o máximo de pessoas na live (Zoom) menos a equipe, ' +
  'que não conta como comparecimento nem como pessoa única. As pessoas da equipe aparecem no card "Pessoas da equipe na sala".';

export const CARDS_COMPARECIMENTO: readonly CardComparecimento[] = [
  { rotulo: 'Pico de audiência', chave: 'pico_audiencia', tipo: 'inteiro', ajuda: 'Sem a equipe. Máximo de pessoas na live menos as pessoas da equipe.' },
  { rotulo: 'Comparecimento dos leads', chave: 'pico_sobre_leads_pct', tipo: 'percentual', ajuda: 'Pico de audiência ÷ total de leads.' },
  { rotulo: 'Comparecimento do grupo', chave: 'pico_sobre_grupo_pct', tipo: 'percentual', ajuda: 'Pico de audiência ÷ total no grupo.' },
  { rotulo: 'Total de leads', chave: 'total_leads', tipo: 'inteiro' },
  { rotulo: 'Total no grupo', chave: 'total_grupo', tipo: 'inteiro' },
  { rotulo: 'Pessoas da equipe na sala', chave: 'equipe_na_sala', tipo: 'inteiro', ajuda: 'Fora do pico e do comparecimento.' },
  { rotulo: 'Vendas', chave: 'vendas', tipo: 'inteiro' },
  { rotulo: 'Conversão', chave: 'conversao_pct', tipo: 'percentual' },
  { rotulo: 'Conversão no grupo', chave: 'conversao_grupo_pct', tipo: 'percentual' },
  { rotulo: 'Conversão sobre o pico', chave: 'conversao_pico_pct', tipo: 'percentual' },
];
