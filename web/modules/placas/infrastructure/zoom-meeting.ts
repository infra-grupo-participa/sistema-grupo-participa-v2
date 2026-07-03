import type { MeetingProvider } from '../application/ports';
import { logSystemEvent, snippet } from '@/shared/infrastructure/observability/system-events';

// Provedor de reunião Zoom (Server-to-Server OAuth) — porta de confirm-horario.php.
// Não configurado (env ausente) → retorna null e o fluxo segue salvando sem link.
// Toda falha (HTTP, timeout, resposta inesperada) vira evento em thb_system_events
// para a aba Admin Dev — o retorno continua null para não travar o agendamento.
export class ZoomMeetingProvider implements MeetingProvider {
  async createMeeting(input: { topic: string; startIso: string; durationMin: number }) {
    const accountId = process.env.ZOOM_ACCOUNT_ID;
    const clientId = process.env.ZOOM_CLIENT_ID;
    const clientSecret = process.env.ZOOM_CLIENT_SECRET;
    const ctx = { topic: input.topic, start: input.startIso };
    if (!accountId || !clientId || !clientSecret) {
      await logSystemEvent({ tipo: 'warn', fonte: 'zoom', titulo: 'Zoom não configurado — agendamento seguirá sem link', detalhe: ctx });
      return null;
    }

    try {
      const tokenResp = await fetch(
        `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${encodeURIComponent(accountId)}`,
        {
          method: 'POST',
          headers: { Authorization: 'Basic ' + Buffer.from(`${clientId}:${clientSecret}`).toString('base64') },
          signal: AbortSignal.timeout(15000),
        },
      );
      if (!tokenResp.ok) {
        await logSystemEvent({
          tipo: 'error',
          fonte: 'zoom',
          titulo: `Falha no OAuth do Zoom (HTTP ${tokenResp.status})`,
          detalhe: { ...ctx, etapa: 'token', http_status: tokenResp.status, resposta: snippet(await tokenResp.text().catch(() => '')) },
        });
        return null;
      }
      const accessToken = ((await tokenResp.json()) as { access_token?: string }).access_token;
      if (!accessToken) {
        await logSystemEvent({ tipo: 'error', fonte: 'zoom', titulo: 'OAuth do Zoom sem access_token na resposta', detalhe: { ...ctx, etapa: 'token' } });
        return null;
      }

      const meetResp = await fetch('https://api.zoom.us/v2/users/me/meetings', {
        method: 'POST',
        headers: { Authorization: `Bearer ${accessToken}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          topic: input.topic,
          type: 2,
          start_time: input.startIso, // 'Y-m-dTH:i:s'
          duration: input.durationMin,
          timezone: 'America/Sao_Paulo',
          settings: {
            join_before_host: false,
            waiting_room: true,
            mute_upon_entry: true,
            participant_video: true,
            host_video: true,
          },
        }),
        signal: AbortSignal.timeout(15000),
      });
      if (meetResp.status !== 201) {
        await logSystemEvent({
          tipo: 'error',
          fonte: 'zoom',
          titulo: `Falha ao criar reunião no Zoom (HTTP ${meetResp.status})`,
          detalhe: { ...ctx, etapa: 'meeting', http_status: meetResp.status, resposta: snippet(await meetResp.text().catch(() => '')) },
        });
        return null;
      }
      const joinUrl = ((await meetResp.json()) as { join_url?: string }).join_url;
      if (!joinUrl) {
        await logSystemEvent({ tipo: 'error', fonte: 'zoom', titulo: 'Reunião criada mas sem join_url na resposta', detalhe: { ...ctx, etapa: 'meeting' } });
        return null;
      }
      return { joinUrl };
    } catch (err) {
      await logSystemEvent({
        tipo: 'error',
        fonte: 'zoom',
        titulo: 'Exceção ao falar com o Zoom (timeout/rede)',
        detalhe: { ...ctx, erro: snippet(err instanceof Error ? `${err.name}: ${err.message}` : String(err)) },
      });
      return null;
    }
  }
}
