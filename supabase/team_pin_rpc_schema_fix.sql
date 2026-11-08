begin;

drop function if exists public.servicos_equipe_com_sessao(text);

create or replace function public.servicos_equipe_com_sessao(
  p_access_token text
)
returns table (
  id uuid,
  profissional_id uuid,
  titulo text,
  categoria text,
  preco numeric,
  duracao_minutos integer
)
language sql
stable
security definer
set search_path = ''
as $$
  select service_row.id as id,
         service_row.profissional_id as profissional_id,
         service_row.titulo as titulo,
         service_row.categoria as categoria,
         service_row.preco as preco,
         service_row.duracao_minutos as duracao_minutos
  from public.validar_sessao_equipe(p_access_token) as team_session
  join public.servicos as service_row
    on service_row.profissional_id = team_session.professional_id
  where service_row.ativo
  order by service_row.titulo
$$;

drop function if exists public.agenda_equipe_com_sessao(text);
drop function if exists public.agenda_equipe_com_sessao(text, date);

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
  with team_session_rows as (
    select session_row.professional_id, session_row.team_member_id
    from public.validar_sessao_equipe(p_access_token) as session_row
  ),
  session_timezone as (
    select coalesce(
      professional_config.timezone,
      'America/Sao_Paulo'
    ) as timezone
    from team_session_rows
    left join public.profissionais_config as professional_config
      on professional_config.profissional_id =
        team_session_rows.professional_id
  ),
  requested_day as (
    select coalesce(
      p_day,
      (now() at time zone session_timezone.timezone)::date
    ) as day,
    session_timezone.timezone
    from session_timezone
  ),
  day_bounds as (
    select requested_day.day::timestamp
             at time zone requested_day.timezone as starts_at,
           (requested_day.day + 1)::timestamp
             at time zone requested_day.timezone as ends_at
    from requested_day
  )
  select appointment.id as appointment_id,
         appointment.data_hora_inicio as appointment_starts_at,
         service_row.titulo as service_title,
         coalesce(client_profile.nome, salon_client.nome, 'Cliente')
           as client_name,
         appointment.valor as appointment_value,
         appointment.status as appointment_status
  from team_session_rows
  cross join day_bounds
  join public.agendamentos as appointment
    on appointment.profissional_id = team_session_rows.professional_id
    and appointment.team_member_id = team_session_rows.team_member_id
  join public.servicos as service_row
    on service_row.id = appointment.servico_id
  left join public.perfis as client_profile
    on client_profile.id = appointment.cliente_id
  left join public.clientes_salao as salon_client
    on salon_client.id = appointment.cliente_salao_id
  where appointment.data_hora_inicio >= day_bounds.starts_at
    and appointment.data_hora_inicio < day_bounds.ends_at
    and appointment.status <> 'cancelado'
  order by appointment.data_hora_inicio
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
  select salon_client.id as client_id,
         salon_client.nome as client_name,
         salon_client.telefone as client_phone
  from public.validar_sessao_equipe(p_access_token) as team_session
  join public.clientes_salao as salon_client
    on salon_client.team_member_id = team_session.team_member_id
   and salon_client.profissional_id = team_session.professional_id
  order by salon_client.nome
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

  perform set_config(
    'request.jwt.claim.sub', v_professional_id::text, true
  );

  insert into public.agendamentos (
    profissional_id,
    cliente_salao_id,
    servico_id,
    team_member_id,
    data_hora_inicio,
    tipo_pagamento,
    valor,
    status
  )
  values (
    v_professional_id,
    p_client_id,
    p_service_id,
    v_team_member_id,
    p_starts_at,
    'local',
    0,
    'confirmado'
  );
end;
$$;

revoke all on function public.servicos_equipe_com_sessao(text)
  from public;
grant execute on function public.servicos_equipe_com_sessao(text)
  to anon, authenticated;

revoke all on function public.clientes_equipe_com_sessao(text)
  from public;
grant execute on function public.clientes_equipe_com_sessao(text)
  to anon, authenticated;

revoke all on function public.criar_agendamento_equipe_com_sessao(
  text, uuid, uuid, timestamptz
) from public;
grant execute on function public.criar_agendamento_equipe_com_sessao(
  text, uuid, uuid, timestamptz
) to anon, authenticated;

revoke all on function public.agenda_equipe_com_sessao(text, date)
  from public;
grant execute on function public.agenda_equipe_com_sessao(text, date)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
