-- 20260928z6 — "Seminário ATM" saiu das ações do HM (João, 28/09: "o seminário ATM é do seminário, não tem nada a ver
-- com o Holding Masters"). Os 2 cards que caíam nele compraram pelo link comercial_jonathan (18 e 22/09) e passam a
-- "Comercial (venda direta)". Arquivada (sem janela e sem link), não apagada.
update fin.acoes set inicio = null, fim = null, sck_regex = null,
  fonte = fonte || ' | DESATIVADA 28/09 (João): Seminário ATM é do escritório, não capta aluno do HM'
 where produto = 'HM' and nome = 'Seminário ATM (09/09)' and inicio is not null;
