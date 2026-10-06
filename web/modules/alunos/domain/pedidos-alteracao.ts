// Domínio puro dos Pedidos de alteração de cadastro (migration 20261005j_pedidos_alteracao.sql).
// Quem pede não tem acesso à Central: vê só os próprios pedidos. Quem aprova (pa_aprovadores no banco)
// decide na aba da Central. As regras aqui ESPELHAM as do banco (pa_normalizar, pa_pode_pedir); a trava
// real é a do Postgres, a da tela só evita mandar pedido que o banco vai recusar.
import type { GpUser } from '@/shared/domain/auth';
import { ESPACO_LABEL, INSTRUCOES, parseInstrucao } from './aluno-360';

export const SETOR_PEDIDOS = 'pedidos_alteracao';

/** Espelho de pa_pode_pedir(): dev/admin, ou gestor/operador com a área 'pedidos_alteracao' (catálogo 3.6). */
export function podePedirAlteracao(u: GpUser | null): boolean {
  if (!u) return false;
  if (u.cargo === 'dev' || u.cargo === 'admin') return true;
  if (u.cargo === 'gestor' || u.cargo === 'operador') return (u.setores || []).includes(SETOR_PEDIDOS);
  return false;
}

export type TipoPedido = 'alterar_dado' | 'trocar_socio' | 'outro';
export type StatusPedido = 'pendente' | 'aprovado' | 'recusado' | 'aplicado' | 'erro';
export type StatusPlanilha = 'pendente' | 'ok' | 'erro';

export const ROTULO_TIPO: Record<TipoPedido, string> = {
  alterar_dado: 'Alterar dado',
  trocar_socio: 'Trocar sócio',
  outro: 'Outro',
};

export const ROTULO_STATUS: Record<StatusPedido, string> = {
  pendente: 'Aguardando aprovação',
  aprovado: 'Aprovado, falta aplicar',
  recusado: 'Recusado',
  aplicado: 'Aplicado',
  erro: 'Erro ao aplicar',
};

export const TOM_STATUS: Record<StatusPedido, 'warning' | 'info' | 'danger' | 'success'> = {
  pendente: 'warning',
  aprovado: 'info',
  recusado: 'danger',
  aplicado: 'success',
  erro: 'danger',
};

export const ROTULO_PLANILHA: Record<StatusPlanilha, string> = {
  pendente: 'Planilha: pendente',
  ok: 'Planilha: atualizada',
  erro: 'Planilha: erro',
};

/**
 * Lista FECHADA de campos editáveis por "alterar dado". Mesma ordem e chaves de pa_campos() no banco
 * (o teste confere contra a migration). Nunca dinheiro, compra ou Hotmart.
 */
export const CAMPOS_EDITAVEIS = [
  { campo: 'nome', rotulo: 'Nome' },
  { campo: 'email', rotulo: 'E-mail' },
  { campo: 'telefone', rotulo: 'Telefone' },
  { campo: 'telefone_profissional', rotulo: 'Telefone profissional' },
  { campo: 'documento', rotulo: 'Documento (CPF ou CNPJ)' },
  { campo: 'endereco', rotulo: 'Endereço' },
  { campo: 'profissao', rotulo: 'Profissão' },
  { campo: 'turma_id', rotulo: 'Turma' },
  { campo: 'instrucao', rotulo: 'Instrução' },
  { campo: 'espaco_instrucao', rotulo: 'Espaço de instrução' },
  { campo: 'obs_central', rotulo: 'Observação da Central' },
] as const;
export type CampoEditavel = (typeof CAMPOS_EDITAVEIS)[number]['campo'];

export const rotuloCampo = (campo: string | null | undefined): string =>
  CAMPOS_EDITAVEIS.find((c) => c.campo === campo)?.rotulo ?? (campo || '');

/** Partes do endereço, na ordem de pa_colunas_endereco(). */
export const ENDERECO_PARTES = [
  { k: 'cep', rotulo: 'CEP' },
  { k: 'endereco_logradouro', rotulo: 'Logradouro' },
  { k: 'endereco_numero', rotulo: 'Número' },
  { k: 'endereco_complemento', rotulo: 'Complemento' },
  { k: 'bairro', rotulo: 'Bairro' },
  { k: 'cidade', rotulo: 'Cidade' },
  { k: 'estado', rotulo: 'Estado (UF)' },
  { k: 'pais', rotulo: 'País' },
] as const;
export type Endereco = Partial<Record<(typeof ENDERECO_PARTES)[number]['k'], string | null>>;

export const ESPACOS = Object.keys(ESPACO_LABEL);
export { INSTRUCOES };

export type Validacao = { ok: true; valor: unknown } | { ok: false; erro: string };

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
const digitos = (v: unknown) => String(v ?? '').replace(/\D/g, '');
const txt = (v: unknown): string | null => {
  const s = String(v ?? '').trim();
  return s ? s : null;
};

/** Telefone no padrão da Central (55 + DDD + número). Espelho de pa_telefone(). */
export function normalizarTelefone(v: unknown): Validacao {
  let d = digitos(v);
  if (!d) return { ok: true, valor: null };
  if (d.length === 10 || d.length === 11) d = '55' + d;
  if (d.length < 10 || d.length > 15) return { ok: false, erro: 'Telefone inválido: use DDD + número (ex.: 21 99999-9999).' };
  return { ok: true, valor: d };
}

// ── Documento, telefone e endereço (20261005k) ──

/** As 27 UFs. Mesma lista de pa_ufs() (o teste confere contra a migration). */
export const UFS = ['AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO', 'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE',
  'PI', 'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO'] as const;

/** Sugestões do campo país (texto livre: qualquer país é aceito). */
export const PAISES_SUGERIDOS = ['Portugal', 'Estados Unidos', 'Espanha', 'Itália', 'França', 'Alemanha', 'Reino Unido',
  'Irlanda', 'Suíça', 'Canadá', 'Argentina', 'Uruguai', 'Paraguai', 'Chile', 'México', 'Japão', 'Emirados Árabes Unidos'];

const semAcento = (v: string) => v.normalize('NFD').replace(/[̀-ͯ]/g, '');

/** País vazio conta como Brasil (default da coluna). Espelho de pa_eh_brasil(). */
export function ehBrasil(pais: unknown): boolean {
  const p = semAcento(String(pais ?? '')).trim().toLowerCase().replace(/\s+/g, ' ');
  return p === '' || p === 'brasil' || p === 'brazil' || p === 'br';
}

function dvCpf(d: string): boolean {
  if (d.length !== 11 || d === d[0].repeat(11)) return false;
  for (const n of [9, 10]) {
    let s = 0;
    for (let i = 0; i < n; i++) s += Number(d[i]) * (n + 1 - i);
    let r = (s * 10) % 11;
    if (r === 10) r = 0;
    if (r !== Number(d[n])) return false;
  }
  return true;
}

function dvCnpj(d: string): boolean {
  if (d.length !== 14 || d === d[0].repeat(14)) return false;
  const pesos = [[5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2]];
  for (const w of pesos) {
    let s = 0;
    for (let i = 0; i < w.length; i++) s += Number(d[i]) * w[i];
    const r = s % 11 < 2 ? 0 : 11 - (s % 11);
    if (r !== Number(d[w.length])) return false;
  }
  return true;
}

/** CPF (11) ou CNPJ (14) com dígito verificador. Espelho de pa_doc_valido(). */
export function documentoValido(v: unknown): boolean {
  const d = digitos(v);
  return d.length === 11 ? dvCpf(d) : d.length === 14 ? dvCnpj(d) : false;
}

/** Máscara de digitação: até 11 dígitos = CPF (000.000.000-00), até 14 = CNPJ (00.000.000/0000-00). */
export function formatarDocumento(v: string): string {
  const d = digitos(v).slice(0, 14);
  if (d.length <= 11) {
    return d.replace(/^(\d{3})(\d)/, '$1.$2').replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3').replace(/\.(\d{3})(\d{1,2})$/, '.$1-$2');
  }
  return d.replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{0,2})$/, '$1.$2.$3/$4-$5').replace(/-$/, '');
}

/** Máscara de CEP brasileiro (00000-000). */
export function formatarCep(v: string): string {
  const d = digitos(v).slice(0, 8);
  return d.length > 5 ? `${d.slice(0, 5)}-${d.slice(5)}` : d;
}

/**
 * Telefone de pessoa nova (obrigatório). Brasil: 55 + DDD + número (12 ou 13 dígitos). Exterior: código do país +
 * número, de 8 a 15 dígitos. Espelho de pa_telefone_pessoa() (mesmas mensagens).
 */
export function normalizarTelefonePessoa(v: unknown, brasil: boolean): Validacao {
  let d = digitos(v);
  if (!d) return { ok: false, erro: 'Informe o telefone.' };
  if (brasil) {
    if (d.length === 10 || d.length === 11) d = '55' + d;
    if (!/^55[1-9]\d{9,10}$/.test(d)) return { ok: false, erro: 'Telefone inválido: use DDD + número (ex.: 21 99999-9999).' };
  } else if (d.length < 8 || d.length > 15) {
    return { ok: false, erro: 'Telefone internacional inválido: código do país + número, de 8 a 15 dígitos.' };
  }
  return { ok: true, valor: d };
}

export type ParteEndereco = (typeof ENDERECO_PARTES)[number]['k'];
export type EnderecoNorm = Record<ParteEndereco, string | null>;
export type ValidacaoEndereco =
  | { ok: true; valor: EnderecoNorm }
  | { ok: false; erro: string; erros: Partial<Record<ParteEndereco, string>> };

export const ENDERECO_VAZIO: Record<ParteEndereco, string> = {
  cep: '', endereco_logradouro: '', endereco_numero: '', endereco_complemento: '', bairro: '', cidade: '', estado: '', pais: 'Brasil',
};

/** Obrigatórios do cadastro novo. Brasil: tudo menos complemento. Exterior: endereço e cidade. */
const OBRIGATORIOS_BR: [ParteEndereco, string][] = [
  ['cep', 'CEP'], ['endereco_logradouro', 'logradouro'], ['endereco_numero', 'número'], ['bairro', 'bairro'],
  ['cidade', 'cidade'], ['estado', 'estado'],
];
const OBRIGATORIOS_EXT: [ParteEndereco, string][] = [['endereco_logradouro', 'endereço'], ['cidade', 'cidade']];

/**
 * Valida e normaliza um endereço. `completo` = cadastro de pessoa nova (obrigatórios); sem ele, "alterar dado"
 * (pode vir parcial). Brasil: CEP com 8 dígitos e UF da lista; exterior: CEP e estado/província livres.
 * Espelho de pa_endereco() (mesmas mensagens). `erros` traz a mensagem de cada campo, para mostrar ao lado dele.
 */
export function validarEndereco(valor: unknown, completo: boolean): ValidacaoEndereco {
  if (!valor || typeof valor !== 'object') return { ok: false, erro: 'Endereço inválido.', erros: {} };
  const e = valor as Record<string, unknown>;
  let pais = txt(e.pais)?.slice(0, 100) ?? null;
  const br = ehBrasil(pais);
  if (br && (pais !== null || completo)) pais = 'Brasil';
  const out = {} as EnderecoNorm;
  const erros: Partial<Record<ParteEndereco, string>> = {};
  let primeiro: string | null = null;
  const falha = (k: ParteEndereco, m: string) => { erros[k] = m; primeiro ??= m; };
  for (const { k } of ENDERECO_PARTES) {
    let p = txt(String(e[k] ?? '').replace(/\s+/g, ' '));
    if (p) p = p.slice(0, 200);
    if (k === 'pais') p = pais;
    else if (k === 'cep' && p) {
      if (br) {
        p = digitos(p);
        if (p.length !== 8) falha(k, 'CEP deve ter 8 dígitos.');
      } else p = p.slice(0, 20);
    } else if (k === 'estado' && p) {
      if (br) {
        p = p.toUpperCase();
        if (!(UFS as readonly string[]).includes(p)) falha(k, 'Estado inválido: escolha uma das 27 UFs (ex.: SP).');
      } else p = p.slice(0, 100);
    }
    out[k] = p;
  }
  if (primeiro) return { ok: false, erro: primeiro, erros };
  if (completo) {
    const falta = (br ? OBRIGATORIOS_BR : OBRIGATORIOS_EXT).filter(([k]) => !out[k]);
    if (falta.length) {
      for (const [k] of falta) erros[k] = 'Obrigatório.';
      return { ok: false, erro: `Endereço incompleto: falta ${falta.map(([, l]) => l).join(', ')}.`, erros };
    }
  }
  return { ok: true, valor: out };
}

/** O endereço tem algum dado além do país? (o país vem 'Brasil' por padrão em quase todo cadastro) */
export function enderecoTemDado(e: Endereco | null | undefined): boolean {
  if (!e) return false;
  return ENDERECO_PARTES.some(({ k }) => k !== 'pais' && !!txt(e[k]));
}

/** Endereço numa linha, para conferência (mesma ordem de pa_exibir). */
export function enderecoEmLinha(e: Endereco | null | undefined): string | null {
  if (!e) return null;
  const t = (k: ParteEndereco) => txt(e[k]);
  const cep = t('cep');
  const cepFmt = cep && ehBrasil(e.pais) ? formatarCep(cep) : cep;
  const linha = [t('endereco_logradouro'), t('endereco_numero'), t('endereco_complemento'), t('bairro'),
    [t('cidade'), t('estado')].filter(Boolean).join('/') || null, cepFmt ? `CEP ${cepFmt}` : null, t('pais')]
    .filter(Boolean).join(', ');
  return linha || null;
}

/** Valida e normaliza o valor pedido. Espelho de pa_normalizar() (mesmas mensagens). */
export function validarValor(campo: string, valor: unknown): Validacao {
  if (!CAMPOS_EDITAVEIS.some((c) => c.campo === campo)) return { ok: false, erro: 'Campo fora da lista de campos editáveis.' };
  const v = txt(valor);
  switch (campo as CampoEditavel) {
    case 'nome': {
      const n = (v ?? '').replace(/\s+/g, ' ');
      if (n.length < 3 || n.length > 200) return { ok: false, erro: 'Nome deve ter entre 3 e 200 caracteres.' };
      return { ok: true, valor: n };
    }
    case 'email':
      if (!v || !EMAIL_RE.test(v) || v.length > 200) return { ok: false, erro: 'E-mail inválido.' };
      return { ok: true, valor: v };
    case 'telefone':
    case 'telefone_profissional':
      return normalizarTelefone(v);
    case 'documento': {
      const d = digitos(v);
      if (d.length !== 11 && d.length !== 14) return { ok: false, erro: 'Documento inválido: CPF com 11 dígitos ou CNPJ com 14.' };
      if (!documentoValido(d)) return { ok: false, erro: 'CPF ou CNPJ inválido: confira os dígitos.' };
      return { ok: true, valor: d };
    }
    case 'endereco': {
      const r = validarEndereco(valor, false);
      return r.ok ? { ok: true, valor: r.valor } : { ok: false, erro: r.erro };
    }
    case 'turma_id':
      if (!v || !/^\d{1,6}$/.test(v)) return { ok: false, erro: 'Turma inexistente.' };
      return { ok: true, valor: Number(v) };
    case 'instrucao': {
      const i = (v ?? '').toUpperCase();
      if (!INSTRUCOES.includes(i)) return { ok: false, erro: 'Instrução fora das 12 da Central.' };
      return { ok: true, valor: i };
    }
    case 'espaco_instrucao':
      if (!v || !ESPACOS.includes(v)) return { ok: false, erro: 'Espaço de instrução inválido.' };
      return { ok: true, valor: v };
    case 'profissao':
      if ((v ?? '').length > 200) return { ok: false, erro: 'Profissão com mais de 200 caracteres.' };
      return { ok: true, valor: v };
    case 'obs_central':
      if ((v ?? '').length > 2000) return { ok: false, erro: 'Observação com mais de 2000 caracteres.' };
      return { ok: true, valor: v };
  }
  return { ok: false, erro: 'Campo sem regra de validação.' };
}

/** Motivo obrigatório (5 a 2000) e evidência opcional só como link. Espelho de pa_criar(). */
export function validarMotivoEvidencia(motivo: string, evidencia: string): string | null {
  const m = motivo.trim();
  if (m.length < 5) return 'Explique o motivo (mínimo 5 caracteres).';
  if (m.length > 2000) return 'Motivo com mais de 2000 caracteres.';
  const e = evidencia.trim();
  if (e && (!/^https?:\/\/\S+$/.test(e) || e.length > 1000)) return 'Evidência deve ser um link (http ou https).';
  return null;
}

// ── Troca de sócio ──

/** Resumo de aluno devolvido pela busca (pa_resumo_aluno): só o mínimo para distinguir homônimos. */
export interface AlunoResumo {
  id: string;
  nome: string | null;
  instrucao: string | null;
  espaco: string | null;
  eh_socio: boolean;
  titular_nome: string | null;
  titular_id: string | null;
  turma: string | null;
  email: string | null;
  telefone_final: string | null;
  doc_final: string | null;
  num_socios: number | null;
}

/**
 * Instrução que o sócio que entra recebe: o nível do titular com " - SÓCIO" (sócio acompanha o titular).
 * Espelho de pa_instrucao_canonica(titular, espaço, false) + sufixo. Null = titular sem instrução nem espaço.
 */
export function instrucaoDoSocio(titular: { instrucao: string | null; espaco_instrucao: string | null }): string | null {
  const i = parseInstrucao({ instrucao: titular.instrucao, espaco_instrucao: titular.espaco_instrucao, eh_socio: false });
  return i ? `${i.nivel} - SÓCIO` : null;
}

/** Formulário da pessoa nova (tela). `endereco_mantido` = "mesmo endereço do sócio que sai". */
export interface SocioNovo {
  nome: string;
  email: string;
  telefone: string;
  documento: string;
  profissao: string;
  endereco_mantido: boolean;
  endereco: Record<ParteEndereco, string>;
}

export const SOCIO_NOVO_VAZIO: SocioNovo = {
  nome: '', email: '', telefone: '', documento: '', profissao: '', endereco_mantido: false, endereco: { ...ENDERECO_VAZIO },
};

/** Dados da pessoa nova como vão no pedido (pa_criar). Com endereço mantido, o banco lê o endereço de quem sai. */
export interface SocioNovoPayload {
  nome: string;
  email: string;
  telefone: string;
  documento: string;
  profissao: string | null;
  endereco_mantido: boolean;
  endereco: EnderecoNorm | null;
}

/**
 * Endereço que vale para a pessoa nova: o de quem sai (mantido) ou o digitado. Mantido só vale se quem sai tem
 * endereço; o banco faz a mesma conta (e guarda a foto do endereço de quem sai no pedido).
 */
export function enderecoDoSocioNovo(novo: Pick<SocioNovo, 'endereco_mantido' | 'endereco'>, enderecoSai: Endereco | null): Endereco {
  if (novo.endereco_mantido && enderecoTemDado(enderecoSai)) return { ...enderecoSai };
  return novo.endereco;
}

export type ErrosSocioNovo = Partial<Record<'nome' | 'email' | 'telefone' | 'documento' | 'profissao' | 'endereco' | ParteEndereco, string>>;

/**
 * Valida a pessoa nova campo a campo (mensagens ao lado de cada campo). Espelho das recusas de pa_criar() para o
 * sócio novo. `enderecoSai` = endereço atual de quem sai (pa_valor_atual), usado quando o endereço é mantido.
 */
export function validarSocioNovo(novo: SocioNovo, enderecoSai: Endereco | null): { erros: ErrosSocioNovo; payload: SocioNovoPayload | null } {
  const erros: ErrosSocioNovo = {};
  const nome = novo.nome.trim().replace(/\s+/g, ' ');
  if (nome.length < 3 || nome.length > 200) erros.nome = 'Informe o nome completo do sócio novo.';
  const email = novo.email.trim();
  if (!EMAIL_RE.test(email) || email.length > 200) erros.email = 'E-mail inválido.';
  const docDig = digitos(novo.documento);
  if (!docDig) erros.documento = 'Informe o CPF ou CNPJ.';
  else if (docDig.length !== 11 && docDig.length !== 14) erros.documento = 'Documento inválido: CPF com 11 dígitos ou CNPJ com 14.';
  else if (!documentoValido(docDig)) erros.documento = 'CPF ou CNPJ inválido: confira os dígitos.';
  const profissao = novo.profissao.trim();
  if (profissao.length > 200) erros.profissao = 'Profissão com mais de 200 caracteres.';

  let endereco: EnderecoNorm | null = null;
  let paisTel: unknown = 'Brasil';
  if (novo.endereco_mantido) {
    if (!enderecoTemDado(enderecoSai)) erros.endereco = 'O sócio que sai não tem endereço cadastrado: preencha o endereço do sócio novo.';
    paisTel = enderecoSai?.pais;
  } else {
    const r = validarEndereco(novo.endereco, true);
    if (r.ok) endereco = r.valor;
    else { erros.endereco = r.erro; Object.assign(erros, r.erros); }
    paisTel = novo.endereco.pais;
  }
  const tel = normalizarTelefonePessoa(novo.telefone, ehBrasil(paisTel));
  if (!tel.ok) erros.telefone = tel.erro;

  if (Object.keys(erros).length) return { erros, payload: null };
  return {
    erros,
    payload: {
      nome, email, telefone: String((tel as { valor: string }).valor), documento: docDig, profissao: profissao || null,
      endereco_mantido: novo.endereco_mantido, endereco: novo.endereco_mantido ? null : endereco,
    },
  };
}

/** Primeira mensagem de erro da pessoa nova, na ordem do formulário. */
export function primeiroErroSocioNovo(erros: ErrosSocioNovo): string | null {
  for (const k of ['nome', 'email', 'telefone', 'documento', 'profissao', 'endereco'] as const) if (erros[k]) return erros[k]!;
  return null;
}

/**
 * Confere a troca antes de enviar. Espelho das recusas de pa_criar() para trocar_socio.
 * `socios` = sócios atuais do titular (pa_socios_do_titular).
 */
export function validarTrocaSocio(p: {
  titular: AlunoResumo | null;
  sai: AlunoResumo | null;
  socios: AlunoResumo[];
  entra: AlunoResumo | null;
  novo: SocioNovo | null;
  /** Endereço atual de quem sai (para "mesmo endereço"). */
  enderecoSai?: Endereco | null;
}): string | null {
  const { titular, sai, socios, entra, novo, enderecoSai } = p;
  if (!titular) return 'Escolha o titular.';
  if (titular.eh_socio) return 'O aluno escolhido é sócio. Escolha o titular.';
  if (!sai) return 'Escolha o sócio que sai.';
  if (!socios.some((s) => s.id === sai.id)) return `${sai.nome} não é sócio de ${titular.nome}.`;
  if (entra) {
    if (entra.id === titular.id || entra.id === sai.id) return 'O sócio que entra tem de ser outra pessoa.';
    if (socios.some((s) => s.id === entra.id)) return `${entra.nome} já é sócio deste titular.`;
    if (entra.titular_id) return `${entra.nome} já é sócio de outro titular.`;
    return null;
  }
  if (!novo) return 'Escolha o sócio que entra (existente ou novo).';
  const e = primeiroErroSocioNovo(validarSocioNovo(novo, enderecoSai ?? null).erros);
  return e ? 'Sócio novo: ' + e : null;
}

/** Texto curto de distinção de um aluno na busca (instrução, sócio de, turma, contato parcial). */
export function distincaoAluno(a: AlunoResumo, rotuloInstrucao: (i: string) => string = (i) => i): string {
  return [
    a.instrucao ? rotuloInstrucao(a.instrucao) : null,
    a.eh_socio ? `sócio de ${a.titular_nome || 'titular sem nome'}` : null,
    a.turma ? `turma ${a.turma}` : null,
    a.email,
    a.telefone_final ? `tel. final ${a.telefone_final}` : null,
    a.doc_final ? `doc. final ${a.doc_final}` : null,
  ].filter(Boolean).join(' · ');
}

// ── Linhas de tela (pa_linha) ──

export interface EventoPedido { acao: string; em: string; por: string | null; detalhe: Record<string, unknown> }

export interface PedidoLinha {
  id: number;
  tipo: TipoPedido;
  status: StatusPedido;
  aluno_id: string | null;
  aluno_nome: string;
  aluno: AlunoResumo | null;
  campo: string | null;
  de: string | null;
  para: string | null;
  agora: string | null;
  valor_novo: unknown;
  conflito: boolean;
  socio_sai_id: string | null;
  socio_sai_nome: string | null;
  socio_sai_vinculado: boolean | null;
  socio_entra_id: string | null;
  socio_entra_nome: string | null;
  socio_entra_novo: {
    nome?: string; email?: string; telefone?: string | null; documento?: string | null; tipo_documento?: string | null;
    profissao?: string | null; endereco_mantido?: boolean; endereco?: Endereco | null;
  } | null;
  descricao: string | null;
  motivo: string;
  evidencia: string | null;
  solicitado_em: string;
  solicitado_por_nome: string | null;
  decidido_em: string | null;
  decidido_por_nome: string | null;
  motivo_recusa: string | null;
  conflito_confirmado: boolean;
  aplicado_em: string | null;
  erro_msg: string | null;
  planilha_status: StatusPlanilha | null;
  planilha_em: string | null;
  planilha_erro: string | null;
  ra_caso_id: string | null;
  historico: EventoPedido[] | null;
  /** Quem decidiu = quem pediu (pa_fila/pa_linha, etapa 2). Opcional: some antes da migration aplicada. */
  autoaprovado?: boolean | null;
}

export interface PapelPedidos { pode_pedir: boolean; pode_aprovar: boolean; pode_ver_doc: boolean; pendentes: number | null }

/** Abas da tela de pedidos. "Aprovar" só com pa_meu_papel().pode_aprovar === true (o banco trava de novo em pa_fila/pa_decidir). */
export type AbaPedidos = 'pedir' | 'aprovar';
export function abasPedidos(papel: Pick<PapelPedidos, 'pode_aprovar'> | null | undefined): AbaPedidos[] {
  return papel?.pode_aprovar === true ? ['pedir', 'aprovar'] : ['pedir'];
}

/**
 * Selo "aprovou o próprio pedido". `autoaprovado` é decidido_por = criado_por, o que também vale para a
 * recusa do próprio pedido: por isso o selo só aparece quando a decisão foi aprovar (aprovado ou aplicado).
 */
export function aprovouProprioPedido(p: Pick<PedidoLinha, 'autoaprovado' | 'status'>): boolean {
  return p.autoaprovado === true && (p.status === 'aprovado' || p.status === 'aplicado');
}

/** Linha de pa_historico_aluno(p_aluno): o texto já vem pronto do banco (nomes e documento mascarado lá). */
export type PapelHistorico = 'titular' | 'sai' | 'entra' | 'aluno';
export interface ItemHistoricoAluno { em: string; pedido_id: number; papel: PapelHistorico; texto: string }

/** Mais recente primeiro; empate na data, o pedido de número maior primeiro. Data ilegível vai para o fim. */
export function ordenarHistorico(itens: readonly ItemHistoricoAluno[]): ItemHistoricoAluno[] {
  const t = (s: string) => { const n = Date.parse(s); return Number.isNaN(n) ? -Infinity : n; };
  return [...itens].sort((a, b) => (t(b.em) - t(a.em)) || (b.pedido_id - a.pedido_id));
}

/** Resumo de uma linha em texto (lista do solicitante e cabeçalho do aprovador). */
export function resumoPedido(p: Pick<PedidoLinha, 'tipo' | 'campo' | 'de' | 'para' | 'socio_sai_nome' | 'socio_entra_nome' | 'descricao'>): string {
  if (p.tipo === 'alterar_dado') return `${rotuloCampo(p.campo)}: ${p.de ?? '(vazio)'} → ${p.para ?? '(vazio)'}`;
  if (p.tipo === 'trocar_socio') return `Sai ${p.socio_sai_nome ?? '?'}, entra ${p.socio_entra_nome ?? '?'}`;
  return p.descricao ?? '';
}

/** Ajuste do aprovador só cabe em campo de texto simples (endereço e listas se recusam e pedem de novo). */
export const campoAceitaAjusteTexto = (campo: string | null): boolean =>
  !!campo && ['nome', 'email', 'telefone', 'telefone_profissional', 'documento', 'profissao', 'obs_central'].includes(campo);
