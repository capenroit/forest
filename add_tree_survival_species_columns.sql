-- ============================================================
-- Add seed_name / planted_count directly to tree_survival_monitoring
-- so species name and planted count no longer depend on seed_id
-- staying valid against tree_growing_data (which gets rebuilt with
-- fresh row ids every time an activity's seedling list is edited,
-- orphaning old seed_id references and breaking the Report page's
-- join).
--
-- Existing rows are left NULL here — there's no way to recover their
-- original species/count now that the tree_growing_data rows they
-- pointed to are gone. New saves from the monitoring form will
-- populate both columns going forward.
-- ============================================================

alter table public.tree_survival_monitoring
  add column if not exists seed_name text,
  add column if not exists planted_count integer;
