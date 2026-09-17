-- Run before the Drill Test Manager migration.
select
  to_regclass('public.profiles') as profiles,
  to_regclass('public.units') as units,
  to_regclass('public.members') as members,
  to_regclass('public.member_unit_assignments') as member_unit_assignments,
  to_regprocedure('public.is_app_admin()') as schedule_app_admin_function,
  to_regprocedure('public.set_updated_at()') as updated_at_function;

select id,charter_number,name,active from public.units order by charter_number;
select count(*) as profile_count from public.profiles;
select count(*) as member_count from public.members;
