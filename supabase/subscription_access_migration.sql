begin;

alter table public.perfis
  add column if not exists status_acesso text;

alter table public.perfis
  add column if not exists plano_assinatura text;

update public.perfis
set status_acesso = 'cortesia'
where status_acesso is null;

update public.perfis
set plano_assinatura = 'gratis'
where plano_assinatura is null;

alter table public.perfis
  alter column status_acesso set default 'pendente',
  alter column status_acesso set not null,
  alter column plano_assinatura set default 'gratis',
  alter column plano_assinatura set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'perfis_status_acesso_check'
      and conrelid = 'public.perfis'::regclass
  ) then
    alter table public.perfis
      add constraint perfis_status_acesso_check
      check (
        status_acesso in (
          'pendente', 'ativo', 'bloqueado', 'cortesia', 'recusado'
        )
      );
  end if;
end;
$$;

create or replace function public.proteger_status_assinatura()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if auth.role() = 'authenticated'
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

commit;
