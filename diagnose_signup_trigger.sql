-- ============================================================
-- Diagnostic: find the trigger/function that auto-creates a
-- public.users row when someone signs up, plus the users table's
-- default status/access_level, so the fix can read division_type_id
-- from signup metadata instead of requiring a follow-up UPDATE
-- (which needs an active session that won't exist until the user
-- confirms their email).
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
-- ============================================================

-- 1) Triggers on auth.users (this is almost certainly where the
--    "create a public.users row on signup" trigger lives).
select trigger_name, event_manipulation, action_timing, action_statement
from information_schema.triggers
where event_object_schema = 'auth'
  and event_object_table = 'users';

-- 2) Full source of every trigger function in public — one of these
--    is the one referenced by query 1's action_statement.
select p.proname as function_name, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.prorettype = 'trigger'::regtype;

-- 3) users table schema — confirms status/access_level/division_type_id
--    column names, types, and defaults.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'users'
order by ordinal_position;

-- 4) What status value new signups actually end up with today (sample
--    of the most recently created accounts).
select id, email, name, status, access_level, division_type_id, created_at
from public.users
order by created_at desc
limit 10;
