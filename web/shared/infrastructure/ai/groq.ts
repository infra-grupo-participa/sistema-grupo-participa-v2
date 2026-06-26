// Cliente Groq (OpenAI-compatible) — porta da chamada de processar-highlights.php.

export interface GroqChatResult {
  status: number;
  retryAfter: string;
  content: string;
  upstreamMessage: string;
  error?: string;
}

export async function groqChatJson(opts: {
  apiKey: string;
  model: string;
  system: string;
  user: string;
  temperature?: number;
  maxTokens?: number;
}): Promise<GroqChatResult> {
  try {
    const resp = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${opts.apiKey}`, 'Content-Type': 'application/json', Accept: 'application/json' },
      body: JSON.stringify({
        model: opts.model,
        temperature: opts.temperature ?? 0.2,
        max_tokens: opts.maxTokens ?? 1200,
        response_format: { type: 'json_object' },
        messages: [
          { role: 'system', content: opts.system },
          { role: 'user', content: opts.user },
        ],
      }),
      signal: AbortSignal.timeout(90000),
    });
    const retryAfter = resp.headers.get('retry-after') ?? '';
    const json = (await resp.json().catch(() => null)) as Record<string, unknown> | null;
    const upstreamMessage =
      (json?.error as Record<string, unknown> | undefined)?.message != null
        ? String((json!.error as Record<string, unknown>).message)
        : String((json as Record<string, unknown>)?.message ?? '');
    const content = String(
      ((json?.choices as unknown[])?.[0] as Record<string, unknown> | undefined)?.message != null
        ? ((((json!.choices as unknown[])[0] as Record<string, unknown>).message as Record<string, unknown>).content ?? '')
        : '',
    );
    return { status: resp.status, retryAfter, content, upstreamMessage };
  } catch (e) {
    return { status: 0, retryAfter: '', content: '', upstreamMessage: '', error: String(e) };
  }
}
