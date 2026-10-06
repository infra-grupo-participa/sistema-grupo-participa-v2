// Acesso tipado e centralizado a variáveis de ambiente.
// Único ponto que lê process.env — facilita validação e troca de provedor.

function required(name: string, value: string | undefined): string {
  if (!value) throw new Error(`Variável de ambiente ausente: ${name}`);
  return value;
}

export const env = {
  supabase: {
    url: process.env.NEXT_PUBLIC_SUPABASE_URL ?? '',
    anonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ?? '',
    get serviceRoleKey() {
      return required('SUPABASE_SERVICE_ROLE_KEY', process.env.SUPABASE_SERVICE_ROLE_KEY);
    },
    /**
     * Segredo JWT (HS256, "legacy JWT secret" do projeto) — SÓ servidor. Usado apenas pelo MCP do Comercial
     * (`/api/mcp`) para assinar um JWT curto (5 min) do PRÓPRIO dono do token, para chamar as RPCs crm_* sob RLS.
     * Ausente = o MCP responde 503 (o resto do app não usa).
     */
    get jwtSecret() {
      return required('SUPABASE_JWT_SECRET', process.env.SUPABASE_JWT_SECRET);
    },
  },
  app: {
    environment: process.env.APP_ENV ?? 'development',
    allowedOrigins: (process.env.APP_ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  },
} as const;

// Fallback de PRODUÇÃO para a config pública do Supabase.
// A anon key é pública por design (protegida por RLS) — o legado config.js também a
// embutia. Isto garante que o app funcione mesmo se o build não receber NEXT_PUBLIC_*.
// Para homologação, basta definir as env vars (têm prioridade sobre o fallback).
const FALLBACK_SUPABASE_URL = 'https://mbvybujpkwuorhtdzcde.supabase.co';
const FALLBACK_SUPABASE_ANON_KEY =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1idnlidWpwa3d1b3JodGR6Y2RlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE2Nzk5MjYsImV4cCI6MjA4NzI1NTkyNn0.02UmV0FaJ4O8AaUOEjkKWlVfWKt1y0Nr8afcKRmUE0I';

/** Fonte de dados do CRM Comercial: demonstração em memória ou banco real. Valor ausente/inválido = 'mock'. */
export type ComercialFonte = 'mock' | 'supabase';
export function lerComercialFonte(v: string | undefined): ComercialFonte {
  return v?.trim().toLowerCase() === 'supabase' ? 'supabase' : 'mock';
}

/** Flag booleana de env: só 'true', '1', 'sim' ou 'on' ligam. Ausente/qualquer outro valor = desligada. */
export function lerFlag(v: string | undefined): boolean {
  return ['true', '1', 'sim', 'on'].includes(v?.trim().toLowerCase() ?? '');
}

// Para uso no browser (apenas chaves públicas NEXT_PUBLIC_*, com fallback de produção).
// NEXT_PUBLIC_* é embutido no build: mudar pede rebuild.
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL || FALLBACK_SUPABASE_URL,
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || FALLBACK_SUPABASE_ANON_KEY,
  comercialFonte: lerComercialFonte(process.env.NEXT_PUBLIC_COMERCIAL_FONTE),
  /**
   * Libera o departamento Comercial para quem é do Comercial (gestor com área `comercial` e vendedor com área
   * `comercial` + função `comercial.vender`), além de admin/dev. Padrão DESLIGADO (só admin/dev entram).
   * Ligar só com NEXT_PUBLIC_COMERCIAL_FONTE=supabase (no modo demonstração o vendedor veria dados fictícios).
   */
  comercialVendedores: lerFlag(process.env.NEXT_PUBLIC_COMERCIAL_VENDEDORES),
} as const;
