-- ============================================================
-- Adds the missing project_type row for Monitoring of Mangrove
-- Survival, so it shows up as a selectable Project Type in the
-- Reports page. Mirrors how Mangrove Planting (id=6) was added
-- earlier -- ids 1-9 are already taken, so this uses 10.
-- ============================================================

insert into public.project_type (id, projectname, dashboard_filter)
values (10, 'Monitoring of Mangrove Survival', false);

-- Verify:
select id, projectname, dashboard_filter
from public.project_type
order by id;
