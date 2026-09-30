-- pgTAP: целостность сдач/оценок и вывод university_id триггерами (миграция 012).
-- Запуск: supabase test db. Требует миграций до 012 включительно.

begin;
create extension if not exists pgtap with schema extensions;
select plan(25);

-- ============================== Фикстуры ==============================
insert into public.universities (id, name, slug) values
  ('a0000000-0000-0000-0000-00000000000a', 'Uni A', 'uni-a');

insert into public.programs (id, university_id, name) values
  ('a0000000-0000-0000-0000-0000000000f1', 'a0000000-0000-0000-0000-00000000000a', 'Program A');

insert into public.terms (id, university_id, name, starts_on, ends_on, is_current) values
  ('a0000000-0000-0000-0000-0000000000e1', 'a0000000-0000-0000-0000-00000000000a', 'Fall', '2026-09-01', '2026-12-31', true);

insert into public.groups (id, university_id, program_id, name) values
  ('a0000000-0000-0000-0000-0000000009a1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000f1', 'GA1'),
  ('a0000000-0000-0000-0000-0000000009a2', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000f1', 'GA2');

insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-0000000005a1', 'student.a1@test.local'),
  ('a0000000-0000-0000-0000-0000000005a2', 'student.a2@test.local'),
  ('a0000000-0000-0000-0000-00000000007e', 'teacher.a@test.local'),
  ('a0000000-0000-0000-0000-0000000001d1', 'leader.a@test.local')
on conflict do nothing;

insert into public.profiles (user_id, university_id, full_name, status) values
  ('a0000000-0000-0000-0000-0000000005a1', 'a0000000-0000-0000-0000-00000000000a', 'Student A1', 'active'),
  ('a0000000-0000-0000-0000-0000000005a2', 'a0000000-0000-0000-0000-00000000000a', 'Student A2', 'active'),
  ('a0000000-0000-0000-0000-00000000007e', 'a0000000-0000-0000-0000-00000000000a', 'Teacher A', 'active'),
  ('a0000000-0000-0000-0000-0000000001d1', 'a0000000-0000-0000-0000-00000000000a', 'Leader A', 'active');

insert into public.memberships (user_id, university_id, role, scope_type, scope_id, status) values
  ('a0000000-0000-0000-0000-0000000005a1', 'a0000000-0000-0000-0000-00000000000a', 'student', 'group', 'a0000000-0000-0000-0000-0000000009a1', 'active'),
  ('a0000000-0000-0000-0000-0000000005a2', 'a0000000-0000-0000-0000-00000000000a', 'student', 'group', 'a0000000-0000-0000-0000-0000000009a2', 'active'),
  ('a0000000-0000-0000-0000-0000000001d1', 'a0000000-0000-0000-0000-00000000000a', 'group_leader', 'group', 'a0000000-0000-0000-0000-0000000009a1', 'active');

insert into public.courses (id, university_id, title) values
  ('a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-00000000000a', 'Course A1'),
  ('a0000000-0000-0000-0000-0000000000c2', 'a0000000-0000-0000-0000-00000000000a', 'Course A2');

insert into public.course_offerings (id, university_id, course_id, term_id, status) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000c1', 'a0000000-0000-0000-0000-0000000000e1', 'active'),
  ('a0000000-0000-0000-0000-0000000000a2', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000c2', 'a0000000-0000-0000-0000-0000000000e1', 'active');

insert into public.offering_groups (offering_id, group_id, university_id) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-0000000009a1', 'a0000000-0000-0000-0000-00000000000a'),
  ('a0000000-0000-0000-0000-0000000000a2', 'a0000000-0000-0000-0000-0000000009a2', 'a0000000-0000-0000-0000-00000000000a');

insert into public.offering_staff (offering_id, user_id, university_id, staff_role) values
  ('a0000000-0000-0000-0000-0000000000a1', 'a0000000-0000-0000-0000-00000000007e', 'a0000000-0000-0000-0000-00000000000a', 'lecturer');

-- AS1: срок в будущем. AS2: срок прошёл, allow_late=false. AS3: срок прошёл, allow_late=true.
-- AS4: черновик (не опубликовано). AS5: для удаления черновика. AS6: для оценивания (сдача SUBX).
insert into public.assignments (id, university_id, offering_id, title, status, due_at, allow_late, max_score) values
  ('a0000000-0000-0000-0000-00000000aa01', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS1', 'published', now() + interval '7 days', false, 100),
  ('a0000000-0000-0000-0000-00000000aa02', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS2', 'published', now() - interval '1 day',  false, 100),
  ('a0000000-0000-0000-0000-00000000aa03', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS3', 'published', now() - interval '1 day',  true,  100),
  ('a0000000-0000-0000-0000-00000000aa04', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS4', 'draft',     now() + interval '7 days', false, 100),
  ('a0000000-0000-0000-0000-00000000aa05', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS5', 'published', now() + interval '7 days', false, 100),
  ('a0000000-0000-0000-0000-00000000aa06', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-0000000000a1', 'AS6', 'published', now() + interval '7 days', false, 100);

insert into public.submissions (id, university_id, assignment_id, student_id, text_answer, status, submitted_at) values
  ('a0000000-0000-0000-0000-00000000dd01', 'a0000000-0000-0000-0000-00000000000a', 'a0000000-0000-0000-0000-00000000aa06', 'a0000000-0000-0000-0000-0000000005a1', 'answer', 'submitted', now());

set local role authenticated;

-- ============================== Student A1 ==============================
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000005a1","role":"authenticated","aal":"aal1"}', true); end $$;

select lives_ok(
  $$insert into public.submissions (assignment_id, student_id, text_answer) values ('a0000000-0000-0000-0000-00000000aa01', 'a0000000-0000-0000-0000-0000000005a1', 'draft text')$$,
  'student создаёт черновик без university_id (выводится триггером)');

select throws_ok(
  $$insert into public.submissions (assignment_id, student_id) values ('a0000000-0000-0000-0000-00000000aa04', 'a0000000-0000-0000-0000-0000000005a1')$$,
  'P0001', 'assignment is not published', 'нельзя сдавать в неопубликованное задание');

select lives_ok(
  $$insert into public.submissions (assignment_id, student_id) values
      ('a0000000-0000-0000-0000-00000000aa02', 'a0000000-0000-0000-0000-0000000005a1'),
      ('a0000000-0000-0000-0000-00000000aa03', 'a0000000-0000-0000-0000-0000000005a1'),
      ('a0000000-0000-0000-0000-00000000aa05', 'a0000000-0000-0000-0000-0000000005a1')$$,
  'student может создать черновики по заданиям со сроками');

select throws_ok(
  $$update public.submissions set status = 'graded' where assignment_id = 'a0000000-0000-0000-0000-00000000aa01'$$,
  'P0001', 'students can only submit their own work', 'student не может сам поставить себе status=graded');

select lives_ok(
  $$update public.submissions set status = 'submitted', is_late = false, submitted_at = null where assignment_id = 'a0000000-0000-0000-0000-00000000aa01'$$,
  'student сдаёт работу в срок');

reset role;
select is(
  (select submitted_at is not null and is_late = false from public.submissions where assignment_id = 'a0000000-0000-0000-0000-00000000aa01'),
  true, 'submitted_at выставлен сервером, is_late = false');
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000005a1","role":"authenticated","aal":"aal1"}', true); end $$;

select throws_ok(
  $$update public.submissions set text_answer = 'edited after submit' where assignment_id = 'a0000000-0000-0000-0000-00000000aa01'$$,
  'P0001', 'submission is locked', 'после сдачи student не может править ответ');

select throws_ok(
  $$update public.submissions set status = 'submitted' where assignment_id = 'a0000000-0000-0000-0000-00000000aa02'$$,
  'P0001', 'deadline passed', 'просроченная сдача отклоняется при allow_late=false');

select lives_ok(
  $$update public.submissions set status = 'submitted', is_late = false where assignment_id = 'a0000000-0000-0000-0000-00000000aa03'$$,
  'просроченная сдача принимается при allow_late=true');

reset role;
select is(
  (select is_late from public.submissions where assignment_id = 'a0000000-0000-0000-0000-00000000aa03'),
  true, 'is_late вычислен сервером (student не смог подделать false)');
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000005a1","role":"authenticated","aal":"aal1"}', true); end $$;

select throws_ok(
  $$delete from public.submissions where assignment_id = 'a0000000-0000-0000-0000-00000000aa01'$$,
  'P0001', 'only drafts can be deleted', 'сданную работу удалить нельзя');

select lives_ok(
  $$delete from public.submissions where assignment_id = 'a0000000-0000-0000-0000-00000000aa05'$$,
  'черновик удалить можно');

-- ============================== Student A2 (не зачислен на OA1) ==============================
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000005a2","role":"authenticated","aal":"aal1"}', true); end $$;

select throws_ok(
  $$insert into public.submissions (assignment_id, student_id) values ('a0000000-0000-0000-0000-00000000aa01', 'a0000000-0000-0000-0000-0000000005a2')$$,
  'P0001', 'not enrolled in this offering', 'student, не зачисленный на курс, не может сдавать по нему');

-- ============================== Teacher A ==============================
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-00000000007e","role":"authenticated","aal":"aal1"}', true); end $$;

select throws_ok(
  $$insert into public.grades (submission_id, graded_by, score) values ('a0000000-0000-0000-0000-00000000dd01', 'a0000000-0000-0000-0000-00000000007e', 90)$$,
  '42501', null, 'teacher без aal2 не может ставить оценки (MFA)');

do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-00000000007e","role":"authenticated","aal":"aal2"}', true); end $$;

select lives_ok(
  $$insert into public.grades (submission_id, graded_by, score, feedback) values ('a0000000-0000-0000-0000-00000000dd01', 'a0000000-0000-0000-0000-0000000005a1', 90, 'ok')$$,
  'teacher с aal2 ставит оценку без university_id и с чужим graded_by в запросе');

reset role;
select is(
  (select graded_by = 'a0000000-0000-0000-0000-00000000007e'
      and university_id = 'a0000000-0000-0000-0000-00000000000a'
   from public.grades where submission_id = 'a0000000-0000-0000-0000-00000000dd01'),
  true, 'graded_by = преподаватель, university_id выведен из сдачи');
set local role authenticated;
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-00000000007e","role":"authenticated","aal":"aal2"}', true); end $$;

select throws_ok(
  $$update public.grades set score = 101 where submission_id = 'a0000000-0000-0000-0000-00000000dd01'$$,
  'P0001', 'score exceeds max_score', 'оценка не может превышать max_score задания');

select lives_ok(
  $$update public.submissions set status = 'returned' where id = 'a0000000-0000-0000-0000-00000000dd01'$$,
  'teacher возвращает работу на доработку');

select throws_ok(
  $$update public.submissions set text_answer = 'rewritten' where id = 'a0000000-0000-0000-0000-00000000dd01'$$,
  'P0001', 'staff cannot edit student content', 'teacher не может переписать ответ студента');

select throws_ok(
  $$update public.submissions set status = 'draft' where id = 'a0000000-0000-0000-0000-00000000dd01'$$,
  'P0001', 'staff can only return or grade', 'teacher не может вернуть сдачу в draft');

select lives_ok(
  $$insert into public.lectures (offering_id, title) values ('a0000000-0000-0000-0000-0000000000a1', 'Auto lecture')$$,
  'teacher создаёт лекцию без university_id');

select lives_ok(
  $$insert into public.assignments (offering_id, title) values ('a0000000-0000-0000-0000-0000000000a1', 'Auto assignment')$$,
  'teacher создаёт задание без university_id');

select is(
  (select university_id from public.lectures where title = 'Auto lecture'),
  'a0000000-0000-0000-0000-00000000000a'::uuid, 'university_id лекции выведен из offering');

select lives_ok(
  $$insert into public.schedule_items (offering_id, day_of_week, start_time, end_time) values ('a0000000-0000-0000-0000-0000000000a1', 3, '10:00', '11:30')$$,
  'teacher добавляет пару в расписание без university_id');

-- ============================== Староста GA1 ==============================
do $$ begin perform set_config('request.jwt.claims', '{"sub":"a0000000-0000-0000-0000-0000000001d1","role":"authenticated","aal":"aal1"}', true); end $$;

select lives_ok(
  $$insert into public.schedule_items (group_id, title, day_of_week, start_time, end_time) values ('a0000000-0000-0000-0000-0000000009a1', 'Собрание', 3, '12:00', '12:30')$$,
  'староста добавляет событие группы без university_id');

select * from finish();
rollback;
