// Entrada do harness: o MensageriaClient real dentro de uma casca igual à do AppShell
// (flex; main com min-w-0 overflow-auto p-4 sm:p-6; sidebar de 264px a partir de md).
import { createRoot } from 'react-dom/client';
import { MensageriaClient } from '@/modules/marketing/mensageria/ui/MensageriaClient';

function Casca() {
  return (
    <div className="flex h-screen flex-col">
      <div className="h-[60px] shrink-0 border-b border-[var(--border)]" />
      <div className="flex min-h-0 flex-1">
        <div className="hidden w-[var(--sidebar-width)] shrink-0 md:block" />
        <main id="main" className="min-w-0 flex-1 overflow-auto bg-[var(--surface-0)] p-4 sm:p-6">
          <MensageriaClient hoje="2026-10-05" nomeUsuario="Teste" />
        </main>
      </div>
    </div>
  );
}

const raiz = document.getElementById('root');
if (raiz) createRoot(raiz).render(<Casca />);
