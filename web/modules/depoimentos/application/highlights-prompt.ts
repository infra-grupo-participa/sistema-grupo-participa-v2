// Prompt de extração de highlights — porta fiel de processar-highlights.php.

export interface PromptContext {
  alunoNome?: string;
  profissao?: string;
  alunoNivel?: string;
  cidade?: string;
  estado?: string;
  transcript: string;
}

export const HIGHLIGHTS_SYSTEM = `Voce e um analista de conteudo que trabalha com a equipe de copywriting do Grupo Participa.
Sua tarefa e extrair elementos acionaveis de depoimentos de alunos para uso em posts, reels e anuncios.
Responda SEMPRE em JSON valido, em portugues do Brasil, sem markdown, sem texto extra.
Use apenas informacoes presentes na transcricao. Nao invente dados.
Se algum campo nao estiver presente na transcricao, retorne string vazia ou array vazio.`;

export function buildHighlightsUserPrompt(ctx: PromptContext): string {
  const ctxParts: string[] = [];
  if (ctx.alunoNome) ctxParts.push('Nome: ' + ctx.alunoNome);
  if (ctx.profissao) ctxParts.push('Profissao: ' + ctx.profissao);
  if (ctx.alunoNivel) ctxParts.push('Nivel: ' + ctx.alunoNivel);
  const loc = [ctx.cidade, ctx.estado].filter(Boolean).join('/');
  if (loc) ctxParts.push('Localizacao: ' + loc);
  const contexto = ctxParts.length ? ctxParts.join(' | ') : '(sem contexto adicional)';
  const transcript = Array.from(ctx.transcript).slice(0, 30000).join('');

  return `Contexto do aluno: ${contexto}

Transcricao do depoimento:
"""
${transcript}
"""

Retorne um objeto JSON EXATAMENTE neste formato:
{
  "highlights": [
    { "texto": "citacao curta pronta para post (max 280 caracteres)", "tipo": "citacao|objecao|transformacao|gancho" }
  ],
  "objecao": "objecao vencida em 1 frase (ou string vazia)",
  "antes_depois": { "antes": "situacao antes em 1 frase", "depois": "situacao depois em 1 frase" },
  "gancho": "a frase mais forte do depoimento, ideal para abrir um reel (max 200 caracteres)",
  "resumo": "resumo executivo em 1 linha (max 180 caracteres)"
}

Regras:
- Gere entre 3 e 5 highlights.
- Cada highlight deve ser uma frase completa, pronta para copiar e colar em um post.
- Preserve o tom da pessoa (nao reescreva no estilo corporativo).
- Se a pessoa nao mencionar antes/depois, deixe os campos como string vazia.`;
}
