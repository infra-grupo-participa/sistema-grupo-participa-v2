/** Prova de envio do e-mail de confirmação: só `true` explícito conta (undefined = resposta antiga = não confirmado). */
export const emailConfirmado = (r: { email_enviado?: boolean } | null | undefined): boolean => r?.email_enviado === true;

export const EMAIL_CONFIRMADO_TEXTO = 'O link da sala e os detalhes já estão na sua caixa de entrada (confira o spam).';
export const EMAIL_FALHOU_TITULO = 'Não conseguimos enviar o e-mail';
export const EMAIL_FALHOU_TEXTO = 'Guarde o link desta página: ele leva ao seu acompanhamento e ao link da sala.';
