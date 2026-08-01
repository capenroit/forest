-- ============================================================
-- Diagnostic: division_type_id still not saving on signup even
-- after fix_handle_new_user_division.sql and a fresh test signup.
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
-- ============================================================

-- 1) Confirm the live trigger function actually includes the
--    division_type_id fix (in case the CREATE OR REPLACE didn't
--    take, or an old cached definition is somehow still active).
select pg_get_functiondef(oid)
from pg_proc
where proname = 'handle_new_user'
  and pronamespace = 'public'::regnamespace;

-- 2) Look at your most recent test signup: what metadata did
--    auth.users actually receive? If division_type_id is missing or
--    null here, the problem is upstream of the trigger (the app
--    isn't sending it, or Supabase isn't storing it as expected).
select id, email, raw_user_meta_data, created_at
from auth.users
order by created_at desc
limit 5;

-- 3) Same accounts' resulting public.users row — compare
--    division_type_id here against what raw_user_meta_data showed
--    in query 2, for the same id.
select id, email, name, division_type_id, access_level, status, created_at
from public.users
order by created_at desc
limit 5;
