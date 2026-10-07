// Ativação na DEMONSTRAÇÃO: o mesmo painel que `crm_ativacao_painel` devolve, montado em memória a partir dos funis,
// negócios e atividades da base demo. Regras do banco repetidas: vendedor conta só os dele (D6); conversa nova =
// toque 1 que vence hoje; o teto é por número (total do dia vai para todos).
import { agendaAtivacao, type EdicaoAtivacao, type PainelAtivacao, type ProjetoAtivacao } from '../domain/ativacao';
import type { Atividade, Funil, Negocio, SessaoComercial } from '../domain/types';

export const SUFIXO_ATIVACAO = ' · Ativação';

export function ehFunilAtivacao(f: Pick<Funil, 'nome' | 'projeto'>): boolean {
  return !!f.projeto && f.nome.endsWith(SUFIXO_ATIVACAO);
}

export type CadastroAtivacao = Omit<EdicaoAtivacao, 'projeto'> & { encerradoEm: string | null; filaId: string | null };

export const cadastroVazio = (): CadastroAtivacao =>
  ({ eventoInicio: null, eventoFim: null, eventoHora: null, carrinhoFim: null, hotmartOferta: [], ligado: true, encerradoEm: null, filaId: null });

const diaLocal = (d: Date) => new Date(d.getTime() - 3 * 3600000).toISOString().slice(0, 10);

export function painelAtivacaoDemo(p: {
  funis: Funil[]; negocios: Negocio[]; atividades: Atividade[]; cadastros: Map<string, CadastroAtivacao>;
  eu: SessaoComercial; agora: Date;
}): PainelAtivacao {
  const gestor = p.eu.papel === 'gestor';
  const meu = (dono: string | null) => gestor || dono === p.eu.vendedorId;
  const hoje = diaLocal(p.agora);
  const ativos = p.funis.filter((f) => f.ativo && ehFunilAtivacao(f));
  const idsAtiv = new Set(ativos.map((f) => f.id));
  const projetos: ProjetoAtivacao[] = ativos.map((f) => {
    const c = p.cadastros.get(f.projeto!) ?? cadastroVazio();
    const doFunil = p.negocios.filter((n) => n.funilId === f.id);
    const porEtapa: Record<string, number> = {};
    for (const n of doFunil) if (n.status === 'aberto' && meu(n.donoId)) porEtapa[n.etapaId] = (porEtapa[n.etapaId] ?? 0) + 1;
    return {
      projeto: f.projeto!, nome: f.nome.slice(0, -SUFIXO_ATIVACAO.length), funilId: f.id, produto: f.produto,
      eventoInicio: c.eventoInicio, eventoFim: c.eventoFim, eventoHora: c.eventoHora, hotmartOferta: [...c.hotmartOferta],
      carrinhoFim: c.carrinhoFim, fimAtivacao: c.carrinhoFim ?? c.eventoFim, datasDoMarketing: false,
      ligado: c.ligado, encerradoEm: c.encerradoEm, filaId: c.filaId, porEtapa,
      entradasHoje: doFunil.filter((n) => meu(n.donoId) && diaLocal(new Date(n.criadoEm)) === hoje).length,
      mqls: 0, mensageriaHoje: 0,
    };
  });
  const negAtiv = new Map(p.negocios.filter((n) => idsAtiv.has(n.funilId)).map((n) => [n.id, n]));
  const deHoje = p.atividades.filter((a) => a.negocioId && negAtiv.has(a.negocioId) && diaLocal(new Date(a.venceEm)) === hoje
    && !(a.resultado ?? '').startsWith('Encerrada:'));
  const porDono = new Map<string, { novas: number; toques: number }>();
  for (const a of deHoje) {
    if (!meu(a.donoId)) continue;
    const x = porDono.get(a.donoId) ?? { novas: 0, toques: 0 };
    x.toques += 1;
    if (a.titulo.startsWith('Toque 1:')) x.novas += 1;
    porDono.set(a.donoId, x);
  }
  const projetosComFunil = new Set(p.funis.filter((f) => f.ativo && f.projeto).map((f) => f.projeto!));
  return {
    projetos,
    carga: [...porDono].map(([vendedorId, x]) => ({ vendedorId, novasHoje: x.novas, toquesHoje: x.toques })),
    totalNovasHoje: deHoje.filter((a) => a.titulo.startsWith('Toque 1:')).length,
    ligada: true,
    semAtivacao: gestor ? [...projetosComFunil].filter((k) => !projetos.some((x) => x.projeto === k)) : [],
  };
}

/** Atividades dos três toques de um negócio novo de ativação (o banco cria por trigger). */
export function toquesDoNegocio(n: Pick<Negocio, 'id' | 'contatoId' | 'donoId'>, c: CadastroAtivacao, agora: Date, novoId: () => string): Atividade[] {
  if (!n.donoId) return [];
  return agendaAtivacao(agora, c).map((t) => ({
    id: novoId(), negocioId: n.id, contatoId: n.contatoId, donoId: n.donoId!, tipo: t.tipo, titulo: t.titulo,
    venceEm: t.venceEm.toISOString(), concluidaEm: null, resultado: null, cadenciaDia: null,
  }));
}
