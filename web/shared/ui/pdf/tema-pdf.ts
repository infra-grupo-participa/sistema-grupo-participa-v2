// Tema do PDF de relatório — ÚNICA fonte de cor, fonte e medida do documento.
//
// Hex aqui é obrigatório: o @react-pdf/renderer desenha num canvas próprio e não
// lê variável CSS (var(--accent) não existe fora do DOM). Por isso este arquivo
// está em SKIP_FILES de scripts/check-hex.mjs, igual ao template de e-mail.
// Nenhum outro arquivo do PDF declara cor: todos importam daqui.
//
// Origem de cada valor:
//  - laranja #F29725 = `fill` do símbolo em public/images/logo-grupo-participa-preto.svg
//    (o logo do PDF é o vetor de logo-pdf.ts pintado com `texto` + `marca`)
//    e --accent do tema escuro em app/globals.css. No papel ele só aparece em FIO
//    (linha fina sob o cabeçalho), nunca em texto: contraste 2,3:1 sobre branco.
//  - grafite #1D1D1B = cor de texto da identidade Grupo Participa (quase-preto).
//  - cinzas medidos (WCAG, 28/09): #5F5F5B = 6,41:1 no branco e 5,93:1 na zebra;
//    #6B6B67 = 5,35:1 no branco e 4,95:1 na zebra. Grafite = 16,88:1.

export const COR_PDF = {
  texto: '#1D1D1B',
  textoSecundario: '#5F5F5B',
  textoDiscreto: '#6B6B67',
  fio: '#D9D9D6',
  fioForte: '#1D1D1B',
  zebra: '#F6F6F4',
  marca: '#F29725',
  fundo: '#FFFFFF',
} as const;

export const FONTE_PDF = {
  familia: 'Inter',
  /**
   * Caminhos relativos à raiz pública (web/public). Só os pesos que algum estilo usa:
   * 400 e 600. Peso novo exige o .ttf aqui E a métrica em metrica-inter.ts.
   */
  arquivos: [
    { arquivo: 'fonts/Inter-Regular.ttf', peso: 400 },
    { arquivo: 'fonts/Inter-SemiBold.ttf', peso: 600 },
  ],
} as const;

/** A4 paisagem, em pontos (1 pt = 1/72 pol). */
export const MEDIDA_PDF = {
  larguraPagina: 841.89,
  alturaPagina: 595.28,
  margemX: 36,
  /** Espaço reservado ao cabeçalho fixo (logo + título + recorte + fio). */
  margemTopo: 126,
  /** Espaço reservado ao rodapé fixo. */
  margemBase: 40,
  larguraLogo: 92,
  corpo: 7.5,
  alturaLinhaTexto: 1.3,
  celulaPadY: 3.5,
  celulaPadX: 4,
  titulo: 14,
  secao: 9.5,
  rotulo: 6.5,
  kpiValor: 13,
  rodape: 6.5,
} as const;

export const LARGURA_UTIL_PDF = MEDIDA_PDF.larguraPagina - 2 * MEDIDA_PDF.margemX;
export const ALTURA_UTIL_PDF = MEDIDA_PDF.alturaPagina - MEDIDA_PDF.margemTopo - MEDIDA_PDF.margemBase;
