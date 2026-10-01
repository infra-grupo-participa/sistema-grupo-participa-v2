import type { MeetingProvider } from '../application/ports';
import { logSystemEvent, snippet } from '@/shared/infrastructure/observability/system-events';

// Provedor de reunião Zoom (Server-to-Server OAuth) — porta de confirm-horario.php.
// Não configurado (env ausente) → retorna null e o fluxo segue salvando sem link.
// Toda falha (HTTP, timeout, resposta inesperada) vira evento em thb_system_events
// para a aba Admin Dev — o retorno continua null/false para não travar o agendamento.

export interface ZoomMeeting {
  joinUrl: string;
  /** Id da reunião no Zoom (string: o id numérico pode passar de 2^31). Necessário para apagar a sala. */
  meetingId: string | null;
}

const TIMEOUT_MS = 15000;

export class ZoomMeetingProvider implements MeetingProvider {
  /** OAuth account_credentials. Falha já vira evento; devolve null. Exceção sobe para o chamador. */
  private async accessToken(ctx: Record<string, unknown>, ev: { warnNaoConfigurado: string }): Promise<string | null> {
    const accountId = process.env.ZOOM_ACCOUNT_ID;
    const clientId = process.env.ZOOM_CLIENT_ID;
    const clientSecret = process.env.ZOOM_CLIENT_SECRET;
    if (!accountId || !clientId || !clientSecret) {
      await logSystemEvent({ tipo: 'warn', fonte: 'zoom', titulo: ev.warnNaoConfigurado, detalhe: ctx });
      return null;
    }
    const tokenResp = await fetch(
      `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${encodeURIComponent(accountId)}`,
      {
        method: 'POST',
        headers: { Authorization: 'Basic ' + Buffer.from(`${clientId}:${clientSecret}`).toString('base64') },
        signal: AbortSignal.timeout(TIMEOUT_MS),
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
    return accessToken;
  }

  /** Cria a reunião. Retorno compatível com o formato antigo ({ joinUrl }) + `meetingId`. */
  async createMeeting(input: { topic: string; startIso: string; durationMin: number }): Promise<ZoomMeeting | null> {
    // Sem o topic: ele carrega o nome do candidato e o ctx vai para thb_system_events.
    const ctx = { start: input.startIso };
    try {
      const accessToken = await this.accessToken(ctx, { warnNaoConfigurado: 'Zoom não configurado — agendamento seguirá sem link' });
      if (!accessToken) return null;

      // Anfitrião: ZOOM_HOST_USER (e-mail ou userId do Zoom) ou o dono do app S2S ('me').
      const host = encodeURIComponent(process.env.ZOOM_HOST_USER || 'me');
      const meetResp = await fetch(`https://api.zoom.us/v2/users/${host}/meetings`, {
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
        signal: AbortSignal.timeout(TIMEOUT_MS),
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
      const body = (await meetResp.json()) as { join_url?: string; id?: number | string };
      const joinUrl = body.join_url;
      if (!joinUrl) {
        await logSystemEvent({ tipo: 'error', fonte: 'zoom', titulo: 'Reunião criada mas sem join_url na resposta', detalhe: { ...ctx, etapa: 'meeting' } });
        return null;
      }
      const meetingId = body.id === undefined || body.id === null || body.id === '' ? null : String(body.id);
      if (!meetingId) {
        // Link funciona; só não será possível apagar a sala num reagendamento.
        await logSystemEvent({ tipo: 'warn', fonte: 'zoom', titulo: 'Reunião criada sem id na resposta — sala não poderá ser apagada', detalhe: { ...ctx, etapa: 'meeting' } });
      }
      return { joinUrl, meetingId };
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

  /**
   * Apaga a reunião (reagendamento/cancelamento). 204 e 404 (já não existe) contam como ok.
   * Nunca lança: falha vira evento e devolve false.
   */
  async deleteMeeting(meetingId: string): Promise<boolean> {
    const id = String(meetingId ?? '').trim();
    const ctx = { meeting_id: id, etapa: 'delete' };
    if (!/^\d+$/.test(id)) {
      await logSystemEvent({ tipo: 'error', fonte: 'zoom', titulo: 'Id de reunião inválido para apagar no Zoom', detalhe: ctx });
      return false;
    }
    try {
      const accessToken = await this.accessToken(ctx, { warnNaoConfigurado: 'Zoom não configurado — sala antiga não foi apagada' });
      if (!accessToken) return false;

      const resp = await fetch(`https://api.zoom.us/v2/meetings/${encodeURIComponent(id)}`, {
        method: 'DELETE',
        headers: { Authorization: `Bearer ${accessToken}` },
        signal: AbortSignal.timeout(TIMEOUT_MS),
      });
      if (resp.ok || resp.status === 404) return true;
      await logSystemEvent({
        tipo: 'error',
        fonte: 'zoom',
        titulo: `Falha ao apagar reunião no Zoom (HTTP ${resp.status})`,
        detalhe: { ...ctx, http_status: resp.status, resposta: snippet(await resp.text().catch(() => '')) },
      });
      return false;
    } catch (err) {
      await logSystemEvent({
        tipo: 'error',
        fonte: 'zoom',
        titulo: 'Exceção ao apagar reunião no Zoom (timeout/rede)',
        detalhe: { ...ctx, erro: snippet(err instanceof Error ? `${err.name}: ${err.message}` : String(err)) },
      });
      return false;
    }
  }
}
