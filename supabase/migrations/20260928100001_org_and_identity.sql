-- 001: организации, профили, memberships, инвайты
-- Принципы: uuid везде; university_id в каждой таблице; составные FK
-- (id, university_id) не дают связать строки разных университетов.

create schema if not exists app;   -- внутренние функции (не отдаются через API)

create type public.app_role as enum
  ('platform_admin', 'uni_admin', 'teacher', 'assistant', 'group_leader', 'student');
create type public.scope_type as enum ('platform', 'university', 'group', 'offering');
create type public.membership_status as enum ('pending', 'active', 'revoked');
create type public.profile_status as enum ('pending', 'active', 'blocked');

-- Серверные настройки (не видны клиентам). require_mfa=false только для dev.
create table app.settings (
  key   text primary key,
  value text not null
);
insert into app.settings (key, value) values ('require_mfa', 'true');

create table public.universities (
  id         uuid primary key default gen_random_uuid(),
  name       text not null check (length(trim(name)) > 0),
  slug       text not null unique check (slug ~ '^[a-z0-9-]+$'),
  country    text,
  timezone   text not null default 'Asia/Bishkek',
  locale     text not null default 'ru',
  settings   jsonb not null default '{}'::jsonb,
  status     text not null default 'active' check (status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.faculties (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  name          text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, university_id),
  unique (university_id, name)
);

create table public.departments (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  faculty_id    uuid,
  name          text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, university_id),
  foreign key (faculty_id, university_id) references public.faculties (id, university_id)
);

create table public.programs (
  id             uuid primary key default gen_random_uuid(),
  university_id  uuid not null references public.universities(id) on delete cascade,
  faculty_id     uuid,
  name           text not null,
  degree         text,
  duration_years smallint check (duration_years between 1 and 10),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  unique (id, university_id),
  foreign key (faculty_id, university_id) references public.faculties (id, university_id)
);

create table public.terms (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  name          text not null,
  starts_on     date not null,
  ends_on       date not null,
  is_current    boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_on > starts_on),
  unique (id, university_id)
);
create unique index terms_one_current_idx on public.terms (university_id) where is_current;

create table public.groups (
  id              uuid primary key default gen_random_uuid(),
  university_id   uuid not null references public.universities(id) on delete cascade,
  program_id      uuid not null,
  name            text not null,
  admission_year  smallint,
  current_term_id uuid,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (id, university_id),
  unique (university_id, name, admission_year),
  foreign key (program_id, university_id) references public.programs (id, university_id),
  foreign key (current_term_id, university_id) references public.terms (id, university_id)
);

create table public.profiles (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  university_id   uuid not null references public.universities(id),
  full_name       text not null check (length(trim(full_name)) > 0),
  avatar_path     text,
  phone           text,
  locale          text not null default 'ru',
  timezone        text not null default 'Asia/Bishkek',
  status          public.profile_status not null default 'pending',
  onboarding_done boolean not null default false,
  last_seen_at    timestamptz,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, university_id)
);
create index profiles_university_idx on public.profiles (university_id);

create table public.memberships (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null,
  university_id uuid not null,
  role          public.app_role not null,
  scope_type    public.scope_type not null,
  scope_id      uuid,
  status        public.membership_status not null default 'pending',
  granted_by    uuid references auth.users(id) on delete set null,
  granted_at    timestamptz not null default now(),
  expires_at    timestamptz,
  created_at    timestamptz not null default now(),
  foreign key (user_id, university_id)
    references public.profiles (user_id, university_id) on delete cascade,
  constraint membership_role_scope check (
       (role = 'platform_admin' and scope_type = 'platform')
    or (role in ('uni_admin', 'teacher') and scope_type = 'university')
    or (role in ('student', 'group_leader') and scope_type = 'group')
    or (role = 'assistant' and scope_type = 'offering')),
  constraint membership_scope_id check ((scope_type = 'platform') = (scope_id is null)),
  constraint membership_university_scope check (scope_type <> 'university' or scope_id = university_id)
);
create unique index memberships_unique_idx on public.memberships
  (user_id, role, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid));
create index memberships_lookup_idx on public.memberships (user_id, scope_type, scope_id)
  where status = 'active';
create index memberships_university_idx on public.memberships (university_id);

create table public.invitations (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  role          public.app_role not null,
  scope_type    public.scope_type not null,
  scope_id      uuid not null,
  email         text,
  code_hash     text not null unique,
  max_uses      integer not null default 1 check (max_uses between 1 and 500),
  used_count    integer not null default 0,
  expires_at    timestamptz not null,
  revoked_at    timestamptz,
  created_by    uuid references auth.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  check (used_count <= max_uses),
  check (role <> 'platform_admin'),
  check (
       (role in ('uni_admin', 'teacher') and scope_type = 'university')
    or (role in ('student', 'group_leader') and scope_type = 'group')
    or (role = 'assistant' and scope_type = 'offering'))
);
create index invitations_university_idx on public.invitations (university_id);

create table public.teacher_profiles (
  user_id         uuid primary key,
  university_id   uuid not null,
  department_id   uuid,
  position        text,
  academic_degree text,
  verified_at     timestamptz,
  verified_by     uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  foreign key (user_id, university_id)
    references public.profiles (user_id, university_id) on delete cascade,
  foreign key (department_id, university_id)
    references public.departments (id, university_id)
);
