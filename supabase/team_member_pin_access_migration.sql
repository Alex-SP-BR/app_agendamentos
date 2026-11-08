begin;

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

do $$
begin
  if exists (
    select 1
    from pg_catalog.pg_extension e
    join pg_catalog.pg_namespace n on n.oid = e.extnamespace
    where e.extname = 'pgcrypto'
      and n.nspname <> 'extensions'
  ) then
    execute 'alter extension pgcrypto set schema extensions';
  end if;
end;
$$;

create table if not exists public.profissionais_equipe_pin_tentativas (
  team_member_id uuid primary key
    references public.profissionais_equipe (id) on delete cascade,
  tentativas_falhas integer not null default 0,
  bloqueado_ate timestamptz
);
alter table public.profissionais_equipe_pin_tentativas enable row level security;

alter table public.profissionais_equipe
  add column if not exists pin_hash text;

create or replace function public.definir_pin_profissional_equipe(
  p_team_member_id uuid,
  p_pin text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.profissionais_equipe e
    where e.id = p_team_member_id
      and e.profissional_id = auth.uid()
  ) then
    raise exception 'Profissional da equipe não encontrado';
  end if;

  if p_pin is not null and p_pin !~ '^[0-9]{6,12}$' then
    raise exception 'O PIN deve conter de 6 a 12 dígitos';
  end if;

  update public.profissionais_equipe as team_member
  set pin_hash = case
    when p_pin is null then null
    else extensions.crypt(p_pin, extensions.gen_salt('bf', 12))
  end
  where team_member.id = p_team_member_id
    and team_member.profissional_id = auth.uid();

  delete from public.profissionais_equipe_pin_tentativas as attempts
  where attempts.team_member_id = p_team_member_id;
end;
$$;

create or replace function public.agenda_equipe_com_pin(
  p_team_member_id uuid,
  p_pin text
)
returns table (
  appointment_id uuid,
  appointment_starts_at timestamptz,
  service_title text,
  client_name text,
  appointment_value numeric,
  appointment_status text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pin_hash text;
  v_timezone text;
  v_failed_attempts integer;
  v_locked_until timestamptz;
  v_starts_at timestamptz;
  v_ends_at timestamptz;
begin
  select e.pin_hash, coalesce(c.timezone, 'America/Sao_Paulo')
    into v_pin_hash, v_timezone
  from public.profissionais_equipe e
  left join public.profissionais_config c
    on c.profissional_id = e.profissional_id
  where e.id = p_team_member_id
    and e.ativo;

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

  v_starts_at :=
    date_trunc('day', now() at time zone v_timezone) at time zone v_timezone;
  v_ends_at :=
    (date_trunc('day', now() at time zone v_timezone) + interval '1 day')
    at time zone v_timezone;

  return query
  select a.id,
         a.data_hora_inicio,
         s.titulo,
         coalesce(p.nome, cs.nome, 'Cliente'),
         a.valor,
         a.status
  from public.agendamentos a
  join public.servicos s on s.id = a.servico_id
  left join public.perfis p on p.id = a.cliente_id
  left join public.clientes_salao cs on cs.id = a.cliente_salao_id
  where a.team_member_id = p_team_member_id
    and a.data_hora_inicio >= v_starts_at
    and a.data_hora_inicio < v_ends_at
    and a.status <> 'cancelado'
  order by a.data_hora_inicio;
end;
$$;

revoke all on public.profissionais_equipe_pin_tentativas
  from public, anon, authenticated;
revoke all on public.profissionais_equipe from authenticated;
grant select (id, profissional_id, nome, ativo, criado_em)
  on public.profissionais_equipe to authenticated;
grant insert (profissional_id, nome, ativo)
  on public.profissionais_equipe to authenticated;
grant update (nome, ativo)
  on public.profissionais_equipe to authenticated;
grant delete on public.profissionais_equipe to authenticated;
revoke all on function public.definir_pin_profissional_equipe(uuid, text)
  from public, anon;
revoke all on function public.agenda_equipe_com_pin(uuid, text)
  from public;
grant execute on function public.definir_pin_profissional_equipe(uuid, text)
  to authenticated;
grant execute on function public.agenda_equipe_com_pin(uuid, text)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
