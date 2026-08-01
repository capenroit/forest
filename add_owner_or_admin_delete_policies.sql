-- ============================================================
-- Owner-or-admin delete rule across every activity table.
--
-- Findings from diagnostics run earlier:
--  - crm_habitat_assssment / crm_marine_protected already track the
--    creator via an existing "userid" (bigint) column, referencing
--    public.users.seq_id — NOT auth.uid() directly. (habitat_assessment_form.dart
--    already passes AuthSession.currentUser?.seqId into this column.)
--    No new column is needed for these two.
--  - flora_fauna_survey, seed_donation, tree_growing,
--    tree_survival_monitoring all use "user_id" (uuid), matching
--    auth.uid() directly.
--  - seedling_transaction uses "user_id" (integer), also referencing
--    users.seq_id like the habitat/marine tables.
--  - flora_fauna_survey, seed_donation, seedling_transaction, and
--    tree_growing each had a DELETE policy literally named
--    "Enable delete for users based on user_id" whose qual was just
--    `true` — i.e. it did NOT actually check user_id despite the
--    name. Anyone could delete anyone else's row.
--  - tree_survival_monitoring already had a correctly-restricted
--    DELETE policy (auth.uid() = user_id), just no admin override.
--  - crm_habitat_assssment / crm_marine_protected had a single "ALL"
--    policy (qual = true) covering select/insert/update/delete with
--    no restriction at all.
--
-- IMPORTANT: "Delete" in the app is a real SQL DELETE only for
-- seed_donation and seedling_transaction. For tree_growing,
-- tree_survival_monitoring, flora_fauna_survey, crm_habitat_assssment,
-- and crm_marine_protected, "Delete" is actually
-- UPDATE ... SET is_deleted = 1 — so a DELETE policy alone wouldn't
-- gate what the app's Delete button does. Those five get a trigger
-- instead (added at the bottom) that blocks the specific
-- is_deleted 0->1 transition unless the caller owns the row or is an
-- admin, while leaving every other UPDATE (normal edits) unrestricted
-- — exactly like today.
--
-- Run this whole script in one go, not statement-by-statement.
-- ============================================================

-- ---- 1) flora_fauna_survey: fix the DELETE-only policy -------------
drop policy if exists "Enable delete for users based on user_id" on public.flora_fauna_survey;

create policy "Owner or admin can delete"
on public.flora_fauna_survey for delete
to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 2) seed_donation: fix the DELETE-only policy -------------------
drop policy if exists "Enable delete for users based on user_id" on public.seed_donation;

create policy "Owner or admin can delete"
on public.seed_donation for delete
to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 3) tree_growing: fix the DELETE-only policy --------------------
drop policy if exists "Everyone can delete plantings" on public.tree_growing;

create policy "Owner or admin can delete"
on public.tree_growing for delete
to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 4) tree_survival_monitoring: add the admin override ------------
drop policy if exists "Enable delete for users based on user_id" on public.tree_survival_monitoring;

create policy "Owner or admin can delete"
on public.tree_survival_monitoring for delete
to authenticated
using (
  auth.uid() = user_id
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 5) seedling_transaction: user_id is an int referencing seq_id -
drop policy if exists "Enable delete for users based on user_id" on public.seedling_transaction;

create policy "Owner or admin can delete"
on public.seedling_transaction for delete
to authenticated
using (
  user_id = (select seq_id from public.users where id = auth.uid())
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 6) crm_habitat_assssment / crm_marine_protected: split the ----
-- ---- ALL policy so DELETE can be restricted without touching -------
-- ---- select/insert/update behavior ----------------------------------
drop policy if exists "Policy with security definer functions" on public.crm_habitat_assssment;

create policy "Enable read access for all users"
on public.crm_habitat_assssment for select
to public
using (true);

create policy "Enable insert for authenticated users"
on public.crm_habitat_assssment for insert
to authenticated
with check (true);

create policy "Enable update for authenticated users"
on public.crm_habitat_assssment for update
to authenticated
using (true)
with check (true);

create policy "Owner or admin can delete"
on public.crm_habitat_assssment for delete
to authenticated
using (
  userid = (select seq_id from public.users where id = auth.uid())
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

drop policy if exists "Policy with security definer functions" on public.crm_marine_protected;

create policy "Enable read access for all users"
on public.crm_marine_protected for select
to public
using (true);

create policy "Enable insert for authenticated users"
on public.crm_marine_protected for insert
to authenticated
with check (true);

create policy "Enable update for authenticated users"
on public.crm_marine_protected for update
to authenticated
using (true)
with check (true);

create policy "Owner or admin can delete"
on public.crm_marine_protected for delete
to authenticated
using (
  userid = (select seq_id from public.users where id = auth.uid())
  or exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.access_level in (1, 2)
  )
);

-- ---- 7) Trigger-based enforcement for the soft-delete tables --------
-- Two variants: one for the uuid-keyed tables (user_id = auth.uid()),
-- one for the seq_id-keyed tables (userid = users.seq_id).

create or replace function public.enforce_owner_or_admin_soft_delete_uuid()
returns trigger
language plpgsql
as $$
begin
  if coalesce(new.is_deleted, 0) = 1 and coalesce(old.is_deleted, 0) <> 1 then
    if not (
      auth.uid() = old.user_id
      or exists (
        select 1 from public.users u
        where u.id = auth.uid() and u.access_level in (1, 2)
      )
    ) then
      raise exception 'Only the record creator or an admin can delete this record.';
    end if;
  end if;
  return new;
end;
$$;

create or replace function public.enforce_owner_or_admin_soft_delete_seqid()
returns trigger
language plpgsql
as $$
begin
  if coalesce(new.is_deleted, 0) = 1 and coalesce(old.is_deleted, 0) <> 1 then
    if not (
      old.userid = (select seq_id from public.users where id = auth.uid())
      or exists (
        select 1 from public.users u
        where u.id = auth.uid() and u.access_level in (1, 2)
      )
    ) then
      raise exception 'Only the record creator or an admin can delete this record.';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_owner_or_admin_delete on public.tree_growing;
create trigger enforce_owner_or_admin_delete
before update on public.tree_growing
for each row
execute function public.enforce_owner_or_admin_soft_delete_uuid();

drop trigger if exists enforce_owner_or_admin_delete on public.tree_survival_monitoring;
create trigger enforce_owner_or_admin_delete
before update on public.tree_survival_monitoring
for each row
execute function public.enforce_owner_or_admin_soft_delete_uuid();

drop trigger if exists enforce_owner_or_admin_delete on public.flora_fauna_survey;
create trigger enforce_owner_or_admin_delete
before update on public.flora_fauna_survey
for each row
execute function public.enforce_owner_or_admin_soft_delete_uuid();

drop trigger if exists enforce_owner_or_admin_delete on public.crm_habitat_assssment;
create trigger enforce_owner_or_admin_delete
before update on public.crm_habitat_assssment
for each row
execute function public.enforce_owner_or_admin_soft_delete_seqid();

drop trigger if exists enforce_owner_or_admin_delete on public.crm_marine_protected;
create trigger enforce_owner_or_admin_delete
before update on public.crm_marine_protected
for each row
execute function public.enforce_owner_or_admin_soft_delete_seqid();

-- ---- Verify afterward -------------------------------------------------
select tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public'
  and tablename in (
    'tree_growing',
    'tree_survival_monitoring',
    'crm_habitat_assssment',
    'crm_marine_protected',
    'seed_donation',
    'flora_fauna_survey',
    'seedling_transaction'
  )
  and cmd = 'DELETE'
order by tablename;

select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name = 'enforce_owner_or_admin_delete'
order by event_object_table;
