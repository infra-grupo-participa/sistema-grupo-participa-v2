// Máscaras de input do formulário público — porta de solicitar-placa (maskPhone/Doc/Cep/Currency).

export function maskPhoneMobile(v: string): string {
  const d = v.replace(/\D/g, '').slice(0, 11);
  if (d.length <= 2) return d.replace(/(\d{0,2})/, '($1');
  if (d.length <= 7) return d.replace(/(\d{2})(\d{0,5})/, '($1) $2');
  return d.replace(/(\d{2})(\d{5})(\d{0,4})/, '($1) $2-$3');
}

export function maskPhoneLandline(v: string): string {
  const d = v.replace(/\D/g, '').slice(0, 10);
  if (d.length <= 2) return d.replace(/(\d{0,2})/, '($1');
  if (d.length <= 6) return d.replace(/(\d{2})(\d{0,4})/, '($1) $2');
  return d.replace(/(\d{2})(\d{4})(\d{0,4})/, '($1) $2-$3');
}

export function maskDoc(v: string): string {
  const d = v.replace(/\D/g, '').slice(0, 14);
  if (d.length <= 11) {
    return d
      .replace(/(\d{3})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d)/, '$1.$2')
      .replace(/(\d{3})(\d{1,2})$/, '$1-$2');
  }
  return d
    .replace(/(\d{2})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1.$2')
    .replace(/(\d{3})(\d)/, '$1/$2')
    .replace(/(\d{4})(\d{1,2})$/, '$1-$2');
}

export function maskCep(v: string): string {
  const d = v.replace(/\D/g, '').slice(0, 8);
  return d.length > 5 ? d.replace(/(\d{5})(\d{0,3})/, '$1-$2') : d;
}

/** Valor inteiro em reais a partir de uma string mascarada (R$ 50.000 → 50000). */
export function currencyDigits(v: string): number {
  const d = v.replace(/\D/g, '');
  return d ? parseInt(d, 10) : 0;
}

export function maskCurrency(v: string): string {
  const n = currencyDigits(v);
  if (!n) return '';
  return 'R$ ' + n.toLocaleString('pt-BR');
}
