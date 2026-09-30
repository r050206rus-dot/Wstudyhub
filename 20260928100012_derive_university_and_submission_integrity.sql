-- 012: (A) university_id выводится на сервере из родительской строки;
--      (B) целостность сдач и оценок на стороне БД.
--
-- (A) Клиент не передаёт university_id при вставке в lectures,
--     presentations, materials, assignments, schedule_items, submissions,
--     grades, а колонка NOT NULL без DEFAULT — эти операции падали.
--     Триггеры BEFORE INSERT берут значение из родителя (offering/group/
--     assignment/submission) и ПЕРЕЗАПИСЫВАЮТ присланное клиентом, так что
--     расхождение между university_id и родителем невозможно.
--
-- (B) Политика submissions_own (for all) позволяла студенту: выставить
--     себе status='graded', подделать is_late/submitted_at, править текст
--     после сдачи, сдавать в неопубликованное задание и в курс, на который
--     он не зачислен. Теперь это проверяют триггеры. Проверки не применяются,
--     когда auth.uid() is null (service_role, миграции, скрипт переноса).
--     Срок сдачи: при allow_late=false просроченная сдача отклоняется
--     ('deadline passed'), при allow_late=true принимается и помечается is_late.

-- ============================== (A) university_id ==============================

create or replace function app.set_university_from_offering()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  select o.university_id into new.university_id
  from public.course_offerings o where o.id = new.offering_id;
  if new.university_id is null then
    raise exception 'offering not found';
  end if;
  return new;
end;
$$;

create or replace function app.set_university_for_schedule()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if new.offering_id is not null then
    select o.university_id into new.university_id
    from public.course_offerings o where o.id = new.offering_id;
  elsif new.group_id is not null then
    select g.university_id into new.university_id
    from public.groups g where g.id = new.group_id;
  end if;
  if new.university_id is null then
    raise exception 'parent not found';
  end if;
  return new;
end;
$$;

create trigger lectures_set_university      before insert on public.lectures
  for each row execute function app.set_university_from_offering();
create trigger presentations_set_university before insert on public.presentations
  for each row execute function app.set_university_from_offering();
create trigger materials_set_university     before insert on public.materials
  for each row execute function app.set_university_from_offering();
create trigger assignments_set_university   before insert on public.assignments
  for each row execute function app.set_university_from_offering();
create trigger schedule_items_set_university before insert on public.schedule_items
  for each row execute function app.set_university_for_schedule();

-- ============================== (B) submissions ==============================

create or replace function app.submissions_before_insert()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  a public.assignments;
begin
  select * into a from public.assignments
  where id = new.assignment_id and deleted_at is null;
  if a.id is null then
    raise exception 'assignment not found';
  end if;
  new.university_id := a.university_id;

  if auth.uid() is not null then
    if new.student_id is distinct from auth.uid() then
      raise exception 'cannot create a submission for another user';
    end if;
    if a.status <> 'published' then
      raise exception 'assignment is not published';
    end if;
    if not app.enrolled_in_offering(a.offering_id) then
      raise exception 'not enrolled in this offering';
    end if;
    new.status := 'draft';
    new.submitted_at := null;
    new.is_late := false;
  end if;
  return new;
end;
$$;

create or replace function app.submissions_before_update()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  a public.assignments;
begin
  if auth.uid() is null then
    return new;   -- service_role / миграции / скрипты
  end if;

  if new.assignment_id <> old.assignment_id
     or new.student_id <> old.student_id
     or new.university_id <> old.university_id
     or new.attempt_no <> old.attempt_no then
    raise exception 'immutable columns';
  end if;

  select * into a from public.assignments where id = old.assignment_id;

  if old.student_id = auth.uid() then
    -- студент: правит только черновик или возвращённую работу
    if old.status in ('submitted', 'graded') then
      raise exception 'submission is locked';
    end if;
    if new.status = 'draft' then
      new.status := old.status;       -- "сохранить черновик" не сбрасывает 'returned'
    elsif new.status <> 'submitted' and new.status <> old.status then
      raise exception 'students can only submit their own work';
    end if;

    if new.status = 'submitted' then
      new.submitted_at := now();
      new.is_late := (a.due_at is not null and now() > a.due_at);
      if new.is_late and not a.allow_late then
        raise exception 'deadline passed';
      end if;
    else
      new.submitted_at := old.submitted_at;
      new.is_late := old.is_late;
    end if;

  elsif app.staff_of_offering(a.offering_id) then
    -- преподаватель: только вернуть или оценить, содержимое студента не трогает
    if new.text_answer is distinct from old.text_answer
       or new.submitted_at is distinct from old.submitted_at
       or new.is_late is distinct from old.is_late then
      raise exception 'staff cannot edit student content';
    end if;
    if new.status not in ('returned', 'graded') then
      raise exception 'staff can only return or grade';
    end if;

  else
    raise exception 'not allowed';
  end if;

  return new;
end;
$$;

create or replace function app.submissions_before_delete()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is not null and old.status <> 'draft' then
    raise exception 'only drafts can be deleted';
  end if;
  return old;
end;
$$;

create trigger submissions_bi before insert on public.submissions
  for each row execute function app.submissions_before_insert();
create trigger submissions_bu before update on public.submissions
  for each row execute function app.submissions_before_update();
create trigger submissions_bd before delete on public.submissions
  for each row execute function app.submissions_before_delete();

-- ============================== (B) grades ==============================

create or replace function app.grades_before_write()
returns trigger
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  s public.submissions;
  a public.assignments;
begin
  select * into s from public.submissions where id = new.submission_id;
  if s.id is null then
    raise exception 'submission not found';
  end if;
  select * into a from public.assignments where id = s.assignment_id;

  if tg_op = 'UPDATE' and new.submission_id <> old.submission_id then
    raise exception 'immutable columns';
  end if;

  new.university_id := s.university_id;
  if auth.uid() is not null then
    new.graded_by := auth.uid();      -- нельзя выставить оценку "от имени" другого
  end if;
  if new.score > a.max_score then
    raise exception 'score exceeds max_score';
  end if;
  if tg_op = 'UPDATE' then
    new.version := old.version + 1;
    new.updated_at := now();
  end if;
  return new;
end;
$$;

create trigger grades_bw before insert or update on public.grades
  for each row execute function app.grades_before_write();
