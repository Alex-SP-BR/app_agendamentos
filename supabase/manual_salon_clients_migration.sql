begin;

alter table public.perfis
  add column if not exists telefone text;

update public.perfis p
set telefone = nullif(trim(u.phone), '')
from auth.users u
where u.id = p.id
  and p.telefone is null
  and nullif(trim(u.phone), '') is not null;

create table if not exists public.clientes_salao (
  id uuid primary key default gen_random_uuid(),
  profissional_id uuid not null references public.perfis (id) on delete cascade,
  nome text not null check (length(trim(nome)) > 0),
  telefone text not null check (
    length(regexp_replace(telefone, '[^0-9]', '', 'g')) between 8 and 15
  ),
  criado_em timestamptz not null default now()
);

create unique index if not exists clientes_salao_profissional_telefone_idx
  on public.clientes_salao (
    profissional_id,
    (regexp_replace(telefone, '[^0-9]', '', 'g'))
  );

alter table public.agendamentos
  alter column cliente_id drop not null,
  add column if not exists cliente_salao_id uuid
    references public.clientes_salao (id) on delete restrict;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'agendamento_cliente_unico_check'
      and conrelid = 'public.agendamentos'::regclass
  ) then
    alter table public.agendamentos
      add constraint agendamento_cliente_unico_check
      check (num_nonnulls(cliente_id, cliente_salao_id) = 1);
  end if;
end;
$$;

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
    coalesce(
      nullif(trim(new.phone), ''),
      nullif(trim(new.raw_user_meta_data ->> 'telefone'), '')
    ),
    v_tipo
  );

  if v_tipo = 'profissional' then
    insert into public.profissionais_config (profissional_id) values (new.id);
    insert into public.profissionais_pagamentos (profissional_id) values (new.id);
  end if;
  return new;
end;
$$;

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
    )
  then
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
      and a.team_member_id = new.team_member_id
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
        and a.team_member_id = new.team_member_id
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

alter table public.clientes_salao enable row level security;

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

drop policy if exists "cliente cria próprio agendamento" on public.agendamentos;
drop policy if exists "cliente ou profissional cria agendamento"
  on public.agendamentos;
create policy "cliente ou profissional cria agendamento"
  on public.agendamentos for insert to authenticated
  with check (
    (
      cliente_id = (select auth.uid())
      and cliente_salao_id is null
      and exists (
        select 1 from public.perfis p
        where p.id = (select auth.uid()) and p.tipo = 'cliente'
      )
    )
    or (
      profissional_id = (select auth.uid())
      and exists (
        select 1 from public.perfis p
        where p.id = (select auth.uid()) and p.tipo = 'profissional'
      )
    )
  );

grant select, insert, update, delete on public.clientes_salao to authenticated;

notify pgrst, 'reload schema';

commit;
