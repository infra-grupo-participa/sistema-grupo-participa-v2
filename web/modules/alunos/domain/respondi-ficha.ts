// `dados` de uma resposta do Respondi (já normalizado pelo carga.py — contrato em
// infra/scripts/respondi/LEIAME.md) montado como ficha: blocos com campos prontos para a tela.
// Campo vazio não entra; bloco sem campo some. Na família "socios" os campos `socio_*` viram
// o bloco "Sócio declarado". Links de rede só saem com host da rede certa (safeHttpUrl).
import { safeHttpUrl, HOSTS_REDE } from '@/shared/domain/url-segura';

export type TipoCampo = 'texto' | 'cpf' | 'nivel' | 'turma' | 'link';

export interface CampoFicha {
  k: string;
  rotulo: string;
  valor: string;
  tipo: TipoCampo;
  /** Só em `link`: URL http(s) do host da rede. Sem ela o valor aparece como texto. */
  href?: string | null;
  /** Só em `cpf`: `cpf_valido === false` no `dados`. */
  invalido?: boolean;
}

export type ChaveBloco = 'identificacao' | 'programa' | 'endereco' | 'redes' | 'socio';

export interface BlocoFicha {
  k: ChaveBloco;
  titulo: string;
  campos: CampoFicha[];
}

type Dados = Record<string, unknown> | null | undefined;

const txt = (d: Dados, k: string): string => {
  const v = d?.[k];
  if (v == null || typeof v === 'object') return '';
  return String(v).trim();
};

const digitos = (s: string) => s.replace(/\D/g, '');

/** CPF com o começo e o verificador ocultos: `***.456.789-**`. Fora de 11 dígitos, tudo oculto. */
export function mascararCpf(v: string): string {
  const d = digitos(v);
  if (d.length !== 11) return v.replace(/\d/g, '*');
  return `***.${d.slice(3, 6)}.${d.slice(6, 9)}-**`;
}

export function formatarCpf(v: string): string {
  const d = digitos(v);
  return d.length === 11 ? `${d.slice(0, 3)}.${d.slice(3, 6)}.${d.slice(6, 9)}-${d.slice(9)}` : v;
}

/** Endereço numa linha: "Rua X, 120, ap 3 · Centro · Goiânia/GO · CEP 74000-000". */
export function linhaEndereco(d: Dados, p = ''): string {
  const g = (k: string) => txt(d, p + k);
  const rua = [g('endereco'), g('numero'), g('complemento')].filter(Boolean).join(', ');
  const cidade = [g('cidade'), g('uf_sigla')].filter(Boolean).join('/');
  const cepD = digitos(g('cep'));
  const cep = cepD.length === 8 ? `${cepD.slice(0, 5)}-${cepD.slice(5)}` : g('cep');
  return [rua, g('bairro'), cidade, cep && `CEP ${cep}`].filter(Boolean).join(' · ');
}

type Rede = keyof typeof HOSTS_REDE;
const REDES: { k: Rede; rotulo: string }[] = [
  { k: 'instagram', rotulo: 'Instagram' },
  { k: 'facebook', rotulo: 'Facebook' },
  { k: 'youtube', rotulo: 'YouTube' },
];
const ARROBA = /^@?([A-Za-z0-9._]{1,30})$/;

/** URL da rede: aceita URL completa, URL sem esquema e, no Instagram, o @ do perfil. */
export function urlRede(rede: Rede, valor: string): string | null {
  const hosts = HOSTS_REDE[rede];
  const direta = safeHttpUrl(valor, hosts) ?? (/^[a-z]+:/i.test(valor) ? null : safeHttpUrl(`https://${valor}`, hosts));
  if (direta) return direta;
  const m = rede === 'instagram' ? ARROBA.exec(valor) : null;
  return m ? `https://www.instagram.com/${m[1]}` : null;
}

function campos(d: Dados, p: string, quais: ('cpf' | 'email' | 'telefone' | 'profissao' | 'nivel' | 'turma' | 'endereco' | 'redes')[]): CampoFicha[] {
  const out: CampoFicha[] = [];
  const add = (k: string, rotulo: string, tipo: TipoCampo = 'texto', extra: Partial<CampoFicha> = {}) => {
    const valor = k === 'endereco' ? linhaEndereco(d, p) : txt(d, p + k);
    if (valor) out.push({ k: p + k, rotulo, valor, tipo, ...extra });
  };
  for (const q of quais) {
    if (q === 'cpf') add('cpf', 'CPF', 'cpf', d?.[p + 'cpf_valido'] === false ? { invalido: true } : {});
    else if (q === 'email') add('email', 'E-mail');
    else if (q === 'telefone') add('telefone', 'Telefone');
    else if (q === 'profissao') add('profissao', 'Profissão');
    else if (q === 'nivel') add('nivel_codigo', 'Nível declarado', 'nivel');
    else if (q === 'turma') add('turma_codigo', 'Turma declarada', 'turma');
    else if (q === 'endereco') add('endereco', 'Endereço');
    else for (const r of REDES) {
      const valor = txt(d, p + r.k);
      if (valor) out.push({ k: p + r.k, rotulo: r.rotulo, valor, tipo: 'link', href: urlRede(r.k, valor) });
    }
  }
  return out;
}

export function fichaRespondi(dados: Dados, familia: string): BlocoFicha[] {
  const blocos: BlocoFicha[] = [
    { k: 'identificacao', titulo: 'Identificação e contato', campos: campos(dados, '', ['cpf', 'email', 'telefone', 'profissao']) },
    { k: 'programa', titulo: 'Programa', campos: campos(dados, '', ['nivel', 'turma']) },
    { k: 'endereco', titulo: 'Endereço', campos: campos(dados, '', ['endereco']) },
    { k: 'redes', titulo: 'Redes', campos: campos(dados, '', ['redes']) },
  ];
  if (familia === 'socios') {
    blocos.push({
      k: 'socio',
      titulo: 'Sócio declarado',
      campos: campos(dados, 'socio_', ['cpf', 'email', 'telefone', 'profissao', 'nivel', 'turma', 'endereco', 'redes']),
    });
  }
  return blocos.filter((b) => b.campos.length > 0);
}
