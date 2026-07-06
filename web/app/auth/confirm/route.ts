import { type NextRequest, NextResponse } from 'next/server';
import type { EmailOtpType } from '@supabase/supabase-js';
import { createServerSupabase } from '@/shared/infrastructure/supabase/server-client';

// Porta de entrada do link de acesso: valida o token_hash (invite/recovery),
// grava a sessão nos cookies via verifyOtp e leva a pessoa para definir a senha.
const ALLOWED_TYPES: EmailOtpType[] = ['invite', 'recovery', 'magiclink'];

/** Só destinos internos (evita open redirect). */
function safeNext(next: string | null): string {
  if (!next || !next.startsWith('/') || next.startsWith('//')) return '/definir-senha';
  return next;
}

export async function GET(request: NextRequest) {
  const { searchParams, origin } = new URL(request.url);
  const tokenHash = searchParams.get('token_hash');
  const type = searchParams.get('type') as EmailOtpType | null;
  const next = safeNext(searchParams.get('next'));

  const invalido = NextResponse.redirect(new URL('/login?erro=link_invalido', origin));
  if (!tokenHash || !type || !ALLOWED_TYPES.includes(type)) return invalido;

  const supabase = await createServerSupabase();
  const { error } = await supabase.auth.verifyOtp({ type, token_hash: tokenHash });
  if (error) return invalido;

  return NextResponse.redirect(new URL(next, origin));
}
