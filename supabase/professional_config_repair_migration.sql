begin;

insert into public.profissionais_config (profissional_id)
select p.id
from public.perfis p
where p.tipo = 'profissional'
on conflict (profissional_id) do nothing;

notify pgrst, 'reload schema';
commit;
