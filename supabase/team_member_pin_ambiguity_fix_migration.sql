begin;

create or replace function public.autenticar_equipe_com_pin(
  p_team_member_id uuid,
  p_pin text
)
returns table (
  access_token text,
  team_member_id uuid,
  team_member_name text,
  professional_id uuid
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pin_hash text;
  v_failed_attempts integer;
  v_locked_until timestamptz;
  v_token text;
  v_member_id uuid;
  v_member_name text;
  v_professional_id uuid;
begin
  select e.pin_hash, e.id, e.nome, e.profissional_id
    into v_pin_hash, v_member_id, v_member_name, v_professional_id
  from public.profissionais_equipe e
  where e.id = p_team_member_id and e.ativo
  for update;

  if not found or v_pin_hash is null then
    return;
  end if;

  insert into public.profissionais_equipe_pin_tentativas (
    team_member_id, tentativas_falhas
  )
  values (p_team_member_id, 0)
  on conflict (team_member_id) do nothing;

  select a.tentativas_falhas, a.bloqueado_ate
    into v_failed_attempts, v_locked_until
  from public.profissionais_equipe_pin_tentativas a
  where a.team_member_id = p_team_member_id
  for update;

  if v_locked_until is not null and v_locked_until > now() then
    return;
  end if;

  if p_pin is null or extensions.crypt(p_pin, v_pin_hash) <> v_pin_hash then
    if v_locked_until is not null and v_locked_until <= now() then
      v_failed_attempts := 0;
    end if;
    v_failed_attempts := v_failed_attempts + 1;
    update public.profissionais_equipe_pin_tentativas as attempts
    set tentativas_falhas = v_failed_attempts,
        bloqueado_ate = case
          when v_failed_attempts >= 5 then now() + interval '15 minutes'
          else null
        end
    where attempts.team_member_id = p_team_member_id;
    return;
  end if;

  delete from public.profissionais_equipe_pin_tentativas as attempts
  where attempts.team_member_id = p_team_member_id;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');
  insert into public.profissionais_equipe_sessoes (
    token_hash, team_member_id, expira_em
  )
  values (
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    p_team_member_id,
    now() + interval '12 hours'
  );

  delete from public.profissionais_equipe_sessoes as sessions
  where sessions.expira_em <= now();

  return query
  select v_token, v_member_id, v_member_name, v_professional_id;
end;
$$;

revoke all on function public.autenticar_equipe_com_pin(uuid, text)
  from public;
grant execute on function public.autenticar_equipe_com_pin(uuid, text)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
