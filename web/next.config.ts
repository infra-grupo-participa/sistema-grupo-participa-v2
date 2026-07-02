import type { NextConfig } from 'next';
import path from 'node:path';

const nextConfig: NextConfig = {
  // Raiz do workspace = este diretório (evita ambiguidade com o lockfile legado na raiz do repo).
  turbopack: {
    root: path.join(__dirname),
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
