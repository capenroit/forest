-- ============================================================
-- Add a "userid" (bigint, referencing public.users.seq_id) column
-- to the four tables that currently only track the creator via
-- "user_id" (uuid, referencing auth.uid()) — matching the convention
-- already used by crm_habitat_assssment, crm_marine_protected, and
-- seedling_transaction.
--
-- This is additive: the existing uuid user_id column on each table
-- stays exactly as-is (the RLS delete policies and trigger added
-- earlier still key off it) — userid is a second, seq_id-based
-- tracking column populated going forward by the app for display/
-- consistency with the other tables' convention. Existing rows are
-- left NULL; there's no reliable way to backfill seq_id purely from
-- the uuid without matching against users.id at this point (and even
-- then, only for rows whose user_id is itself non-null).
-- ============================================================

alter table public.tree_growing add column if not exists userid bigint;
alter table public.flora_fauna_survey add column if not exists userid bigint;
alter table public.seed_donation add column if not exists userid bigint;
alter table public.tree_survival_monitoring add column if not exists userid bigint;

-- Best-effort backfill for existing rows whose uuid user_id still
-- matches a current users.id row.
update public.tree_growing t
set userid = u.seq_id
from public.users u
where t.user_id = u.id
  and t.userid is null;

update public.flora_fauna_survey t
set userid = u.seq_id
from public.users u
where t.user_id = u.id
  and t.userid is null;

update public.seed_donation t
set userid = u.seq_id
from public.users u
where t.user_id = u.id
  and t.userid is null;

update public.tree_survival_monitoring t
set userid = u.seq_id
from public.users u
where t.user_id = u.id
  and t.userid is null;

-- Verify afterward
select 'tree_growing' as table_name, count(*) total_rows,
       count(*) filter (where userid is not null) as rows_with_userid
from public.tree_growing
union all
select 'flora_fauna_survey', count(*), count(*) filter (where userid is not null)
from public.flora_fauna_survey
union all
select 'seed_donation', count(*), count(*) filter (where userid is not null)
from public.seed_donation
union all
select 'tree_survival_monitoring', count(*), count(*) filter (where userid is not null)
from public.tree_survival_monitoring;
