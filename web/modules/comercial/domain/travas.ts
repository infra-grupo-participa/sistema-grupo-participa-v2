// Travas de escrita no negócio, puras e testáveis. ESPELHO das guardas da F2 (migration 20261005t):
// `crm_mover_etapa`, `crm_salvar_campos`, `crm_marcar_perdido`, `crm_criar_atividade` e `crm_adicionar_nota` (com
// negócio) recusam com "Este negócio não é seu." quando quem chama não é gestor e não é o dono — inclusive negócio
// SEM dono (dono null ≠ eu); `crm_transferir_dono` só aceita gestor; `crm_mover_etapa` recusa a etapa de ganho e
// pede os campos obrigatórios do funil. A tela usa estas funções para nem oferecer a ação; o banco continua mandando.
import { ROTULO_CAMPO } from './catalogo';
import { bloqueioMoverNoFunil, camposFaltandoNoFunil } from './funis';
import type { Atividade, CampoKey, Contato, Funil, Negocio, SessaoComercial } from './types';

type Quem = Pick<SessaoComercial, 'vendedorId' | 'papel'> | null | undefined;

/** Texto padrão da recusa do leitor — o mesmo que o banco devolve (`crm.guarda_escrita` / `crm.pode_escrever`). */
export const MSG_SOMENTE_LEITURA = 'Acesso só de leitura.';

/**
 * Leitor (20261008151801): admin/dev do sistema fora do Comercial. Vê tudo o que o gestor vê e não escreve nada.
 * Todas as funções `pode*` abaixo já devolvem false para ele (não é gestor nem dono de nada); esta serve para
 * esconder as ações que não passam por elas (novo negócio, novo contato, nova ficha, links, painel, tokens…).
 */
export function somenteLeitura(quem: Quem): boolean {
  return quem?.papel === 'leitor';
}

/** Pode escrever alguma coisa no CRM (gestor ou vendedor). Sem sessão: não. */
export function podeEscrever(quem: Quem): boolean {
  return !!quem && quem.papel !== 'leitor';
}

/** Vê a operação inteira (time, todos os funis, todas as conversas): gestor e leitor. */
export function veComoGestor(quem: Quem): boolean {
  return quem?.papel === 'gestor' || quem?.papel === 'leitor';
}

/** Gestor mexe em qualquer negócio; vendedor só no que é dele. Sem sessão: não mexe. */
export function podeMexerNoNegocio(n: Pick<Negocio, 'donoId'>, quem: Quem): boolean {
  if (!quem || somenteLeitura(quem)) return false;
  if (quem.papel === 'gestor') return true;
  return !!n.donoId && n.donoId === quem.vendedorId;
}

/** Trocar o dono do negócio (ou definir o dono do contato) é só do gestor. */
export function podeTrocarDono(quem: Quem): boolean {
  return quem?.papel === 'gestor';
}

/** Frase para a tela explicar por que o negócio está só para leitura. null = pode mexer. */
export function motivoSomenteLeitura(n: Pick<Negocio, 'donoId'>, quem: Quem, nomeDe: (id: string | null) => string): string | null {
  if (podeMexerNoNegocio(n, quem)) return null;
  if (!quem) return 'Carregando quem você é.';
  if (somenteLeitura(quem)) return MSG_SOMENTE_LEITURA;
  if (!n.donoId) return 'Negócio sem dono: o gestor define quem atende antes.';
  return `Negócio de ${nomeDe(n.donoId)}: só o dono ou o gestor altera.`;
}

/** Concluir atividade (espelho de `crm_concluir_atividade`): só o dono DA ATIVIDADE ou o gestor; já concluída, ninguém. */
export function podeConcluirAtividade(a: Pick<Atividade, 'donoId' | 'concluidaEm'>, quem: Quem): boolean {
  if (!quem || a.concluidaEm || somenteLeitura(quem)) return false;
  return quem.papel === 'gestor' || (!!a.donoId && a.donoId === quem.vendedorId);
}

/**
 * Abrir negócio novo para o contato (espelho de `crm_criar_negocio` → `crm.pode_ver_pessoa`): gestor sempre;
 * vendedor se o contato é dele, está sem dono, ou se ele já é dono de algum negócio da pessoa.
 */
export function podeAbrirNegocioPara(c: Pick<Contato, 'donoId'>, negociosDaPessoa: Pick<Negocio, 'donoId'>[], quem: Quem): boolean {
  if (!quem || somenteLeitura(quem)) return false;
  if (quem.papel === 'gestor') return true;
  return !c.donoId || c.donoId === quem.vendedorId || negociosDaPessoa.some((n) => !!n.donoId && n.donoId === quem.vendedorId);
}

/** Frase para a tela explicar por que não dá para abrir negócio para o contato. null = pode. */
export function motivoSemNovoNegocio(c: Pick<Contato, 'donoId'>, negociosDaPessoa: Pick<Negocio, 'donoId'>[], quem: Quem, nomeDe: (id: string | null) => string): string | null {
  if (podeAbrirNegocioPara(c, negociosDaPessoa, quem)) return null;
  if (!quem) return 'Carregando quem você é.';
  if (somenteLeitura(quem)) return MSG_SOMENTE_LEITURA;
  return `Contato de ${nomeDe(c.donoId)}: só o dono ou o gestor abre negócio.`;
}

export interface TravaMover {
  permitido: boolean;
  /** Texto curto para title/aviso. null quando permitido. */
  motivo: string | null;
  /** Campos obrigatórios que faltam para entrar na etapa (rótulos). */
  faltam: string[];
}

/**
 * Pode mover o negócio para a etapa destino? Ordem das recusas = ordem do banco: dono, etapa atual, encerrado,
 * etapa inexistente, ganho, campos obrigatórios.
 */
export function travaMover(n: Pick<Negocio, 'donoId' | 'campos' | 'status' | 'etapaId'>, funil: Funil, destinoId: string, quem: Quem, nomeDe: (id: string | null) => string): TravaMover {
  const leitura = motivoSomenteLeitura(n, quem, nomeDe);
  if (leitura) return { permitido: false, motivo: leitura, faltam: [] };
  if (n.etapaId === destinoId) return { permitido: false, motivo: 'Etapa atual.', faltam: [] };
  const b = bloqueioMoverNoFunil(n, funil, destinoId);
  if (b === 'negocio_encerrado') return { permitido: false, motivo: 'Negócio encerrado não muda de etapa.', faltam: [] };
  if (b === 'etapa_inexistente') return { permitido: false, motivo: 'Etapa não existe neste funil.', faltam: [] };
  if (b === 'ganho_so_com_pagamento') return { permitido: false, motivo: 'Ganho só com pagamento aprovado na Hotmart.', faltam: [] };
  if (b === 'campos_faltando') {
    const faltam = rotulosCampos(camposFaltandoNoFunil(n, funil, destinoId));
    return { permitido: false, motivo: `Falta preencher: ${faltam.join(', ')}.`, faltam };
  }
  return { permitido: true, motivo: null, faltam: [] };
}

export function rotulosCampos(campos: CampoKey[]): string[] {
  return campos.map((c) => ROTULO_CAMPO[c]);
}

/**
 * Escrever para o contato no WhatsApp (mensagem, anexo, áudio). ESPELHO de `crm.pode_escrever_pessoa` (usada por
 * `crm_enviar_mensagem`, recusa "Este contato não é seu."): gestor sempre; vendedor se é dono do contato OU dono de
 * algum negócio da pessoa (qualquer status). Contato sem dono e sem negócio dele: só o gestor (diferente de abrir negócio).
 * `negociosDaPessoa` = negócios do contato (o banco olha o grupo inteiro da pessoa; a tela passa os que conhece).
 */
export function podeEscreverContato(c: Pick<Contato, 'donoId'>, negociosDaPessoa: Pick<Negocio, 'donoId'>[], quem: Quem): boolean {
  if (!quem || somenteLeitura(quem)) return false;
  if (quem.papel === 'gestor') return true;
  return (!!c.donoId && c.donoId === quem.vendedorId) || negociosDaPessoa.some((n) => !!n.donoId && n.donoId === quem.vendedorId);
}

/** Frase para a tela explicar por que não dá para escrever ao contato. null = pode. */
export function motivoSemEscrita(c: Pick<Contato, 'donoId'>, negociosDaPessoa: Pick<Negocio, 'donoId'>[], quem: Quem, nomeDe: (id: string | null) => string): string | null {
  if (podeEscreverContato(c, negociosDaPessoa, quem)) return null;
  if (!quem) return 'Carregando quem você é.';
  if (somenteLeitura(quem)) return MSG_SOMENTE_LEITURA;
  if (!c.donoId) return 'Lead sem dono. O gestor atribui o dono antes de qualquer conversa.';
  return `Lead de ${nomeDe(c.donoId)}. Lead que não é seu não se toca: transfira pelo gestor.`;
}
