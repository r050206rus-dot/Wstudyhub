-- 003: вспомогательные функции для RLS.
-- security definer + search_path зафиксирован: иначе функцию можно
-- обмануть, подменив search_path в своей же сессии.

create or replace function app.current_university_id()
returns uuid
language sql stable security definer set search_path = public, pg_temp
as $$
  select university_id from public.profiles where user_id = auth.uid()
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
$$;

create or replace function app.is_uni_admin(p_university_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select app.has_role('uni_admin', 'university', p_university_id)
      or app.has_role('platform_admin', 'platform', null)
$$;

create or replace function app.is_platform_admin()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select app.has_role('platform_admin', 'platform', null)
$$;

-- Учит ли пользователь эту группу (teacher/assistant через offering_groups)
create or replace function app.teaches_group(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.offering_groups og
    join public.offering_staff os on os.offering_id = og.offering_id
    where og.group_id = p_group_id and os.user_id = auth.uid()
  )
$$;

create or replace function app.member_of_group(p_group_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid() and m.scope_type = 'group' and m.scope_id = p_group_id
      and m.status = 'active' and (m.expires_at is null or m.expires_at > now())
  )
$$;

create or replace function app.staff_of_offering(p_offering_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.offering_staff os
    where os.offering_id = p_offering_id and os.user_id = auth.uid()
  )
$$;

-- Учится ли пользователь на этом offering (через свою группу)
create or replace function app.enrolled_in_offering(p_offering_id uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.offering_groups og
    where og.offering_id = p_offering_id and app.member_of_group(og.group_id)
  )
$$;
