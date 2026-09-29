-- 005: MFA (aal2) для привилегированных ролей + права на схему app.
-- Если app.settings.require_mfa = 'true', роли platform_admin / uni_admin /
-- teacher и доступ через offering_staff работают только при aal2 в JWT.

create or replace function app.mfa_ok()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce((select value from app.settings where key = 'require_mfa'), 'true') <> 'true'
      or coalesce(auth.jwt() ->> 'aal', 'aal1') = 'aal2'
$$;

create or replace function app.has_role(p_role public.app_role, p_scope_type public.scope_type, p_scope_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid()
      and m.role = p_role
      and m.scope_type = p_scope_type
      and (p_scope_id is null or m.scope_id = p_scope_id)
      and m.status = 'active'
      and (m.expires_at is null or m.expires_at > now())
  )
  and (p_role not in ('platform_admin', 'uni_admin', 'teacher') or app.mfa_ok())
$$;

create or replace function app.teaches_group(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select app.mfa_ok() and exists (
    select 1
    from public.offering_groups og
    join public.offering_staff os on os.offering_id = og.offering_id
    where og.group_id = p_group_id and os.user_id = auth.uid()
  )
$$;

create or replace function app.staff_of_offering(p_offering_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select app.mfa_ok() and exists (
    select 1 from public.offering_staff os
    where os.offering_id = p_offering_id and os.user_id = auth.uid()
  )
$$;

-- Без этого политики RLS не смогут вызывать функции из схемы app.
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
