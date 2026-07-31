-- ============================================================
-- Diagnostic: find auth accounts missing (or blocked from
-- reading) their public.users profile row.
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
-- ============================================================

-- 1) Every signed-up auth account, joined to its profile row (if any).
--    Look at "has_profile_row" = false rows -- those are accounts
--    where main.dart's profile fetch will always return null,
--    leaving AuthSession.currentUser unset even with a valid session.
select
  au.id,
  au.email,
  au.created_at        as auth_created_at,
  au.last_sign_in_at,
  (pu.id is not null)   as has_profile_row,
  pu.name,
  pu.status,
  pu.division_type_id,
  pu.access_level
from auth.users au
left join public.users pu on pu.id = au.id
order by au.created_at desc;

-- 2) Is Row Level Security even enabled on public.users, and what
--    policies exist? If RLS is on with no SELECT policy that matches
--    the logged-in user's own row, the query above will return the
--    row via this admin connection, but the app's own read (as that
--    user) would still come back empty.
select relrowsecurity, relforcerowsecurity
from pg_class
where relname = 'users'
  and relnamespace = 'public'::regnamespace;

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'users';
