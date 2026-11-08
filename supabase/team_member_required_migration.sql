begin;

create or replace function public.criar_membro_equipe_padrao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.tipo = 'profissional' then
    insert into public.profissionais_equipe (profissional_id, nome)
    select new.id, new.nome
    where not exists (
      select 1
      from public.profissionais_equipe e
      where e.profissional_id = new.id
    );
  end if;
  return new;
end;
$$;

drop trigger if exists criar_membro_equipe_padrao on public.perfis;
create trigger criar_membro_equipe_padrao
  after insert on public.perfis
  for each row execute function public.criar_membro_equipe_padrao();

insert into public.profissionais_equipe (profissional_id, nome)
select p.id, p.nome
from public.perfis p
where p.tipo = 'profissional'
  and not exists (
    select 1
    from public.profissionais_equipe e
    where e.profissional_id = p.id
  );

update public.profissionais_equipe e
set ativo = true
where not e.ativo
  and not exists (
    select 1
    from public.profissionais_equipe active_member
    where active_member.profissional_id = e.profissional_id
      and active_member.ativo
  )
  and e.id = (
    select first_member.id
    from public.profissionais_equipe first_member
    where first_member.profissional_id = e.profissional_id
    order by first_member.criado_em, first_member.id
    limit 1
  );

drop trigger if exists before_agendamento_update on public.agendamentos;

update public.agendamentos a
set team_member_id = (
  select e.id
  from public.profissionais_equipe e
  where e.profissional_id = a.profissional_id
    and e.ativo
  order by e.criado_em, e.id
  limit 1
)
where a.team_member_id is null;

do $$
begin
  if exists (
    select 1
    from public.agendamentos
    where team_member_id is null
  ) then
    raise exception
      'Não foi possível vincular todos os agendamentos a um profissional da equipe.';
  end if;
end;
$$;

alter table public.agendamentos
  alter column team_member_id set not null;

create trigger before_agendamento_update
  before update on public.agendamentos
  for each row execute function public.proteger_agendamento();

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
  if new.team_member_id is null or not exists (
    select 1
    from public.profissionais_equipe e
    where e.id = new.team_member_id
      and e.profissional_id = new.profissional_id
      and e.ativo
  ) then
    raise exception 'Selecione um profissional ativo desta equipe';
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

notify pgrst, 'reload schema';
commit;
