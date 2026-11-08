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

create table if not exists public.perfis (
  id uuid primary key references auth.users (id) on delete cascade,
  nome text not null,
  email text not null,
  telefone text,
  tipo text not null check (tipo in ('cliente', 'profissional')),
  status_acesso text not null default 'pendente'
    check (
      status_acesso in ('pendente', 'ativo', 'bloqueado', 'cortesia', 'recusado')
    ),
  plano_assinatura text not null default 'gratis',
  tema_preferido text not null default 'light'
    check (tema_preferido in ('light', 'dark', 'colorfulLight', 'colorfulDark')),
  criado_em timestamptz not null default now()
);

create table if not exists public.profissionais_equipe (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  nome text not null check (length(trim(nome)) > 0),
  pin_hash text,
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint team_member_id_professional_unique unique (id, profissional_id)
);

create unique index if not exists profissionais_equipe_nome_unico_idx
  on public.profissionais_equipe (
    profissional_id,
    lower(regexp_replace(btrim(nome), '[[:space:]]+', ' ', 'g'))
  );

create table if not exists public.profissionais_equipe_pin_tentativas (
  team_member_id uuid primary key
    references public.profissionais_equipe (id) on delete cascade,
  tentativas_falhas integer not null default 0,
  bloqueado_ate timestamptz
);

create table if not exists public.profissionais_equipe_sessoes (
  token_hash text primary key,
  team_member_id uuid not null
    references public.profissionais_equipe (id) on delete cascade,
  expira_em timestamptz not null,
  criado_em timestamptz not null default now()
);
create index if not exists profissionais_equipe_sessoes_expira_em_idx
  on public.profissionais_equipe_sessoes (expira_em);

create table if not exists public.profissionais_config (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null unique references public.perfis (id) on delete cascade,
  horario_inicio time not null default '09:00',
  horario_fim time not null default '18:00',
  almoco_inicio time,
  almoco_fim time,
  timezone text not null default 'America/Sao_Paulo',
  dias_abertos smallint[] not null default array[1,2,3,4,5,6]::smallint[],
  dias_folga date[] not null default '{}',
  aceita_pacotes boolean not null default false,
  dias_pacotes_permitidos smallint[] not null default array[1,2,3]::smallint[],
  permite_pagamento_local boolean not null default false,
  criado_em timestamptz not null default now(),
  constraint horario_valido check (horario_inicio < horario_fim),
  constraint intervalo_almoco_valido check (
    (almoco_inicio is null and almoco_fim is null)
    or (almoco_inicio is not null and almoco_fim is not null and almoco_inicio < almoco_fim)
  )
);

create table if not exists public.profissionais_pagamentos (
  profissional_id uuid primary key references public.perfis (id) on delete cascade,
  chave_pix text
);

create table if not exists public.servicos (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  titulo text not null check (length(trim(titulo)) > 0),
  categoria text not null,
  preco numeric(10,2) not null check (preco >= 0),
  duracao_minutos integer not null check (duracao_minutos between 5 and 600),
  ativo boolean not null default true,
  criado_em timestamptz not null default now(),
  constraint servicos_id_profissional_unique unique (id, profissional_id)
);

create index if not exists servicos_profissional_ativo_idx
  on public.servicos (profissional_id, ativo);

create table if not exists public.clientes_salao (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  team_member_id uuid,
  nome text not null check (length(trim(nome)) > 0),
  telefone text not null check (
    length(regexp_replace(telefone, '[^0-9]', '', 'g')) between 8 and 15
  ),
  criado_em timestamptz not null default now(),
  constraint cliente_salao_equipe_profissional_fk
    foreign key (team_member_id, profissional_id)
    references public.profissionais_equipe (id, profissional_id)
);

create unique index if not exists clientes_salao_profissional_telefone_idx
  on public.clientes_salao (
    profissional_id,
    (regexp_replace(telefone, '[^0-9]', '', 'g'))
  );

create table if not exists public.pacotes_clientes (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfis (id) on delete cascade,
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  servico_id uuid not null references public.servicos (id) on delete restrict,
  creditos_restantes integer not null check (creditos_restantes >= 0),
  tipo_plano text not null,
  dias_permitidos_semana smallint[] not null default array[1,2,3]::smallint[],
  criado_em timestamptz not null default now(),
  constraint pacote_servico_profissional_fk
    foreign key (servico_id, profissional_id)
    references public.servicos (id, profissional_id)
);

create table if not exists public.agendamentos (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  cliente_id uuid references public.perfis (id) on delete cascade,
  cliente_salao_id uuid references public.clientes_salao (id) on delete restrict,
  servico_id uuid not null references public.servicos (id) on delete restrict,
  team_member_id uuid not null,
  data_hora_inicio timestamptz not null,
  tipo_pagamento text not null check (tipo_pagamento in ('pix_antecipado', 'local')),
  valor numeric(10,2) not null check (valor >= 0),
  status text not null default 'pendente'
    check (status in ('pendente', 'confirmado', 'concluido', 'cancelado')),
  criado_em timestamptz not null default now(),
  constraint agendamento_servico_profissional_fk
    foreign key (servico_id, profissional_id)
    references public.servicos (id, profissional_id),
  constraint agendamento_cliente_unico_check
    check (num_nonnulls(cliente_id, cliente_salao_id) = 1),
  constraint agendamento_equipe_profissional_fk
    foreign key (team_member_id, profissional_id)
    references public.profissionais_equipe (id, profissional_id)
);

create index if not exists agendamentos_profissional_data_idx
  on public.agendamentos (profissional_id, data_hora_inicio);
create index if not exists agendamentos_cliente_data_idx
  on public.agendamentos (cliente_id, data_hora_inicio);

create or replace function public.criar_perfil_e_config()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tipo text := coalesce(new.raw_user_meta_data ->> 'tipo', 'profissional');
begin
  if v_tipo not in ('cliente', 'profissional') then
    raise exception 'Tipo de perfil inválido';
  end if;

  insert into public.perfis (id, nome, email, telefone, tipo)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'nome'), ''), split_part(new.email, '@', 1)),
    new.email,
    coalesce(nullif(trim(new.phone), ''), nullif(trim(new.raw_user_meta_data ->> 'telefone'), '')),
    v_tipo
  );

  if v_tipo = 'profissional' then
    insert into public.profissionais_config (profissional_id) values (new.id);
    insert into public.profissionais_pagamentos (profissional_id) values (new.id);
    insert into public.profissionais_equipe (profissional_id, nome)
    select p.id, p.nome
    from public.perfis p
    where p.id = new.id
      and not exists (
        select 1
        from public.profissionais_equipe e
        where e.profissional_id = p.id
      );
  end if;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.criar_perfil_e_config();

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
  if new.team_member_id is null then
    raise exception 'Selecione um profissional da equipe para o agendamento';
  end if;

  if new.profissional_id = auth.uid() then
    if not exists (
      select 1 from public.perfis p
      where p.id = auth.uid() and p.tipo = 'profissional'
    ) then
      raise exception 'Agendamento manual requer um cliente cadastrado';
    end if;
    if new.cliente_id is not null and not exists (
      select 1 from public.perfis p
      where p.id = new.cliente_id and p.tipo = 'cliente'
    ) then
      raise exception 'Cliente inválido para este agendamento';
    end if;
    if new.cliente_salao_id is not null and not exists (
      select 1 from public.clientes_salao c
      where c.id = new.cliente_salao_id
        and c.profissional_id = new.profissional_id
    ) then
      raise exception 'Cliente não pertence a este salão';
    end if;
    if new.cliente_id is null and new.cliente_salao_id is null then
      raise exception 'Selecione ou cadastre um cliente para o agendamento';
    end if;
  elsif new.cliente_salao_id is not null
    or new.cliente_id is distinct from auth.uid()
    or not exists (
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

drop trigger if exists before_agendamento_insert on public.agendamentos;
create trigger before_agendamento_insert
  before insert on public.agendamentos
  for each row execute function public.validar_agendamento();

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
    or new.cliente_id is distinct from old.cliente_id
    or new.cliente_salao_id is distinct from old.cliente_salao_id
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

drop trigger if exists before_agendamento_update on public.agendamentos;
create trigger before_agendamento_update
  before update on public.agendamentos
  for each row execute function public.proteger_agendamento();

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
revoke all on public.profissionais_equipe_sessoes
  from public, anon, authenticated;
revoke all on function public.definir_pin_profissional_equipe(uuid, text)
  from public, anon;
revoke all on function public.agenda_equipe_com_pin(uuid, text)
  from public;
grant execute on function public.definir_pin_profissional_equipe(uuid, text)
  to authenticated;
grant execute on function public.agenda_equipe_com_pin(uuid, text)
  to anon, authenticated;

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

drop function if exists public.servicos_equipe_com_sessao(text);
create function public.servicos_equipe_com_sessao(
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
create function public.agenda_equipe_com_sessao(
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

create or replace function public.agenda_profissional_por_dia(
  p_professional_id uuid,
  p_day date
)
returns table (
  appointment_id uuid,
  professional_id uuid,
  client_id uuid,
  salon_client_id uuid,
  service_id uuid,
  team_member_id uuid,
  appointment_starts_at timestamptz,
  service_title text,
  client_name text,
  appointment_value numeric,
  payment_type text,
  appointment_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_timezone text;
begin
  if p_professional_id is null
    or (
      auth.uid() is distinct from p_professional_id
      and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin'
    )
  then
    raise exception 'Acesso não autorizado à agenda do profissional';
  end if;

  select coalesce(c.timezone, 'America/Sao_Paulo')
    into v_timezone
  from public.perfis p
  left join public.profissionais_config c on c.profissional_id = p.id
  where p.id = p_professional_id
    and p.tipo = 'profissional';

  if not found then
    raise exception 'Profissional não encontrado';
  end if;

  return query
  select a.id,
         a.profissional_id,
         a.cliente_id,
         a.cliente_salao_id,
         a.servico_id,
         a.team_member_id,
         a.data_hora_inicio,
         s.titulo,
         coalesce(p.nome, cs.nome, 'Cliente'),
         a.valor,
         a.tipo_pagamento,
         a.status
  from public.agendamentos a
  join public.servicos s on s.id = a.servico_id
  left join public.perfis p on p.id = a.cliente_id
  left join public.clientes_salao cs on cs.id = a.cliente_salao_id
  where a.profissional_id = p_professional_id
    and a.data_hora_inicio >= p_day::timestamp at time zone v_timezone
    and a.data_hora_inicio < (p_day + 1)::timestamp at time zone v_timezone
    and a.status <> 'cancelado'
  order by a.data_hora_inicio;
end;
$$;

revoke all on public.profissionais_equipe_sessoes
  from public, anon, authenticated;
revoke all on function public.autenticar_equipe_com_pin(uuid, text)
  from public;
revoke all on function public.validar_sessao_equipe(text)
  from public, anon, authenticated;
revoke all on function public.servicos_equipe_com_sessao(text)
  from public;
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
revoke all on function public.agenda_profissional_por_dia(uuid, date)
  from public;
grant execute on function public.autenticar_equipe_com_pin(uuid, text)
  to anon, authenticated;
grant execute on function public.agenda_equipe_com_sessao(text, date)
  to anon, authenticated;
grant execute on function public.servicos_equipe_com_sessao(text)
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
grant execute on function public.agenda_profissional_por_dia(uuid, date)
  to authenticated;

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
    raise exception 'Informe o salão e a data para consultar horários';
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
      raise exception 'Salão ou membro da equipe não encontrado';
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
    raise exception 'Membro da equipe não encontrado para este salão';
  end if;

  select c.timezone,
         c.almoco_inicio,
         c.almoco_fim,
         c.dias_abertos,
         c.dias_folga
    into v_timezone,
         v_horario_almoco_inicio,
         v_horario_almoco_fim,
         v_dias_abertos,
         v_dias_folga
  from public.perfis p
  left join public.profissionais_config c
    on c.profissional_id = p.id
  where p.id = v_profissional_id
    and p.tipo = 'profissional';

  if not found then
    raise exception 'Configuração do salão não encontrada';
  end if;

  v_timezone := coalesce(v_timezone, 'America/Sao_Paulo');
  v_dias_abertos := coalesce(v_dias_abertos, array[1,2,3,4,5,6]::smallint[]);
  v_dias_folga := coalesce(v_dias_folga, array[]::date[]);

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

create or replace function public.proteger_tipo_perfil()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if new.id <> old.id or new.email <> old.email or new.tipo <> old.tipo then
    raise exception 'Identidade, e-mail e tipo de perfil não podem ser alterados pelo cliente';
  end if;
  return new;
end;
$$;

drop trigger if exists before_perfil_update on public.perfis;
create trigger before_perfil_update
  before update on public.perfis
  for each row execute function public.proteger_tipo_perfil();

create or replace function public.proteger_status_assinatura()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.role() = 'authenticated'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin'
    and (
      new.status_acesso is distinct from old.status_acesso
      or new.plano_assinatura is distinct from old.plano_assinatura
    )
  then
    raise exception 'O status e o plano da assinatura não podem ser alterados pelo usuário';
  end if;
  return new;
end;
$$;

drop trigger if exists before_perfil_subscription_update on public.perfis;
create trigger before_perfil_subscription_update
  before update of status_acesso, plano_assinatura on public.perfis
  for each row execute function public.proteger_status_assinatura();

alter table public.perfis enable row level security;
alter table public.clientes_salao enable row level security;
alter table public.profissionais_equipe enable row level security;
alter table public.profissionais_equipe_pin_tentativas enable row level security;
alter table public.profissionais_equipe_sessoes enable row level security;
alter table public.profissionais_config enable row level security;
alter table public.profissionais_pagamentos enable row level security;
alter table public.servicos enable row level security;
alter table public.pacotes_clientes enable row level security;
alter table public.agendamentos enable row level security;

drop policy if exists "perfil próprio visível ao titular" on public.perfis;
create policy "perfil próprio visível ao titular"
  on public.perfis for select to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1 from public.agendamentos a
      where a.cliente_id = perfis.id
        and a.profissional_id = auth.uid()
    )
  );
drop policy if exists "administrador lista perfis" on public.perfis;
create policy "administrador lista perfis"
  on public.perfis for select to authenticated
  using (
    tipo = 'profissional'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
  );
drop policy if exists "perfil próprio atualizado pelo titular" on public.perfis;
create policy "perfil próprio atualizado pelo titular"
  on public.perfis for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

drop policy if exists "profissional gerencia os próprios clientes do salão"
  on public.clientes_salao;
create policy "profissional gerencia os próprios clientes do salão"
  on public.clientes_salao for all to authenticated
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

create or replace function public.admin_set_access_status(
  p_profile_id uuid,
  p_status text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') <> 'admin' then
    raise exception 'Apenas administradores podem alterar status de acesso';
  end if;

  if p_status is null
    or p_status not in (
      'pendente', 'ativo', 'bloqueado', 'cortesia', 'recusado'
    )
  then
    raise exception 'Status de acesso inválido';
  end if;

  update public.perfis
  set status_acesso = p_status
  where id = p_profile_id and tipo = 'profissional';

  if not found then
    raise exception 'Perfil não encontrado';
  end if;
end;
$$;

revoke all on function public.admin_set_access_status(uuid, text) from public;
grant execute on function public.admin_set_access_status(uuid, text)
  to authenticated;

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

drop policy if exists "configuração visível para agendamento"
  on public.profissionais_config;
create policy "configuração visível para agendamento"
  on public.profissionais_config for select to anon, authenticated
  using (true);
drop policy if exists "profissional cria própria configuração"
  on public.profissionais_config;
create policy "profissional cria própria configuração"
  on public.profissionais_config for insert to authenticated
  with check (profissional_id = (select auth.uid()));
drop policy if exists "profissional atualiza própria configuração"
  on public.profissionais_config;
create policy "profissional atualiza própria configuração"
  on public.profissionais_config for update to authenticated
  using (profissional_id = (select auth.uid()))
  with check (profissional_id = (select auth.uid()));

drop policy if exists "chave PIX visível para clientes"
  on public.profissionais_pagamentos;
create policy "chave PIX visível para clientes"
  on public.profissionais_pagamentos for select to anon, authenticated
  using (true);
drop policy if exists "profissional cria própria chave PIX"
  on public.profissionais_pagamentos;
create policy "profissional cria própria chave PIX"
  on public.profissionais_pagamentos for insert to authenticated
  with check (profissional_id = (select auth.uid()));
drop policy if exists "profissional atualiza própria chave PIX"
  on public.profissionais_pagamentos;
create policy "profissional atualiza própria chave PIX"
  on public.profissionais_pagamentos for update to authenticated
  using (profissional_id = (select auth.uid()))
  with check (profissional_id = (select auth.uid()));

drop policy if exists "serviços ativos visíveis publicamente"
  on public.servicos;
create policy "serviços ativos visíveis publicamente"
  on public.servicos for select to anon, authenticated
  using (ativo or profissional_id = (select auth.uid()));
drop policy if exists "profissional gerencia próprios serviços"
  on public.servicos;
create policy "profissional gerencia próprios serviços"
  on public.servicos for all to authenticated
  using (profissional_id = (select auth.uid()))
  with check (
    profissional_id = (select auth.uid())
    and exists (
      select 1 from public.perfis p
      where p.id = (select auth.uid()) and p.tipo = 'profissional'
    )
  );

drop policy if exists "cliente e profissional consultam seus pacotes"
  on public.pacotes_clientes;
create policy "cliente e profissional consultam seus pacotes"
  on public.pacotes_clientes for select to authenticated
  using (cliente_id = (select auth.uid()) or profissional_id = (select auth.uid()));
drop policy if exists "profissional emite pacote para cliente"
  on public.pacotes_clientes;
create policy "profissional emite pacote para cliente"
  on public.pacotes_clientes for insert to authenticated
  with check (
    profissional_id = (select auth.uid())
    and exists (
      select 1 from public.profissionais_config c
      where c.profissional_id = (select auth.uid()) and c.aceita_pacotes
    )
  );

drop policy if exists "participantes consultam agendamento"
  on public.agendamentos;
create policy "participantes consultam agendamento"
  on public.agendamentos for select to authenticated
  using (cliente_id = auth.uid() or profissional_id = auth.uid());
drop policy if exists "cliente ou profissional cria agendamento"
  on public.agendamentos;
create policy "cliente ou profissional cria agendamento"
  on public.agendamentos for insert to authenticated
  with check (cliente_id = auth.uid() or profissional_id = auth.uid());
drop policy if exists "profissional atualiza status dos próprios agendamentos"
  on public.agendamentos;
create policy "profissional atualiza status dos próprios agendamentos"
  on public.agendamentos for update to authenticated
  using (profissional_id = auth.uid())
  with check (profissional_id = auth.uid());

grant select, update on public.perfis to authenticated;
grant select, insert, update, delete on public.clientes_salao to authenticated;
revoke all on public.profissionais_equipe from authenticated;
grant select (id, profissional_id, nome, ativo, criado_em)
  on public.profissionais_equipe to authenticated;
grant insert (profissional_id, nome, ativo)
  on public.profissionais_equipe to authenticated;
grant update (nome, ativo)
  on public.profissionais_equipe to authenticated;
grant delete on public.profissionais_equipe to authenticated;
grant select on public.profissionais_config to anon, authenticated;
grant insert, update on public.profissionais_config to authenticated;
grant select on public.profissionais_pagamentos to anon, authenticated;
grant insert, update on public.profissionais_pagamentos to authenticated;
grant select on public.servicos to anon, authenticated;
grant insert, update, delete on public.servicos to authenticated;
grant select, insert on public.pacotes_clientes to authenticated;
grant select, insert, update on public.agendamentos to authenticated;
revoke all on function public.horarios_ocupados(uuid, date, uuid) from public;
grant execute on function public.horarios_ocupados(uuid, date, uuid) to anon, authenticated;
