begin;

do $$
declare
  v_definition text;
begin
  select pg_get_functiondef('public.validar_agendamento()'::regprocedure)
    into v_definition;
  v_definition := regexp_replace(
    v_definition,
    'and[[:space:]]+a\.team_member_id[[:space:]]+is[[:space:]]+not[[:space:]]+distinct[[:space:]]+from[[:space:]]+new\.team_member_id',
    '',
    'gi'
  );
  if v_definition ~* 'a\.team_member_id[[:space:]]+is[[:space:]]+not[[:space:]]+distinct[[:space:]]+from[[:space:]]+new\.team_member_id' then
    raise exception 'Não foi possível atualizar a validação da agenda unificada';
  end if;
  execute v_definition;

  select pg_get_functiondef('public.proteger_agendamento()'::regprocedure)
    into v_definition;
  v_definition := regexp_replace(
    v_definition,
    'and[[:space:]]+a\.team_member_id[[:space:]]+is[[:space:]]+not[[:space:]]+distinct[[:space:]]+from[[:space:]]+new\.team_member_id',
    '',
    'gi'
  );
  if v_definition ~* 'a\.team_member_id[[:space:]]+is[[:space:]]+not[[:space:]]+distinct[[:space:]]+from[[:space:]]+new\.team_member_id' then
    raise exception 'Não foi possível atualizar a reativação de agendamentos';
  end if;
  execute v_definition;

end;
$$;

notify pgrst, 'reload schema';

commit;
