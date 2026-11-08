do $$
begin
  if exists (
    select 1
    from public.profissionais_equipe
    group by profissional_id,
      lower(regexp_replace(btrim(nome), '[[:space:]]+', ' ', 'g'))
    having count(*) > 1
  ) then
    raise exception
      'Existem nomes duplicados na equipe. Diferencie-os com sobrenomes antes de aplicar esta migração.';
  end if;
end;
$$;

create unique index if not exists profissionais_equipe_nome_unico_idx
  on public.profissionais_equipe (
    profissional_id,
    lower(regexp_replace(btrim(nome), '[[:space:]]+', ' ', 'g'))
  );
