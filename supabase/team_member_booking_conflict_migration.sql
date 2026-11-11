begin;

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

do $$
declare
  v_definition text;
  v_updated_definition text;
begin
  select pg_get_functiondef(
    'public.proteger_agendamento()'::regprocedure
  )
    into v_definition;

  if v_definition !~* 'where[[:space:]]+a\.profissional_id[[:space:]]*=[[:space:]]*new\.profissional_id[[:space:]]+and[[:space:]]+a\.team_member_id[[:space:]]*(=[[:space:]]*|is[[:space:]]+not[[:space:]]+distinct[[:space:]]+from[[:space:]]+)new\.team_member_id'
  then
    v_updated_definition := regexp_replace(
      v_definition,
      '(where[[:space:]]+a\.profissional_id[[:space:]]*=[[:space:]]*new\.profissional_id)',
      E'\\1\n        and a.team_member_id = new.team_member_id',
      'i'
    );
    if v_updated_definition = v_definition then
      raise exception 'Could not update proteger_agendamento conflict check';
    end if;
    execute v_updated_definition;
  end if;
end;
$$;

notify pgrst, 'reload schema';
commit;
