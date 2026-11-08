begin;

alter table public.perfis
  drop constraint if exists perfis_status_acesso_check;

alter table public.perfis
  add constraint perfis_status_acesso_check
  check (
    status_acesso in (
      'pendente', 'ativo', 'bloqueado', 'cortesia', 'recusado'
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

commit;
