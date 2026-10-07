create table if not exists public.drill_user_settings (
  user_id uuid primary key references auth.users(id) on delete cascade,
  home_unit_id uuid references public.units(id),
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id)
);

alter table public.drill_user_settings enable row level security;
revoke all on table public.drill_user_settings from public, anon, authenticated;
grant all on table public.drill_user_settings to service_role;

insert into public.drill_user_settings(user_id,home_unit_id,updated_at,updated_by)
select p.id,
  (select a.unit_id from public.member_unit_assignments a
   where a.member_id=p.member_id and a.active and a.is_primary
   order by a.start_date desc,a.created_at desc limit 1),
  now(),null
from public.profiles p
where p.member_id is not null
  and exists(select 1 from public.member_unit_assignments a
             where a.member_id=p.member_id and a.active and a.is_primary)
on conflict(user_id) do nothing;

create or replace function public.drill_current_home_unit(p_user_id uuid)
returns uuid language sql stable security definer set search_path to 'pg_catalog'
as $$ select s.home_unit_id from public.drill_user_settings s where s.user_id=p_user_id limit 1; $$;
revoke execute on function public.drill_current_home_unit(uuid) from public, anon;
grant execute on function public.drill_current_home_unit(uuid) to authenticated;

create or replace function public.drill_set_user_home_unit(p_user uuid,p_home uuid)
returns void language plpgsql security definer set search_path to 'pg_catalog'
as $$
declare v_old uuid; v_is_app_admin boolean;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if not exists(select 1 from auth.users u where u.id=p_user) then raise exception 'Shared login account not found'; end if;
 v_is_app_admin:=public.is_drill_app_admin();
 v_old:=public.drill_current_home_unit(p_user);
 if p_home is null then
   if not v_is_app_admin then raise exception 'Only a Drill App Admin can clear a Drill home unit'; end if;
 else
   if not exists(select 1 from public.units u where u.id=p_home and u.active) then raise exception 'Valid active Drill home unit required'; end if;
   if not v_is_app_admin then
     if not public.has_drill_unit_role(p_home,'unit_admin') then raise exception 'Unit Admin permission required for the selected Drill home unit'; end if;
     if v_old is not null and v_old<>p_home then raise exception 'Only a Drill App Admin can move a login to a different Drill home unit'; end if;
   end if;
 end if;
 insert into public.drill_user_settings(user_id,home_unit_id,updated_at,updated_by)
 values(p_user,p_home,now(),auth.uid())
 on conflict(user_id) do update set home_unit_id=excluded.home_unit_id,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,target_user_id,details)
 values(auth.uid(),'SET_HOME_UNIT','drill_user_settings',p_user::text,coalesce(p_home,v_old),p_user,
        pg_catalog.jsonb_build_object('old_home_unit',v_old,'new_home_unit',p_home));
end $$;
revoke execute on function public.drill_set_user_home_unit(uuid,uuid) from public, anon;
grant execute on function public.drill_set_user_home_unit(uuid,uuid) to authenticated;

create or replace function public.drill_admin_directory()
returns table(user_id uuid,email text,display_name text,member_id uuid,capid text,first_name text,last_name text,home_unit_id uuid,is_app_admin boolean,manage_activities boolean)
language sql stable security definer set search_path to 'pg_catalog'
as $$
 select u.id,u.email::text,coalesce(nullif(p.display_name,''),u.email::text,'CAP User'),
        p.member_id,m.capid,m.first_name,m.last_name,public.drill_current_home_unit(u.id),
        coalesce(g.is_app_admin,false),coalesce(g.manage_activities,false)
 from auth.users u
 left join public.profiles p on p.id=u.id
 left join public.members m on m.id=p.member_id
 left join public.drill_global_permissions g on g.user_id=u.id
 where public.is_drill_app_admin()
    or exists(
      select 1 from public.drill_unit_permissions mine
      where mine.user_id=auth.uid() and mine.unit_admin and mine.revoked_at is null
        and (mine.expires_at is null or mine.expires_at>=now())
        and (mine.unit_id=public.drill_current_home_unit(u.id)
          or exists(select 1 from public.drill_unit_permissions theirs
                    where theirs.user_id=u.id and theirs.unit_id=mine.unit_id
                      and theirs.revoked_at is null and (theirs.expires_at is null or theirs.expires_at>=now())))
    )
 order by coalesce(nullif(p.display_name,''),u.email::text,'CAP User');
$$;
revoke execute on function public.drill_admin_directory() from public, anon;
grant execute on function public.drill_admin_directory() to authenticated;

create or replace function public.drill_find_user_for_host_grant(p_email text,p_host_unit uuid)
returns table(user_id uuid,email text,display_name text,member_id uuid,capid text,home_unit_id uuid)
language sql stable security definer set search_path to 'pg_catalog'
as $$
 select u.id,u.email::text,coalesce(nullif(p.display_name,''),u.email::text,'CAP User'),
        p.member_id,m.capid,public.drill_current_home_unit(u.id)
 from auth.users u left join public.profiles p on p.id=u.id left join public.members m on m.id=p.member_id
 where (public.is_drill_app_admin() or public.has_drill_unit_role(p_host_unit,'unit_admin'))
   and lower(u.email)=lower(btrim(p_email))
   and public.drill_current_home_unit(u.id) is not null
 limit 1;
$$;
revoke execute on function public.drill_find_user_for_host_grant(text,uuid) from public, anon;
grant execute on function public.drill_find_user_for_host_grant(text,uuid) to authenticated;

create or replace function public.drill_get_my_context()
returns jsonb language plpgsql stable security definer set search_path to 'pg_catalog'
as $$
declare v jsonb;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select pg_catalog.jsonb_build_object(
   'userId',p.id,'displayName',coalesce(nullif(p.display_name,''),'CAP User'),'memberId',p.member_id,
   'homeUnitId',public.drill_current_home_unit(p.id),
   'appAdmin',coalesce(g.is_app_admin,false),'manageActivities',coalesce(g.manage_activities,false),
   'defaultScopeType',pref.default_scope_type,'defaultUnitId',pref.default_unit_id,'defaultActivityId',pref.default_activity_id,
   'unitPermissions',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'unitId',up.unit_id,'dataEntry',up.data_entry,'unitAdmin',up.unit_admin,'expiresAt',up.expires_at,
      'grantedAt',up.granted_at,'grantedBy',up.granted_by,'grantingUnitId',up.granting_unit_id,'grantNote',up.grant_note))
      from public.drill_unit_permissions up where up.user_id=p.id and up.revoked_at is null and (up.expires_at is null or up.expires_at>=now())),'[]'::jsonb),
   'activityPermissions',coalesce((select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'activityId',ap.activity_id,'dataEntry',ap.data_entry,'activityAdmin',ap.activity_admin,'expiresAt',ap.expires_at))
      from public.drill_activity_permissions ap where ap.user_id=p.id and ap.revoked_at is null and (ap.expires_at is null or ap.expires_at>=now())),'[]'::jsonb)
 ) into v
 from public.profiles p left join public.drill_global_permissions g on g.user_id=p.id
 left join public.drill_user_preferences pref on pref.user_id=p.id
 where p.id=auth.uid();
 if v is null then raise exception 'Profile not found'; end if;
 return v;
end $$;
revoke execute on function public.drill_get_my_context() from public, anon;
grant execute on function public.drill_get_my_context() to authenticated;

create or replace function public.drill_set_unit_permission(p_user uuid,p_unit uuid,p_entry boolean,p_admin boolean,p_expires timestamptz default null,p_note text default null)
returns void language plpgsql security definer set search_path to 'pg_catalog'
as $$
declare h uuid;
begin
 if not (public.is_drill_app_admin() or public.has_drill_unit_role(p_unit,'unit_admin')) then raise exception 'Host Unit Admin or App Admin required'; end if;
 h:=public.drill_current_home_unit(p_user);
 if h is null then raise exception 'Target user must have a Drill home unit before unit permissions can be assigned'; end if;
 if h<>p_unit and p_admin and not public.is_drill_app_admin() then raise exception 'Cross-unit grants may be Data Entry only'; end if;
 if p_expires is not null and p_expires<=now() then raise exception 'Expiration must be in the future'; end if;
 insert into public.drill_global_permissions(user_id) values(p_user) on conflict(user_id) do nothing;
 insert into public.drill_unit_permissions(user_id,unit_id,data_entry,unit_admin,granted_by,granting_unit_id,granted_at,expires_at,grant_note,revoked_at,revoked_by,revoke_reason)
 values(p_user,p_unit,coalesce(p_entry,false) or coalesce(p_admin,false),coalesce(p_admin,false),auth.uid(),p_unit,now(),p_expires,p_note,null,null,null)
 on conflict(user_id,unit_id) do update set data_entry=excluded.data_entry,unit_admin=excluded.unit_admin,granted_by=auth.uid(),granting_unit_id=p_unit,granted_at=now(),expires_at=p_expires,grant_note=p_note,revoked_at=null,revoked_by=null,revoke_reason=null;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,target_user_id,details)
 values(auth.uid(),'GRANT_OR_UPDATE','unit_permission',p_user::text||':'||p_unit::text,p_unit,p_user,
        pg_catalog.jsonb_build_object('data_entry',p_entry,'unit_admin',p_admin,'expires_at',p_expires,'target_home_unit',h,'note',p_note));
end $$;
revoke execute on function public.drill_set_unit_permission(uuid,uuid,boolean,boolean,timestamptz,text) from public, anon;
grant execute on function public.drill_set_unit_permission(uuid,uuid,boolean,boolean,timestamptz,text) to authenticated;
