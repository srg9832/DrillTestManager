-- CAP Drill Test Manager production migration
-- Additive migration for the existing CAP Schedule + CAP Leadership Feedback Supabase project.
-- Development project ref: vosvdkkuiijywwmqzdiu
begin;
create extension if not exists pgcrypto;

do $$ begin
  if to_regclass('public.profiles') is null
     or to_regclass('public.units') is null
     or to_regclass('public.members') is null
     or to_regclass('public.member_unit_assignments') is null then
    raise exception 'Drill Test Manager requires profiles, units, members, and member_unit_assignments from the existing CAP apps.';
  end if;
  if to_regprocedure('public.is_app_admin()') is null then raise exception 'Missing public.is_app_admin().'; end if;
  if to_regprocedure('public.set_updated_at()') is null then raise exception 'Missing public.set_updated_at().'; end if;
end $$;

create table if not exists public.drill_global_permissions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  is_app_admin boolean not null default false,
  manage_activities boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drill_activities (
  id uuid primary key default gen_random_uuid(),
  activity_type text not null default 'Cadet Program Activity',
  name text not null,
  location text not null,
  start_date date not null,
  end_date date not null,
  active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(end_date>=start_date)
);
create index if not exists idx_drill_activities_dates on public.drill_activities(start_date desc,end_date desc);

create table if not exists public.drill_user_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  default_scope_type text check(default_scope_type in ('unit','activity')),
  default_unit_id uuid references public.units(id) on delete set null,
  default_activity_id uuid references public.drill_activities(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check(
    (default_scope_type is null and default_unit_id is null and default_activity_id is null)
    or (default_scope_type='unit' and default_unit_id is not null and default_activity_id is null)
    or (default_scope_type='activity' and default_unit_id is null and default_activity_id is not null)
  )
);

create table if not exists public.drill_unit_permissions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  unit_id uuid not null references public.units(id) on delete cascade,
  data_entry boolean not null default false,
  unit_admin boolean not null default false,
  granted_by uuid references public.profiles(id) on delete set null,
  granting_unit_id uuid references public.units(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  grant_note text,
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(id) on delete set null,
  revoke_reason text,
  updated_at timestamptz not null default now(),
  primary key(user_id,unit_id)
);
create index if not exists idx_drill_unit_perm_unit on public.drill_unit_permissions(unit_id);
create index if not exists idx_drill_unit_perm_user on public.drill_unit_permissions(user_id);
create index if not exists idx_drill_unit_perm_expiry on public.drill_unit_permissions(expires_at);

create table if not exists public.drill_activity_permissions (
  user_id uuid not null references public.profiles(id) on delete cascade,
  activity_id uuid not null references public.drill_activities(id) on delete cascade,
  data_entry boolean not null default false,
  activity_admin boolean not null default false,
  granted_by uuid references public.profiles(id) on delete set null,
  granted_at timestamptz not null default now(),
  expires_at timestamptz,
  grant_note text,
  revoked_at timestamptz,
  revoked_by uuid references public.profiles(id) on delete set null,
  revoke_reason text,
  updated_at timestamptz not null default now(),
  primary key(user_id,activity_id)
);
create index if not exists idx_drill_activity_perm_activity on public.drill_activity_permissions(activity_id);
create index if not exists idx_drill_activity_perm_user on public.drill_activity_permissions(user_id);

create table if not exists public.drill_test_definitions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  label text not null,
  topic text not null,
  conditions text not null default '',
  scoring_mode text not null check(scoring_mode in ('su','points')),
  pass_required integer not null check(pass_required>=0),
  max_score integer not null check(max_score>0),
  source_page text,
  sequence jsonb not null default '[]'::jsonb,
  active boolean not null default true,
  display_order integer not null default 100,
  version integer not null default 1,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.drill_test_items (
  id uuid primary key default gen_random_uuid(),
  test_id uuid not null references public.drill_test_definitions(id) on delete cascade,
  item_key text not null,
  item_order integer not null default 100,
  group_label text,
  command text not null,
  standards jsonb not null default '[]'::jsonb,
  points integer not null default 1 check(points>0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(test_id,item_key)
);
create index if not exists idx_drill_test_items_order on public.drill_test_items(test_id,item_order);

create table if not exists public.drill_records (
  id uuid primary key default gen_random_uuid(),
  test_definition_id uuid not null references public.drill_test_definitions(id) on delete restrict,
  subject_member_id uuid not null references public.members(id) on delete restrict,
  home_unit_id_at_evaluation uuid not null references public.units(id) on delete restrict,
  evaluation_scope_type text not null check(evaluation_scope_type in ('unit','activity')),
  evaluation_unit_id uuid references public.units(id) on delete restrict,
  activity_id uuid references public.drill_activities(id) on delete restrict,
  test_date date not null default current_date,
  testing_officer_name text not null,
  testing_officer_user_id uuid references public.profiles(id) on delete set null,
  created_by_user_id uuid not null references public.profiles(id) on delete restrict,
  status text not null default 'draft' check(status in ('draft','submitted')),
  raw_score integer not null default 0,
  max_score integer not null,
  passed boolean not null default false,
  results jsonb not null default '{}'::jsonb,
  notes text,
  capid_snapshot text not null,
  first_name_snapshot text not null,
  last_name_snapshot text not null,
  test_code_snapshot text not null,
  test_label_snapshot text not null,
  test_topic_snapshot text,
  pass_required_snapshot integer not null,
  test_items_snapshot jsonb not null default '[]'::jsonb,
  sequence_snapshot jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  submitted_at timestamptz,
  check((evaluation_scope_type='unit' and evaluation_unit_id is not null and activity_id is null)
     or (evaluation_scope_type='activity' and evaluation_unit_id is null and activity_id is not null))
);
create index if not exists idx_drill_records_home_unit_date on public.drill_records(home_unit_id_at_evaluation,test_date desc,submitted_at desc,id desc);
create index if not exists idx_drill_records_unit_date on public.drill_records(evaluation_unit_id,test_date desc,submitted_at desc,id desc);
create index if not exists idx_drill_records_activity_date on public.drill_records(activity_id,test_date desc,submitted_at desc,id desc);
create index if not exists idx_drill_records_member_date on public.drill_records(subject_member_id,test_date desc);
create index if not exists idx_drill_records_creator on public.drill_records(created_by_user_id);

create table if not exists public.drill_audit_log (
  id bigint generated always as identity primary key,
  actor_user_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id text,
  unit_id uuid references public.units(id) on delete set null,
  activity_id uuid references public.drill_activities(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_drill_audit_created on public.drill_audit_log(created_at desc);
create index if not exists idx_drill_audit_unit on public.drill_audit_log(unit_id,created_at desc);
create index if not exists idx_drill_audit_target on public.drill_audit_log(target_user_id,created_at desc);

do $$ declare t text; begin
  foreach t in array array['drill_global_permissions','drill_activities','drill_user_preferences','drill_unit_permissions','drill_activity_permissions','drill_test_definitions','drill_test_items','drill_records'] loop
    execute format('drop trigger if exists trg_%I_updated_at on public.%I',t,t);
    execute format('create trigger trg_%I_updated_at before update on public.%I for each row execute function public.set_updated_at()',t,t);
  end loop;
end $$;

-- Authorization helpers
create or replace function public.is_drill_app_admin() returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and exists(select 1 from public.drill_global_permissions where user_id=auth.uid() and is_app_admin);
$$;
create or replace function public.has_drill_global_role(p_role text) returns boolean
language sql stable security definer set search_path=public as $$
 select public.is_drill_app_admin() or exists(select 1 from public.drill_global_permissions where user_id=auth.uid() and case p_role when 'manage_activities' then manage_activities when 'app_admin' then is_app_admin else false end);
$$;
create or replace function public.drill_current_home_unit(p_user_id uuid) returns uuid
language sql stable security definer set search_path=public as $$
 select a.unit_id from public.profiles p join public.member_unit_assignments a on a.member_id=p.member_id
 where p.id=p_user_id and a.active and a.is_primary order by a.start_date desc,a.created_at desc limit 1;
$$;
create or replace function public.has_drill_unit_role(p_unit_id uuid,p_role text) returns boolean
language sql stable security definer set search_path=public as $$
 select public.is_drill_app_admin() or exists(select 1 from public.drill_unit_permissions p where p.user_id=auth.uid() and p.unit_id=p_unit_id and p.revoked_at is null and (p.expires_at is null or p.expires_at>=now()) and case p_role when 'data_entry' then (p.data_entry or p.unit_admin) when 'unit_admin' then p.unit_admin else false end);
$$;
create or replace function public.has_drill_activity_role(p_activity_id uuid,p_role text) returns boolean
language sql stable security definer set search_path=public as $$
 select public.is_drill_app_admin() or exists(select 1 from public.drill_activity_permissions p where p.user_id=auth.uid() and p.activity_id=p_activity_id and p.revoked_at is null and (p.expires_at is null or p.expires_at>=now()) and case p_role when 'data_entry' then (p.data_entry or p.activity_admin) when 'activity_admin' then p.activity_admin else false end);
$$;
create or replace function public.has_any_drill_access() returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and (public.is_drill_app_admin() or public.has_drill_global_role('manage_activities')
 or exists(select 1 from public.drill_unit_permissions p where p.user_id=auth.uid() and p.revoked_at is null and (p.expires_at is null or p.expires_at>=now()) and (p.data_entry or p.unit_admin))
 or exists(select 1 from public.drill_activity_permissions p where p.user_id=auth.uid() and p.revoked_at is null and (p.expires_at is null or p.expires_at>=now()) and (p.data_entry or p.activity_admin)));
$$;
create or replace function public.drill_is_home_unit_admin_for_user(p_target_user uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select public.is_drill_app_admin() or (public.drill_current_home_unit(p_target_user) is not null and public.has_drill_unit_role(public.drill_current_home_unit(p_target_user),'unit_admin'));
$$;
create or replace function public.can_read_drill_member(p_member_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select auth.uid() is not null and (public.is_drill_app_admin() or exists(select 1 from public.profiles where id=auth.uid() and member_id=p_member_id)
 or exists(select 1 from public.member_unit_assignments a where a.member_id=p_member_id and a.active and public.has_drill_unit_role(a.unit_id,'data_entry')));
$$;
create or replace function public.can_read_drill_record(p_status text,p_home uuid,p_scope text,p_unit uuid,p_activity uuid,p_creator uuid) returns boolean
language sql stable security definer set search_path=public as $$
 -- Data Entry is intentionally a unit/activity-wide read role in this application.
 -- This keeps Dashboard, Records, Reports, and statistics consistent for everyone
 -- assigned to the same scope; edit authority remains more restrictive.
 select public.is_drill_app_admin() or p_creator=auth.uid()
 or public.has_drill_unit_role(p_home,'data_entry')
 or (p_scope='unit' and public.has_drill_unit_role(p_unit,'data_entry'))
 or (p_scope='activity' and public.has_drill_activity_role(p_activity,'data_entry'));
$$;
create or replace function public.can_edit_drill_record(p_id uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.drill_records r where r.id=p_id and (public.is_drill_app_admin() or r.created_by_user_id=auth.uid() or public.has_drill_unit_role(r.home_unit_id_at_evaluation,'unit_admin') or (r.evaluation_scope_type='unit' and public.has_drill_unit_role(r.evaluation_unit_id,'unit_admin')) or (r.evaluation_scope_type='activity' and public.has_drill_activity_role(r.activity_id,'activity_admin'))));
$$;

-- Current-user context and roster lookup
create or replace function public.drill_get_my_context() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare v jsonb; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 select jsonb_build_object('userId',p.id,'displayName',coalesce(nullif(p.display_name,''),trim(concat_ws(' ',m.first_name,m.last_name)),'CAP User'),'memberId',p.member_id,'homeUnitId',public.drill_current_home_unit(p.id),
 'appAdmin',coalesce(g.is_app_admin,false),'manageActivities',coalesce(g.manage_activities,false),'defaultScopeType',pref.default_scope_type,'defaultUnitId',pref.default_unit_id,'defaultActivityId',pref.default_activity_id,
 'unitPermissions',coalesce((select jsonb_agg(jsonb_build_object('unitId',up.unit_id,'dataEntry',up.data_entry,'unitAdmin',up.unit_admin,'expiresAt',up.expires_at,'grantedAt',up.granted_at,'grantedBy',up.granted_by,'grantingUnitId',up.granting_unit_id,'grantNote',up.grant_note)) from public.drill_unit_permissions up where up.user_id=p.id and up.revoked_at is null and (up.expires_at is null or up.expires_at>=now())),'[]'::jsonb),
 'activityPermissions',coalesce((select jsonb_agg(jsonb_build_object('activityId',ap.activity_id,'dataEntry',ap.data_entry,'activityAdmin',ap.activity_admin,'expiresAt',ap.expires_at)) from public.drill_activity_permissions ap where ap.user_id=p.id and ap.revoked_at is null and (ap.expires_at is null or ap.expires_at>=now())),'[]'::jsonb)) into v
 from public.profiles p left join public.members m on m.id=p.member_id left join public.drill_global_permissions g on g.user_id=p.id left join public.drill_user_preferences pref on pref.user_id=p.id where p.id=auth.uid();
 if v is null then raise exception 'Profile not found'; end if; return v;
end $$;

create or replace function public.drill_lookup_member(p_capid text)
returns table(member_id uuid,capid text,first_name text,last_name text,member_type text,active boolean,home_unit_id uuid)
language sql stable security definer set search_path=public as $$
 select m.id,m.capid,m.first_name,m.last_name,m.member_type,m.active,(select a.unit_id from public.member_unit_assignments a where a.member_id=m.id and a.active and a.is_primary order by a.start_date desc limit 1)
 from public.members m where auth.uid() is not null and public.has_any_drill_access() and m.capid=btrim(p_capid) limit 1;
$$;
create or replace function public.drill_member_suggestions(p_unit_id uuid)
returns table(member_id uuid,capid text,first_name text,last_name text,active boolean)
language sql stable security definer set search_path=public as $$
 select m.id,m.capid,m.first_name,m.last_name,m.active from public.member_unit_assignments a join public.members m on m.id=a.member_id
 where public.has_drill_unit_role(p_unit_id,'data_entry') and a.unit_id=p_unit_id and a.active and a.is_primary and m.active and m.member_type='Cadet' order by m.last_name,m.first_name;
$$;
create or replace function public.drill_ensure_member(p_capid text,p_first text,p_last text,p_home uuid) returns uuid
language plpgsql security definer set search_path=public as $$
declare v uuid; begin
 if auth.uid() is null or not public.has_any_drill_access() then raise exception 'Drill access required'; end if;
 select id into v from public.members where capid=btrim(p_capid); if v is not null then return v; end if;
 if nullif(btrim(p_capid),'') is null or nullif(btrim(p_first),'') is null or nullif(btrim(p_last),'') is null then raise exception 'CAPID and name are required'; end if;
 if not exists(select 1 from public.units where id=p_home and active) then raise exception 'Valid active home unit required'; end if;
 insert into public.members(capid,first_name,last_name,member_type,active) values(btrim(p_capid),btrim(p_first),btrim(p_last),'Cadet',true) returning id into v;
 insert into public.member_unit_assignments(member_id,unit_id,is_primary,active,start_date) values(v,p_home,true,true,current_date);
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,details) values(auth.uid(),'CREATE','member',v::text,p_home,jsonb_build_object('capid',btrim(p_capid),'source','drill entry'));
 return v;
end $$;

create or replace function public.drill_upsert_member(p_member uuid,p_capid text,p_first text,p_last text,p_home uuid,p_active boolean) returns uuid
language plpgsql security definer set search_path=public as $$
declare v uuid; old_home uuid; begin
 if not (public.is_drill_app_admin() or public.has_drill_unit_role(p_home,'unit_admin')) then raise exception 'Not authorized for destination unit'; end if;
 v:=p_member; if v is null then select id into v from public.members where capid=btrim(p_capid); end if;
 if v is null then insert into public.members(capid,first_name,last_name,member_type,active) values(btrim(p_capid),btrim(p_first),btrim(p_last),'Cadet',coalesce(p_active,true)) returning id into v; end if;
 select unit_id into old_home from public.member_unit_assignments where member_id=v and active and is_primary order by start_date desc limit 1;
 if old_home is not null and old_home<>p_home and not public.is_drill_app_admin() and not public.has_drill_unit_role(old_home,'unit_admin') then raise exception 'Not authorized to move member from current home unit'; end if;
 if exists(select 1 from public.members where capid=btrim(p_capid) and id<>v) then raise exception 'CAPID already belongs to another member'; end if;
 update public.members set capid=btrim(p_capid),first_name=btrim(p_first),last_name=btrim(p_last),active=coalesce(p_active,true) where id=v;
 if old_home is distinct from p_home then update public.member_unit_assignments set active=false,end_date=current_date where member_id=v and active and is_primary; insert into public.member_unit_assignments(member_id,unit_id,is_primary,active,start_date) values(v,p_home,true,true,current_date); end if;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,details) values(auth.uid(),'UPSERT','member',v::text,p_home,jsonb_build_object('capid',p_capid,'active',p_active)); return v;
end $$;

-- Permission management
create or replace function public.drill_set_unit_permission(p_user uuid,p_unit uuid,p_entry boolean,p_admin boolean,p_expires timestamptz default null,p_note text default null) returns void
language plpgsql security definer set search_path=public as $$
declare h uuid; begin
 if not (public.is_drill_app_admin() or public.has_drill_unit_role(p_unit,'unit_admin')) then raise exception 'Host Unit Admin or App Admin required'; end if;
 h:=public.drill_current_home_unit(p_user); if h is null then raise exception 'Target user must be linked to a member/home unit'; end if;
 if h<>p_unit and p_admin and not public.is_drill_app_admin() then raise exception 'Cross-unit grants may be Data Entry only'; end if;
 if p_expires is not null and p_expires<=now() then raise exception 'Expiration must be in the future'; end if;
 insert into public.drill_global_permissions(user_id) values(p_user) on conflict(user_id) do nothing;
 insert into public.drill_unit_permissions(user_id,unit_id,data_entry,unit_admin,granted_by,granting_unit_id,granted_at,expires_at,grant_note,revoked_at,revoked_by,revoke_reason)
 values(p_user,p_unit,coalesce(p_entry,false) or coalesce(p_admin,false),coalesce(p_admin,false),auth.uid(),p_unit,now(),p_expires,p_note,null,null,null)
 on conflict(user_id,unit_id) do update set data_entry=excluded.data_entry,unit_admin=excluded.unit_admin,granted_by=auth.uid(),granting_unit_id=p_unit,granted_at=now(),expires_at=p_expires,grant_note=p_note,revoked_at=null,revoked_by=null,revoke_reason=null;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,target_user_id,details) values(auth.uid(),'GRANT_OR_UPDATE','unit_permission',p_user::text||':'||p_unit::text,p_unit,p_user,jsonb_build_object('data_entry',p_entry,'unit_admin',p_admin,'expires_at',p_expires,'target_home_unit',h,'note',p_note));
end $$;
create or replace function public.drill_grant_temporary_unit_access(p_user uuid,p_unit uuid,p_expires timestamptz default null,p_note text default null) returns void
language sql security definer set search_path=public as $$ select public.drill_set_unit_permission(p_user,p_unit,true,false,p_expires,p_note); $$;
create or replace function public.drill_revoke_unit_access(p_user uuid,p_unit uuid,p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$
declare h uuid; begin h:=public.drill_current_home_unit(p_user);
 if not (public.is_drill_app_admin() or public.has_drill_unit_role(p_unit,'unit_admin') or (h is not null and h<>p_unit and public.has_drill_unit_role(h,'unit_admin'))) then raise exception 'Not authorized to revoke this permission'; end if;
 update public.drill_unit_permissions set revoked_at=now(),revoked_by=auth.uid(),revoke_reason=coalesce(nullif(btrim(p_reason),''),'Permission revoked') where user_id=p_user and unit_id=p_unit and revoked_at is null;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,target_user_id,details) values(auth.uid(),'REVOKE','unit_permission',p_user::text||':'||p_unit::text,p_unit,p_user,jsonb_build_object('reason',p_reason,'target_home_unit',h));
end $$;
create or replace function public.drill_set_global_permissions(p_user uuid,p_app boolean,p_manage boolean) returns void
language plpgsql security definer set search_path=public as $$ begin if not public.is_drill_app_admin() then raise exception 'App Admin required'; end if;
 insert into public.drill_global_permissions(user_id,is_app_admin,manage_activities) values(p_user,p_app,p_manage) on conflict(user_id) do update set is_app_admin=excluded.is_app_admin,manage_activities=excluded.manage_activities;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,target_user_id,details) values(auth.uid(),'UPDATE','global_permission',p_user::text,p_user,jsonb_build_object('app_admin',p_app,'manage_activities',p_manage)); end $$;
create or replace function public.drill_set_activity_permission(p_user uuid,p_activity uuid,p_entry boolean,p_admin boolean,p_expires timestamptz default null,p_note text default null) returns void
language plpgsql security definer set search_path=public as $$ begin
 if not (public.is_drill_app_admin() or public.has_drill_activity_role(p_activity,'activity_admin')) then raise exception 'Activity Admin or App Admin required'; end if;
 insert into public.drill_activity_permissions(user_id,activity_id,data_entry,activity_admin,granted_by,granted_at,expires_at,grant_note,revoked_at,revoked_by,revoke_reason) values(p_user,p_activity,coalesce(p_entry,false) or coalesce(p_admin,false),coalesce(p_admin,false),auth.uid(),now(),p_expires,p_note,null,null,null)
 on conflict(user_id,activity_id) do update set data_entry=excluded.data_entry,activity_admin=excluded.activity_admin,granted_by=auth.uid(),granted_at=now(),expires_at=p_expires,grant_note=p_note,revoked_at=null,revoked_by=null,revoke_reason=null;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,activity_id,target_user_id,details) values(auth.uid(),'GRANT_OR_UPDATE','activity_permission',p_user::text||':'||p_activity::text,p_activity,p_user,jsonb_build_object('data_entry',p_entry,'activity_admin',p_admin,'expires_at',p_expires)); end $$;
create or replace function public.drill_revoke_activity_access(p_user uuid,p_activity uuid,p_reason text default null) returns void
language plpgsql security definer set search_path=public as $$ begin if not (public.is_drill_app_admin() or public.has_drill_activity_role(p_activity,'activity_admin')) then raise exception 'Not authorized'; end if;
 update public.drill_activity_permissions set revoked_at=now(),revoked_by=auth.uid(),revoke_reason=coalesce(p_reason,'Permission revoked') where user_id=p_user and activity_id=p_activity and revoked_at is null;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,activity_id,target_user_id,details) values(auth.uid(),'REVOKE','activity_permission',p_user::text||':'||p_activity::text,p_activity,p_user,jsonb_build_object('reason',p_reason)); end $$;
create or replace function public.drill_set_user_preference(p_scope text,p_id uuid) returns void
language plpgsql security definer set search_path=public as $$ begin
 if p_scope='unit' and not public.has_drill_unit_role(p_id,'data_entry') then raise exception 'No access to selected unit'; end if;
 if p_scope='activity' and not public.has_drill_activity_role(p_id,'data_entry') then raise exception 'No access to selected activity'; end if;
 insert into public.drill_user_preferences(user_id,default_scope_type,default_unit_id,default_activity_id) values(auth.uid(),p_scope,case when p_scope='unit' then p_id end,case when p_scope='activity' then p_id end)
 on conflict(user_id) do update set default_scope_type=excluded.default_scope_type,default_unit_id=excluded.default_unit_id,default_activity_id=excluded.default_activity_id; end $$;

-- Activity / unit / test definition management
create or replace function public.drill_save_activity(p_id uuid,p_type text,p_name text,p_location text,p_start date,p_end date,p_active boolean) returns uuid
language plpgsql security definer set search_path=public as $$ declare v uuid; begin
 if p_end<p_start then raise exception 'End date cannot be before start date'; end if;
 if p_id is null then if not public.has_drill_global_role('manage_activities') then raise exception 'Create / Manage Activities permission required'; end if;
   insert into public.drill_activities(activity_type,name,location,start_date,end_date,active,created_by) values(coalesce(nullif(btrim(p_type),''),'Other'),btrim(p_name),btrim(p_location),p_start,p_end,coalesce(p_active,true),auth.uid()) returning id into v;
   if not public.is_drill_app_admin() then insert into public.drill_activity_permissions(user_id,activity_id,data_entry,activity_admin,granted_by) values(auth.uid(),v,true,true,auth.uid()) on conflict(user_id,activity_id) do update set data_entry=true,activity_admin=true,revoked_at=null,expires_at=null; end if;
 else if not (public.is_drill_app_admin() or public.has_drill_global_role('manage_activities') or public.has_drill_activity_role(p_id,'activity_admin')) then raise exception 'Not authorized'; end if;
   update public.drill_activities set activity_type=btrim(p_type),name=btrim(p_name),location=btrim(p_location),start_date=p_start,end_date=p_end,active=p_active where id=p_id returning id into v; end if;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,activity_id,details) values(auth.uid(),case when p_id is null then 'CREATE' else 'UPDATE' end,'activity',v::text,v,jsonb_build_object('name',p_name,'type',p_type)); return v; end $$;
create or replace function public.drill_upsert_unit(p_id uuid,p_charter text,p_name text,p_active boolean) returns uuid
language plpgsql security definer set search_path=public as $$ declare v uuid; begin if not public.is_drill_app_admin() then raise exception 'Drill App Admin required'; end if;
 if p_id is null then insert into public.units(charter_number,name,active) values(upper(btrim(p_charter)),btrim(p_name),coalesce(p_active,true)) returning id into v; else update public.units set charter_number=upper(btrim(p_charter)),name=btrim(p_name),active=p_active where id=p_id returning id into v; end if;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,details) values(auth.uid(),'UPSERT','unit',v::text,v,jsonb_build_object('charter',p_charter,'name',p_name,'active',p_active)); return v; end $$;
create or replace function public.drill_save_test_definition(p jsonb) returns uuid
language plpgsql security definer set search_path=public as $$ declare v uuid; it jsonb; n int:=0; begin if not public.is_drill_app_admin() then raise exception 'Drill App Admin required'; end if;
 v:=nullif(p->>'id','')::uuid; if v is null then insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,updated_by) values(btrim(p->>'code'),btrim(p->>'label'),btrim(p->>'topic'),coalesce(p->>'conditions',''),p->>'scoringMode',(p->>'passRequired')::int,(p->>'maxScore')::int,p->>'sourcePage',coalesce(p->'sequence','[]'::jsonb),coalesce((p->>'active')::boolean,true),coalesce((p->>'displayOrder')::int,100),auth.uid()) returning id into v;
 else update public.drill_test_definitions set code=btrim(p->>'code'),label=btrim(p->>'label'),topic=btrim(p->>'topic'),conditions=coalesce(p->>'conditions',''),scoring_mode=p->>'scoringMode',pass_required=(p->>'passRequired')::int,max_score=(p->>'maxScore')::int,source_page=p->>'sourcePage',sequence=coalesce(p->'sequence','[]'::jsonb),active=coalesce((p->>'active')::boolean,true),display_order=coalesce((p->>'displayOrder')::int,100),version=version+1,updated_by=auth.uid() where id=v; delete from public.drill_test_items where test_id=v; end if;
 for it in select * from jsonb_array_elements(coalesce(p->'items','[]'::jsonb)) loop n:=n+1; insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) values(v,coalesce(it->>'id',n::text),n,nullif(it->>'group',''),it->>'command',coalesce(it->'standards','[]'::jsonb),coalesce((it->>'points')::int,1),true); end loop;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,details) values(auth.uid(),'UPSERT','test_definition',v::text,jsonb_build_object('code',p->>'code')); return v; end $$;

-- Secure drill record save
create or replace function public.drill_save_record(p jsonb) returns uuid
language plpgsql security definer set search_path=public as $$
declare v uuid; t public.drill_test_definitions%rowtype; m public.members%rowtype; h uuid; sc text; u uuid; a uuid; st text; score int; passed bool; items jsonb; old public.drill_records%rowtype; nowv timestamptz:=now(); begin
 if auth.uid() is null then raise exception 'Authentication required'; end if; sc:=p->>'scopeType'; u:=nullif(p->>'unitId','')::uuid; a:=nullif(p->>'activityId','')::uuid;
 if sc='unit' and not public.has_drill_unit_role(u,'data_entry') then raise exception 'No Data Entry permission for selected unit'; end if; if sc='activity' and not public.has_drill_activity_role(a,'data_entry') then raise exception 'No Data Entry permission for selected activity'; end if;
 select * into t from public.drill_test_definitions where id=(p->>'testId')::uuid and active; if t.id is null then raise exception 'Active drill test not found'; end if;
 select * into m from public.members where capid=btrim(p->>'capid'); if m.id is null then perform public.drill_ensure_member(p->>'capid',p->>'firstName',p->>'lastName',(p->>'homeUnitId')::uuid); select * into m from public.members where capid=btrim(p->>'capid'); end if;
 select unit_id into h from public.member_unit_assignments where member_id=m.id and active and is_primary order by start_date desc limit 1; if h is null then raise exception 'Member has no active primary unit assignment'; end if;
 st:=coalesce(p->>'status','draft');
 if st not in ('draft','submitted') then raise exception 'Invalid record status'; end if;
 -- Calculate the score on the server from the submitted per-item results. Do not trust
 -- a browser-supplied total score.
 if t.scoring_mode='points' then
   select coalesce(sum(case when lower(coalesce(p->'results'->>i.item_key,'false'))='true' then i.points else 0 end),0)
   into score from public.drill_test_items i where i.test_id=t.id and i.active;
 else
   if st='submitted' and exists(
     select 1 from public.drill_test_items i
     where i.test_id=t.id and i.active and coalesce(p->'results'->>i.item_key,'') not in ('S','U')
   ) then raise exception 'Every graded S/U item must be scored before submission'; end if;
   select count(*)::int into score from public.drill_test_items i
   where i.test_id=t.id and i.active and p->'results'->>i.item_key='S';
 end if;
 passed:=score>=t.pass_required;
 select coalesce(jsonb_agg(jsonb_build_object('id',i.item_key,'command',i.command,'standards',i.standards,'points',i.points,'group',i.group_label) order by i.item_order),'[]'::jsonb) into items from public.drill_test_items i where i.test_id=t.id and i.active;
 v:=nullif(p->>'recordId','')::uuid; if v is null then insert into public.drill_records(test_definition_id,subject_member_id,home_unit_id_at_evaluation,evaluation_scope_type,evaluation_unit_id,activity_id,test_date,testing_officer_name,testing_officer_user_id,created_by_user_id,status,raw_score,max_score,passed,results,notes,capid_snapshot,first_name_snapshot,last_name_snapshot,test_code_snapshot,test_label_snapshot,test_topic_snapshot,pass_required_snapshot,test_items_snapshot,sequence_snapshot,submitted_at)
 values(t.id,m.id,h,sc,case when sc='unit' then u end,case when sc='activity' then a end,coalesce(nullif(p->>'testDate','')::date,current_date),btrim(p->>'testingOfficerName'),nullif(p->>'testingOfficerUserId','')::uuid,auth.uid(),st,score,t.max_score,passed,coalesce(p->'results','{}'::jsonb),nullif(p->>'notes',''),m.capid,m.first_name,m.last_name,t.code,t.label,t.topic,t.pass_required,items,t.sequence,case when st='submitted' then nowv end) returning id into v;
 else select * into old from public.drill_records where id=v; if old.id is null or not public.can_edit_drill_record(v) then raise exception 'Not authorized to edit this record'; end if; update public.drill_records set test_definition_id=t.id,subject_member_id=m.id,home_unit_id_at_evaluation=h,evaluation_scope_type=sc,evaluation_unit_id=case when sc='unit' then u end,activity_id=case when sc='activity' then a end,test_date=coalesce(nullif(p->>'testDate','')::date,current_date),testing_officer_name=btrim(p->>'testingOfficerName'),testing_officer_user_id=nullif(p->>'testingOfficerUserId','')::uuid,status=st,raw_score=score,max_score=t.max_score,passed=passed,results=coalesce(p->'results','{}'::jsonb),notes=nullif(p->>'notes',''),capid_snapshot=m.capid,first_name_snapshot=m.first_name,last_name_snapshot=m.last_name,test_code_snapshot=t.code,test_label_snapshot=t.label,test_topic_snapshot=t.topic,pass_required_snapshot=t.pass_required,test_items_snapshot=items,sequence_snapshot=t.sequence,submitted_at=case when st='submitted' then coalesce(old.submitted_at,nowv) else null end where id=v; end if;
 insert into public.drill_audit_log(actor_user_id,action,entity_type,entity_id,unit_id,activity_id,details) values(auth.uid(),case when old.id is null then 'CREATE' else 'UPDATE' end,'record',v::text,case when sc='unit' then u else h end,case when sc='activity' then a end,jsonb_build_object('capid',m.capid,'test',t.code,'status',st,'score',score)); return v; end $$;

create or replace function public.drill_dashboard_summary(p_scope text,p_id uuid)
returns table(submitted_count bigint,passing_count bigint,draft_count bigint,cadets_tested bigint)
language sql stable security definer set search_path=public as $$
 select count(*) filter(where status='submitted'),count(*) filter(where status='submitted' and passed),count(*) filter(where status='draft'),count(distinct subject_member_id) filter(where status='submitted') from public.drill_records r
 where public.can_read_drill_record(r.status,r.home_unit_id_at_evaluation,r.evaluation_scope_type,r.evaluation_unit_id,r.activity_id,r.created_by_user_id)
 and ((p_scope='unit' and (r.home_unit_id_at_evaluation=p_id or (r.evaluation_scope_type='unit' and r.evaluation_unit_id=p_id))) or (p_scope='activity' and r.evaluation_scope_type='activity' and r.activity_id=p_id));
$$;

create or replace function public.drill_admin_directory()
returns table(user_id uuid,email text,display_name text,member_id uuid,capid text,first_name text,last_name text,home_unit_id uuid,is_app_admin boolean,manage_activities boolean)
language sql stable security definer set search_path=public as $$
 select distinct p.id,u.email,coalesce(nullif(p.display_name,''),trim(concat_ws(' ',m.first_name,m.last_name)),'CAP User'),p.member_id,m.capid,m.first_name,m.last_name,public.drill_current_home_unit(p.id),coalesce(g.is_app_admin,false),coalesce(g.manage_activities,false)
 from public.profiles p join auth.users u on u.id=p.id left join public.members m on m.id=p.member_id left join public.drill_global_permissions g on g.user_id=p.id
 where public.is_drill_app_admin() or exists(select 1 from public.drill_unit_permissions mine where mine.user_id=auth.uid() and mine.unit_admin and mine.revoked_at is null and (mine.expires_at is null or mine.expires_at>=now()) and (mine.unit_id=public.drill_current_home_unit(p.id) or exists(select 1 from public.drill_unit_permissions theirs where theirs.user_id=p.id and theirs.unit_id=mine.unit_id))) order by display_name;
$$;
create or replace function public.drill_permission_audit()
returns table(id bigint,created_at timestamptz,action text,entity_type text,unit_id uuid,activity_id uuid,target_user_id uuid,actor_user_id uuid,details jsonb)
language sql stable security definer set search_path=public as $$
 select a.id,a.created_at,a.action,a.entity_type,a.unit_id,a.activity_id,a.target_user_id,a.actor_user_id,a.details from public.drill_audit_log a
 where public.is_drill_app_admin() or (a.unit_id is not null and public.has_drill_unit_role(a.unit_id,'unit_admin')) or (a.activity_id is not null and public.has_drill_activity_role(a.activity_id,'activity_admin')) or (a.target_user_id is not null and public.drill_is_home_unit_admin_for_user(a.target_user_id)) order by a.created_at desc limit 200;
$$;

-- Exact-email lookup used only when a host Unit Admin is granting temporary
-- cross-unit Data Entry. This avoids exposing a statewide user directory.
create or replace function public.drill_find_user_for_host_grant(p_email text,p_host_unit uuid)
returns table(user_id uuid,email text,display_name text,member_id uuid,capid text,home_unit_id uuid)
language sql stable security definer set search_path=public,auth as $$
 select p.id,u.email,
   coalesce(nullif(p.display_name,''),trim(concat_ws(' ',m.first_name,m.last_name)),'CAP User'),
   p.member_id,m.capid,public.drill_current_home_unit(p.id)
 from auth.users u
 join public.profiles p on p.id=u.id
 left join public.members m on m.id=p.member_id
 where (public.is_drill_app_admin() or public.has_drill_unit_role(p_host_unit,'unit_admin'))
   and lower(u.email)=lower(btrim(p_email))
   and p.member_id is not null
 limit 1;
$$;

create or replace function public.drill_user_names_for_visible_records()
returns table(user_id uuid,display_name text)
language sql stable security definer set search_path=public as $$
 select distinct p.id,
   coalesce(nullif(p.display_name,''),trim(concat_ws(' ',m.first_name,m.last_name)),'CAP User')
 from public.profiles p
 left join public.members m on m.id=p.member_id
 where p.id=auth.uid()
    or exists(
      select 1 from public.drill_records r
      where r.created_by_user_id=p.id
        and public.can_read_drill_record(r.status,r.home_unit_id_at_evaluation,r.evaluation_scope_type,r.evaluation_unit_id,r.activity_id,r.created_by_user_id)
    )
 order by 2;
$$;

-- Public, safe projection for the signed-out sequence viewer.
create or replace view public.drill_public_sequences with (security_invoker=false) as
 select id,code,label,topic,conditions,source_page,sequence,display_order,version,updated_at from public.drill_test_definitions where active order by display_order,label;

-- RLS
alter table public.drill_global_permissions enable row level security;
alter table public.drill_activities enable row level security;
alter table public.drill_user_preferences enable row level security;
alter table public.drill_unit_permissions enable row level security;
alter table public.drill_activity_permissions enable row level security;
alter table public.drill_test_definitions enable row level security;
alter table public.drill_test_items enable row level security;
alter table public.drill_records enable row level security;
alter table public.drill_audit_log enable row level security;
alter table public.members enable row level security;
alter table public.member_unit_assignments enable row level security;
do $$ declare r record; begin for r in select schemaname,tablename,policyname from pg_policies where schemaname='public' and policyname like 'drill_%' loop execute format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename); end loop; end $$;
-- Adds Drill-specific visibility without replacing CAP Schedule's existing units policies.
create policy drill_units_read on public.units for select to authenticated
using(active or public.is_drill_app_admin() or public.has_drill_unit_role(id,'unit_admin'));
create policy drill_global_read on public.drill_global_permissions for select to authenticated using(user_id=auth.uid() or public.is_drill_app_admin());
create policy drill_prefs_read on public.drill_user_preferences for select to authenticated using(user_id=auth.uid() or public.is_drill_app_admin());
create policy drill_unit_permissions_read on public.drill_unit_permissions for select to authenticated using(user_id=auth.uid() or public.is_drill_app_admin() or public.has_drill_unit_role(unit_id,'unit_admin') or public.drill_is_home_unit_admin_for_user(user_id));
create policy drill_activities_read on public.drill_activities for select to authenticated using(active or public.is_drill_app_admin() or public.has_drill_global_role('manage_activities') or public.has_drill_activity_role(id,'data_entry'));
create policy drill_activity_permissions_read on public.drill_activity_permissions for select to authenticated using(user_id=auth.uid() or public.is_drill_app_admin() or public.has_drill_activity_role(activity_id,'activity_admin'));
create policy drill_tests_read on public.drill_test_definitions for select to authenticated using(active or public.is_drill_app_admin());
create policy drill_items_read on public.drill_test_items for select to authenticated using(exists(select 1 from public.drill_test_definitions t where t.id=test_id and (t.active or public.is_drill_app_admin())));
create policy drill_records_read on public.drill_records for select to authenticated using(public.can_read_drill_record(status,home_unit_id_at_evaluation,evaluation_scope_type,evaluation_unit_id,activity_id,created_by_user_id));
create policy drill_audit_read on public.drill_audit_log for select to authenticated using(public.is_drill_app_admin() or (unit_id is not null and public.has_drill_unit_role(unit_id,'unit_admin')) or (activity_id is not null and public.has_drill_activity_role(activity_id,'activity_admin')) or (target_user_id is not null and public.drill_is_home_unit_admin_for_user(target_user_id)));
create policy drill_members_read on public.members for select to authenticated using(public.can_read_drill_member(id));
create policy drill_assignments_read on public.member_unit_assignments for select to authenticated using(public.can_read_drill_member(member_id));

-- Sensitive functions are authenticated only. Do not change unrelated Schedule/Leadership privileges.

revoke execute on function public.is_drill_app_admin() from public,anon;
grant execute on function public.is_drill_app_admin() to authenticated;
revoke execute on function public.has_drill_global_role(text) from public,anon;
grant execute on function public.has_drill_global_role(text) to authenticated;
revoke execute on function public.drill_current_home_unit(uuid) from public,anon;
grant execute on function public.drill_current_home_unit(uuid) to authenticated;
revoke execute on function public.has_drill_unit_role(uuid,text) from public,anon;
grant execute on function public.has_drill_unit_role(uuid,text) to authenticated;
revoke execute on function public.has_drill_activity_role(uuid,text) from public,anon;
grant execute on function public.has_drill_activity_role(uuid,text) to authenticated;
revoke execute on function public.has_any_drill_access() from public,anon;
grant execute on function public.has_any_drill_access() to authenticated;
revoke execute on function public.drill_is_home_unit_admin_for_user(uuid) from public,anon;
grant execute on function public.drill_is_home_unit_admin_for_user(uuid) to authenticated;
revoke execute on function public.can_read_drill_member(uuid) from public,anon;
grant execute on function public.can_read_drill_member(uuid) to authenticated;
revoke execute on function public.can_read_drill_record(text,uuid,text,uuid,uuid,uuid) from public,anon;
grant execute on function public.can_read_drill_record(text,uuid,text,uuid,uuid,uuid) to authenticated;
revoke execute on function public.can_edit_drill_record(uuid) from public,anon;
grant execute on function public.can_edit_drill_record(uuid) to authenticated;
revoke execute on function public.drill_get_my_context() from public,anon;
grant execute on function public.drill_get_my_context() to authenticated;
revoke execute on function public.drill_lookup_member(text) from public,anon;
grant execute on function public.drill_lookup_member(text) to authenticated;
revoke execute on function public.drill_member_suggestions(uuid) from public,anon;
grant execute on function public.drill_member_suggestions(uuid) to authenticated;
revoke execute on function public.drill_ensure_member(text,text,text,uuid) from public,anon;
grant execute on function public.drill_ensure_member(text,text,text,uuid) to authenticated;
revoke execute on function public.drill_upsert_member(uuid,text,text,text,uuid,boolean) from public,anon;
grant execute on function public.drill_upsert_member(uuid,text,text,text,uuid,boolean) to authenticated;
revoke execute on function public.drill_set_unit_permission(uuid,uuid,boolean,boolean,timestamptz,text) from public,anon;
grant execute on function public.drill_set_unit_permission(uuid,uuid,boolean,boolean,timestamptz,text) to authenticated;
revoke execute on function public.drill_grant_temporary_unit_access(uuid,uuid,timestamptz,text) from public,anon;
grant execute on function public.drill_grant_temporary_unit_access(uuid,uuid,timestamptz,text) to authenticated;
revoke execute on function public.drill_revoke_unit_access(uuid,uuid,text) from public,anon;
grant execute on function public.drill_revoke_unit_access(uuid,uuid,text) to authenticated;
revoke execute on function public.drill_set_global_permissions(uuid,boolean,boolean) from public,anon;
grant execute on function public.drill_set_global_permissions(uuid,boolean,boolean) to authenticated;
revoke execute on function public.drill_set_activity_permission(uuid,uuid,boolean,boolean,timestamptz,text) from public,anon;
grant execute on function public.drill_set_activity_permission(uuid,uuid,boolean,boolean,timestamptz,text) to authenticated;
revoke execute on function public.drill_revoke_activity_access(uuid,uuid,text) from public,anon;
grant execute on function public.drill_revoke_activity_access(uuid,uuid,text) to authenticated;
revoke execute on function public.drill_set_user_preference(text,uuid) from public,anon;
grant execute on function public.drill_set_user_preference(text,uuid) to authenticated;
revoke execute on function public.drill_save_activity(uuid,text,text,text,date,date,boolean) from public,anon;
grant execute on function public.drill_save_activity(uuid,text,text,text,date,date,boolean) to authenticated;
revoke execute on function public.drill_upsert_unit(uuid,text,text,boolean) from public,anon;
grant execute on function public.drill_upsert_unit(uuid,text,text,boolean) to authenticated;
revoke execute on function public.drill_save_test_definition(jsonb) from public,anon;
grant execute on function public.drill_save_test_definition(jsonb) to authenticated;
revoke execute on function public.drill_save_record(jsonb) from public,anon;
grant execute on function public.drill_save_record(jsonb) to authenticated;
revoke execute on function public.drill_dashboard_summary(text,uuid) from public,anon;
grant execute on function public.drill_dashboard_summary(text,uuid) to authenticated;
revoke execute on function public.drill_admin_directory() from public,anon;
grant execute on function public.drill_admin_directory() to authenticated;
revoke execute on function public.drill_permission_audit() from public,anon;
grant execute on function public.drill_permission_audit() to authenticated;
revoke execute on function public.drill_find_user_for_host_grant(text,uuid) from public,anon;
grant execute on function public.drill_find_user_for_host_grant(text,uuid) to authenticated;
revoke execute on function public.drill_user_names_for_visible_records() from public,anon;
grant execute on function public.drill_user_names_for_visible_records() to authenticated;
grant select on public.drill_public_sequences to anon,authenticated;
grant select on public.drill_test_definitions,public.drill_test_items,public.drill_activities,public.drill_unit_permissions,public.drill_activity_permissions,public.drill_records,public.drill_global_permissions,public.drill_user_preferences,public.drill_audit_log to authenticated;
revoke insert,update,delete on public.drill_global_permissions,public.drill_unit_permissions,public.drill_activity_permissions,public.drill_activities,public.drill_test_definitions,public.drill_test_items,public.drill_records,public.drill_audit_log from authenticated,anon;

-- Bootstrap existing Schedule App Admins as Drill App Admins (one-time; independent afterward).
insert into public.drill_global_permissions(user_id,is_app_admin)
select id,true from public.profiles where is_app_admin
on conflict(user_id) do update set is_app_admin=true;

-- Ensure the current Montana unit list exists.
insert into public.units(charter_number,name,active) values
('MT-008','Beartooth Composite',true),
('MT-012','Malmstrom Composite',true),
('MT-018','Grizzly Composite',true),
('MT-031','Butte Composite',true),
('MT-037','Gallatin Composite',true),
('MT-053','Flathead Composite',true),
('MT-060','Lewis and Clark Composite',true)
on conflict(charter_number) do update set name=excluded.name;

-- Seed CAPP 60-34 test definitions
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-1','Achievement 1','Basic Drill as an Element Member','Form at least 3 cadets as a single element. Test no more than 2 cadets at a time per testing officer. Tested cadets should not be on the flanks of the element.','su',11,15,'5–6','["1. FALL IN", "2. Parade, REST", "\u2014 Flight, ATTENTION [not graded]", "3. Present, ARMS", "4. Order, ARMS", "5. About, FACE", "\u2014 About, FACE [return / second chance; not graded]", "6. Dress Right, DRESS", "7. Ready, FRONT", "8. Right, FACE", "\u2014 Left, FACE [return / second chance; not graded]", "9. COVER", "10. AT EASE", "11. Flight, ATTENTION", "12. Hand, SALUTE", "13. Eyes, RIGHT", "14. Ready, FRONT", "15. FALL OUT"]'::jsonb,true,10,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','FALL IN','["Automatically executes Dress Right, DRESS.", "Adjusts position to achieve proper dress.", "Automatically executes Ready, FRONT.", "Stands at position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Parade, REST','["Moves left foot such that heels are about 12-inches apart.", "Extends arms behind body & places right hand in palm of the left hand.", "Keeps head and eyes straight ahead; is immobile and silent."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Present, ARMS','["Smartly raises right hand directly to head or headdress.", "Right hand is flat, with fingers fully extended, canted slightly down."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Order, ARMS','["Smoothly and smartly retraces path of arm.", "Ends at the position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','About, FACE','["Pivots 180-degrees clockwise on the ball of the right foot and heel of the left foot.", "Maintains upper body in position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'6',6,'','Dress Right, DRESS','["Raises and extends left arm laterally from the shoulder with snap so arm is parallel with the ground, palm down, hand flat.", "At the same time as left arm is raised, turns head 45-degrees to the right.", "Establishes exact shoulder-to-fingertip contact with the individual to the immediate right."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'7',7,'','Ready, FRONT','["Arms are lowered with snap to their sides and hand is cupped when arm is at approximately waist level.", "As the arm is lowered, returns head to the front with snap."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'8',8,'','Right, FACE','["Pivots 90-degrees to the right on the ball of the left foot and heel of the right foot.", "Maintains upper body in position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'9',9,'','COVER','["Adjusts by taking small choppy steps if needed to establish cover and distance."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'10',10,'','AT EASE','["Relaxes in standing position.", "Keeps right foot in place.", "Silent."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'11',11,'','Flight, ATTENTION','["Assumes Parade Rest on preparatory command.", "Remains immobile and silent, hands cupped."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'12',12,'','Hand, SALUTE','["Count One: arm raised smartly; fingers, palm, and forearm form straight line; upper arm parallel to ground; tip of middle finger touches correct point on headdress/eyebrow/glasses; rest of body remains at attention.", "Count Two: arm comes smoothly and smartly down; retraces path; hand is cupped as it passes the waist; ends with entire body at attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'13',13,'','Eyes, RIGHT','["Turns head and eyes smartly 45 degrees to the right."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'14',14,'','Ready, FRONT','["On FRONT, head and eyes are turned smartly to the front."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'15',15,'','FALL OUT','["Simply breaks ranks but remains in vicinity."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-1' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-2','Achievement 2','Basic Drill as a Flight Member','Form at least 6 cadets into a flight of 2 elements.','su',11,15,'7–8','["\u2014 FALL IN [not graded]", "\u2014 Right, FACE [not graded]", "1. Forward, MARCH", "2. Double Time, MARCH", "3. Quick Time, MARCH", "4. Flight, HALT", "\u2014 Left, FACE [not graded]", "5. Open Ranks, MARCH", "6. Ready, FRONT", "7. Close Ranks, MARCH", "8. Right Step, MARCH", "9. Flight, HALT", "\u2014 Right, FACE [not graded]", "10. Forward, MARCH", "11. Right Flank, MARCH", "12. Left Flank, MARCH", "13. Count Cadence, COUNT", "14. To the Rear, MARCH", "15. Flight, HALT", "\u2014 FALL OUT [not graded]"]'::jsonb,true,11,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','Forward, MARCH','["Steps off on left foot.", "Does not anticipate the command of execution."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Double Time, MARCH','["Takes one more step in quick time and then steps off in double time."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Quick Time, MARCH','["Advances two more steps in double time.", "Resumes quick time.", "Lowers arms to sides and resumes armswing."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Flight, HALT','["After HALT, takes one more 24-inch step.", "Trailing foot is brought smartly alongside front foot.", "Heels finish together, on line, with cadet at attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Open Ranks, MARCH','["Marches forward the correct number of steps for the element (1st=3, 2nd=2).", "Automatically executes Dress Right, DRESS once halted."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'6',6,'','Ready, FRONT','["Lowers arm with snap but without slapping leg.", "Turns head to front with snap."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'7',7,'','Close Ranks, MARCH','["1st Element stands fast; 2nd Element takes 1 step forward."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'8',8,'','Right Step, MARCH','["Leg is kept straight, but not stiff.", "Right foot moves 12 inches to the right.", "Left foot is brought smartly alongside the right foot without scraping the ground."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'9',9,'','Flight, HALT','["On HALT, one more step is taken and trailing foot is placed smartly alongside halted foot at attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'10',10,'','Forward, MARCH','["Steps off on left foot.", "Does not anticipate the command of execution."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'11',11,'','Right Flank, MARCH','["While marching, turns 90-degrees to the right.", "Maintains proper dress, cover, interval, and distance.", "Maintains posture as if at attention; suspends armswing during pivot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'12',12,'','Left Flank, MARCH','["While marching, turns 90-degrees to the left.", "Maintains proper dress, cover, interval, and distance.", "Maintains posture as if at attention; suspends armswing during pivot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'13',13,'','Count Cadence, COUNT','["Gives count sharply and clearly without shouting and separates each number distinctly.", "Counts ONE-TWO-THREE-FOUR-ONE-TWO-THREE-FOUR."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'14',14,'','To the Rear, MARCH','["Takes a half step, pivots, another half step, then steps off with a 24-inch step.", "Maintains posture as if at attention; suspends armswing during pivot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'15',15,'','Flight, HALT','["After HALT, takes one more 24-inch step.", "Trailing foot is brought smartly alongside front foot.", "Heels finish together, on line, with cadet at attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-3','Achievement 3','Advanced Drill as a Flight Member','Form at least 6 cadets into a flight of 2 elements. Graded cadet will be 1st element leader.','su',9,12,'9–10','["1. At Close Interval, FALL IN", "2. At Close Interval, Dress Right, DRESS", "\u2014 Ready, FRONT", "\u2014 FALL OUT [not graded]", "\u2014 FALL IN [not graded]", "\u2014 Right, FACE [not graded]", "3. Close, MARCH", "4. Extend, MARCH", "5. Column of Files from the Right, Column Right, MARCH", "\u2014 Flight, HALT [not graded]", "\u2014 FALL OUT [not graded]", "\u2014 FALL IN [not graded]", "\u2014 Right, FACE [not graded]", "6. Forward, MARCH", "7. Close, MARCH / Forward, MARCH", "8. Extend, MARCH / Forward, MARCH", "9. Change Step, MARCH", "10. Column Left, MARCH / Forward, MARCH", "11. Eyes, RIGHT / Ready, FRONT", "12. Flight, HALT", "\u2014 FALL OUT [not graded]"]'::jsonb,true,12,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','At Close Interval, FALL IN','["Automatically executes At Close Interval Dress Right, DRESS.", "Automatically executes Ready, FRONT.", "Stands at the position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','At Close Interval, Dress Right, DRESS & Ready, FRONT','["On DRESS, left hand is placed so heel of hand rests on left hip, fingertips point toward ground, elbow in line with body; adjusts as necessary.", "On FRONT, returns to position of attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Close, MARCH (while halted)','["Second element stands fast; first element takes two 12-inch steps to the right."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Extend, MARCH (while halted)','["Second element stands fast; first element takes two 12-inch steps to the left."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Column of Files from the Right, Column Right, MARCH','["On preparatory command, element leaders turn heads 45 degrees right; 2nd element leader commands Column Right and 1st element leader commands STAND FAST.", "On MARCH, 2nd element leader executes a face in marching to the right and continues in new direction.", "Remaining members of 2nd element march forward, pivot at approximately same location, and maintain 40-inch distance.", "After last cadet of 2nd element passes, 1st element leader commands Column Right, MARCH on right foot; all cadets perform movement like base element."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'6',6,'','Forward, MARCH','["Steps off on left foot.", "Does not anticipate command of execution."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'7',7,'','Close, MARCH & Forward, MARCH (while marching)','["2nd element takes up half step following command of execution.", "1st element obtains close interval via correct 45-degree pivots and 24-inch step, then takes up half step.", "On Forward, MARCH both elements resume a 24-inch step."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'8',8,'','Extend, MARCH & Forward, MARCH (while marching)','["Uses same procedures and steps as close interval except command is given on left foot and pivots are made on right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'9',9,'','Change Step, MARCH','["On MARCH takes one 24-inch step with left foot.", "Places ball of right foot alongside heel of left foot, pins arms, shifts weight to right foot.", "Steps off with left foot in full 24-inch step and resumes coordinated armswing."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'10',10,'','Column Left, MARCH & Forward, MARCH','["While marching, turns 90-degrees to the left.", "Takes up half step.", "Resumes full 24-inch steps after Forward, MARCH."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'11',11,'','Eyes, RIGHT & Ready, FRONT (while marching)','["On RIGHT, all cadets except those on right flank smartly turn heads 45 degrees right.", "On FRONT, heads turn smartly back to front."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'12',12,'','Flight, HALT','["After HALT, takes one more 24-inch step.", "Trailing foot is brought smartly alongside front foot.", "Heels finish together, on line, with cadet at attention."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-3' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('WBA-2','Wright Brothers Award — Part 2','Advanced Drill as an Element Leader','This is the second part of the Wright Brothers Exam. Form at least 6 cadets into a flight of 2 elements. Graded cadet will be 1st element leader.','su',16,20,'11–12','["31. FALL IN", "32. Present, ARMS / Order, ARMS", "33. Parade, REST", "34. Flight, ATTENTION", "35. Left Step, MARCH / Flight, HALT", "36. Left, FACE", "37. About, FACE", "38. Forward, MARCH", "39. Right Flank, MARCH", "40. Left Flank, MARCH", "41. Column Right, MARCH / Forward, MARCH", "42. To the Rear, MARCH", "\u2014 To the Rear, MARCH [not graded; positions flight]", "43. Column Left, MARCH / Forward, MARCH", "44. Change Step, MARCH", "45. Count Cadence, COUNT", "46. Flight, HALT", "47. Right, FACE", "48. Open Ranks, MARCH", "49. Ready, FRONT", "50. Close Ranks, MARCH / FALL OUT"]'::jsonb,true,13,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'31',1,'','FALL IN','["Assumes position of Attention.", "Raises left arm to establish interval for the flight."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'32',2,'','Present, ARMS & Order, ARMS','["Smartly raises right hand to right eyebrow, glasses, or bill of cap; holds salute slightly canted down.", "Smoothly and smartly retraces path of arm down to position of Attention."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'33',3,'','Parade, REST','["Moves left foot so heels are about 12 inches apart.", "Extends arms behind body and places right hand in palm of left hand.", "Keeps head and eyes straight ahead; is immobile and silent."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'34',4,'','Flight, ATTENTION','["Stands and shows good posture; hands cupped on pant/skirt seam.", "Remains immobile and silent."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'35',5,'','Left Step, MARCH & Flight, HALT','["Steps sideways left via series of 12-inch steps without dragging right foot.", "After halt, takes another step left and brings feet together."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'36',6,'','Left, FACE','["Pivots 90-degrees to the left on ball and heel.", "Maintains upper body in position of Attention."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'37',7,'','About, FACE','["Pivots 180-degrees to the right on ball and heel in 2 counts.", "Maintains upper body in position of Attention."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'38',8,'','Forward, MARCH','["Steps off with left foot.", "Does not anticipate command of execution."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'39',9,'','Right Flank, MARCH','["While marching, turns 90-degrees to the right.", "Maintains proper dress, cover, interval, and distance.", "Suspends armswing during pivot."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'40',10,'','Left Flank, MARCH','["While marching, turns 90-degrees to the left.", "Maintains proper dress, cover, interval, and distance.", "Suspends armswing during pivot."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'41',11,'','Column Right, MARCH & Forward, MARCH','["While marching, turns 90-degrees right via two 45-degree pivots.", "Takes up half-step at correct time and maintains until Forward, MARCH.", "Maintains proper dress and interval."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'42',12,'','To the Rear, MARCH','["While marching, reverses direction smartly by pivoting 180-degrees right.", "Takes half step, pivot, half step, full step; suspends armswing during pivot.", "Maintains proper dress, cover, interval, and distance."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'43',13,'','Column Left, MARCH & Forward, MARCH','["While marching, turns 90-degrees left via one 90-degree pivot.", "Takes up half-step at correct time and maintains until Forward, MARCH.", "Maintains proper dress and interval."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'44',14,'','Change Step, MARCH','["In one count, places ball of right foot alongside heel of left foot, then steps off with left foot.", "Maintains posture as if at Attention; suspends armswing during maneuver."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'45',15,'','Count Cadence, COUNT','["Counts cadence for eight steps.", "Does not shout; makes counts sharp and clear as heel strikes the ground."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'46',16,'','Flight, HALT','["Comes to full stop in two counts.", "Maintains position of Attention."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'47',17,'','Right, FACE','["Pivots 90-degrees to the left on ball and heel.", "Maintains upper body in position of Attention."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'48',18,'','Open Ranks, MARCH','["1st Element takes 3 steps forward.", "Automatically executes Dress Right, DRESS once halted."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'49',19,'','Ready, FRONT','["Lowers arm with snap but without slapping leg.", "Turns head to front with snap."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'50',20,'','Close Ranks, MARCH & FALL OUT','["1st Element stands fast at Attention.", "Breaks ranks to fall out; no specific method of dispersal is required."]'::jsonb,1,true from public.drill_test_definitions where code='WBA-2' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-4','Achievement 4','Drill of the Element as an Element Leader (not in ranks)','Provide the cadet the command list and allow reference during the test. Cadet leads an element of at least 3 proficient cadets and completes all commands in sequence. Only the cadet’s ability to call commands properly is evaluated.','su',4,5,'13','["1. FALL IN", "2. Dress Right, DRESS (check alignment)", "3. Ready, FRONT", "4. Right, FACE", "5. Left, FACE", "6. About, FACE", "7. Left, FACE", "8. Forward, MARCH", "9. Left Flank, MARCH", "10. Right Flank, MARCH", "11. To the Rear, MARCH", "12. Element, HALT", "13. FALL OUT"]'::jsonb,true,14,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','Knowledge','["Calls commands on the correct foot when the foot corresponding to the direction of movement strikes the ground."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-4' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Timing','["Calls commands of execution two steps after calling preparatory commands."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-4' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Voice','["Calls commands loud enough for the element to hear.", "Calls commands clear enough for the element to understand.", "Uses proper inflection (raising)."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-4' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Bearing','["Calls commands decisively, with snap and a sense of \u201cGo!\u201d", "Maintains good military bearing."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-4' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Overall Leadership','["Calls cadence or halts and restarts the element if cadets fall out of step or lose alignment.", "Completes all assigned commands."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-4' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-5','Achievement 5','Drill of the Flight as a Flight Sergeant','Form at least 6 cadets into a flight of 2 elements. Provide the cadet the command list without standards and allow reference. Cadet leads the flight through all commands. The flight’s ability to perform is not graded; only the cadet’s ability to call commands properly.','su',16,21,'14–15','["1. FALL IN", "2. Dress Right, DRESS (check alignment)", "3. Ready, FRONT", "4. Right, FACE", "5. Forward, MARCH", "6. Column Right, MARCH", "7. Forward, MARCH", "8. Close, MARCH & Forward, MARCH", "9. Extend, MARCH & Forward, MARCH", "10. Change Step, MARCH", "11. Count Cadence, COUNT", "12. Flight, HALT", "13. Left Step, MARCH", "14. Flight, HALT", "15. Left, FACE", "16. Open Ranks, MARCH (check alignment)", "17. Ready, FRONT", "18. Close Ranks, MARCH", "\u2014 Right, FACE [not graded]", "19. Column of Files from the Right, Forward, MARCH", "20. Flight, HALT", "21. FALL OUT"]'::jsonb,true,15,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','FALL IN','["Gives command from position of attention.", "Combined command given with steady inflection without pause between words."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Dress Right, DRESS (check alignment)','["Proceeds to right flank and directs individual cadets to move as needed.", "Proceeds from element to element by facing in marching.", "After checking 2nd element, faces in marching right, moves 3 paces forward of front rank, halts, faces left."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Ready, FRONT','["After giving command, resumes position 3 paces from and centered on flight.", "Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Right, FACE','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Forward, MARCH','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'6',6,'','Column Right, MARCH','["Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'7',7,'','Forward, MARCH','["Command is clear and snaps. Given on left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'8',8,'','Close, MARCH & Forward, MARCH','["Close: preparatory right foot, execution right foot.", "Forward: preparatory left foot, execution left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'9',9,'','Extend, MARCH & Forward, MARCH','["Extend: preparatory left foot, execution left foot.", "Forward: preparatory left foot, execution left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'10',10,'','Change Step, MARCH','["Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'11',11,'','Count Cadence, COUNT','["Preparatory: left foot. Execution: left foot.", "Preparatory command is given in one count, not spread out or sung."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'12',12,'','Flight, HALT','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'13',13,'','Left Step, MARCH','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'14',14,'','Flight, HALT','["Preparatory when heels are together. Execution when heels are together."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'15',15,'','Left, FACE','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'16',16,'','Open Ranks, MARCH (check alignment)','["At command of execution, takes six steps backward and halts; executes a face in marching 45 degrees left, halts next to 1st element leader facing rear of flight, and faces right.", "Takes short side steps to check alignment without bending body.", "Directs individual cadets to move as needed.", "After checking 2nd element, faces in marching right, moves 3 paces forward of front rank, halts, faces left."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'17',17,'','Ready, FRONT','["After giving command, resumes position 3 paces from and centered on flight.", "Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'18',18,'','Close Ranks, MARCH','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'19',19,'','Column of Files from the Right, Forward, MARCH','["Preparatory command is given without \u201csinging,\u201d in one count.", "Pauses between preparatory command and command of execution to allow element leaders to give supplementary commands.", "Command of execution is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'20',20,'','Flight, HALT','["Command is clear and snaps."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'21',21,'','FALL OUT','["Combined command given in steady inflection without pause between words."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-5' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-6','Achievement 6','Squadron Formations','At least 3 additional cadets are needed to role play. Graded cadet is Squadron First Sergeant. Instruct the cadet to assume the role of first sergeant and assemble the squadron. The squadron’s ability to perform is not graded; only the cadet’s ability to assemble the squadron is evaluated.','su',4,5,'16','[]'::jsonb,true,16,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','Sq/CCF: FALL IN','["Positions self 9 paces away and centered from where flights are to be formed."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-6' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Sq/CCF: REPORT','["After flights are assembled, commands REPORT.", "Receives report from Alpha flight sergeant.", "Turns head toward A Flight and returns salute.", "Receives report from Bravo flight sergeant.", "Turns head toward B Flight and returns salute."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-6' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Sq/CCF: POST','["Commands flight sergeants to post.", "Faces about in anticipation of Sq/CC\u2019s arrival."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-6' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Sq/CC takes position','["Salutes.", "Immediately reports attendance to Sq/CC: \u201cSir/Ma\u2019am, All Present or Accounted For.\u201d"]'::jsonb,1,true from public.drill_test_definitions where code='ACH-6' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Sq/CC returns salute','["Drops salute.", "Faces about.", "Marches without pivots to position behind the last cadet (not flight sergeant) in Bravo Flight\u2019s last element; simulate if necessary and verbally quiz exact position."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-6' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-7','Achievement 7','Squadron Formations','Problem #1 is completed on paper with no reference materials. Problem #2 requires 3 cadets in addition to the cadet being tested to role play a formal Change of Command Ceremony.','points',16,20,'17–19','["Problem #1: Diagram the Squadron in Line with three Flights in Line; label required distances; use proper drill symbols.", "Problem #2: Conduct the Change of Command ceremony using the scorecard sequence."]'::jsonb,true,17,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-1',1,'Problem #1 — Squadron in Line','Correct locations for unit commanders','["Diagram places unit commanders correctly."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-2',2,'Problem #1 — Squadron in Line','Correct locations for flight sergeants','["Diagram places flight sergeants correctly."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-3',3,'Problem #1 — Squadron in Line','Correct locations for flight guides','["Diagram places flight guides correctly."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-4',4,'Problem #1 — Squadron in Line','Correct location for squadron guidon bearer','["Diagram places squadron guidon bearer correctly."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-5',5,'Problem #1 — Squadron in Line','Units arrayed in Line','["Units are next to one another, not behind one another as in Column."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-6',6,'Problem #1 — Distances','Three paces between flights','["Labels 3 paces between flights."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-7',7,'Problem #1 — Distances','Flight commanders 6 paces in front','["Labels flight commanders 6 paces in front of their flights."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-8',8,'Problem #1 — Distances','Squadron commander 12 paces in front','["Labels squadron commander 12 paces in front of the squadron."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-9',9,'Problem #1 — Drill Symbols','At least half of symbols are correct','["Award this point if at least half of the drill symbols are correct."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p1-10',10,'Problem #1 — Drill Symbols','At least 80% of symbols are correct','["Award this additional point if at least 80% of drill symbols are correct."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-1',11,'Problem #2 — Change of Command','Participants form as shown facing audience','["Incoming Commander, Outgoing Commander, Wing Commander, and Flag Bearer are positioned for the start of the ceremony."]'::jsonb,2,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-2',12,'Problem #2 — Change of Command','Flag Bearer commands “Officers, CENTER”','["Arnold and Curry face right.", "Mitchell faces left."]'::jsonb,2,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-3',13,'Problem #2 — Change of Command','Curry relinquishes command','["Curry salutes Mitchell.", "Curry states \u201cSir/Ma\u2019am, I relinquish command.\u201d", "Mitchell returns salute."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-4',14,'Problem #2 — Change of Command','Curry transfers flag to Mitchell','["Curry takes flag from Flag Bearer and presents it to Mitchell."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-5',15,'Problem #2 — Change of Command','Commanders reposition','["Curry takes 1 step right, 2 steps back, and 1 step left.", "Simultaneously, Arnold takes 2 steps forward."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-6',16,'Problem #2 — Change of Command','Mitchell presents flag to Arnold','["Mitchell presents flag to Arnold, who passes it to Flag Bearer."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-7',17,'Problem #2 — Change of Command','Arnold assumes command','["Arnold salutes Mitchell.", "Arnold states \u201cSir/Ma\u2019am, I assume command.\u201d", "Mitchell returns salute."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'p2-8',18,'Problem #2 — Change of Command','Flag Bearer commands “Officers, POST”','["All 3 officers face forward."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-7' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_definitions(code,label,topic,conditions,scoring_mode,pass_required,max_score,source_page,sequence,active,display_order,version) values('ACH-8','Achievement 8','Squadron Drill','At least two cadets who can competently command a flight in a squadron formation are needed. Provide the cadet the command list without standards and allow reference. Cadet forms the squadron in line and leads two flights through the sequence. Flight performance is not graded; the first sergeant’s commands are.','su',13,17,'20–22','["\u2014 FALL IN [not graded; reporting not necessary]", "1. AT EASE", "2. Squadron, ATTENTION", "3. Right, FACE", "4. Forward, MARCH", "5. Column Left, MARCH", "6. Forward, MARCH", "7. Column Right, MARCH", "8. Forward, MARCH", "9. Right Flank, MARCH", "10. Left Flank, MARCH", "11. To the Rear, MARCH", "12. To the Rear, MARCH", "13. Eyes, RIGHT", "14. Ready, FRONT", "15. Squadron, HALT", "16. Left, FACE", "17. DISMISSED"]'::jsonb,true,18,1) on conflict(code) do update set label=excluded.label,topic=excluded.topic,conditions=excluded.conditions,scoring_mode=excluded.scoring_mode,pass_required=excluded.pass_required,max_score=excluded.max_score,source_page=excluded.source_page,sequence=excluded.sequence,active=true,display_order=excluded.display_order;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'1',1,'','AT EASE','["Gives combined command properly with no pause and no supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'2',2,'','Squadron, ATTENTION','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'3',3,'','Right, FACE','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'4',4,'','Forward, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'5',5,'','Column Left, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary commands.", "Preparatory: left foot. Execution: left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'6',6,'','Forward, MARCH','["Waits for 2nd flight to complete column movement.", "Given on left foot.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'7',7,'','Column Right, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary commands.", "Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'8',8,'','Forward, MARCH','["Waits for 2nd flight to complete column movement.", "Given on left foot.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'9',9,'','Right Flank, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'10',10,'','Left Flank, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: left foot. Execution: left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'11',11,'','To the Rear, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'12',12,'','To the Rear, MARCH','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'13',13,'','Eyes, RIGHT','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: right foot. Execution: right foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'14',14,'','Ready, FRONT','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command.", "Preparatory: left foot. Execution: left foot."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'15',15,'','Squadron, HALT','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'16',16,'','Left, FACE','["Command is clear and snaps.", "Pauses after preparatory command for flight sergeants to give supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
insert into public.drill_test_items(test_id,item_key,item_order,group_label,command,standards,points,active) select id,'17',17,'','DISMISSED','["Gives combined command properly with no pause and no supplementary command."]'::jsonb,1,true from public.drill_test_definitions where code='ACH-8' on conflict(test_id,item_key) do update set item_order=excluded.item_order,group_label=excluded.group_label,command=excluded.command,standards=excluded.standards,points=excluded.points,active=true;
commit;
