-- 20261004m — Conciliação, decisões do João (01/10/2026): "sim, executa" no plano de fechamento.
--  0. trg_aluno_retornou não reativa ficha ARQUIVADA (cancelado_origem 'arquivo:%'): arquivar tem que ser estável.
--  1. Duplicatas: fica a ficha com o login mais recente (auth.users.last_sign_in_at); a outra é arquivada
--     (cancelado_em, nunca apagada). Fichas de teste (ddd1c3e8 e o sócio de teste 9d532b23) também.
--  2. Revogações A (renovação reembolsada), B (sócio sem titular, compra vencida), C (compra reembolsada):
--     aplica a proposta, salvo pagamento do programa (HM/Aurum/Diamante) aprovado nos últimos 12 meses.
--     valor_total fica como histórico do contrato.
--  3. G: sócio de titular vencido vence junto, salvo pagamento do titular ou do sócio nos últimos 12 meses.
--  4. b17de93b: expirou e segue a_vencer → vencido, salvo pagamento depois da expiração anterior.
--  5. C8: turma_id é a turma de ENTRADA: troca só quando a data de entrada cai na coorte declarada e fora da coorte da ficha.
--  6. E (juros a confirmar): aplica a base sem juros quando o dinheiro que entrou no ciclo cobre o preço; aí fica quitado.
-- Regras: só ficha ativa; update só se o valor atual não mudou; valor anterior em cruzamentos_correcoes. Sem PII (repo público).
create or replace function public.trg_aluno_retornou()
 returns trigger language plpgsql as $f$
begin
  if old.cancelado_em is not null
     and coalesce(old.cancelado_origem, '') not like 'arquivo:%'
     and new.situacao_financeira is distinct from 'cancelado'
     and coalesce(new.data_expiracao, current_date) >= current_date then
    new.retornou_em      := now();
    new.cancelado_em     := null;
    new.cancelado_origem := null;
  end if;
  return new;
end;
$f$;

create function pg_temp._conc_pagou(p uuid, desde timestamptz default now() - interval '12 months') returns boolean
 language sql stable as $f$
  select exists (select 1 from public.thb_alunos a
                   join (select * from fin.hotmart_transacoes where conta = 'academy') t on lower(t.comprador_email) = lower(trim(a.email))
                   join fin.produtos pr on pr.produto_id = t.produto_id
                  where a.id = p and t.status in ('APPROVED', 'COMPLETE')
                    and pr.familia in ('HM', 'AURUM', 'PROGRAMA_DIAMANTE') and t.aprovado_em > desde)
$f$;

create temp table _abc (aluno_id uuid, campo text, atual text, novo text, cl text) on commit drop;
insert into _abc values
('a524f128-d6c5-4bb3-b8b1-939613e99fbe'::uuid,'situacao_acesso','em_dia','vencido','A'),
('a524f128-d6c5-4bb3-b8b1-939613e99fbe'::uuid,'status_acesso','renovado','vencido','A'),
('a524f128-d6c5-4bb3-b8b1-939613e99fbe'::uuid,'status_acesso_central','Ativo','Vencido','A'),
('a524f128-d6c5-4bb3-b8b1-939613e99fbe'::uuid,'data_expiracao','2027-01-29','2025-12-31','A'),
('9b7aa845-2bc5-4414-b76a-0ca34da68041'::uuid,'situacao_acesso','em_dia','vencido','A'),
('9b7aa845-2bc5-4414-b76a-0ca34da68041'::uuid,'status_acesso','renovado','vencido','A'),
('9b7aa845-2bc5-4414-b76a-0ca34da68041'::uuid,'status_acesso_central','Ativo','Vencido','A'),
('9b7aa845-2bc5-4414-b76a-0ca34da68041'::uuid,'data_expiracao','2027-01-05','2025-12-31','A'),
('56703125-844a-4fbb-9e20-f9fe0b91aa0e'::uuid,'situacao_acesso','em_dia','vencido','A'),
('56703125-844a-4fbb-9e20-f9fe0b91aa0e'::uuid,'status_acesso','vigente','vencido','A'),
('56703125-844a-4fbb-9e20-f9fe0b91aa0e'::uuid,'status_acesso_central','Ativo','Vencido','A'),
('56703125-844a-4fbb-9e20-f9fe0b91aa0e'::uuid,'data_expiracao','2026-11-21','2025-12-31','A'),
('9243aa67-299c-45ae-9a59-1b1bf1867834'::uuid,'situacao_acesso','acompanha_titular','vencido','B'),
('9243aa67-299c-45ae-9a59-1b1bf1867834'::uuid,'status_acesso_central','Acompanha titular','Vencido','B'),
('8ad297e5-481d-4cb4-a678-7708a756884a'::uuid,'situacao_acesso','acompanha_titular','vencido','B'),
('8ad297e5-481d-4cb4-a678-7708a756884a'::uuid,'status_acesso_central','Acompanha titular','Vencido','B'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'situacao_acesso','em_dia','sem_acesso','C'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'situacao_financeira','quitado','reembolsado','C'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'status_pagamento','Quitado','Reembolsado','C'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'valor_pago','2000','0','C'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'data_expiracao','2027-06-08','2026-06-08','C'),
('495f430b-6309-49cf-acf2-73c811fc0725'::uuid,'status_acesso_central','Ativo','fora_central_acessos_2026','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'situacao_acesso','em_dia','sem_acesso','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'situacao_financeira','quitado','reembolsado','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'status_pagamento','Quitado','Reembolsado','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'valor_pago','2000','0','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'data_expiracao','2027-06-08','2026-06-08','C'),
('94995b42-8071-43f0-879f-d2a5296cbae0'::uuid,'status_acesso_central','Ativo','fora_central_acessos_2026','C'),
('4c3961fc-95ae-4c50-9692-cf06b4c2d114'::uuid,'situacao_acesso','em_dia','sem_acesso','C'),
('4c3961fc-95ae-4c50-9692-cf06b4c2d114'::uuid,'situacao_financeira','quitado','reembolsado','C'),
('4c3961fc-95ae-4c50-9692-cf06b4c2d114'::uuid,'status_pagamento','Quitado','Reembolsado','C'),
('4c3961fc-95ae-4c50-9692-cf06b4c2d114'::uuid,'valor_pago','1200295','0','C'),
('4c3961fc-95ae-4c50-9692-cf06b4c2d114'::uuid,'data_expiracao','2027-09-02','2026-09-02','C');
-- G: (sócio, titular). Troca acompanha_titular→vencido, vigente/renovado→vencido, 'Acompanha titular'→'Vencido'.
create temp table _g (socio_id uuid, titular_id uuid) on commit drop;
insert into _g values
('006fde35-cd5d-49ab-89bb-eb6d3f3d9124'::uuid,'0e7ed2bb-91b6-43d9-99a0-44377c4ced88'::uuid),
('048870c4-e0dc-4af2-bb11-a9fa6a69063a'::uuid,'f7f09114-414d-4573-8e11-c08a372c90db'::uuid),
('05f4cdc1-4276-4261-9566-1606983016ce'::uuid,'ced63591-b4da-4f5d-9bce-486eea9a507b'::uuid),
('0634614e-b964-45c8-b57e-ef81e9a32c31'::uuid,'2a56c770-d904-4204-bfcd-5e372a01d3f2'::uuid),
('064ba908-81a4-44a6-9c29-562bd03fead5'::uuid,'211de797-a4af-46ab-bc44-26fd92ed3084'::uuid),
('06ee094b-c778-4ae6-a3a5-b0a516f21854'::uuid,'f9d24de7-2cb4-4d56-99a9-5a169aad3374'::uuid),
('09033662-fd47-48e2-9ba3-2843d7719f80'::uuid,'7903a203-3c8e-47e8-822a-0ccaf5cef3b1'::uuid),
('0b31eb10-6eb5-415b-9993-5f5ec74cfd79'::uuid,'dc8e037d-77ac-4a88-8cd9-69ee3b360768'::uuid),
('0b92919d-72c7-4ed5-9dd2-5d79d80442d1'::uuid,'1d5f3dc7-389e-4983-93bb-3a88e5178d7c'::uuid),
('0da014b5-0162-49b4-b1d5-77d4019dcbc0'::uuid,'18087f01-41fe-4979-a812-82cbd868d8f5'::uuid),
('163ce13c-94da-4fee-b0d9-58b06569e77f'::uuid,'774a14e5-3748-4c39-8af6-6b64132567ce'::uuid),
('16e8b77d-14ff-4527-9479-ded2f116e29b'::uuid,'7ea65d73-a7e4-4e41-aeb4-f62b50b91ed2'::uuid),
('17549a8e-3aa1-4edc-8b6e-acf470e46d91'::uuid,'1881f2ca-ef56-4311-b62d-45792f158b10'::uuid),
('1e80137c-369d-4ffe-9a67-bf1c3a0b17d7'::uuid,'2699be4f-70ee-4578-aea5-5153395a2dbc'::uuid),
('223d160a-961b-4a4c-a8d6-188599a53467'::uuid,'d02c0c21-3999-46bf-aaa2-4437e5bd5355'::uuid),
('2bf00075-eb03-452f-8e50-3db9368f27da'::uuid,'6f54dea5-34bc-4c4b-a135-c22d0659aebc'::uuid),
('3073c92c-d5f0-4194-ab74-4c83d7dfa8ba'::uuid,'cb67828a-d3eb-4833-8aa5-2e18b9f9f2cc'::uuid),
('30b87d06-0e0d-43d8-9741-0d023efca7e2'::uuid,'09a95950-6489-4ec0-9a24-af6131ec3a2d'::uuid),
('31cb7e7f-63c8-4670-97fa-3b262d49c015'::uuid,'e53cc0fa-6456-486e-acce-ac5b563832df'::uuid),
('33931a03-c877-4de2-a254-26e100e877ba'::uuid,'c526f92c-f65d-46ab-88fe-3157027c5b47'::uuid),
('36db231b-ad34-4f77-9fe8-8646fc84a7da'::uuid,'10edf7e7-f4f9-4b37-8e4c-3bddc3544502'::uuid),
('396334b7-f67a-4665-8e6a-0b53f5c3e49f'::uuid,'1af7b08c-54bb-4920-a980-09440cc76f18'::uuid),
('3cc16d43-f31c-47d5-8478-a978c4472eab'::uuid,'f496284a-08fe-419b-9409-d02086a8cdd1'::uuid),
('3f3e4cb1-e954-4a18-9fcb-f97fc4b9d0dd'::uuid,'0575b11f-dc80-4fe9-b553-ee9e414e2858'::uuid),
('3fc42546-2b75-4c9a-b879-2b33b82f4450'::uuid,'e2dca730-adc2-4fa1-ae69-f83547a88736'::uuid),
('46e8e849-0265-453d-be23-ffaab0021f9c'::uuid,'6986c518-9d2a-4873-bf37-dd5bb5d4ac13'::uuid),
('4a434378-bd3c-464b-8855-0683ccb6d46e'::uuid,'2c452daf-c9ae-4044-a1a6-f60eaf025fe1'::uuid),
('4a69f43c-df2a-484d-aea4-46b7e94f80fa'::uuid,'9d436c5b-719a-4ab6-bf19-10d336716b55'::uuid),
('4c3c8b17-9301-442e-aacd-cb5dbf548c98'::uuid,'c0470b5e-6587-4f84-bc8c-a716ee3e3c25'::uuid),
('4e0a4df1-1184-4d93-92ef-d70feb7fe413'::uuid,'d12b6bd4-fe79-4249-b793-a232760e15b6'::uuid),
('51191f08-6f1f-4166-9b88-e91d39bb27a9'::uuid,'b565e9da-56a5-4ce9-b8b1-1a4da3ad394a'::uuid),
('59e3ee30-63af-4b77-a93d-25ee7cecdb4a'::uuid,'3b4dfab4-8039-4f29-b89a-24a24d194160'::uuid),
('5aaa4a0d-c7c2-4b1a-bf5e-6b3d70dc0638'::uuid,'8188e523-d75e-4e15-9551-e084a3f03fdb'::uuid),
('5d97a43d-e790-4d0c-84e3-25a2d029ad63'::uuid,'297072df-8741-4db4-8464-275d58728bc0'::uuid),
('5e81437d-3ee5-48f7-8363-11aef963387a'::uuid,'af958888-f26a-4ed7-9c2b-697e9b12a571'::uuid),
('5e8d8dfc-ca64-4691-a48e-5d62ab108dba'::uuid,'859e3e87-a49c-45d0-a53c-a16c43c8f71a'::uuid),
('5fc5caf3-0d83-4cd4-b5a4-6b5956c0333d'::uuid,'1725c3eb-191d-4354-9e24-d8df61ac4b15'::uuid),
('6489bb94-f92b-4054-8b09-752d715969ac'::uuid,'67896e13-a04a-439d-85d4-e5b7a1340182'::uuid),
('64d63bcc-1439-4206-8f84-0b91f576abe2'::uuid,'be5d6c01-3e16-4476-b7ce-393aad84302d'::uuid),
('6561d1e3-854f-47b8-bc7d-2b4728ba4906'::uuid,'12e67afe-1f07-4909-af21-e9c6eb9d5a66'::uuid),
('66b8e8ea-710e-487f-9f82-d68b6bfeef00'::uuid,'32981a7d-e389-4bf6-b046-8830e9bae117'::uuid),
('68251146-efca-4622-9dac-9371d7c622d6'::uuid,'a7759646-0e96-4ae2-ac86-7ffebc83e321'::uuid),
('69673a28-d40b-4f99-8e0d-1ae6003e2483'::uuid,'6e529507-e592-44e4-95f2-bd3d584182c0'::uuid),
('6ae58ade-7ddd-4d74-9f11-0b2f9aa4e692'::uuid,'1fa0dfa7-daa0-4c76-b7df-7c5b4241ead6'::uuid),
('6c1c1401-d745-49c0-ae84-e89811b96649'::uuid,'80ea647a-e184-4e6d-9a77-6c0960566f39'::uuid),
('6c673bce-879a-4259-a2d7-4c198af0c9d2'::uuid,'e1713304-b8c1-41bd-8130-46da8bb54e10'::uuid),
('70f03e41-1080-4a01-be3e-aa5f4399624d'::uuid,'ca9f78ac-6829-4d5b-8e84-28dc23778def'::uuid),
('7125e36c-fa95-4c69-9baa-4f34feeea3f1'::uuid,'538a1693-e3af-404d-ba9f-05465ce41d73'::uuid),
('731eba99-4771-4397-a256-d1277dc72541'::uuid,'ae4795fe-1186-47c1-9372-ecc2fcd50bab'::uuid),
('737668aa-4c0b-4300-9701-e173ce845938'::uuid,'7ad98bee-41f8-4e53-a884-f4b918ca0f03'::uuid),
('809c726c-bc84-4ac2-8c0b-3d2e96d662b1'::uuid,'0dcb13f9-755d-41db-927e-44c2d7a19e24'::uuid),
('812a09d8-287f-4a4c-ab7b-539d8230e444'::uuid,'7fc388ce-a4f8-4a6a-bf0a-80af32cc682f'::uuid),
('85c72138-de35-4105-82c2-1c1e5fca1109'::uuid,'8ba908e6-71e8-48c7-a48f-913175b36758'::uuid),
('89830df3-c84e-407f-a51c-2c8dd43e7adc'::uuid,'dfffb365-4e49-4863-90fe-71b61c4b9ed6'::uuid),
('906548f7-f221-4691-8290-e07202de150d'::uuid,'fc232cc3-7750-4188-8349-230c501f613a'::uuid),
('91dcb3e1-fa35-4452-8ba8-cd7300f7e823'::uuid,'a518537a-07f9-4719-bb17-a2592bc4bee9'::uuid),
('94aecf05-652c-42a9-b054-03bfef42c1b0'::uuid,'52d2258d-3982-4b97-8d3d-0d21df20766d'::uuid),
('95fa0821-d6d6-481e-9f25-96e3c4193745'::uuid,'09bbd98e-7394-4be1-b076-0f8b17df1c20'::uuid),
('97001547-0149-46b2-a4ef-9fd59e57e97f'::uuid,'b1fdf91b-ba59-4499-a047-74ae000179bf'::uuid),
('9c2b2054-20fc-49ca-8d12-bde47caa91fe'::uuid,'20ccbe5a-6cef-47d7-83e1-affaa43ac19d'::uuid),
('9d4ffc1d-a32b-4446-9280-8ef81abcde26'::uuid,'41b63c17-58d0-4faa-913c-ac72b32b3c3f'::uuid),
('a03ebcfa-398c-428b-9798-831c3097181d'::uuid,'e262fb95-54a0-4ebb-a9eb-f531bfecdda0'::uuid),
('a87be9f8-0ef4-4e0f-b439-be28b1427b1d'::uuid,'64066ac2-1e03-4850-adee-42dda7bf1411'::uuid),
('aafa8c0d-5e29-412d-bb65-95dd4fc4bcf9'::uuid,'9be37875-0f1e-4ba2-91a7-91883a7542d5'::uuid),
('acc43bb4-d056-43d4-990c-3e075b475152'::uuid,'bd6d9c51-727d-4c51-8c35-8b9bb9804081'::uuid),
('ad285281-71d7-46e8-8ce8-e1ace8c68673'::uuid,'e35f378d-f527-4259-802e-7b98f36b29fd'::uuid),
('b0fcf302-ed8d-453b-b140-829932fbd973'::uuid,'465d3cb9-a743-44c6-bc09-4894656c0d76'::uuid),
('b29d88fc-dec3-431b-b2b2-ff735597f7c5'::uuid,'547c9170-c453-4698-80fd-4ac71cb625b4'::uuid),
('bb422eff-2ec4-4d7e-83f6-a855be597928'::uuid,'f93cdfaa-7698-4cf8-97c6-9ce231d6f7d6'::uuid),
('bd40f34c-a022-43b5-90a9-a4d1f73ab9a4'::uuid,'611472aa-e349-4988-a8dc-b7ec7763d77b'::uuid),
('c151b4c2-8b9e-4138-bf6a-b6a1391d49eb'::uuid,'6ca9097d-235f-4540-a143-5e7574433e0b'::uuid),
('c1dbc310-c1a3-4f1c-8618-251fddf9ccf3'::uuid,'1609f670-1b55-46a8-985c-227f5e6cd517'::uuid),
('c2c7e51c-3b29-4df0-a757-fbc61727b567'::uuid,'d2010a67-6e35-4926-82e5-a603e5283041'::uuid),
('c5898471-3d5b-4f26-b685-2aca092e68c0'::uuid,'9cf8edd6-4af2-465f-924e-dac65c4bd544'::uuid),
('c7d1c4ad-211d-4d0f-8bf7-bb6aa399c779'::uuid,'8f15c550-8830-475b-8856-038c82fe568a'::uuid),
('c7ddfdc9-102f-47a2-a89c-de751c53b986'::uuid,'3004d79a-6a9e-42ea-b645-92497b452400'::uuid),
('c7e19777-7db8-4dc4-971b-bc3169004247'::uuid,'a94c6e66-9885-4566-94c9-09ac2977a99c'::uuid),
('c89f0786-e55d-4cc4-9a96-fcea1b3696f7'::uuid,'167d92be-dbaf-4fa2-af4b-9c25737c3faa'::uuid),
('ca823166-af23-42df-9918-ad0dfe54fcb2'::uuid,'298e1d8c-d88d-4816-9250-1491a4669e8d'::uuid),
('cb19903c-e3cc-4bc6-8e7d-eb6625434228'::uuid,'d0c81e46-5d91-4890-960c-e71c2cc03cfc'::uuid),
('ce46f01d-c404-419b-99f8-5664d69fe680'::uuid,'955e47ca-1d92-48f4-a167-942c98250bd0'::uuid),
('d01b0f5c-4b67-4119-af71-2276ee995a67'::uuid,'bd4c384c-3ddd-4753-a0c2-64e659b8985a'::uuid),
('d62993d4-248c-4e6b-b93c-c289da3602d5'::uuid,'80ca278f-09ed-456b-83b4-b63960bb8a92'::uuid),
('d78d394f-413b-417d-b5a9-58366f2f9fa4'::uuid,'97daad77-11a4-4793-839e-e762eae6b6c4'::uuid),
('d79c4f42-5727-4ccf-90ba-03fd36aa4143'::uuid,'665104fa-b88c-4c9b-b256-c24778ce64b7'::uuid),
('d7b6d0f9-247d-4285-8917-fcd7ab1173f6'::uuid,'315052ce-4125-419d-ae87-ea9338813bd8'::uuid),
('db298f17-5668-478a-a21e-cb713167a6a6'::uuid,'4527a9e8-94e6-4e90-a410-f5613563ea38'::uuid),
('dc5896dc-aefa-4642-89df-f7426c1d65b7'::uuid,'472b65c7-f8d0-48be-8d48-d626aacbfbea'::uuid),
('dca4280e-b598-4959-baf2-4d8ae98ded65'::uuid,'e47f9e9e-6c04-4d31-a68c-e6797667c2b7'::uuid),
('dd3546fa-ec5f-47d4-9370-ccce3bf3e412'::uuid,'5f2a198a-ffe6-47b7-9bac-3078185143a8'::uuid),
('e54b700b-7e7b-492a-9d76-5ca0cd0a16ba'::uuid,'d9849cef-e145-42e7-b8de-9313aa94be51'::uuid),
('e6192404-96c7-4a04-bf36-61bd9f6d9b4e'::uuid,'6bb9b6c6-efb8-4e92-8d52-11eb757e2b06'::uuid),
('e8516345-becc-4092-a5b2-5ec60b5cc62d'::uuid,'914e48a5-6351-46db-8f2e-487a65d71710'::uuid),
('eb5d671d-a7c1-4a4a-836d-407f208cb709'::uuid,'11ac9ae7-b773-413b-8b5a-e35ccf62dfd9'::uuid),
('ef235f77-3ac8-46d0-ae14-70e7a22d147a'::uuid,'6976a94b-f667-43af-9b00-abc5b18c48ef'::uuid),
('f328e7cf-9621-42c0-9a8a-5893af51db8a'::uuid,'272d528c-2de1-4288-94d7-aef75159ccee'::uuid),
('f7bc608a-fe41-4e2b-8f33-6beeb71dbf23'::uuid,'153c067a-7d2a-4e9c-8b3a-21722f20978b'::uuid),
('f7f56da3-f40e-46ef-bcc8-264012411e16'::uuid,'d47e4c71-8479-498b-a2e2-354cd2bd8808'::uuid),
('fa6d4d31-1732-432d-803e-b910527d4201'::uuid,'b150e150-4f2c-4601-954a-2bf4ed763852'::uuid),
('fe2195a0-e50e-4c8b-aa24-fc965d43bc24'::uuid,'b183b985-d5c6-45c9-88c2-a61b8e405da6'::uuid);
create temp table _c8 (aluno_id uuid, atual smallint, novo smallint) on commit drop;
insert into _c8 values
('83e69ac5-b4d5-4c88-a062-9b1511f00a40'::uuid,17,7),
('39d5a527-0b11-4f80-8ae0-f2a03627bbdc'::uuid,37,10),
('fd5360ce-0a2d-4ad0-83c4-8f133de77335'::uuid,15,9),
('30844fc4-8814-44cf-8074-ef16a165bdbc'::uuid,53,7),
('5232011e-2822-4cfd-894b-7d486df6b8ca'::uuid,14,11),
('f3ea952c-d4ca-4f71-ab40-fad51d399e08'::uuid,30,21),
('ac86d2d2-0d42-403c-aeb6-67c801159aad'::uuid,37,11),
('4e055d58-f8bd-44d5-9304-e82264669610'::uuid,16,14),
('e839402d-cc55-44c0-9b9c-2e4c2e14f765'::uuid,37,14),
('3d37877b-2016-4928-b3c8-3ac06d38c562'::uuid,14,11),
('66e37da0-4d9f-4d27-a415-fda91546f948'::uuid,53,50),
('1c506b44-d61d-4a71-8c56-e3ff3372aece'::uuid,37,17),
('bc2781e8-459d-4a12-a6cf-23a288ddaad1'::uuid,17,30),
('117673c8-c3a6-41e4-bbac-2287708db6c5'::uuid,38,17),
('f4198f04-2f80-4f99-8168-f36f3fa59d88'::uuid,16,21),
('427562dd-00fb-41ca-966f-c39defc064dd'::uuid,29,20),
('06d95bd5-5d9c-4a1d-9dc0-548f45fe7280'::uuid,16,11),
('50d47cd2-3cd9-4e2d-8946-2d8f5f20a0e3'::uuid,21,14),
('f8b28f27-3a18-4f0b-af0e-b69166b22c59'::uuid,21,22);
create temp table _e (aluno_id uuid, campo text, atual text, novo numeric, cobrado numeric, tipo text) on commit drop;
insert into _e values
('3b570eb2-b421-46cd-a416-1bd3e6e81a10'::uuid,'valor_total','5200',10100.00,10100.0,'sinal_fora_do_total'),
('df233950-a707-45c4-8b32-0a9a17001e90'::uuid,'valor_total','22500',25000.00,29113.68,'sinal_fora_do_total'),
('df233950-a707-45c4-8b32-0a9a17001e90'::uuid,'valor_pago','29113.68',25000.00,29113.68,'sinal_fora_do_total'),
('ce403c29-db07-4f87-92b0-090150a395b8'::uuid,'valor_total','22500',25000.00,25196.97,'sinal_fora_do_total'),
('ce403c29-db07-4f87-92b0-090150a395b8'::uuid,'valor_pago','25196.97',25000.00,25196.97,'sinal_fora_do_total'),
('83e69ac5-b4d5-4c88-a062-9b1511f00a40'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('7cc498eb-2f98-413c-ae36-4f0c99a36c04'::uuid,'valor_total','22500',25000.00,31085.8,'sinal_fora_do_total'),
('7cc498eb-2f98-413c-ae36-4f0c99a36c04'::uuid,'valor_pago','31085.8',25000.00,31085.8,'sinal_fora_do_total'),
('fdff4dd6-421f-4687-9d6b-66c4547e33ee'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('7d22390f-dbed-4b57-a8d1-19a7c276bc58'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('d22123c4-afc1-4493-8725-307a6eedc076'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('5b940737-e287-4309-920f-a0440ab165e6'::uuid,'valor_pago','57700.03',26297.00,27201.0,'renovacao_somada'),
('8b8657aa-ff1a-4821-87e1-202583050221'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('3909db80-51d5-4a61-a7a2-29d7916299d9'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('7d08bd4a-34d0-4148-8004-5217ae597070'::uuid,'valor_total','12500',15000.00,18392.5,'sinal_fora_do_total'),
('7d08bd4a-34d0-4148-8004-5217ae597070'::uuid,'valor_pago','18392.5',15000.00,18392.5,'sinal_fora_do_total'),
('d1f6aac5-b01c-400d-a09a-74dd6ba43c7d'::uuid,'valor_total','23000',25999.97,32220.96,'sinal_fora_do_total'),
('d1f6aac5-b01c-400d-a09a-74dd6ba43c7d'::uuid,'valor_pago','32220.96',25999.97,32220.96,'sinal_fora_do_total'),
('1305017f-3e38-45a4-9796-1ddc9356fdf2'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('858fe98a-a349-4bce-a4e7-af1166aacfe5'::uuid,'valor_total','47000',55000.00,55000.0,'sinal_fora_do_total'),
('437e65f1-b0e7-48a4-92d2-c4e53b76a552'::uuid,'valor_total','14000',16000.00,16000.0,'sinal_fora_do_total'),
('f959d677-43d9-4cdb-a5aa-4e2e8800624e'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('ca6fd937-5863-4c56-9fe2-ccfc33a9c0b5'::uuid,'valor_pago','58999.99',6000.00,6000.0,'renovacao_somada'),
('18087f01-41fe-4979-a812-82cbd868d8f5'::uuid,'valor_total','40500',45000.00,45000.0,'sinal_fora_do_total'),
('4a6e211f-7f42-4f79-a348-b0c02d0ef88b'::uuid,'valor_total','48000',51000.00,51000.0,'sinal_fora_do_total'),
('e65d0bef-b6ed-4bf9-83dd-e4965caffa30'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('d0c81e46-5d91-4890-960c-e71c2cc03cfc'::uuid,'valor_total','14995',15468.30,16399.74,'sinal_fora_do_total'),
('d0c81e46-5d91-4890-960c-e71c2cc03cfc'::uuid,'valor_pago','16399.74',15468.30,16399.74,'sinal_fora_do_total'),
('80ea647a-e184-4e6d-9a77-6c0960566f39'::uuid,'valor_total','40500',45000.00,52404.64,'sinal_fora_do_total'),
('80ea647a-e184-4e6d-9a77-6c0960566f39'::uuid,'valor_pago','52404.64',45000.00,52404.64,'sinal_fora_do_total'),
('b48d9a65-34fb-471d-83bd-53bf01b1a20a'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('c3303a4f-ee6a-4420-84b1-2ce448f73026'::uuid,'valor_total','52000',55000.00,55000.0,'sinal_fora_do_total'),
('35460d1d-25ff-493c-bb8e-251e936341d6'::uuid,'valor_total','22500',25000.00,30336.56,'sinal_fora_do_total'),
('35460d1d-25ff-493c-bb8e-251e936341d6'::uuid,'valor_pago','30336.56',25000.00,30336.56,'sinal_fora_do_total'),
('b530558d-9619-4c23-a281-cc77ddb100be'::uuid,'valor_total','2000',30000.04,38069.85,'sinal_fora_do_total'),
('b530558d-9619-4c23-a281-cc77ddb100be'::uuid,'valor_pago','38069.85',30000.04,38069.85,'sinal_fora_do_total'),
('59962d24-ed9e-4c8d-9462-6d6d57ba531d'::uuid,'valor_total','40500',45000.00,45000.0,'sinal_fora_do_total'),
('3aac9c04-2faa-4c52-a9ee-afe8917b5ce9'::uuid,'valor_total','22500',25000.00,25000.0,'sinal_fora_do_total'),
('d9849cef-e145-42e7-b8de-9313aa94be51'::uuid,'valor_total','40500',45000.00,45000.0,'sinal_fora_do_total'),
('4236680c-2141-4a37-bb27-e97905580bf8'::uuid,'valor_pago','59000.01',3997.05,5078.16,'renovacao_somada'),
('9fcdbc29-2440-403f-bff1-2eb6f2677ce6'::uuid,'valor_pago','19053.36',15000.04,18976.08,'renovacao_somada'),
('32ecc1ca-cb8d-4091-a0d6-7a2c87bb8f1f'::uuid,'valor_pago','19053.36',11342.46,14329.2,'renovacao_somada'),
('ade45b63-eb6b-4633-88b6-8b5093ae1130'::uuid,'valor_total','22500',25000.00,25196.97,'sinal_fora_do_total'),
('ade45b63-eb6b-4633-88b6-8b5093ae1130'::uuid,'valor_pago','25196.97',25000.00,25196.97,'sinal_fora_do_total'),
('fcf761a2-6924-4724-b484-d9c11fb87e5a'::uuid,'valor_total','8666',11666.67,11666.67,'sinal_fora_do_total'),
('f3a0df52-1d64-44a1-ad3a-7e35076859c5'::uuid,'valor_total','22500',25000.00,26468.02,'sinal_fora_do_total'),
('f3a0df52-1d64-44a1-ad3a-7e35076859c5'::uuid,'valor_pago','26468.02',25000.00,26468.02,'sinal_fora_do_total');
create temp table _arq (aluno_id uuid, fica uuid, motivo text) on commit drop;
insert into _arq values
('9472cd26-59e9-4ba4-b554-b77881933d99', 'f73b2b74-3cbd-4c7b-b926-e954129e3d63', 'duplicata'),
('519fb300-89c8-4364-887f-beda18e67454', '5305f4d2-e316-4cda-8c8d-a46969bf42f5', 'duplicata'),
('63a2019b-ac5b-44a1-b51e-ab31d5483d64', '38f0340b-3b14-4bfb-b247-a8fe9da0e0b0', 'duplicata'),
('9d532b23-a225-47fa-bb3a-dcf9e77b4b79', null, 'teste'),
('ddd1c3e8-7fb2-48f1-b215-e1d40fecda32', null, 'teste');

do $$
declare k int; r text := '';
begin
  -- 1. duplicatas e teste. Sócio da ficha arquivada passa para a que fica (S→NULL antes de T→S, trava de vínculo).
  create temp table _mov on commit drop as
    select s.id, x.fica from public.thb_alunos s join _arq x on s.socio_de_aluno_id = x.aluno_id
     where s.cancelado_em is null and x.fica is not null;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select s.id, 'socio_de_aluno_id', s.socio_de_aluno_id::text, m.fica::text, 'conc_duplicata:certo'
    from public.thb_alunos s join _mov m on m.id = s.id;
  update public.thb_alunos s set socio_de_aluno_id = null from _mov m where s.id = m.id;
  update public.thb_alunos s set socio_de_aluno_id = m.fica,
         obs_central = concat_ws(' | ', nullif(s.obs_central, ''), '[2026-10-01] [conc:socio_vinculo] titular duplicado arquivado: vínculo passa para ' || left(m.fica::text, 8))
    from _mov m where s.id = m.id;
  get diagnostics k = row_count; r := r || ' socio_movido=' || k;
  update public.thb_alunos a set num_socios = n.n
    from (select socio_de_aluno_id t, count(*) n from public.thb_alunos where cancelado_em is null and socio_de_aluno_id in (select fica from _mov) group by 1) n
   where a.id = n.t and coalesce(a.num_socios, 0) < n.n;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, 'cancelado_em', null, now()::text, 'conc_' || x.motivo || ':certo'
    from public.thb_alunos a join _arq x on x.aluno_id = a.id where a.cancelado_em is null;
  update public.thb_alunos a
     set cancelado_em = now(),
         cancelado_origem = 'arquivo: ' || case when x.motivo = 'teste' then 'ficha de teste' else 'duplicata de ' || left(x.fica::text, 8) || ' (fica a de login mais recente)' end,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:documento_unico] arquivada: '
           || case when x.motivo = 'teste' then 'ficha de teste' else 'duplicata, fica ' || left(x.fica::text, 8) || ' (login mais recente)' end)
    from _arq x where x.aluno_id = a.id and a.cancelado_em is null;
  get diagnostics k = row_count; r := r || ' arquivadas=' || k;
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:documento_unico] duplicata resolvida: ficha ' || left(x.aluno_id::text, 8) || ' arquivada, esta fica (login mais recente)')
    from _arq x where x.fica = a.id;

  -- 2. revogações A, B, C
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.situacao_acesso::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'situacao_acesso' and a.cancelado_em is null and a.situacao_acesso is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set situacao_acesso = c.novo::text from _abc c
   where a.id = c.aluno_id and c.campo = 'situacao_acesso' and a.cancelado_em is null and a.situacao_acesso is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.situacao_acesso=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.status_acesso::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'status_acesso' and a.cancelado_em is null and a.status_acesso is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set status_acesso = c.novo::text from _abc c
   where a.id = c.aluno_id and c.campo = 'status_acesso' and a.cancelado_em is null and a.status_acesso is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.status_acesso=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.status_acesso_central::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'status_acesso_central' and a.cancelado_em is null and a.status_acesso_central is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set status_acesso_central = c.novo::text from _abc c
   where a.id = c.aluno_id and c.campo = 'status_acesso_central' and a.cancelado_em is null and a.status_acesso_central is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.status_acesso_central=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.situacao_financeira::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'situacao_financeira' and a.cancelado_em is null and a.situacao_financeira is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set situacao_financeira = c.novo::text from _abc c
   where a.id = c.aluno_id and c.campo = 'situacao_financeira' and a.cancelado_em is null and a.situacao_financeira is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.situacao_financeira=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.status_pagamento::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'status_pagamento' and a.cancelado_em is null and a.status_pagamento is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set status_pagamento = c.novo::text from _abc c
   where a.id = c.aluno_id and c.campo = 'status_pagamento' and a.cancelado_em is null and a.status_pagamento is not distinct from c.atual::text and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.status_pagamento=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.valor_pago::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'valor_pago' and a.cancelado_em is null and a.valor_pago is not distinct from c.atual::numeric and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set valor_pago = c.novo::numeric from _abc c
   where a.id = c.aluno_id and c.campo = 'valor_pago' and a.cancelado_em is null and a.valor_pago is not distinct from c.atual::numeric and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.valor_pago=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, c.campo, a.data_expiracao::text, c.novo, 'conc_' || c.cl || ':certo' from public.thb_alunos a join _abc c on a.id = c.aluno_id
   where c.campo = 'data_expiracao' and a.cancelado_em is null and true and not pg_temp._conc_pagou(a.id);
  update public.thb_alunos a set data_expiracao = c.novo::date from _abc c
   where a.id = c.aluno_id and c.campo = 'data_expiracao' and a.cancelado_em is null and true and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc.data_expiracao=' || k;
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:acesso] '
       || case c.cl when 'A' then 'renovação reembolsada sem compra nova: vencido'
                    when 'B' then 'compra própria vencida e sem titular: vencido'
                    else 'compra reembolsada na Hotmart sem substituta: sem acesso' end || ' (decisão do João, 01/10/2026)')
    from (select distinct aluno_id, cl from _abc) c
   where a.id = c.aluno_id and a.cancelado_em is null and not pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc_fichas=' || k;
  update public.thb_alunos a
     set obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:acesso] revogação não aplicada: pagamento do programa nos últimos 12 meses')
    from (select distinct aluno_id from _abc) c where a.id = c.aluno_id and a.cancelado_em is null and pg_temp._conc_pagou(a.id);
  get diagnostics k = row_count; r := r || ' abc_pagou=' || k;

  -- 3. G: sócio de titular vencido
  create temp table _g_ok on commit drop as
    select distinct g.socio_id from _g g
      join public.thb_alunos s on s.id = g.socio_id and s.cancelado_em is null and s.socio_de_aluno_id = g.titular_id and s.situacao_acesso = 'acompanha_titular'
      join public.thb_alunos t on t.id = g.titular_id and t.situacao_acesso = 'vencido'
     where not pg_temp._conc_pagou(g.socio_id) and not pg_temp._conc_pagou(g.titular_id);
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select s.id, f.campo, f.antes, f.novo, 'conc_G:certo'
    from public.thb_alunos s join _g_ok o on o.socio_id = s.id
   cross join lateral (values ('situacao_acesso', s.situacao_acesso, 'vencido', s.situacao_acesso = 'acompanha_titular'),
                              ('status_acesso', s.status_acesso, 'vencido', s.status_acesso in ('vigente', 'renovado')),
                              ('status_acesso_central', s.status_acesso_central, 'Vencido', s.status_acesso_central = 'Acompanha titular')) f(campo, antes, novo, troca)
   where f.troca;
  update public.thb_alunos s
     set situacao_acesso = case when s.situacao_acesso = 'acompanha_titular' then 'vencido' else s.situacao_acesso end,
         status_acesso = case when s.status_acesso in ('vigente', 'renovado') then 'vencido' else s.status_acesso end,
         status_acesso_central = case when s.status_acesso_central = 'Acompanha titular' then 'Vencido' else s.status_acesso_central end
    from _g_ok o where o.socio_id = s.id and s.situacao_acesso = 'acompanha_titular';
  get diagnostics k = row_count; r := r || ' g=' || k;
  update public.thb_alunos s
     set obs_central = concat_ws(' | ', nullif(s.obs_central, ''), '[2026-10-01] [conc:acesso] titular vencido sem pagamento em 12 meses: sócio vence junto (decisão do João, 01/10/2026)')
   where s.id in (select socio_id from _g_ok);
  get diagnostics k = row_count; r := r || ' g_fichas=' || k;
  update public.thb_alunos s
     set obs_central = concat_ws(' | ', nullif(s.obs_central, ''), '[2026-10-01] [conc:acesso] sócio mantido: titular ou sócio pagou o programa nos últimos 12 meses, ou titular não está vencido')
   where s.cancelado_em is null and s.situacao_acesso = 'acompanha_titular' and s.id in (select socio_id from _g) and s.id not in (select socio_id from _g_ok);
  get diagnostics k = row_count; r := r || ' g_mantidos=' || k;

  -- 4. b17de93b
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, 'situacao_acesso', a.situacao_acesso, 'vencido', 'conc_vencimento:certo' from public.thb_alunos a
   where a.id::text like 'b17de93b%' and a.cancelado_em is null and a.situacao_acesso in ('a_vencer', 'em_dia')
     and a.data_expiracao < current_date and not pg_temp._conc_pagou(a.id, a.data_expiracao - interval '11 months');
  update public.thb_alunos a
     set situacao_acesso = 'vencido',
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:vencimento] expirou ' || to_char(a.data_expiracao, 'DD/MM/YYYY') || ' sem renovação no espelho Hotmart: vencido')
   where a.id::text like 'b17de93b%' and a.cancelado_em is null and a.situacao_acesso in ('a_vencer', 'em_dia')
     and a.data_expiracao < current_date and not pg_temp._conc_pagou(a.id, a.data_expiracao - interval '11 months');
  get diagnostics k = row_count; r := r || ' b17=' || k;

  -- 5. C8: turma de entrada
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, 'turma_id', a.turma_id::text, c.novo::text, 'conc_8:certo' from public.thb_alunos a join _c8 c on c.aluno_id = a.id
   where a.cancelado_em is null and a.turma_id = c.atual;
  update public.thb_alunos a
     set turma_id = c.novo,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:turma] turma = turma de entrada (data de entrada cai na coorte da turma declarada no Respondi)')
    from _c8 c where c.aluno_id = a.id and a.cancelado_em is null and a.turma_id = c.atual;
  get diagnostics k = row_count; r := r || ' c8=' || k;

  -- 6. E: base sem juros quando o dinheiro que entrou cobre o preço
  create temp table _e_ok on commit drop as
    select e.* from _e e join public.thb_alunos a on a.id = e.aluno_id and a.cancelado_em is null
     where e.cobrado + 0.01 >= coalesce((select x.novo from _e x where x.aluno_id = e.aluno_id and x.campo = 'valor_total'), a.valor_total, e.novo);
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, e.campo, case e.campo when 'valor_total' then a.valor_total else a.valor_pago end::text, e.novo::text, 'conc_E:certo'
    from public.thb_alunos a join _e_ok e on e.aluno_id = a.id
   where case e.campo when 'valor_total' then a.valor_total else a.valor_pago end is not distinct from e.atual::numeric;
  update public.thb_alunos a set valor_total = e.novo from _e_ok e
   where e.aluno_id = a.id and e.campo = 'valor_total' and a.valor_total is not distinct from e.atual::numeric;
  get diagnostics k = row_count; r := r || ' e.total=' || k;
  update public.thb_alunos a set valor_pago = e.novo from _e_ok e
   where e.aluno_id = a.id and e.campo = 'valor_pago' and a.valor_pago is not distinct from e.atual::numeric;
  get diagnostics k = row_count; r := r || ' e.pago=' || k;
  insert into public.cruzamentos_correcoes (aluno_id, campo, valor_antes, valor_novo, regra)
  select a.id, 'situacao_financeira', a.situacao_financeira, 'quitado', 'conc_E:certo' from public.thb_alunos a
   where a.id in (select aluno_id from _e_ok) and a.situacao_financeira is distinct from 'quitado'
     and coalesce(a.situacao_financeira, '') not in ('reembolsado', 'cancelado');
  update public.thb_alunos a
     set situacao_financeira = case when coalesce(a.situacao_financeira, '') in ('reembolsado', 'cancelado') then a.situacao_financeira else 'quitado' end,
         obs_central = concat_ws(' | ', nullif(a.obs_central, ''), '[2026-10-01] [conc:valor] o que entrou no ciclo cobre o preço: base sem juros aplicada, quitado (decisão do João, 01/10/2026)')
   where a.id in (select aluno_id from _e_ok);
  get diagnostics k = row_count; r := r || ' e_fichas=' || k;

  raise notice '20261004m:%', r;
end $$;
