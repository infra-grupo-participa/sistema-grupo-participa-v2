import type { MeetingProvider } from '../application/ports';

// Provedor de reunião Zoom (Server-to-Server OAuth) — porta de confirm-horario.php.
// Não configurado (env ausente) → retorna null e o fluxo segue salvando sem link.
export class ZoomMeetingProvider implements MeetingProvider {
  async createMeeting(input: { topic: string; startIso: string; durationMin: number }) {
    const accountId = process.env.ZOOM_ACCOUNT_ID;
    const clientId = process.env.ZOOM_CLIENT_ID;
    const clientSecret = process.env.ZOOM_CLIENT_SECRET;
    if (!accountId || !clientId || !clientSecret) return null;

    try {
      const tokenResp = await fetch(
        `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${encodeURIComponent(accountId)}`,
        {
          method: 'POST',
          headers: { Authorization: 'Basic ' + Buffer.from(`${clientId}:${clientSecret}`).toString('base64') },
          signal: AbortSignal.timeout(15000),
        },
      );
      if (!tokenResp.ok) return null;
      const accessToken = ((await tokenResp.json()) as { access_token?: string }).access_token;
      if (!accessToken) return null;

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
      if (meetResp.status !== 201) return null;
      const joinUrl = ((await meetResp.json()) as { join_url?: string }).join_url;
      return joinUrl ? { joinUrl } : null;
    } catch {
      return null;
    }
  }
}
