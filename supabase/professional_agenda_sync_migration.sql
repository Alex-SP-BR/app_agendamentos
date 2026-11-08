begin;

insert into public.profissionais_config (profissional_id)
select p.id
from public.perfis p
where p.tipo = 'profissional'
on conflict (profissional_id) do nothing;

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

  select c.timezone
    into v_timezone
  from public.profissionais_config c
  join public.perfis p on p.id = c.profissional_id
  where c.profissional_id = p_professional_id
    and p.tipo = 'profissional';

  if not found then
    raise exception 'Profissional ou configuração não encontrados';
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

revoke all on function public.agenda_profissional_por_dia(uuid, date)
  from public, anon;
grant execute on function public.agenda_profissional_por_dia(uuid, date)
  to authenticated;

notify pgrst, 'reload schema';
commit;
