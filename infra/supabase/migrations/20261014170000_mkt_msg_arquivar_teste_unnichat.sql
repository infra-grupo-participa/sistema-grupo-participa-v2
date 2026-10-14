-- 20261014170000: arquiva o disparo 45721 (Unichat, 13/10 15:15, campanha "atm", 322), que foi teste, a pedido do Victor
-- ("esse disparo q vc ta falando foi teste, tira ele do sistema e banco"). Arquivar e não apagar: o gatilho sem_delete
-- bloqueia delete na tabela (registro permanente) e a integração do Unnichat reenvia os mesmos itens a cada 30 min, então
-- uma linha apagada voltaria pela API; arquivada, a API não mexe (api_item devolve "arquivado") e ela some da Mensageria
-- (mkt_msg_disparos_listar) e dos dashboards (dados_atm_resumo filtra arquivado_em is null).
-- Reversão: update mkt_mensageria.disparos set arquivado_em = null, arquivado_motivo = null where id = 45721;
do $g$
begin
  if (select count(*) from mkt_mensageria.disparos where id = 45721 and origem = 'api' and origem_sistema = 'unichat'
       and campanha = 'atm' and tamanho_lista = 322 and arquivado_em is null and projeto_id is null) <> 1 then
    raise exception '20261014170000: o disparo 45721 não está no estado esperado';
  end if;
end
$g$;
update mkt_mensageria.disparos
   set arquivado_em = now(), arquivado_motivo = 'Teste do Unnichat, não é disparo do ATM (Victor, 14/10/2026)'
 where id = 45721 and arquivado_em is null;
