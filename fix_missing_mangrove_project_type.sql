-- ============================================================
-- Fix: the app hardcodes project_type_id = 6 for Mangrove Planting
-- everywhere (mangrove_planting_form.dart, offline_sync_service.dart,
-- mangrove_planting_activity_page.dart), but no row for id=6 exists
-- in project_type. Existing ids are 1,2,3,4,5,7,8,9 -- 6 is a gap.
--
-- This is why every Mangrove Planting save fails with "Unable to
-- save data.": the insert into tree_growing with project_type_id=6
-- has nothing to reference, regardless of which user/session is
-- signed in. (Confirmed: 0 existing tree_growing rows have
-- project_type_id = 6.)
--
-- dashboard_filter = false to match the pattern of other standalone
-- activity-list features (Seed for a Forest, Seedling Inventory,
-- Seedling Request, Monitoring Tree Survival) -- Mangrove Planting
-- has its own dedicated list page and isn't meant to show up in
-- either dashboard's project-type filter chips.
-- ============================================================

insert into public.project_type (id, projectname, dashboard_filter)
values (6, 'Mangrove Planting', false);

-- Verify:
select id, projectname, dashboard_filter
from public.project_type
order by id;
