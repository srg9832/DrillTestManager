-- DESTRUCTIVE: removes all Drill Test Manager data/objects only.
-- Does NOT delete shared profiles, units, members, Schedule data, or Leadership Feedback data.
begin;
drop view if exists public.drill_public_sequences;
drop table if exists public.drill_audit_log cascade;
drop table if exists public.drill_records cascade;
drop table if exists public.drill_test_items cascade;
drop table if exists public.drill_test_definitions cascade;
drop table if exists public.drill_activity_permissions cascade;
drop table if exists public.drill_user_preferences cascade;
drop table if exists public.drill_activities cascade;
drop table if exists public.drill_unit_permissions cascade;
drop table if exists public.drill_global_permissions cascade;
-- Functions are left in place if PostgreSQL dependencies prevent automatic removal;
-- they are harmless once the Drill tables are gone and can be dropped individually if desired.
commit;
