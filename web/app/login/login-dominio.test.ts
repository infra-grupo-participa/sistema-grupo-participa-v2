import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { ehEmailDaEquipe, DOMINIO_EQUIPE } from '@/shared/domain/auth';

const srcBruto = readFileSync(join(__dirname, 'page.tsx'), 'utf-8');
// Comentários citam os nomes por escrito; a ordem tem que ser medida no código real.
const src = srcBruto.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');

// A tela de login é pública. Ela não pode (a) deixar e-mail de fora autenticar,
// nem (b) contar qual é o domínio da equipe para quem está tentando adivinhar.
describe('tela de login — trava de domínio', () => {
  it('checa o domínio ANTES de chamar signInWithPassword', () => {
    const iCheck = src.indexOf('ehEmailDaEquipe(email)');
    const iSignIn = src.indexOf('signInWithPassword');
    expect(iCheck).toBeGreaterThan(-1);
    expect(iSignIn).toBeGreaterThan(-1);
    expect(iCheck).toBeLessThan(iSignIn);
  });

  it('checa o domínio antes de disparar e-mail de recuperação', () => {
    const iCheck = src.indexOf('ehEmailDaEquipe(email)', src.indexOf('async function recuperar'));
    const iReset = src.indexOf('resetPasswordForEmail');
    expect(iCheck).toBeGreaterThan(-1);
    expect(iCheck).toBeLessThan(iReset);
  });

  it('não escreve o domínio da equipe em nenhum texto da tela', () => {
    expect(src).not.toContain(DOMINIO_EQUIPE);
    expect(src.toLowerCase()).not.toContain('advmais');
  });

  it('usa a mesma mensagem para senha errada e domínio recusado', () => {
    // Duas mensagens distintas transformariam a tela num oráculo de domínio.
    const ocorrencias = src.match(/setErro\(ERRO_CREDENCIAL\)/g) ?? [];
    expect(ocorrencias.length).toBe(2);
    expect(src).not.toContain('exclusivo da equipe');
  });

  it('o predicado recusa aluno e aceita equipe', () => {
    expect(ehEmailDaEquipe('renanaffonso@gmail.com')).toBe(false);
    expect(ehEmailDaEquipe('renan@raconsulting.adv.br')).toBe(false);
    expect(ehEmailDaEquipe('isabela@advmais.com')).toBe(true);
  });
});
