begin;

create table if not exists public.profissionais_equipe (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  nome text not null check (length(trim(nome)) > 0),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint team_member_id_professional_unique unique (id, profissional_id)
);

alter table public.agendamentos
  add column if not exists team_member_id uuid;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamento_team_member_professional_fk'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table public.agendamentos
      add constraint agendamento_team_member_professional_fk
      foreign key (team_member_id, profissional_id)
      references public.profissionais_equipe (id, profissional_id);
  end if;
end;
$$;

alter table public.profissionais_equipe enable row level security;

drop policy if exists "profissional consulta própria equipa"
  on public.profissionais_equipe;
create policy "profissional consulta própria equipa"
  on public.profissionais_equipe for select to authenticated
  using (profissional_id = (select auth.uid()));

drop policy if exists "profissional gere própria equipa"
  on public.profissionais_equipe;
create policy "profissional gere própria equipa"
  on public.profissionais_equipe for all to authenticated
  using (
    profissional_id = (select auth.uid())
    and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.tipo = 'profissional'
    )
  )
  with check (
    profissional_id = (select auth.uid())
    and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.tipo = 'profissional'
    )
  );

drop policy if exists "perfil próprio visível ao titular" on public.perfis;
create policy "perfil próprio visível ao titular"
  on public.perfis for select to authenticated
  using (
    id = (select auth.uid())
    or exists (
      select 1 from public.agendamentos a
      where a.cliente_id = perfis.id
        and a.profissional_id = (select auth.uid())
    )
  );

create or replace function public.validar_agendamento()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_preco numeric(10,2);
  v_ativo boolean;
  v_duracao integer;
  v_perm_local boolean;
  v_horario_inicio time;
  v_horario_fim time;
  v_almoco_inicio time;
  v_almoco_fim time;
  v_dias_abertos smallint[];
  v_dias_folga date[];
  v_timezone text;
  v_inicio_local timestamp;
  v_fim_local timestamp;
begin
  if new.profissional_id = auth.uid() then
    if not exists (
      select 1 from public.perfis p
      where p.id = auth.uid() and p.tipo = 'profissional'
    ) or not exists (
      select 1 from public.perfis p
      where p.id = new.cliente_id and p.tipo = 'cliente'
    ) then
      raise exception 'Agendamento manual requer um cliente cadastrado';
    end if;
  elsif new.cliente_id <> auth.uid() or not exists (
    select 1 from public.perfis p
    where p.id = auth.uid() and p.tipo = 'cliente'
  ) then
    raise exception 'O cliente do agendamento deve ser o usuário autenticado';
  end if;

  if new.team_member_id is not null and not exists (
    select 1 from public.profissionais_equipe e
    where e.id = new.team_member_id
      and e.profissional_id = new.profissional_id
      and e.ativo
  ) then
    raise exception 'Membro da equipa indisponível';
  end if;

  select s.preco, s.ativo, s.duracao_minutos
    into v_preco, v_ativo, v_duracao
  from public.servicos s
  where s.id = new.servico_id and s.profissional_id = new.profissional_id;
  if not found or not v_ativo then
    raise exception 'Serviço indisponível para este profissional';
  end if;

  select c.permite_pagamento_local,
         c.horario_inicio,
         c.horario_fim,
         c.almoco_inicio,
         c.almoco_fim,
         c.dias_abertos,
         c.dias_folga,
         c.timezone
    into v_perm_local,
         v_horario_inicio,
         v_horario_fim,
         v_almoco_inicio,
         v_almoco_fim,
         v_dias_abertos,
         v_dias_folga,
         v_timezone
  from public.profissionais_config c
  where c.profissional_id = new.profissional_id;
  if new.tipo_pagamento = 'local'
    and not coalesce(v_perm_local, false)
    and new.profissional_id <> auth.uid()
  then
    raise exception 'Este profissional não permite pagamento local';
  end if;

  v_inicio_local := new.data_hora_inicio at time zone v_timezone;
  v_fim_local := v_inicio_local + make_interval(mins => v_duracao);
  if new.data_hora_inicio <= now()
    or not (extract(isodow from v_inicio_local)::smallint = any(v_dias_abertos))
    or v_inicio_local::date = any(v_dias_folga)
    or v_inicio_local::time < v_horario_inicio
    or v_fim_local::date <> v_inicio_local::date
    or v_fim_local::time > v_horario_fim
  then
    raise exception 'Horário fora da disponibilidade do profissional';
  end if;

  if v_almoco_inicio is not null
    and v_almoco_fim is not null
    and v_inicio_local::time < v_almoco_fim
    and v_fim_local::time > v_almoco_inicio
  then
    raise exception 'O horário coincide com a pausa do profissional';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(
      new.profissional_id::text || ':' || v_inicio_local::date::text,
      0
    )
  );
  if exists (
    select 1
    from public.agendamentos a
    join public.servicos s on s.id = a.servico_id
    where a.profissional_id = new.profissional_id
      and a.team_member_id is not distinct from new.team_member_id
      and a.status in ('pendente', 'confirmado')
      and a.data_hora_inicio <
        (new.data_hora_inicio + make_interval(mins => v_duracao))
      and (a.data_hora_inicio + make_interval(mins => s.duracao_minutos)) >
        new.data_hora_inicio
  ) then
    raise exception 'Este horário acabou de ser reservado. Escolha outro horário.';
  end if;

  new.valor := v_preco;
  new.status := case
    when new.profissional_id = auth.uid() then 'confirmado'
    else 'pendente'
  end;
  return new;
end;
$$;

create or replace function public.proteger_agendamento()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_timezone text;
begin
  if new.id <> old.id
    or new.profissional_id <> old.profissional_id
    or new.cliente_id <> old.cliente_id
    or new.servico_id <> old.servico_id
    or new.team_member_id is distinct from old.team_member_id
    or new.data_hora_inicio <> old.data_hora_inicio
    or new.tipo_pagamento <> old.tipo_pagamento
    or new.valor <> old.valor
  then
    raise exception 'Somente o status do agendamento pode ser alterado';
  end if;

  if new.status in ('pendente', 'confirmado')
    and old.status not in ('pendente', 'confirmado')
  then
    select c.timezone into v_timezone
    from public.profissionais_config c
    where c.profissional_id = new.profissional_id;
    perform pg_advisory_xact_lock(
      hashtextextended(
        new.profissional_id::text || ':' ||
          (new.data_hora_inicio at time zone v_timezone)::date::text,
        0
      )
    );
    if exists (
      select 1
      from public.agendamentos a
      join public.servicos s on s.id = a.servico_id
      join public.servicos own_service on own_service.id = new.servico_id
      where a.profissional_id = new.profissional_id
        and a.team_member_id is not distinct from new.team_member_id
        and a.id <> old.id
        and a.status in ('pendente', 'confirmado')
        and a.data_hora_inicio <
          (new.data_hora_inicio + make_interval(mins => own_service.duracao_minutos))
        and (a.data_hora_inicio + make_interval(mins => s.duracao_minutos)) >
          new.data_hora_inicio
    ) then
      raise exception 'Este horário já está ocupado por outro agendamento';
    end if;
  end if;
  return new;
end;
$$;

drop function if exists public.horarios_ocupados(uuid, date);
drop function if exists public.horarios_ocupados(uuid, date, uuid);
create function public.horarios_ocupados(
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
  v_timezone text;
begin
  if p_profissional_id is null or p_data is null
    or p_team_member_id is null
  then
    raise exception 'Informe o salão, membro da equipe e data para consultar horários';
  end if;

  select c.timezone into v_timezone
  from public.profissionais_config c
  where c.profissional_id = p_profissional_id;

  if not found then
    raise exception 'Profissional não encontrado';
  end if;

  if not exists (
    select 1
    from public.profissionais_equipe e
    where e.id = p_team_member_id
      and e.profissional_id = p_profissional_id
      and e.ativo
  ) then
    raise exception 'Membro da equipe não encontrado para este profissional';
  end if;

  return query
  select a.data_hora_inicio, s.duracao_minutos
  from public.agendamentos a
  join public.servicos s on s.id = a.servico_id
  where a.profissional_id = p_profissional_id
    and a.team_member_id = p_team_member_id
    and a.status in ('pendente', 'confirmado')
    and a.data_hora_inicio >= (p_data::timestamp at time zone v_timezone)
    and a.data_hora_inicio < ((p_data + 1)::timestamp at time zone v_timezone);
end;
$$;

drop policy if exists "cliente cria próprio agendamento" on public.agendamentos;
drop policy if exists "cliente ou profissional cria agendamento"
  on public.agendamentos;
create policy "cliente ou profissional cria agendamento"
  on public.agendamentos for insert to authenticated
  with check (
    (cliente_id = (select auth.uid()) and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.tipo = 'cliente'
    ))
    or (profissional_id = (select auth.uid()) and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.tipo = 'profissional'
    ))
  );

grant select, insert, update, delete on public.profissionais_equipe
  to authenticated;
grant select, insert, update on public.agendamentos to authenticated;
revoke all on function public.horarios_ocupados(uuid, date, uuid) from public;
grant execute on function public.horarios_ocupados(uuid, date, uuid)
  to anon, authenticated;

commit;
