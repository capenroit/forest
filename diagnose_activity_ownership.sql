-- ============================================================
-- Diagnostic: for every "data entry" activity table, check whether
-- it already tracks the creating user (a user_id column) and what
-- DELETE policies currently exist, before adding an
-- "owner OR access_level 1/2" delete rule everywhere.
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
-- ============================================================

-- 1) Does each activity table have a user_id column, and what type?
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'tree_growing',
    'tree_survival_monitoring',
    'crm_habitat_assssment',
    'crm_marine_protected',
    'seed_donation',
    'flora_fauna_survey',
    'seedling_transaction'
  )
  and column_name in ('user_id', 'id')
order by table_name, column_name;

-- 2) Current DELETE (and other) policies on each of those tables.
select tablename, policyname, cmd, roles, qual, with_check
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
order by tablename, cmd;

-- 3) Sample rows to see if user_id is actually populated where the
--    column exists (a column can exist but be NULL on every row if
--    the app never wrote to it).
select 'tree_growing' as table_name, count(*) as total_rows,
       count(*) filter (where user_id is not null) as rows_with_user_id
from public.tree_growing
union all
select 'tree_survival_monitoring', count(*), count(*) filter (where user_id is not null)
from public.tree_survival_monitoring
union all
select 'seed_donation', count(*), count(*) filter (where user_id is not null)
from public.seed_donation;
