-- ============================================================
-- Fix: signup_screen.dart's Division selection never saves.
--
-- handle_new_user() (fires AFTER INSERT on auth.users) never set
-- division_type_id — it was always left NULL, relying entirely on a
-- follow-up client-side UPDATE from signup_screen.dart right after
-- signUp(). That UPDATE requires an active session for
-- auth.uid() = id to pass under the "Users can update their own
-- record" RLS policy. Now that email confirmation is enabled,
-- signUp() no longer grants a session until the user clicks the
-- confirmation link, so that UPDATE silently matches 0 rows (no
-- error thrown) and division_type_id is never set.
--
-- Fix: read division_type_id out of the signup metadata
-- (raw_user_meta_data) directly in the trigger, which runs as
-- SECURITY DEFINER regardless of session state — no client-side
-- follow-up call needed at all. signup_screen.dart is updated
-- separately to send division_type_id in signUp()'s `data:` map
-- instead of via a follow-up update() call.
-- ============================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  INSERT INTO public.users (
    id,
    email,
    name,
    access_level,
    division_type_id,
    created_at,
    updated_at
  )
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
    3,
    (NEW.raw_user_meta_data->>'division_type_id')::integer,
    NOW(),
    NOW()
  );
  RETURN NEW;
EXCEPTION WHEN UNIQUE_VIOLATION THEN
  RETURN NEW;
END;
$function$;

-- Verify afterward
select pg_get_functiondef(oid)
from pg_proc
where proname = 'handle_new_user'
  and pronamespace = 'public'::regnamespace;
