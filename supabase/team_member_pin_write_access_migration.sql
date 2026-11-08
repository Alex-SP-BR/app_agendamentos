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

alter table public.clientes_salao
  add column if not exists team_member_id uuid;

do $$
begin
  if not exists (
    select 1
    from pg_catalog.pg_constraint
    where conname = 'cliente_salao_equipe_profissional_fk'
      and conrelid = 'public.clientes_salao'::regclass
  ) then
    alter table public.clientes_salao
      add constraint cliente_salao_equipe_profissional_fk
      foreign key (team_member_id, profissional_id)
      references public.profissionais_equipe (id, profissional_id);
  end if;
end;
$$;

create table if not exists public.profissionais_equipe_sessoes (
  token_hash text primary key,
  team_member_id uuid not null
    references public.profissionais_equipe (id) on delete cascade,
  expira_em timestamptz not null,
  criado_em timestamptz not null default now()
);
create index if not exists profissionais_equipe_sessoes_expira_em_idx
  on public.profissionais_equipe_sessoes (expira_em);
alter table public.profissionais_equipe_sessoes enable row level security;
revoke all on public.profissionais_equipe_sessoes
  from public, anon, authenticated;

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
  delete from public.profissionais_equipe_sessoes as sessions
  where sessions.team_member_id = p_team_member_id;
end;
$$;

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

create or replace function public.validar_sessao_equipe(p_access_token text)
returns table (
  team_member_id uuid,
  professional_id uuid,
  team_member_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  select e.id, e.profissional_id, e.nome
  from public.profissionais_equipe_sessoes s
  join public.profissionais_equipe e on e.id = s.team_member_id
  where p_access_token is not null
    and s.token_hash =
      encode(extensions.digest(p_access_token, 'sha256'), 'hex')
    and s.expira_em > now()
    and e.ativo
$$;

drop function if exists public.agenda_equipe_com_sessao(text);
create or replace function public.agenda_equipe_com_sessao(
  p_access_token text,
  p_day date default null
)
returns table (
  appointment_id uuid,
  appointment_starts_at timestamptz,
  service_title text,
  client_name text,
  appointment_value numeric,
  appointment_status text
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id,
         a.data_hora_inicio,
         s.titulo,
         coalesce(p.nome, cs.nome, 'Cliente'),
         a.valor,
         a.status
  from public.validar_sessao_equipe(p_access_token) as team_session
  join public.profissionais_config c
    on c.profissional_id = team_session.professional_id
  join public.agendamentos a
    on a.team_member_id = team_session.team_member_id
  join public.servicos s on s.id = a.servico_id
  left join public.perfis p on p.id = a.cliente_id
  left join public.clientes_salao cs on cs.id = a.cliente_salao_id
  where a.data_hora_inicio >=
      coalesce(p_day, (now() at time zone c.timezone)::date)::timestamp
        at time zone c.timezone
    and a.data_hora_inicio <
      (coalesce(p_day, (now() at time zone c.timezone)::date) + 1)::timestamp
        at time zone c.timezone
    and a.status <> 'cancelado'
  order by a.data_hora_inicio
$$;

create or replace function public.clientes_equipe_com_sessao(
  p_access_token text
)
returns table (
  client_id uuid,
  client_name text,
  client_phone text
)
language sql
stable
security definer
set search_path = ''
as $$
  select salon_client.id, salon_client.nome, salon_client.telefone
  from public.validar_sessao_equipe(p_access_token) as team_session
  join public.clientes_salao as salon_client
    on salon_client.team_member_id = team_session.team_member_id
   and salon_client.profissional_id = team_session.professional_id
  order by salon_client.nome
$$;

create or replace function public.criar_cliente_equipe_com_sessao(
  p_access_token text,
  p_name text,
  p_phone text
)
returns table (
  client_id uuid,
  client_name text,
  client_phone text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member record;
  v_client public.clientes_salao%rowtype;
  v_phone_digits text;
begin
  select * into v_member
  from public.validar_sessao_equipe(p_access_token);
  if not found then
    raise exception 'Sessão expirada. Informe novamente o PIN.';
  end if;

  v_phone_digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if nullif(trim(p_name), '') is null
    or length(v_phone_digits) not between 8 and 15
  then
    raise exception 'Informe nome e telefone válido para o cliente.';
  end if;

  select c.* into v_client
  from public.clientes_salao c
  where c.profissional_id = v_member.professional_id
    and regexp_replace(c.telefone, '[^0-9]', '', 'g') = v_phone_digits;
  if found then
    if v_client.team_member_id is distinct from v_member.team_member_id then
      raise exception 'Este telefone já está cadastrado pelo salão.';
    end if;
    update public.clientes_salao c
    set nome = trim(p_name), telefone = trim(p_phone)
    where c.id = v_client.id
    returning c.* into v_client;
  else
    insert into public.clientes_salao (
      profissional_id, team_member_id, nome, telefone
    )
    values (
      v_member.professional_id, v_member.team_member_id,
      trim(p_name), trim(p_phone)
    )
    returning * into v_client;
  end if;

  return query select v_client.id, v_client.nome, v_client.telefone;
end;
$$;

create or replace function public.atualizar_cliente_equipe_com_sessao(
  p_access_token text,
  p_client_id uuid,
  p_name text,
  p_phone text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member record;
  v_phone_digits text;
begin
  select * into v_member
  from public.validar_sessao_equipe(p_access_token);
  if not found then
    raise exception 'Sessão expirada. Informe novamente o PIN.';
  end if;

  v_phone_digits := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  if nullif(trim(p_name), '') is null
    or length(v_phone_digits) not between 8 and 15
  then
    raise exception 'Informe nome e telefone válido para o cliente.';
  end if;

  update public.clientes_salao c
  set nome = trim(p_name), telefone = trim(p_phone)
  where c.id = p_client_id
    and c.profissional_id = v_member.professional_id
    and c.team_member_id = v_member.team_member_id;
  if not found then
    raise exception 'Cliente não encontrado para este profissional.';
  end if;
end;
$$;

create or replace function public.criar_agendamento_equipe_com_sessao(
  p_access_token text,
  p_client_id uuid,
  p_service_id uuid,
  p_starts_at timestamptz
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_team_member_id uuid;
  v_professional_id uuid;
begin
  select session_row.team_member_id, session_row.professional_id
    into v_team_member_id, v_professional_id
  from public.validar_sessao_equipe(p_access_token) as session_row;
  if not found then
    raise exception 'Sessão inválida ou expirada.';
  end if;

  if not exists (
    select 1
    from public.clientes_salao as salon_client
    where salon_client.id = p_client_id
      and salon_client.profissional_id = v_professional_id
      and salon_client.team_member_id = v_team_member_id
  ) then
    raise exception 'Cliente não encontrado para este profissional.';
  end if;

  -- The trigger reuses the owner's validation path only within this transaction.
  perform set_config(
    'request.jwt.claim.sub', v_professional_id::text, true
  );

  insert into public.agendamentos (
    profissional_id, cliente_salao_id, servico_id, team_member_id,
    data_hora_inicio, tipo_pagamento, valor, status
  )
  values (
    v_professional_id, p_client_id, p_service_id,
    v_team_member_id, p_starts_at, 'local', 0, 'confirmado'
  );
end;
$$;

create or replace function public.atualizar_status_agendamento_equipe(
  p_access_token text,
  p_appointment_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_member record;
begin
  select * into v_member
  from public.validar_sessao_equipe(p_access_token);
  if not found then
    raise exception 'Sessão expirada. Informe novamente o PIN.';
  end if;
  if p_status is null
    or p_status not in ('confirmado', 'concluido', 'cancelado')
  then
    raise exception 'Status de agendamento inválido.';
  end if;

  update public.agendamentos a
  set status = p_status
  where a.id = p_appointment_id
    and a.team_member_id = v_member.team_member_id
    and a.profissional_id = v_member.professional_id
    and a.status in ('pendente', 'confirmado');
  if not found then
    raise exception 'Agendamento não encontrado ou não pode ser alterado.';
  end if;
end;
$$;

revoke all on function public.autenticar_equipe_com_pin(uuid, text)
  from public;
revoke all on function public.validar_sessao_equipe(text)
  from public, anon, authenticated;
revoke all on function public.agenda_equipe_com_sessao(text, date)
  from public;
revoke all on function public.clientes_equipe_com_sessao(text)
  from public;
revoke all on function public.criar_cliente_equipe_com_sessao(text, text, text)
  from public;
revoke all on function public.atualizar_cliente_equipe_com_sessao(
  text, uuid, text, text
) from public;
revoke all on function public.criar_agendamento_equipe_com_sessao(
  text, uuid, uuid, timestamptz
) from public;
revoke all on function public.atualizar_status_agendamento_equipe(
  text, uuid, text
) from public;
grant execute on function public.autenticar_equipe_com_pin(uuid, text)
  to anon, authenticated;
grant execute on function public.agenda_equipe_com_sessao(text, date)
  to anon, authenticated;
grant execute on function public.clientes_equipe_com_sessao(text)
  to anon, authenticated;
grant execute on function public.criar_cliente_equipe_com_sessao(
  text, text, text
) to anon, authenticated;
grant execute on function public.atualizar_cliente_equipe_com_sessao(
  text, uuid, text, text
) to anon, authenticated;
grant execute on function public.criar_agendamento_equipe_com_sessao(
  text, uuid, uuid, timestamptz
) to anon, authenticated;
grant execute on function public.atualizar_status_agendamento_equipe(
  text, uuid, text
) to anon, authenticated;

notify pgrst, 'reload schema';
commit;
