-- ============================================================
-- Fix: "Users can update their own record" is currently:
--   roles = {public}, qual = true, with_check = true
-- which means ANY request -- even fully unauthenticated -- can
-- update ANY row in public.users, including access_level and
-- division_type_id. The policy name implies the intent was to
-- restrict updates to a user's own row; this restores that.
--
-- Confirmed safe for the signup flow: email confirmation is OFF
-- for this project, so auth.signUp() grants a session immediately,
-- meaning auth.uid() resolves correctly when signup_screen.dart
-- writes division_type_id right after signUp().
--
-- No client code updates any users row other than its own (checked
-- across the app), so this does not break any existing feature.
-- ============================================================

drop policy "Users can update their own record" on public.users;

create policy "Users can update their own record"
on public.users
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

-- Verify afterward: should now show roles={authenticated} and
-- qual/with_check referencing auth.uid() = id, matching the
-- "Admin and Manager only" DELETE policy's pattern.
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'users';
