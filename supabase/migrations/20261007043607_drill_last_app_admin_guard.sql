create or replace function public.drill_set_global_permissions(
  p_user uuid,
  p_app boolean,
  p_manage boolean
)
returns void
language plpgsql
security definer
set search_path to 'pg_catalog'
as $$
declare
  v_target_is_admin boolean := false;
  v_admin_count bigint := 0;
begin
  if not public.is_drill_app_admin() then
    raise exception 'App Admin required';
  end if;

  select coalesce(g.is_app_admin,false)
    into v_target_is_admin
  from public.drill_global_permissions g
  where g.user_id = p_user;

  if coalesce(v_target_is_admin,false) and not coalesce(p_app,false) then
    select count(*)
      into v_admin_count
    from public.drill_global_permissions g
    where g.is_app_admin;

    if v_admin_count <= 1 then
      raise exception 'You cannot remove the last Drill Application Administrator';
    end if;
  end if;

  insert into public.drill_global_permissions(user_id,is_app_admin,manage_activities)
  values(p_user,coalesce(p_app,false),coalesce(p_manage,false))
  on conflict(user_id) do update
    set is_app_admin=excluded.is_app_admin,
        manage_activities=excluded.manage_activities;

  insert into public.drill_audit_log(
    actor_user_id,action,entity_type,entity_id,target_user_id,details
  )
  values(
    auth.uid(),'UPDATE','global_permission',p_user::text,p_user,
    pg_catalog.jsonb_build_object(
      'app_admin',coalesce(p_app,false),
      'manage_activities',coalesce(p_manage,false)
    )
  );
end;
$$;

revoke execute on function public.drill_set_global_permissions(uuid,boolean,boolean) from public, anon;
grant execute on function public.drill_set_global_permissions(uuid,boolean,boolean) to authenticated;
