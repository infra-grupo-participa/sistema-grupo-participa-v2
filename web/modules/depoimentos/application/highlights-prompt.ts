// Prompt de extração de highlights — porta fiel de processar-highlights.php.

export interface PromptContext {
  alunoNome?: string;
  profissao?: string;
  alunoNivel?: string;
  cidade?: string;
  estado?: string;
  transcript: string;
}

export const HIGHLIGHTS_SYSTEM = `Você é um analista de conteúdo sênior que trabalha lado a lado com a equipe de copywriting do Grupo Participa.
Sua tarefa é ler o depoimento de um aluno e extrair os trechos mais fortes e acionáveis para virarem posts, reels e anúncios.

Princípios inegociáveis:
- Use SOMENTE informações presentes na transcrição. Nunca invente fatos, números, nomes ou resultados.
- Prefira as PALAVRAS DO PRÓPRIO ALUNO — citações quase literais, em primeira pessoa. Não reescreva no tom corporativo.
- Priorize momentos de carga emocional, virada de chave, objeções vencidas e resultados concretos (números, prazos, valores).
- Se a informação de um campo não existir na transcrição, retorne string vazia ou array vazio — nunca force.
- Responda SEMPRE em JSON válido, em português do Brasil, sem markdown e sem nenhum texto fora do JSON.`;

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
    { "texto": "trecho curto e impactante, de preferência nas palavras do próprio aluno (máx 280 caracteres)", "tipo": "citacao|objecao|transformacao|gancho" }
  ],
  "objecao": "a maior dúvida, medo ou resistência do aluno antes de entrar — e como foi superada, em 1 frase (ou string vazia)",
  "antes_depois": { "antes": "a dor/situação antes do programa em 1 frase", "depois": "o resultado depois em 1 frase, com número ou prazo se houver" },
  "gancho": "a frase mais forte do depoimento para abrir um reel — que prende nos 2 primeiros segundos (máx 200 caracteres)",
  "resumo": "resumo executivo em 1 linha para triagem interna: quem é o aluno + a principal transformação (máx 180 caracteres)",
  "metricas": ["prova numérica concreta dita pelo aluno, ex: 'faturou R$ 50 mil em 3 meses' ou 'saiu de 2 para 15 clientes' (array vazio se não houver)"]
}

Regras:
- Gere entre 3 e 5 highlights, ordenados do mais forte para o menos forte.
- Cada highlight deve ser uma frase completa, pronta para copiar e colar — sem reticências no meio nem cortes que quebrem o sentido.
- Classifique o "tipo" de cada highlight:
  - "gancho": abertura de alto impacto, que prende a atenção;
  - "transformacao": antes/depois ou resultado concreto (números, prazos, valores);
  - "objecao": um medo ou dúvida que foi quebrado;
  - "citacao": elogio ou frase marcante que não se encaixa nos anteriores.
- Preserve o tom e as gírias da pessoa; corrija apenas erros óbvios de transcrição que atrapalhem a leitura.
- Não repita o mesmo trecho em campos diferentes — escolha o melhor lugar para cada ideia.
- Se o aluno citar números (faturamento, tempo, quantidade de clientes/casos), priorize incluí-los: são os trechos mais valiosos para anúncio.
- Em "metricas", liste APENAS números realmente ditos pelo aluno (valores, prazos, quantidades). Nunca estime nem arredonde. Array vazio se não houver.
- Se a pessoa não mencionar antes/depois, deixe os dois campos como string vazia.`;
}
