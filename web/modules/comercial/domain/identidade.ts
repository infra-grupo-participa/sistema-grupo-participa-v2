// Comercial > base única de pessoas: a regra de identidade da casa, em TypeScript. Domínio puro (sem Next, sem Supabase).
//
// É a MESMA regra das funções pessoas.norm_* e pessoas.resolver da migration 20261005o (o banco é quem decide de verdade;
// aqui ela existe para os testes, para o modo de demonstração e para a tela avisar antes de gravar). Mudou uma, muda a
// outra, e os dois testes (identidade.test.ts e o ensaio 20261005o) cobram.
//
// Cascata (Central-de-Alunos/CLAUDE.md): documento → telefone (DDD + 8 últimos) → e-mail → nome + CEP.
// Documento ou telefone com NOME diferente não fundem. Só o nome bate → pessoa nova em revisão. Nada funde no escuro.

const soDigitos = (s: string | null | undefined) => String(s ?? '').replace(/\D/g, '');

/** CPF (11) ou CNPJ (14) com dígito verificador certo; sequência repetida é inválida. */
export function documentoValido(d: string): boolean {
  if (!/^\d+$/.test(d) || /^(\d)\1*$/.test(d)) return false;
  const n = d.split('').map(Number);
  if (d.length === 11) {
    let s = 0;
    for (let i = 0; i < 9; i++) s += n[i] * (10 - i);
    let r = (s * 10) % 11; if (r === 10) r = 0;
    if (r !== n[9]) return false;
    s = 0;
    for (let i = 0; i < 10; i++) s += n[i] * (11 - i);
    r = (s * 10) % 11; if (r === 10) r = 0;
    return r === n[10];
  }
  if (d.length === 14) {
    const p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    const p2 = [6, ...p1];
    let s = p1.reduce((acc, p, i) => acc + p * n[i], 0);
    let r = s % 11; r = r < 2 ? 0 : 11 - r;
    if (r !== n[12]) return false;
    s = p2.reduce((acc, p, i) => acc + p * n[i], 0);
    r = s % 11; r = r < 2 ? 0 : 11 - r;
    return r === n[13];
  }
  return false;
}

/** Só dígitos, zeros à esquerda devolvidos (CPF de 9 a 11 → 11; CNPJ de 12 a 14 → 14). Inválido = null (não casa). */
export function normalizarDocumento(s: string | null | undefined): string | null {
  let d = soDigitos(s);
  if (d.length >= 9 && d.length <= 11) d = d.padStart(11, '0');
  else if (d.length >= 12 && d.length <= 14) d = d.padStart(14, '0');
  else return null;
  return documentoValido(d) ? d : null;
}

/** Telefone BR: tira 55 e o 0 de longa distância; sobra DDD (sem zero) + 8 ou 9 dígitos (9 dígitos começa com 9). */
export function normalizarTelefone(s: string | null | undefined): string | null {
  let d = soDigitos(s);
  if ((d.length === 12 || d.length === 13) && d.startsWith('55')) d = d.slice(2);
  if ((d.length === 11 || d.length === 12) && d.startsWith('0')) d = d.slice(1);
  if (d.length !== 10 && d.length !== 11) return null;
  if (d[0] === '0' || d[1] === '0') return null;
  if (d.length === 11 && d[2] !== '9') return null;
  return d;
}

/** Chave de casamento do telefone: DDD + 8 últimos (o 9 a mais do celular não separa a mesma pessoa). */
export const chaveTelefone = (normalizado: string | null) => (normalizado ? normalizado.slice(0, 2) + normalizado.slice(-8) : null);

export function normalizarEmail(s: string | null | undefined): string | null {
  const e = String(s ?? '').trim().toLowerCase();
  return /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e) ? e : null;
}

/** Maiúsculas, sem acento, só letras e um espaço entre palavras. */
export function normalizarNome(s: string | null | undefined): string | null {
  const n = String(s ?? '')
    .normalize('NFD').replace(/[̀-ͯ]/g, '')
    .toUpperCase().replace(/[^A-Z ]/g, ' ').replace(/ +/g, ' ').trim();
  return n || null;
}

export function normalizarCep(s: string | null | undefined): string | null {
  const d = soDigitos(s);
  return d.length === 8 && !/^0+$/.test(d) ? d : null;
}

/** Nome + CEP só vale com nome de 2 palavras ou mais. */
export function chaveNomeCep(nome: string | null | undefined, cep: string | null | undefined): string | null {
  const n = normalizarNome(nome);
  const c = normalizarCep(cep);
  return n && n.includes(' ') && c ? `${n}|${c}` : null;
}

/** Mesmo primeiro nome. Sem nome de um dos lados = não contradiz. */
export function nomesCompativeis(a: string | null | undefined, b: string | null | undefined): boolean {
  const x = normalizarNome(a);
  const y = normalizarNome(b);
  if (!x || !y) return true;
  return x.split(' ')[0] === y.split(' ')[0];
}

/** Máscara dos 4 últimos (a mesma do mascarar() da Central e de pessoas.mascara_fim). */
export function mascararFim(s: string | null | undefined): string | null {
  if (s == null || s === '') return s ?? null;
  return '*'.repeat(Math.max(s.length - 4, 0)) + s.slice(-4);
}

export function mascararEmail(s: string | null | undefined): string | null {
  if (s == null || !s.includes('@')) return s ?? null;
  const [u, dom] = s.split('@');
  return `${u.slice(0, 1)}***@${dom}`;
}

// ─── Cascata (versão em memória: testes e demonstração) ──────────────────────────────────────────────────────────────
export type Passo = 'documento' | 'telefone' | 'email' | 'nome_cep';
export const PASSOS: Passo[] = ['documento', 'telefone', 'email', 'nome_cep'];
export type MotivoRevisao = 'so_nome' | 'documento_nome_diferente' | 'telefone_nome_diferente' | 'conflito';

export const ROTULO_MOTIVO: Record<MotivoRevisao, string> = {
  so_nome: 'Só o nome bate',
  documento_nome_diferente: 'Mesmo documento, nome diferente',
  telefone_nome_diferente: 'Mesmo telefone, nome diferente',
  conflito: 'Bate com mais de uma pessoa',
};

export interface Entrada { nome?: string | null; email?: string | null; telefone?: string | null; documento?: string | null; cep?: string | null }

/** Pessoa conhecida, com os identificadores que valem para ela (os próprios e os do aluno/comprador ligado). */
export interface Conhecida { id: string; nome: string | null; documento?: string | null; telefone?: string | null; email?: string | null; cep?: string | null }

export interface Resultado {
  /** pessoa que casou; null = pessoa nova */
  pessoaId: string | null;
  como: Passo | 'nova';
  revisao: MotivoRevisao | null;
  candidatos: string[];
}

export function chavesDa(e: Entrada): Record<Passo, string | null> {
  return {
    documento: normalizarDocumento(e.documento),
    telefone: chaveTelefone(normalizarTelefone(e.telefone)),
    email: normalizarEmail(e.email),
    nome_cep: chaveNomeCep(e.nome, e.cep),
  };
}

/** Tem ao menos um identificador forte (documento, telefone ou e-mail válidos)? Sem isso o banco recusa. */
export function temIdentificador(e: Entrada): boolean {
  const k = chavesDa(e);
  return !!(k.documento || k.telefone || k.email);
}

export function resolverIdentidade(entrada: Entrada, conhecidas: Conhecida[]): Resultado {
  const k = chavesDa(entrada);
  const suspeitas = new Set<string>();
  let motivo: MotivoRevisao | null = null;
  for (const passo of PASSOS) {
    const chave = k[passo];
    if (!chave) continue;
    const batem = conhecidas.filter((c) => chavesDa(c)[passo] === chave);
    if (batem.length === 0) continue;
    const compat = batem.filter((c) => nomesCompativeis(entrada.nome, c.nome));
    let alvo: Conhecida[] = batem;
    if (passo === 'documento' || passo === 'telefone') {
      if (compat.length === 0) {
        batem.forEach((c) => suspeitas.add(c.id));
        motivo ??= passo === 'documento' ? 'documento_nome_diferente' : 'telefone_nome_diferente';
        continue;
      }
      alvo = compat;
    } else if (batem.length > 1 && compat.length > 0) {
      alvo = compat;
    }
    if (alvo.length > 1) {
      alvo.forEach((c) => suspeitas.add(c.id));
      motivo = 'conflito';
      continue;
    }
    const id = alvo[0].id;
    suspeitas.delete(id);
    return { pessoaId: id, como: passo, revisao: suspeitas.size ? motivo : null, candidatos: [...suspeitas] };
  }
  if (suspeitas.size === 0) {
    const nome = normalizarNome(entrada.nome);
    if (nome && nome.includes(' ')) {
      conhecidas.filter((c) => normalizarNome(c.nome) === nome).forEach((c) => suspeitas.add(c.id));
      if (suspeitas.size) motivo = 'so_nome';
    }
  }
  return { pessoaId: null, como: 'nova', revisao: suspeitas.size ? motivo : null, candidatos: [...suspeitas] };
}
