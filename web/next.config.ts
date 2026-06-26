import type { NextConfig } from 'next';
import path from 'node:path';

const nextConfig: NextConfig = {
  // Raiz do workspace = este diretório (evita ambiguidade com o lockfile legado na raiz do repo).
  turbopack: {
    root: path.join(__dirname),
  },
};

export default nextConfig;
