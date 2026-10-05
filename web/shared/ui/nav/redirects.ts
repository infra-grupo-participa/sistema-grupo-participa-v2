// Rotas antigas do Educacional → rotas novas (modularização por departamento, 05/10/2026).
//
// 🔴 NUNCA APAGAR uma entrada. Mensagens de Slack já enviadas pela Remoção de Acessos apontam para
// `/relatorios/remocoes?caso=<id>` (montadas no banco a partir de `ra_config.app_url`, ver
// infra/supabase/migrations/20260916_remocao_acessos*.sql), além de favoritos e e-mails antigos.
//
// Aplicada pelo `redirects()` do `web/next.config.ts` como 308 (permanente). O Next preserva a query string
// (`?caso=`) sozinho; o `#hash` (ex.: `#aluno=…`, `#board`) nem chega ao servidor e o navegador o mantém.
// Este arquivo não importa nada (nem alias `@/`): o next.config o carrega fora do bundler.

export interface RotaAntiga {
  /** Caminho antigo, exato. */
  de: string;
  /** Caminho novo. */
  para: string;
}

export const REDIRECTS_EDUCACIONAL: RotaAntiga[] = [
  { de: '/sistema/alunos', para: '/educacional/alunos' },
  { de: '/sistema/pedidos-alteracao', para: '/educacional/pedidos-alteracao' },
  { de: '/relatorios/placas', para: '/educacional/placas' },
  { de: '/relatorios/financeiro', para: '/educacional/financeiro' },
  { de: '/relatorios/remocoes', para: '/educacional/remocoes' },
  { de: '/depoimentos', para: '/educacional/depoimentos' },
  { de: '/depoimentos/biblioteca', para: '/educacional/depoimentos/biblioteca' },
];

/** Formato do `redirects()` do Next. `permanent: true` = 308. */
export function redirectsNext() {
  return REDIRECTS_EDUCACIONAL.map((r) => ({ source: r.de, destination: r.para, permanent: true as const }));
}

/**
 * Para onde vai uma URL antiga (caminho + query + hash), do mesmo jeito que o Next faz: troca só o caminho,
 * mantém `?query` e `#hash`. Usado nos testes e para conferir à mão. URL sem entrada: null.
 */
export function destinoDaRotaAntiga(url: string): string | null {
  const m = url.match(/^([^?#]*)(.*)$/);
  const caminho = (m?.[1] || '/').replace(/\/$/, '') || '/';
  const resto = m?.[2] || '';
  const r = REDIRECTS_EDUCACIONAL.find((x) => x.de === caminho);
  return r ? r.para + resto : null;
}
