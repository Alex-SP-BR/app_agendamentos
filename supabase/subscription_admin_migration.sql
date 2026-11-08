begin;

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

drop policy if exists "administrador lista perfis" on public.perfis;
create policy "administrador lista perfis"
  on public.perfis for select to authenticated
  using (
    tipo = 'profissional'
    and coalesce(auth.jwt() -> 'app_metadata' ->> 'role', '') = 'admin'
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
