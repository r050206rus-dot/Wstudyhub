-- pgTAP-тесты RLS. Запуск: supabase test db
-- Один файл = одна транзакция = один цельный сценарий с двумя вузами,
-- чтобы в первую очередь проверить межвузовую изоляцию (самая частая
-- дыра в RLS — не сама политика, а её отсутствие на "втором" вузе).

begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- ============================== Фикстуры ==============================
-- Выполняются от имени владельца таблиц (postgres), RLS не мешает.

insert into public.universities (id, name, slug) values
  ('a0000000-0000-0000-0000-00000000000a', 'Uni A', 'uni-a'),
  ('b0000000-0000-0000-0000-00000000000b', 'Uni B', 'uni-b');

insert into public.programs (id, university_id, name) values
  ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-00000000000a', 'Finance A'),
  ('b0000000-0000-0000-0000-0000000000f1', 'b0000000-0000-0000-0000-00000000000b', 'Program B');

insert into public.terms (id, university_id, name, starts_on, ends_on, is_current) values
  ('a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-00000000000a', 'Fall', '2026-09-01', '2026-12-31', true);

insert into public.groups (id, university_id, program_id, name) values
  ('a0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000f1', 'IF-1-26'),
  ('b0000000-0000-0000-0000-0000000000b1', 'b0000000-0000-0000-0000-00000000000b', 'b0000000-0000-0000-0000-0000000000f1', 'B-Group');

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-000000000501', 'student.a@test.local'),
  ('b0000000-0000-0000-0000-000000000501', 'student.b@test.local'),
  ('a0000000-0000-0000-0000-000000007e01', 'teacher.a@test.local'),
  ('a0000000-0000-0000-0000-00000000ad01', 'admin.a@test.local')
on conflict do nothing;

insert into public.profiles (user_id, university_id, full_name, status) values
  ('a0000000-0000-0000-0000-000000000501', 'a0000000-0000-0000-0000-00000000000a', 'Student A', 'active'),
  ('b0000000-0000-0000-0000-000000000501', 'b0000000-0000-0000-0000-00000000000b', 'Student B', 'active'),
  ('a0000000-0000-0000-0000-000000007e01', 'a0000000-0000-0000-0000-00000000000a', 'Teacher A', 'active'),
  ('a0000000-0000-0000-0000-00000000ad01', 'a0000000-0000-0000-0000-00000000000a', 'Admin A', 'active');

insert into public.memberships (user_id, university_id, role, scope_type, scope_id, status) values
  ('a0000000-0000-0000-0000-000000000501', 'a0000000-0000-0000-0000-00000000000a', 'student', 'group', 'a0000000-0000-0000-0000-0000000000b1', 'active'),
  ('b0000000-0000-0000-0000-000000000501', 'b0000000-0000-0000-0000-00000000000b', 'student', 'group', 'b0000000-0000-0000-0000-0000000000b1', 'active'),
  ('a0000000-0000-0000-0000-00000000ad01', 'a0000000-0000-0000-0000-00000000000a', 'uni_admin', 'university', 'a0000000-0000-0000-0000-00000000000a', 'active');

insert into public.terms (id, university_id, name, starts_on, ends_on, is_current) values
  ('b0000000-0000-0000-0000-0000000000e1', 'b0000000-0000-0000-0000-00000000000b', 'Fall', '2026-09-01', '2026-12-31', true);

insert into public.courses (id, university_id, title) values
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-00000000000a', 'Macro'),
  ('b0000000-0000-0000-0000-0000000000c1', 'b0000000-0000-0000-0000-00000000000b', 'Macro B');

insert into public.course_offerings (id, university_id, course_id, term_id, status) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-0000000000e1', 'active'),
  ('b0000000-0000-0000-0000-0000000000a1', 'b0000000-0000-0000-0000-00000000000b', 'b0000000-0000-0000-0000-0000000000c1', 'b0000000-0000-0000-0000-0000000000e1', 'active');

insert into public.offering_groups (offering_id, group_id, university_id) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-0000000000b1', 'a0000000-0000-0000-0000-00000000000a');

insert into public.offering_staff (offering_id, user_id, university_id, staff_role) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-000000007e01', 'a0000000-0000-0000-0000-00000000000a', 'lecturer');

insert into public.assignments (id, university_id, offering_id, title, status) values
  ('a0000000-0000-0000-0000-0000000000d1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'Published HW', 'published'),
  ('a0000000-0000-0000-0000-0000000000d2', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'Draft HW', 'draft');

insert into public.submissions (id, university_id, assignment_id, student_id, status) values
  ('a0000000-0000-0000-0000-000000000051', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000d1', 'a0000000-0000-0000-0000-000000000501', 'submitted');

insert into public.grades (id, university_id, submission_id, graded_by, score, released_at) values
  ('a0000000-0000-0000-0000-0000000000f2', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-000000000051', 'a0000000-0000-0000-0000-000000007e01', 85, null);

-- ============================== Хелпер входа ==============================
-- aal2 — как будто пользователь уже прошёл второй фактор. Без него
-- has_role/staff_of_offering теперь отказывают teacher/uni_admin (005).
create or replace function pg_temp.login(p_user_id uuid, p_aal text default 'aal1') returns void as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user_id, 'role', 'authenticated', 'aal', p_aal)::text, true);
end;
$$ language plpgsql;

set local role authenticated;

-- ============================== Student A ==============================
select pg_temp.login('a0000000-0000-0000-0000-000000000501');

select is(
  (select count(*)::int from public.profiles),
  1, 'student видит только свой профиль');

select is(
  (select count(*)::int from public.groups),
  1, 'student видит только свою группу (не Uni B)');

select is(
  (select array_agg(title) from public.assignments),
  array['Published HW'], 'student видит только опубликованное задание');

select is(
  (select count(*)::int from public.submissions),
  1, 'student видит ровно свою сдачу');

select is(
  (select count(*)::int from public.grades),
  0, 'student не видит оценку до released_at');

select is(
  (select count(*)::int from public.universities),
  1, 'student не видит чужой университет (Uni B)');

select is(
  (select count(*)::int from public.course_offerings),
  1, 'student видит только offering своего вуза, не Uni B');

-- RLS не бросает исключение на недоступную строку — она просто не
-- попадает под UPDATE (0 затронутых строк). Проверяем это через
-- реальное состояние строки, а не через ошибку.
update public.grades set score = 100 where id = 'a0000000-0000-0000-0000-0000000000f2';
reset role;
select is(
  (select score from public.grades where id = 'a0000000-0000-0000-0000-0000000000f2'),
  85::numeric, 'попытка student изменить оценку не прошла (RLS)');
set local role authenticated;
select pg_temp.login('a0000000-0000-0000-0000-000000000501');

-- ============================== Student B (другой вуз) ==============================
select pg_temp.login('b0000000-0000-0000-0000-000000000501');

select is(
  (select count(*)::int from public.submissions),
  0, 'student B не видит сдачу student A');

select is(
  (select count(*)::int from public.assignments),
  0, 'student B не видит задания Uni A вообще');

-- ============================== Teacher A ==============================
-- Сначала без второго фактора — доступ по роли teacher должен быть закрыт (005).
select pg_temp.login('a0000000-0000-0000-0000-000000007e01', 'aal1');

select is(
  (select count(*)::int from public.assignments where offering_id = 'a0000000-0000-0000-0000-0000000000a1'),
  0, 'teacher без aal2 не получает доступ преподавателя (MFA)');

-- Теперь с пройденным вторым фактором.
select pg_temp.login('a0000000-0000-0000-0000-000000007e01', 'aal2');

select is(
  (select count(*)::int from public.assignments where offering_id = 'a0000000-0000-0000-0000-0000000000a1'),
  2, 'teacher с aal2 видит и черновик, и опубликованное задание своего offering');

select is(
  (select count(*)::int from public.submissions),
  1, 'teacher с aal2 видит сдачи по своему offering');

reset role;
update public.grades set released_at = now()
  where id = 'a0000000-0000-0000-0000-0000000000f2';
set local role authenticated;

select pg_temp.login('a0000000-0000-0000-0000-000000000501');
select is(
  (select count(*)::int from public.grades),
  1, 'student видит оценку после released_at');

-- ============================== Uni admin A ==============================
select pg_temp.login('a0000000-0000-0000-0000-00000000ad01', 'aal1');

select is(
  (select count(*)::int from public.profiles),
  1, 'admin без aal2 видит только свой профиль, не весь вуз (MFA)');

select pg_temp.login('a0000000-0000-0000-0000-00000000ad01', 'aal2');

select is(
  (select count(*)::int from public.profiles),
  3, 'admin с aal2 видит все профили своего вуза (студент+преподаватель+он сам)');

select is(
  (select count(*)::int from public.universities),
  1, 'uni_admin A не видит Uni B');

select * from finish();
rollback;
