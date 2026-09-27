-- 20260927g — Chave da pessoa opaca (pentest 27/09, MÉDIO).
--
-- A chave interna da pessoa é o menor nó do componente — muitas vezes 'd:<CPF>'. As RPCs a
-- devolviam como md5 sem sal: CPF tem ~10^9 combinações úteis, então o md5 volta ao CPF em
-- segundos. Agora sai HMAC-SHA256 com um segredo que só existe no Vault
-- ('fin_identidade_sal', criado fora da migração — segredo não entra no repo).
--
-- Função interna: ninguém de fora executa; só as RPCs SECURITY DEFINER do financeiro a chamam.
-- Sem o segredo ela FALHA (nunca devolve null: chave nula juntaria todo mundo numa pessoa só).

create or replace function fin.chave_opaca(p text)
returns text language plpgsql stable security definer set search_path = '' as $$
declare v_sal text;
begin
  select s.decrypted_secret into v_sal from vault.decrypted_secrets s where s.name = 'fin_identidade_sal';
  if v_sal is null then
    raise exception 'fin.chave_opaca: segredo fin_identidade_sal ausente no Vault.';
  end if;
  return encode(extensions.hmac(p, v_sal, 'sha256'), 'hex');
end $$;
revoke all on function fin.chave_opaca(text) from public, anon, authenticated;
