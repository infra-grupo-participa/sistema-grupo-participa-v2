// Conteúdo dos e-mails transacionais de placa — porta de getEmailContentByStatus (email-template.php).
// Copy de produto preservado 1:1.

export type EmailTipo =
  | 'link_acesso'
  | 'solicitacao_recebida'
  | 'docs_aprovados'
  | 'entrevista_agendada'
  | 'entrevista_finalizada'
  | 'placa_em_caminho'
  | 'placa_recebida'
  | 'retorno_auditoria'
  | 'nivel_registrado'
  | 'lembrete_entrevista'
  | 'nao_compareceu'
  | 'solicitacao_rejeitada';

export interface EmailTemplateData {
  nome?: string;
  titulo: string;
  titulo_cor?: string;
  introducao?: string;
  corpo_extra?: string;
  cta_link?: string;
  cta_label?: string;
  cta_cor?: string;
  pos_cta?: string;
  nota?: string;
}

export interface EmailContent {
  assunto: string;
  templateData: EmailTemplateData;
}

const esc = (s: string) =>
  String(s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

const SECRETARIA_NOTA = 'Em caso de dúvidas, fale com a nossa Secretaria.';
const SECRETARIA_URL = process.env.NEXT_PUBLIC_APP_URL || 'https://grupoparticipa.app.br';

function entrevistaBox(data?: string, hora?: string): string {
  const dataFmt = data ? data.split('-').reverse().join('/') : '';
  const h = (hora ?? '').slice(0, 5);
  if (!dataFmt && !h) return '';
  const label = dataFmt + (h ? ` às ${h}` : '');
  return `<div style="margin:18px 0;padding:16px;border-radius:10px;background:#eff6ff;border:1px solid #93c5fd;"><p style="margin:0 0 6px;font-size:12px;color:#1e40af;text-transform:uppercase;letter-spacing:.04em;font-weight:700">Sua entrevista</p><p style="margin:0;font-size:18px;color:#1e40af;font-weight:800;">📅 ${esc(label)}</p></div>`;
}

function trackingCodeHtml(codigo: string): string {
  if (!codigo) return '';
  return `<div style="margin:16px 0;padding:14px;border-radius:10px;background:#f0fdf4;border:1px solid #86efac;"><p style="margin:0 0 4px;font-size:12px;color:#166534;text-transform:uppercase;letter-spacing:.04em;font-weight:700">Código de rastreio</p><p style="margin:0;font-size:18px;color:#166534;font-weight:800;font-family:monospace">${esc(codigo)}</p></div>`;
}

function motivoBox(motivo: string): string {
  if (!motivo.trim()) return '';
  return `<div style="margin:18px 0;padding:16px;border-radius:10px;background:#fffbeb;border:1px solid #fcd34d;"><p style="margin:0 0 8px;font-size:12px;color:#92400e;text-transform:uppercase;letter-spacing:.04em;font-weight:700">O que precisa ser corrigido</p><p style="margin:0;font-size:14px;color:#78350f;line-height:1.6;white-space:pre-wrap;">${esc(motivo)}</p></div>`;
}

export interface EmailExtra {
  entrevista_data?: string;
  entrevista_hora?: string;
  zoom_link?: string;
  codigo_rastreio?: string;
  motivo_retorno?: string;
}

/**
 * Blocos dinâmicos (caixa de entrevista, código de rastreio, motivo do retorno) por tipo.
 * Injetados no corpo em tempo de envio para preservar o conteúdo variável mesmo quando o admin
 * sobrescreve o corpo do e-mail na tela de configuração.
 */
export function emailDynamicBoxes(tipo: EmailTipo, extra: EmailExtra): string {
  if (tipo === 'entrevista_agendada' || tipo === 'lembrete_entrevista') return entrevistaBox(extra.entrevista_data, extra.entrevista_hora);
  if (tipo === 'placa_em_caminho') return trackingCodeHtml(extra.codigo_rastreio || '');
  if (tipo === 'retorno_auditoria' || tipo === 'solicitacao_rejeitada') return motivoBox(extra.motivo_retorno || '');
  return '';
}

/** Modelo padrão (texto estático, sem os blocos dinâmicos) — usado para pré-preencher a config. */
export function defaultEmailTemplate(tipo: EmailTipo): { assunto: string; introducao: string; corpo_extra: string } {
  const c = getEmailContentByStatus(tipo, {}, '');
  return {
    assunto: c.assunto,
    introducao: c.templateData.introducao || '',
    corpo_extra: c.templateData.corpo_extra || '',
  };
}

export function getEmailContentByStatus(tipo: EmailTipo, extra: EmailExtra, ctaLink: string): EmailContent {
  switch (tipo) {
    case 'link_acesso':
      return {
        assunto: '[Holding Brasil] Seu link para continuar a solicitação de placa',
        templateData: {
          titulo: 'Guarde este link',
          titulo_cor: '#F29725',
          introducao:
            'Você começou a sua solicitação de placa. Este é o seu link pessoal de acesso — com ele, você continua o preenchimento de qualquer dispositivo, de onde parou.',
          corpo_extra:
            '<p>Se trocar de celular ou computador, basta abrir este e-mail e clicar no botão abaixo.</p><p>Você também pode retomar informando seu e-mail e documento na própria página do formulário.</p>',
          cta_link: ctaLink,
          cta_label: 'Continuar minha solicitação',
          nota: SECRETARIA_NOTA,
        },
      };
    case 'solicitacao_recebida':
      return {
        assunto: '[Holding Brasil] Recebemos a sua solicitação de placa',
        templateData: {
          titulo: 'Solicitação recebida',
          titulo_cor: '#F29725',
          introducao:
            'A sua solicitação de placa foi enviada com sucesso e já está na fila de análise da nossa equipe.',
          corpo_extra:
            '<p>Vamos revisar a documentação enviada e você receberá um novo e-mail assim que a análise for concluída.</p><p>Guarde este e-mail: o link abaixo é o seu canal de acompanhamento.</p>',
          cta_link: ctaLink,
          cta_label: 'Acompanhar solicitação',
          nota: SECRETARIA_NOTA,
        },
      };
    case 'placa_recebida':
      return {
        assunto: '[Holding Brasil] Placa entregue — processo concluído 🎉',
        templateData: {
          titulo: 'Processo concluído!',
          titulo_cor: '#16a34a',
          introducao:
            'Confirmamos a entrega da sua placa e o encerramento do processo. Parabéns por essa conquista!',
          corpo_extra:
            '<p>O seu nível foi registrado oficialmente em nosso sistema.</p><p>Adoraríamos celebrar com você: se puder, compartilhe uma foto ou vídeo da placa e marque o Prof. Márcio (<strong>@marciocarvalhodesa</strong>) no Instagram.</p>',
          cta_link: ctaLink,
          cta_label: 'Ver acompanhamento',
          nota: SECRETARIA_NOTA,
        },
      };
    case 'solicitacao_rejeitada':
      return {
        assunto: '[Holding Brasil] Atualização sobre a sua solicitação de placa',
        templateData: {
          titulo: 'Solicitação não aprovada',
          titulo_cor: '#dc2626',
          introducao:
            'Após análise da nossa equipe, a sua solicitação de placa não pôde ser aprovada neste momento.',
          corpo_extra:
            motivoBox(extra.motivo_retorno || '') +
            '<p>Se você acredita que houve um engano ou quiser entender os critérios, fale com a nossa Secretaria — teremos prazer em orientar os próximos passos.</p>',
          cta_link: ctaLink,
          cta_label: 'Falar com a Secretaria',
          cta_cor: '#dc2626',
        },
      };
    case 'docs_aprovados':
      return {
        assunto: '[Holding Brasil] Documentação validada — agende sua entrevista',
        templateData: {
          titulo: 'Documentação validada',
          titulo_cor: '#16a34a',
          introducao:
            'Temos o prazer de informar que nossa equipe revisou e validou a sua documentação. O próximo passo é agendar a sua entrevista.',
          corpo_extra:
            '<p>Acesse o link abaixo para escolher o melhor horário disponível.</p><p>Após a entrevista, enviaremos uma nova mensagem com os próximos passos.</p>',
          cta_link: ctaLink,
          cta_label: 'Agendar entrevista',
          nota: 'Para consultar a sua solicitação, utilize este mesmo link.',
        },
      };
    case 'entrevista_agendada':
      return {
        assunto: '[Holding Brasil] Entrevista agendada — link de acesso',
        templateData: {
          titulo: 'Entrevista agendada',
          titulo_cor: '#2D8CFF',
          introducao:
            'A sua entrevista com o time Holding Brasil está confirmada. Use o link abaixo para entrar na sala no horário marcado.',
          corpo_extra:
            entrevistaBox(extra.entrevista_data, extra.entrevista_hora) +
            '<p>Recomendamos entrar alguns minutos antes, em um local tranquilo e com boa conexão de internet.</p>',
          cta_link: extra.zoom_link || ctaLink,
          cta_label: 'Acessar sala (Zoom)',
          cta_cor: '#2D8CFF',
          nota: SECRETARIA_NOTA,
        },
      };
    case 'entrevista_finalizada':
      return {
        assunto: '[Holding Brasil] Entrevista realizada — próximos passos',
        templateData: {
          titulo: 'Entrevista realizada',
          titulo_cor: '#16a34a',
          introducao: 'Temos o prazer de informar que a sua entrevista foi registrada pela nossa equipe.',
          corpo_extra:
            '<p>A sua solicitação avançou para a etapa de entrega.</p><p>Assim que houver uma atualização, enviaremos uma nova mensagem com as informações de acompanhamento.</p>',
          cta_link: ctaLink,
          cta_label: 'Acompanhar solicitação',
        },
      };
    case 'placa_em_caminho': {
      const orientacoes = `<div style="margin:18px 0;padding:16px;border-radius:10px;background:#fffbeb;border:1px solid #fde68a;"><p style="margin:0 0 8px;font-size:12px;color:#92400e;text-transform:uppercase;letter-spacing:.04em;font-weight:700">Orientações importantes</p><ul style="margin:0;padding-left:20px;font-size:14px;color:#78350f;line-height:1.7;"><li>Certifique-se de que haverá alguém no local para receber a encomenda em horário comercial.</li><li>Avise-nos assim que a placa chegar, ou se notar qualquer intercorrência. <a href="${SECRETARIA_URL}" target="_blank" style="color:#92400e;text-decoration:underline;">Fale com a Secretaria</a>.</li></ul></div>`;
      const posCta =
        '<p style="margin-top:18px">Adoraríamos celebrar essa conquista com você! Quando receber, se possível, registre a entrega ou o <em>unboxing</em> em vídeo e compartilhe conosco. Se postar no Instagram, marque também o Prof. Márcio (<strong>@marciocarvalhodesa</strong>).</p>';
      return {
        assunto: 'Sua placa já está a caminho! 🚚 | Código de Rastreamento',
        templateData: {
          titulo: 'Sua placa já está a caminho!',
          titulo_cor: '#16a34a',
          introducao:
            'Temos o prazer de informar que a sua placa já foi postada e está a caminho do seu endereço!',
          corpo_extra:
            '<p>Para acompanhar a entrega, utilize os dados abaixo:</p>' +
            trackingCodeHtml(extra.codigo_rastreio || '') +
            '<p>Este é o símbolo de um grande marco na sua jornada, e estamos muito felizes em fazer parte desse momento.</p>' +
            orientacoes,
          cta_link: ctaLink,
          cta_label: 'Acompanhar solicitação',
          pos_cta: posCta,
        },
      };
    }
    case 'retorno_auditoria': {
      const motivoHtml = motivoBox(extra.motivo_retorno || '');
      return {
        assunto: '[Holding Brasil] Pendência na sua solicitação',
        templateData: {
          titulo: 'Pendência na solicitação',
          titulo_cor: '#d97706',
          introducao: 'A nossa equipe revisou a sua solicitação e identificou pontos que precisam ser ajustados.',
          corpo_extra: motivoHtml + '<p>Acesse o link abaixo para revisar e corrigir os dados indicados.</p>',
          cta_link: ctaLink,
          cta_label: 'Revisar solicitação',
          cta_cor: '#d97706',
          nota: 'Após corrigir, reenvie para que possamos dar continuidade.',
        },
      };
    }
    case 'nivel_registrado':
      return {
        assunto: '[Holding Brasil] Nível registrado',
        templateData: {
          titulo: 'Nível registrado',
          titulo_cor: '#16a34a',
          introducao: 'Temos o prazer de informar que os seus dados foram registrados pela nossa equipe.',
          corpo_extra:
            '<p>Os seus dados estão salvos. Caso haja alteração futura no seu nível, você poderá retomar o processo pelo mesmo link.</p>',
          cta_link: ctaLink,
          cta_label: 'Acompanhar solicitação',
        },
      };
    case 'lembrete_entrevista': {
      const dataFmt = extra.entrevista_data ? extra.entrevista_data.split('-').reverse().join('/') : '';
      const hora = (extra.entrevista_hora ?? '').slice(0, 5);
      const dataLabel = dataFmt ? ` em ${dataFmt}` : '';
      const horario = hora ? ` às ${hora}` : '';
      return {
        assunto: '[Holding Brasil] Sua entrevista começa em 4 horas',
        templateData: {
          titulo: 'Lembrete de entrevista',
          titulo_cor: '#1e40af',
          introducao: `A sua entrevista com o time Holding Brasil está agendada para hoje${dataLabel}${horario}. Faltam aproximadamente 4 horas.`,
          corpo_extra:
            entrevistaBox(extra.entrevista_data, extra.entrevista_hora) +
            '<p>Certifique-se de estar em um local tranquilo, com boa conexão de internet.</p>' +
            '<p>O link de acesso à sala foi enviado no e-mail de confirmação do agendamento.</p>',
          cta_link: ctaLink,
          cta_label: 'Ver detalhes da entrevista',
          cta_cor: '#1e40af',
          nota: SECRETARIA_NOTA,
        },
      };
    }
    case 'nao_compareceu':
      return {
        assunto: '[Holding Brasil] Entrevista não realizada — reagendamento disponível',
        templateData: {
          titulo: 'Entrevista não realizada',
          titulo_cor: '#d97706',
          introducao: 'Não registramos a sua presença na entrevista agendada.',
          corpo_extra:
            '<p>O agendamento foi cancelado. Você pode escolher um novo horário pelo link abaixo.</p><p>Acesse e selecione a data mais conveniente.</p>',
          cta_link: ctaLink,
          cta_label: 'Reagendar entrevista',
          cta_cor: '#d97706',
          nota: SECRETARIA_NOTA,
        },
      };
  }
}
