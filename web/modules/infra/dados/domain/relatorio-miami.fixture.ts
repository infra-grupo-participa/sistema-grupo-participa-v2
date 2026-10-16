// Resposta de exemplo de public.dados_miami_relatorio, com cabeçalhos e rótulos EXATOS do contrato (importados do leitor)
// e pessoas INVENTADAS. Só os testes usam. Nenhum dado pessoal real.
import { BLOCOS } from '../../../../../infra/supabase/functions/dados-planilha-relatorio/relatorio-miami';
import type { BlocoKpi, BlocoTabela, ConteudoRelatorioMiami, RespostaRelatorioMiami } from './relatorio-miami';

const colunas = (chave: string) => (BLOCOS.find((b) => b.chave === chave) as { colunas: string[] }).colunas;
const titulo = (chave: string) => BLOCOS.find((b) => b.chave === chave)!.titulo;

export const kpiDadosIniciais: BlocoKpi = { titulo: titulo('dados_iniciais'), itens: [
  { rotulo: 'Pessoas na Lista Diamantes', valor: '76' }, { rotulo: 'Respostas recebidas no formulário', valor: '70' },
  { rotulo: 'Da lista, já preencheram', valor: '67' }, { rotulo: 'Da lista, faltam preencher', valor: '9' },
  { rotulo: '% de preenchimento', valor: '88,2%' }, { rotulo: 'Respostas sem correspondência na lista', valor: '3' },
  { rotulo: 'Situação de quem respondeu', valor: null },
  { rotulo: 'Confirmados, com viagem organizada', valor: '31' }, { rotulo: 'Se organizando, ainda não confirmados', valor: '17' }, { rotulo: 'Não irão participar', valor: '19' },
] };
export const kpiTime: BlocoKpi = { titulo: titulo('time_formulario'), itens: [
  { rotulo: 'Compradores da Clínica', valor: '13' }, { rotulo: 'Já responderam', valor: '8' }, { rotulo: 'Faltam responder', valor: '5' },
  { rotulo: '% de preenchimento', valor: '61,5%' }, { rotulo: 'Respostas recebidas (pessoas únicas)', valor: '8' },
  { rotulo: 'Respostas sem correspondência na lista de compradores', valor: '0' },
] };
export const kpiParticipacao: BlocoKpi = { titulo: titulo('participacao'), itens: [
  { rotulo: 'Respostas recebidas (pessoas únicas)', valor: '27' }, { rotulo: 'Confirmados que já preencheram', valor: '26' },
  { rotulo: 'Confirmados que ainda não preencheram (clique no número para ver quem)', valor: '5' },
] };
export const camisas: BlocoTabela = { titulo: titulo('camisas'), colunas: colunas('camisas'), linhas: [['P', '6', '0', '6'], ['M', '9', '4', '13'], ['G', '10', '3', '13'], ['Total', '25', '7', '32']] };
export const presenca: BlocoTabela = { titulo: titulo('presenca'), colunas: colunas('presenca'), linhas: [
  ['Reunião do Diamante Vermelho', '30/11', '9', '0', '—', '9', '—', '—', '—', '—', '9'],
  ['Happy Hour de boas-vindas', '30/11, 7pm', '25', '2', '9', '34', '7', '1', '0', '7', '41'],
  ['Festa dos Iates', '5/12', '23', '4', '13', '36', '6', '2', '1', '7', '43'],
] };

const linhaDiamante = (n: number, status: string, grupo: string, situacao: string, enviado: string): string[] => {
  const l = colunas('diamantes').map(() => '');
  l[0] = `Pessoa Teste ${n}`; l[1] = `Pessoa Teste ${n}`; l[2] = status; l[3] = `pessoa${n}@exemplo.invalido`; l[4] = `+55 00 00000-000${n}`;
  l[5] = grupo; l[6] = situacao; l[7] = '27/11/2026'; l[8] = '08/12/2026'; l[9] = 'MIA'; l[10] = 'Hotel Teste'; l[11] = 'Não, irei sozinho(a)'; l[13] = enviado;
  return l;
};
export const diamantes: BlocoTabela = { titulo: titulo('diamantes'), colunas: colunas('diamantes'), linhas: [
  linhaDiamante(1, 'Respondeu', 'Diamante Titular', 'Já estou confirmado(a) e com a viagem organizada.', '13/10/2026 15:00'),
  linhaDiamante(2, 'Respondeu', 'Diamante Titular', 'Estou me organizando para participar, mas ainda não confirmado(a).', '02/10/2026 09:30'),
  linhaDiamante(3, 'Pendente', 'Diamante Convidado', '', ''),
  linhaDiamante(10, 'Respondeu', 'Diamante Titular', 'Já estou confirmado(a) e com a viagem organizada.', '09/10/2026 18:00'),
] };
const linhaComprador = (n: number, instrucao: string): string[] => {
  const l = colunas('compradores').map(() => '');
  l[0] = `Comprador Teste ${n}`; l[1] = `comprador${n}@exemplo.invalido`; l[2] = `1100000000${n}`; l[3] = instrucao; l[4] = 'T14'; l[5] = 'Respondeu'; l[7] = '30/11/2026'; l[15] = 'Hotel Teste';
  return l;
};
export const compradores: BlocoTabela = { titulo: titulo('compradores'), colunas: colunas('compradores'), linhas: [linhaComprador(1, 'PLATINA'), linhaComprador(2, 'PLATINA'), linhaComprador(3, 'THB')] };

export const conteudoExemplo: ConteudoRelatorioMiami = {
  versao: 1, aba: 'Relatório', avisos: [],
  blocos: { dados_iniciais: kpiDadosIniciais, time_formulario: kpiTime, participacao: kpiParticipacao, camisas, presenca, diamantes, compradores },
};
export const respostaExemplo = (extra: Partial<RespostaRelatorioMiami> = {}): RespostaRelatorioMiami => ({
  disponivel: true, md5: 'md5-a', igual: false, lido_em: '2026-10-16T17:00:00Z', tentado_em: '2026-10-16T17:00:00Z', erro: null, contato_visivel: true, conteudo: conteudoExemplo, ...extra,
});
