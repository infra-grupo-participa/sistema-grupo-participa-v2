import type { NextConfig } from 'next';
import path from 'node:path';
import { redirectsNext } from './shared/ui/nav/redirects';

const nextConfig: NextConfig = {
  // Raiz do workspace = este diretório (evita ambiguidade com o lockfile legado na raiz do repo).
  turbopack: {
    root: path.join(__dirname),
  },
  // Rotas antigas do Educacional → /educacional/... (308, query preservada). Tabela e motivo em
  // shared/ui/nav/redirects.ts. Rodam ANTES do proxy: link antigo sem sessão vai para a rota nova e só
  // então para o login.
  async redirects() {
    return redirectsNext();
  },
  async headers() {
    return [
      {
        source: '/:path*',
        headers: [
          // CSP conservadora: bloqueia embedding e plugins sem restringir script/style
          // (script-src quebraria os inline scripts do Next; endurecer depois com nonce se necessário).
          { key: 'Content-Security-Policy', value: "frame-ancestors 'none'; object-src 'none'; base-uri 'self'" },
          { key: 'X-Frame-Options', value: 'DENY' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=31536000; includeSubDomains' },
          { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=()' },
        ],
      },
    ];
  },
};

export default nextConfig;
