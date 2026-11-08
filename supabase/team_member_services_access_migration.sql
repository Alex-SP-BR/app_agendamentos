begin;

create or replace function public.servicos_equipe_com_sessao(
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

revoke all on function public.servicos_equipe_com_sessao(text)
  from public;
grant execute on function public.servicos_equipe_com_sessao(text)
  to anon, authenticated;

notify pgrst, 'reload schema';
commit;
