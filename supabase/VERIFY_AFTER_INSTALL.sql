-- CAP Drill Test Manager post-install verification.
-- Run after 20260916_cap_drill_test_manager.sql completes successfully.

-- 1. Drill tables.
select table_name
from information_schema.tables
where table_schema='public' and table_name in (
 'drill_global_permissions','drill_user_preferences','drill_unit_permissions','drill_activities',
 'drill_activity_permissions','drill_test_definitions','drill_test_items','drill_records','drill_audit_log'
)
order by table_name;

-- Expected: 9 rows.

-- 2. Required Drill functions / RPCs.
select routine_name
from information_schema.routines
where routine_schema='public' and routine_name in (
 'is_drill_app_admin','has_drill_global_role','drill_current_home_unit','has_drill_unit_role',
 'has_drill_activity_role','has_any_drill_access','drill_is_home_unit_admin_for_user',
 'can_read_drill_member','can_read_drill_record','can_edit_drill_record','drill_get_my_context',
 'drill_lookup_member','drill_member_suggestions','drill_ensure_member','drill_upsert_member',
 'drill_set_unit_permission','drill_grant_temporary_unit_access','drill_revoke_unit_access',
 'drill_set_global_permissions','drill_set_activity_permission','drill_revoke_activity_access',
 'drill_set_user_preference','drill_save_activity','drill_upsert_unit','drill_save_test_definition',
 'drill_save_record','drill_dashboard_summary','drill_admin_directory','drill_permission_audit',
 'drill_find_user_for_host_grant','drill_user_names_for_visible_records'
)
order by routine_name;

-- 3. RLS enabled on Drill tables.
select c.relname as table_name,c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relname in (
 'drill_global_permissions','drill_user_preferences','drill_unit_permissions','drill_activities',
 'drill_activity_permissions','drill_test_definitions','drill_test_items','drill_records','drill_audit_log'
)
order by c.relname;

-- Expected: every rls_enabled value = true.

-- 4. Drill-owned RLS policies, including the additive policy on shared units/members.
select tablename,policyname,roles,cmd
from pg_policies
where schemaname='public' and policyname like 'drill_%'
order by tablename,policyname;

-- 5. Seeded test definitions.
select code,label,pass_required,max_score,active,display_order
from public.drill_test_definitions
order by display_order;

-- Expected: ACH-1, ACH-2, ACH-3, WBA-2, ACH-4, ACH-5, ACH-6, ACH-7, ACH-8.

-- 6. Graded item counts by test.
select t.code,count(i.id) as item_count
from public.drill_test_definitions t
left join public.drill_test_items i on i.test_id=t.id and i.active
group by t.code,t.display_order
order by t.display_order;

-- 7. Requested Montana units.
select id,charter_number,name,active
from public.units
where charter_number in ('MT-008','MT-012','MT-018','MT-031','MT-037','MT-053','MT-060')
order by charter_number;

-- 8. Bootstrapped Drill App Admin(s).
select p.id,p.display_name,g.is_app_admin,g.manage_activities
from public.profiles p
join public.drill_global_permissions g on g.user_id=p.id
where g.is_app_admin
order by p.display_name;

-- Expected: at least the existing CAP Schedule App Admin account.

-- 9. Public sequence projection.
select code,label,topic,display_order,version
from public.drill_public_sequences
order by display_order;

-- 10. Current Drill data counts (zero records/activities is normal immediately after install).
select
 (select count(*) from public.drill_records) as drill_records,
 (select count(*) from public.drill_activities) as activities,
 (select count(*) from public.drill_unit_permissions where revoked_at is null) as active_unit_permission_rows,
 (select count(*) from public.drill_activity_permissions where revoked_at is null) as active_activity_permission_rows;
