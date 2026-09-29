-- 002: курсы, экземпляры курсов, файлы, задания, сдачи, оценки, аудит

create table public.courses (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  department_id uuid,
  code          text,
  title         text not null,
  description   text,
  credits       numeric(4,1) check (credits >= 0),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,
  unique (id, university_id),
  unique (university_id, code),
  foreign key (department_id, university_id) references public.departments (id, university_id)
);

create table public.course_offerings (
  id             uuid primary key default gen_random_uuid(),
  university_id  uuid not null references public.universities(id) on delete cascade,
  course_id      uuid not null,
  term_id        uuid not null,
  title_override text,
  status         text not null default 'draft' check (status in ('draft', 'active', 'archived')),
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  unique (id, university_id),
  foreign key (course_id, university_id) references public.courses (id, university_id),
  foreign key (term_id, university_id) references public.terms (id, university_id)
);
create index course_offerings_course_idx on public.course_offerings (course_id);

create table public.offering_groups (
  offering_id   uuid not null,
  group_id      uuid not null,
  university_id uuid not null references public.universities(id) on delete cascade,
  primary key (offering_id, group_id),
  foreign key (offering_id, university_id) references public.course_offerings (id, university_id) on delete cascade,
  foreign key (group_id, university_id) references public.groups (id, university_id) on delete cascade
);
create index offering_groups_group_idx on public.offering_groups (group_id);

create table public.offering_staff (
  offering_id   uuid not null,
  user_id       uuid not null,
  university_id uuid not null references public.universities(id) on delete cascade,
  staff_role    text not null check (staff_role in ('lecturer', 'seminar', 'assistant')),
  primary key (offering_id, user_id),
  foreign key (offering_id, university_id) references public.course_offerings (id, university_id) on delete cascade,
  foreign key (user_id, university_id) references public.profiles (user_id, university_id) on delete cascade
);
create index offering_staff_user_idx on public.offering_staff (user_id);

create table public.files (
  id             uuid primary key default gen_random_uuid(),
  university_id  uuid not null references public.universities(id) on delete cascade,
  owner_id       uuid not null,
  purpose        text not null default 'other' check (purpose in ('material', 'submission', 'avatar', 'other')),
  offering_id    uuid,
  bucket         text not null,
  storage_path   text not null,
  original_name  text not null,
  mime           text,
  size_bytes     bigint not null check (size_bytes >= 0),
  sha256         text,
  scan_status    text not null default 'pending' check (scan_status in ('pending', 'clean', 'infected')),
  preview_status text not null default 'none' check (preview_status in ('none', 'pending', 'ready', 'failed')),
  page_count     integer,
  created_at     timestamptz not null default now(),
  deleted_at     timestamptz,
  unique (id, university_id),
  unique (bucket, storage_path),
  check (purpose <> 'material' or offering_id is not null),
  foreign key (owner_id, university_id) references public.profiles (user_id, university_id),
  foreign key (offering_id, university_id) references public.course_offerings (id, university_id)
);
create index files_owner_idx on public.files (owner_id);
create index files_offering_idx on public.files (offering_id) where offering_id is not null;
create index files_sha_idx on public.files (university_id, sha256);

create table public.file_previews (
  file_id    uuid not null references public.files(id) on delete cascade,
  page_no    integer not null,
  image_path text not null,
  primary key (file_id, page_no)
);

create table public.assignments (
  id              uuid primary key default gen_random_uuid(),
  university_id   uuid not null references public.universities(id) on delete cascade,
  offering_id     uuid not null,
  title           text not null,
  description     text,
  due_at          timestamptz,
  max_score       numeric(6,2) not null default 100 check (max_score > 0),
  allow_late      boolean not null default false,
  late_penalty    numeric(5,2) not null default 0 check (late_penalty between 0 and 100),
  submission_type text not null default 'both' check (submission_type in ('file', 'text', 'both')),
  status          text not null default 'draft' check (status in ('draft', 'published')),
  published_at    timestamptz,
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  deleted_at      timestamptz,
  unique (id, university_id),
  foreign key (offering_id, university_id) references public.course_offerings (id, university_id)
);
create index assignments_offering_idx on public.assignments (offering_id, due_at);

create table public.submissions (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  assignment_id uuid not null,
  student_id    uuid not null,
  text_answer   text,
  submitted_at  timestamptz,
  is_late       boolean not null default false,
  status        text not null default 'draft' check (status in ('draft', 'submitted', 'returned', 'graded')),
  attempt_no    integer not null default 1 check (attempt_no >= 1),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (id, university_id),
  unique (assignment_id, student_id, attempt_no),
  foreign key (assignment_id, university_id) references public.assignments (id, university_id),
  foreign key (student_id, university_id) references public.profiles (user_id, university_id)
);
create index submissions_student_idx on public.submissions (student_id);

create table public.submission_files (
  submission_id uuid not null,
  file_id       uuid not null,
  university_id uuid not null references public.universities(id) on delete cascade,
  primary key (submission_id, file_id),
  foreign key (submission_id, university_id) references public.submissions (id, university_id) on delete cascade,
  foreign key (file_id, university_id) references public.files (id, university_id)
);

create table public.grades (
  id            uuid primary key default gen_random_uuid(),
  university_id uuid not null references public.universities(id) on delete cascade,
  submission_id uuid not null unique,
  graded_by     uuid not null,
  score         numeric(6,2) not null check (score >= 0),
  feedback      text,
  released_at   timestamptz,
  version       integer not null default 1,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  foreign key (submission_id, university_id) references public.submissions (id, university_id),
  foreign key (graded_by, university_id) references public.profiles (user_id, university_id)
);

create table public.audit_log (
  id            bigint generated always as identity primary key,
  university_id uuid,
  actor_id      uuid,
  action        text not null,
  entity_type   text not null,
  entity_id     text,
  diff          jsonb,
  ip            text,
  user_agent    text,
  at            timestamptz not null default now()
);
create index audit_log_university_idx on public.audit_log (university_id, at desc);
