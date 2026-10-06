// Marketing > Web > Mapa de calor: a conta do desenho (pura). Porte de sistemas/radar/_interface/src/lib/calor.ts do
// Luiz: a mesma escala do frio ao quente, o mesmo raio e a mesma força por quantidade de pontos. O ponto chega do banco
// como x em % da largura e y como FRAÇÃO da altura da página vista (o gravador manda y em px do documento e a altura do
// documento; a 20261006h divide): assim ele cai no lugar certo sobre qualquer fundo (captura do Google ou a página).
// O desenho no canvas fica em ui/MapaCalor.tsx.

/** escala do frio ao quente: azul, ciano, verde, amarelo, laranja, vermelho (ESCALA do calor.ts) */
export const ESCALA: [number, number, number][] = [[37, 84, 232], [18, 150, 204], [21, 146, 90], [250, 204, 21], [234, 88, 12], [210, 59, 59]];

/** cor de 0 a 1 na escala (interpolação linear entre as paradas) */
export function cor(t: number): [number, number, number] {
  const p = Math.max(0, Math.min(1, t)) * (ESCALA.length - 1);
  const k = Math.floor(p);
  const f = p - k;
  const a = ESCALA[k];
  const b = ESCALA[Math.min(k + 1, ESCALA.length - 1)];
  return [a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f];
}

/** força de cada ponto: mais pontos, menos força (para não virar uma mancha só) */
export const forcaPonto = (quantos: number, soRaiva: boolean) => (soRaiva ? 0.5 : quantos > 600 ? 0.14 : quantos > 150 ? 0.2 : 0.28);
/** raio em px da imagem: menor em tela estreita */
export const raioPonto = (largura: number) => (largura < 700 ? 24 : 34);

/** posição do ponto (x %, y fração) numa imagem de largura w e altura h */
export const posicao = (x: number, yf: number, w: number, h: number) => ({ x: (x / 100) * w, y: Math.max(0, Math.min(1, yf)) * h });

/** tipo do ponto vindo do banco: 1 raiva, 2 morto, 3 os dois */
export const ehRaiva = (tipo: number) => (tipo & 1) === 1;
export const ehMorto = (tipo: number) => (tipo & 2) === 2;

/** alcance da rolagem (visitas que chegaram a 0%, 5%, … 100%) em fração de quem abriu */
export const fracaoAlcance = (alcance: number[], i: number) => (alcance[0] ? (alcance[i] ?? 0) / alcance[0] : 0);

/** a altura em que a camada é desenhada: a da captura, na proporção da largura dela; sem captura, a mediana da página */
export function alturaDoFundo(larguraTela: number, captura: { largura: number; altura: number } | null, larguraPagina: number | null, alturaDoc: number | null): number {
  if (captura && captura.largura > 0) return Math.round((larguraTela * captura.altura) / captura.largura);
  if (larguraPagina && alturaDoc) return Math.round((larguraTela * alturaDoc) / larguraPagina);
  return Math.round(larguraTela * 4);
}
