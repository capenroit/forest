-- ============================================================
-- Diagnostic: Report page shows "no data" for Monitoring Tree
-- Survival / Monitoring of Mangrove Survival, even though the
-- recent-activity list page shows entries fine.
--
-- Read-only. Safe to run as-is in the Supabase SQL Editor.
--
-- Theory: tree_survival_monitoring.seed_id is supposed to equal
-- a live tree_growing_data.id. But editing a Tree Growing /
-- Mangrove Planting activity's seedling list (replaceTreeGrowingDataRows)
-- deletes and re-inserts all of that activity's tree_growing_data
-- rows with fresh ids -- orphaning any tree_survival_monitoring.seed_id
-- that was saved before the edit. The recent-activity list page
-- doesn't need this join to display cards, so it still works; the
-- Report page's join does need it, so those rows silently vanish.
-- ============================================================

-- 1) How many tree_survival_monitoring rows have a seed_id that no
--    longer matches any tree_growing_data.id? If this is > 0 (and
--    close to the total row count), that confirms the theory.
select
  count(*) as total_rows,
  count(*) filter (
    where not exists (
      select 1 from public.tree_growing_data tgd
      where tgd.id = tsm.seed_id
    )
  ) as orphaned_seed_id_rows
from public.tree_survival_monitoring tsm;

-- 2) Sample of the orphaned rows, with their activity, so we can see
--    which Tree Growing/Mangrove Planting record's seedling list was
--    edited after the monitoring entry was saved.
select tsm.id, tsm.activity_id, tsm.seed_id, tsm.quarter, tsm.date,
       tg.activity_name, tg.project_type_id
from public.tree_survival_monitoring tsm
left join public.tree_growing tg on tg.seq_id = tsm.activity_id
where not exists (
  select 1 from public.tree_growing_data tgd
  where tgd.id = tsm.seed_id
)
order by tsm.date desc
limit 20;
