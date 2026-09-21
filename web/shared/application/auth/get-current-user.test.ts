import { describe, it, expect } from 'vitest';
import { GetCurrentUser } from './get-current-user';
import type { AuthGateway, ProfileRepository } from './ports';
import type { PerfilData } from '@/shared/domain/auth';

// Regressão de 21/09/2026: `auth.users` é compartilhada pelos 7 sistemas do grupo.
// 11.011 logins de aluno/lead não tinham perfil e caíam num usuário mínimo com cargo
// `visualizador` — e `podeVer()` libera visualizador em QUALQUER setor. Resultado
// medido: 188 solicitações de placa (nome, telefone, endereço, documento_nf,
// faturamento) visíveis para quem não é equipe.

const auth = (id: string | null, email = ''): AuthGateway => ({
  getAuthUser: async () => (id ? { id, email } : null),
});
const repo = (perfil: PerfilData | null): ProfileRepository => ({
  findById: async () => perfil,
});

const equipe: PerfilData = {
  id: 'u1', nome: 'Isabela', email: 'isabela@advmais.com', cargo: 'admin', status: 'ativo',
};

describe('GetCurrentUser — porteiro do sistema interno', () => {
  it('sem sessão → null', async () => {
    expect(await new GetCurrentUser(auth(null), repo(null)).execute()).toBeNull();
  });

  it('sessão válida SEM perfil → null (não vira visualizador)', async () => {
    const u = await new GetCurrentUser(auth('u9', 'aluno@gmail.com'), repo(null)).execute();
    expect(u).toBeNull();
  });

  it('perfil ativo fora do domínio da equipe → null', async () => {
    const fora = { ...equipe, id: 'u2', email: 'contato@fornecedor.com' };
    expect(await new GetCurrentUser(auth('u2'), repo(fora)).execute()).toBeNull();
  });

  it('perfil do domínio mas pendente → null', async () => {
    const pend = { ...equipe, status: 'pendente' as const };
    expect(await new GetCurrentUser(auth('u1'), repo(pend)).execute()).toBeNull();
  });

  it('equipe ativa do domínio → entra com o cargo real', async () => {
    const u = await new GetCurrentUser(auth('u1'), repo(equipe)).execute();
    expect(u).not.toBeNull();
    expect(u!.cargo).toBe('admin');
    expect(u!.email).toBe('isabela@advmais.com');
  });
});
