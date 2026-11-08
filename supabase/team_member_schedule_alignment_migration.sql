begin;

create or replace function public.horarios_ocupados(
  p_profissional_id uuid,
  p_data date,
  p_team_member_id uuid default null
)
returns table (starts_at timestamptz, duration_minutes integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_profissional_id uuid;
  v_team_member_id uuid := p_team_member_id;
  v_timezone text;
  v_horario_almoco_inicio time;
  v_horario_almoco_fim time;
  v_dias_abertos smallint[];
  v_dias_folga date[];
  v_inicio_dia timestamptz;
  v_fim_dia timestamptz;
begin
  if p_profissional_id is null or p_data is null then
    raise exception 'Informe o profissional e a data para consultar horários';
  end if;

  select p.id
    into v_profissional_id
  from public.perfis p
  where p.id = p_profissional_id
    and p.tipo = 'profissional';

  if not found then
    select e.profissional_id, e.id
      into v_profissional_id, v_team_member_id
    from public.profissionais_equipe e
    where e.id = p_profissional_id
      and e.ativo;

    if not found then
      raise exception 'Profissional ou membro da equipe não encontrado';
    end if;

    if p_team_member_id is not null
      and p_team_member_id is distinct from v_team_member_id
    then
      raise exception 'O membro informado não corresponde ao profissional';
    end if;
  elsif v_team_member_id is null then
    raise exception 'Informe o profissional da equipe para consultar horários';
  elsif not exists (
    select 1
    from public.profissionais_equipe e
    where e.id = v_team_member_id
      and e.profissional_id = v_profissional_id
      and e.ativo
  ) then
    raise exception 'Membro da equipe não encontrado para este profissional';
  end if;

  select coalesce(c.timezone, 'America/Sao_Paulo'),
         c.almoco_inicio,
         c.almoco_fim,
         coalesce(c.dias_abertos, array[1,2,3,4,5,6]::smallint[]),
         coalesce(c.dias_folga, array[]::date[])
    into v_timezone,
         v_horario_almoco_inicio,
         v_horario_almoco_fim,
         v_dias_abertos,
         v_dias_folga
  from public.perfis p
  left join public.profissionais_config c on c.profissional_id = p.id
  where p.id = v_profissional_id
    and p.tipo = 'profissional';

  if not found then
    raise exception 'Profissional não encontrado';
  end if;

  v_inicio_dia := p_data::timestamp at time zone v_timezone;
  v_fim_dia := (p_data + 1)::timestamp at time zone v_timezone;

  if not (extract(isodow from p_data)::smallint = any(v_dias_abertos))
    or p_data = any(v_dias_folga)
  then
    return query
    select v_inicio_dia,
           (extract(epoch from (v_fim_dia - v_inicio_dia)) / 60)::integer;
    return;
  end if;

  return query
  select a.data_hora_inicio, s.duracao_minutos
  from public.agendamentos a
  join public.servicos s on s.id = a.servico_id
  where a.profissional_id = v_profissional_id
    and a.team_member_id = v_team_member_id
    and a.status in ('pendente', 'confirmado')
    and a.data_hora_inicio >= v_inicio_dia
    and a.data_hora_inicio < v_fim_dia;

  if v_horario_almoco_inicio is not null
    and v_horario_almoco_fim is not null
  then
    return query
    select (p_data + v_horario_almoco_inicio) at time zone v_timezone,
           (extract(
             epoch from (
               v_horario_almoco_fim - v_horario_almoco_inicio
             )
           ) / 60)::integer;
  end if;
end;
$$;

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
  left join public.profissionais_config c
    on c.profissional_id = team_session.professional_id
  join public.agendamentos a
    on a.profissional_id = team_session.professional_id
    and a.team_member_id = team_session.team_member_id
  join public.servicos s on s.id = a.servico_id
  left join public.perfis p on p.id = a.cliente_id
  left join public.clientes_salao cs on cs.id = a.cliente_salao_id
  where a.data_hora_inicio >=
      coalesce(
        p_day,
        (now() at time zone coalesce(c.timezone, 'America/Sao_Paulo'))::date
      )::timestamp at time zone coalesce(c.timezone, 'America/Sao_Paulo')
    and a.data_hora_inicio <
      (
        coalesce(
          p_day,
          (now() at time zone coalesce(c.timezone, 'America/Sao_Paulo'))::date
        ) + 1
      )::timestamp at time zone coalesce(c.timezone, 'America/Sao_Paulo')
    and a.status <> 'cancelado'
  order by a.data_hora_inicio
$$;

revoke all on function public.horarios_ocupados(uuid, date, uuid)
  from public;
grant execute on function public.horarios_ocupados(uuid, date, uuid)
  to anon, authenticated;

revoke all on function public.agenda_equipe_com_sessao(text, date)
  from public;
grant execute on function public.agenda_equipe_com_sessao(text, date)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
