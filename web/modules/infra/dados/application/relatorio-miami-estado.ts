import type { ConteudoRelatorioMiami } from '../domain/relatorio-miami';
import type { ResultadoRelatorio } from '../infrastructure/relatorio-miami-data';

export type EstadoRelatorioMiami = {
  chave: string;
  /** Última cópia boa. Nunca é apagada por falha: a tela segura o último valor. */
  conteudo: ConteudoRelatorioMiami | null;
  md5: string | null;
  lidoEm: string | null;
  tentadoEm: string | null;
  /** Código do erro da última leitura da planilha pelo banco (a cópia anterior continua valendo). */
  erroLeitor: string | null;
  /** O banco respondeu, mas ainda não há cópia (antes da 1ª leitura boa). */
  semCopia: boolean;
  contatoVisivel: boolean;
  /** Falha desta chamada (rede, permissão, função fora do banco). */
  erroTela: string | null;
  /** Repetir não adianta: o polling para. */
  permanente: boolean;
  carregando: boolean;
  /** Quando a tela confirmou com o banco, em ms. */
  verificadoEm: number | null;
};

export const estadoInicialRelatorio = (chave: string): EstadoRelatorioMiami => ({
  chave, conteudo: null, md5: null, lidoEm: null, tentadoEm: null, erroLeitor: null, semCopia: false, contatoVisivel: true,
  erroTela: null, permanente: false, carregando: true, verificadoEm: null,
});

/** Junta uma leitura ao estado. Conteúdo igual não é rebaixado; falha mantém o conteúdo e só marca o erro. */
export function aplicarLeitura(anterior: EstadoRelatorioMiami, lida: ResultadoRelatorio, agora: number): EstadoRelatorioMiami {
  const base = { ...anterior, carregando: false };
  const r = lida.data;
  if (lida.erro || !r) return { ...base, erroTela: lida.erro ?? 'Não foi possível carregar agora.', permanente: lida.permanente };

  const meta = { lidoEm: r.lido_em ?? anterior.lidoEm, tentadoEm: r.tentado_em, erroLeitor: r.erro, contatoVisivel: r.contato_visivel, erroTela: null, permanente: false, verificadoEm: agora };

  if (!r.disponivel) {
    if (anterior.conteudo) return { ...base, ...meta, erroTela: 'A cópia deixou de estar disponível no banco. Exibindo a última cópia carregada.' };
    return { ...base, ...meta, lidoEm: null, semCopia: true };
  }
  if (r.igual) {
    if (anterior.conteudo && anterior.md5 !== null && anterior.md5 === r.md5) return { ...base, ...meta, semCopia: false };
    // O banco diz "igual" a uma cópia que a tela não tem: esquece o md5 para a próxima leitura trazer o conteúdo inteiro.
    return { ...base, ...meta, md5: null, erroTela: 'A cópia não foi reconhecida. Recarregando na próxima atualização.' };
  }
  if (!r.conteudo) return { ...base, ...meta, erroTela: 'A resposta do banco veio sem conteúdo.' };
  return { ...base, ...meta, conteudo: r.conteudo, md5: r.md5, semCopia: false };
}
