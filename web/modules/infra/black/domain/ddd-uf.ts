// DDD → UF. ESPELHO da tabela dados.ddd_uf (infra/supabase/migrations/20261008161000_dados_criar_modelo_seminario_atm.sql,
// seção 3.1, que copiou sal_uf do dashboard-ht). O teste ddd-uf.test.ts lê a migration e confere linha a linha:
// se a tabela mudar lá, muda aqui. DDD fora da tabela = 'Outros', igual à leitura de dados.atm_leads.
export const DDD_UF: Readonly<Record<string, string>> = {
  '11': 'SP', '12': 'SP', '13': 'SP', '14': 'SP', '15': 'SP', '16': 'SP', '17': 'SP', '18': 'SP', '19': 'SP',
  '21': 'RJ', '22': 'RJ', '24': 'RJ', '27': 'ES', '28': 'ES',
  '31': 'MG', '32': 'MG', '33': 'MG', '34': 'MG', '35': 'MG', '37': 'MG', '38': 'MG',
  '41': 'PR', '42': 'PR', '43': 'PR', '44': 'PR', '45': 'PR', '46': 'PR',
  '47': 'SC', '48': 'SC', '49': 'SC', '51': 'RS', '53': 'RS', '54': 'RS', '55': 'RS',
  '61': 'DF', '62': 'GO', '64': 'GO', '63': 'TO', '65': 'MT', '66': 'MT', '67': 'MS',
  '68': 'AC', '69': 'RO', '71': 'BA', '73': 'BA', '74': 'BA', '75': 'BA', '77': 'BA', '79': 'SE',
  '81': 'PE', '87': 'PE', '82': 'AL', '83': 'PB', '84': 'RN', '85': 'CE', '88': 'CE', '86': 'PI', '89': 'PI',
  '91': 'PA', '93': 'PA', '94': 'PA', '92': 'AM', '97': 'AM', '95': 'RR', '96': 'AP', '98': 'MA', '99': 'MA',
};

export const UF_FORA_DA_TABELA = 'Outros';

/**
 * DDD do telefone. O país sai do COMPRIMENTO, nunca de "começa com 55" (o DDD 55 do RS existe):
 * 12 ou 13 dígitos começando com 55 = com código do país; 10 ou 11 dígitos = sem código do país.
 * Qualquer outra coisa (vazio, lixo, curto, longo) = null.
 */
export function dddDoTelefone(telefone: string | null | undefined): string | null {
  const d = (telefone ?? '').replace(/\D/g, '');
  let nacional: string;
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) nacional = d.slice(2);
  else if (d.length === 10 || d.length === 11) nacional = d;
  else return null;
  const ddd = nacional.slice(0, 2);
  return /^[1-9][0-9]$/.test(ddd) ? ddd : null;
}

/** UF pelo DDD. null = telefone sem DDD legível (a tela mostra "Não informado"); 'Outros' = DDD fora da tabela. */
export function ufDoTelefone(telefone: string | null | undefined): string | null {
  const ddd = dddDoTelefone(telefone);
  if (ddd === null) return null;
  return DDD_UF[ddd] ?? UF_FORA_DA_TABELA;
}
