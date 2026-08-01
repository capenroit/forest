-- ============================================================
-- Direct, session-independent way to set division_type_id right
-- after signup — a callable RPC function instead of relying on the
-- handle_new_user() trigger picking it up from signup metadata
-- (which isn't taking effect, for reasons not yet pinned down).
--
-- SECURITY DEFINER means this runs with the function owner's
-- privileges, bypassing RLS entirely — it works whether or not the
-- caller has an active session yet (i.e. before email confirmation).
--
-- Scoped narrowly for safety: it only ever sets division_type_id
-- when the target row's division_type_id is currently NULL, so it
-- can only be used to fill in a brand-new signup's division once —
-- it can't be used to overwrite an already-configured account's
-- division.
-- ============================================================

create or replace function public.set_signup_division_type(
  target_user_id uuid,
  division_id integer
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  update public.users
  set division_type_id = division_id,
      updated_at = now()
  where id = target_user_id
    and division_type_id is null;
end;
$$;

grant execute on function public.set_signup_division_type(uuid, integer)
  to anon, authenticated;

-- Verify afterward
select proname, prosecdef, proacl
from pg_proc
where proname = 'set_signup_division_type'
  and pronamespace = 'public'::regnamespace;
