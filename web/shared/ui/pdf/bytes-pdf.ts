// Funções sobre os BYTES do PDF, sem lib de PDF: servem à tela (conferência), ao worker
// que desenha (desenho-pdf.ts) e aos testes. Nada aqui importa @react-pdf.

/** Conta as folhas do PDF gerado (objetos /Type /Page — o /Pages raiz não entra). */
export function contarPaginasPdf(bytes: Uint8Array): number {
  let texto = '';
  const passo = 0x8000;
  for (let i = 0; i < bytes.length; i += passo) texto += String.fromCharCode(...bytes.subarray(i, i + passo));
  return (texto.match(/\/Type\s*\/Page(?![a-zA-Z])/g) ?? []).length;
}

/** SHA-256 em hex minúsculo de 64 — o formato do selo (fn_fin_relatorio_selar). */
export async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', bytes as BufferSource);
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');
}
