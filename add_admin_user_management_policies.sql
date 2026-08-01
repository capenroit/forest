-- ============================================================
-- Allow access_level 1/2 (admin/manager) accounts to view and
-- update OTHER users' rows in public.users, so a Members page can
-- let them approve signups (status -> 'Active') and manage accounts.
--
-- Today's policy ("Users can update their own record") is scoped to
-- auth.uid() = id, which blocks an admin from touching anyone else's
-- row — the Members page's UPDATE would silently be rejected by RLS
-- without this. These are ADDITIVE policies (OR'd with existing ones
-- by Postgres RLS) — they don't remove the existing "own row" access
-- for regular users.
--
-- The subquery in each USING clause checks the CURRENT caller's own
-- access_level via their own row — this does not recurse, since that
-- lookup is satisfied by the existing "own row" SELECT policy.
-- ============================================================

create policy "Admins can view all users"
on public.users
for select
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

create policy "Admins can update any user"
on public.users
for update
to authenticated
using (
  exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
)
with check (
  exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- Verify afterward:
select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename = 'users'
order by cmd, policyname;
