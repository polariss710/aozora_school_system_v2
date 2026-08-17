-- Additional name/evidence fixtures required by the R1 read contracts.
\set ON_ERROR_STOP on

create table public.school_teachers(
  id uuid primary key,name text not null,display_name text,status text default 'active'
);
create table public.school_subjects(
  id uuid primary key,name text not null
);
alter table public.school_students add column display_name text;

insert into public.school_teachers(id,name,display_name)
select teacher_id,'老师-'||right(teacher_id::text,4),'老师-'||right(teacher_id::text,4)
from public.school_lesson_records where teacher_id is not null
group by teacher_id;
insert into public.school_subjects(id,name)
select subject_id,'科目-'||right(subject_id::text,4)
from public.school_lesson_records where subject_id is not null
group by subject_id;

grant select on public.school_teachers,public.school_subjects to authenticated,anon,service_role;
