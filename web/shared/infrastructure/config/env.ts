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

// Para uso no browser (apenas chaves públicas NEXT_PUBLIC_*, com fallback de produção).
export const publicEnv = {
  supabaseUrl: process.env.NEXT_PUBLIC_SUPABASE_URL || FALLBACK_SUPABASE_URL,
  supabaseAnonKey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || FALLBACK_SUPABASE_ANON_KEY,
} as const;
