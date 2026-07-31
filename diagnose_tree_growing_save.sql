-- ============================================================
-- Diagnostic: "Unable to save data." on Tree Growing Data Entry
-- (both new and edited records fail).
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
--
-- The app always sends project_type_id = 1 and, on edit, updates
-- an existing row by its `id`. This checks the two known causes
-- that have already broken saves for other forms in this app:
--   1) A referenced project_type row missing (broke Mangrove
--      Planting's inserts the same way, see
--      fix_missing_mangrove_project_type.sql).
--   2) RLS enabled with no INSERT/UPDATE policy for `authenticated`
--      (broke public.users updates the same way, see
--      fix_users_update_policy.sql).
-- Also checks for NOT NULL columns the app's insert payload
-- doesn't populate, which would raise a distinct error.
-- ============================================================

-- 1) Does project_type id = 1 exist? (Tree Growing form hardcodes
--    project_type_id: 1 in every save.)
select id, projectname, dashboard_filter
from public.project_type
order by id;

-- 2) Is RLS enabled on tree_growing / tree_growing_data, and what
--    policies exist for INSERT/UPDATE? If RLS is on with no policy
--    covering INSERT or UPDATE for role "authenticated", every save
--    from the app will fail (or silently update 0 rows, which then
--    throws "JSON object requested, no rows returned" from
--    `.select().single()`).
select relname, relrowsecurity, relforcerowsecurity
from pg_class
where relname in ('tree_growing', 'tree_growing_data')
  and relnamespace = 'public'::regnamespace;

select tablename, policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('tree_growing', 'tree_growing_data')
order by tablename, cmd;

-- 3) Columns on tree_growing that are NOT NULL and have no default
--    -- if any exist here that aren't in the list below, the app's
--    insert (which only sends user_id, project_type_id, activity_name,
--    barangay, municipality, details, tree_species, number_of_trees,
--    area_cover, perimeter, planting_date, updated_at) would fail
--    with a "null value in column ... violates not-null constraint".
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'tree_growing'
order by ordinal_position;

-- 4) Same NOT NULL/default check for tree_growing_data (the per-seed
--    rows table), since a failed insert there after tree_growing
--    succeeds would surface as the same generic error.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name = 'tree_growing_data'
order by ordinal_position;

-- 5) Foreign keys on tree_growing (e.g. project_type_id, user_id) --
--    confirms what tree_growing.project_type_id actually references
--    and whether user_id must match an existing auth.users/public.users row.
select
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name  as references_table,
  ccu.column_name as references_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu
  on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu
  on tc.constraint_name = ccu.constraint_name
where tc.table_schema = 'public'
  and tc.table_name = 'tree_growing'
  and tc.constraint_type = 'FOREIGN KEY';
