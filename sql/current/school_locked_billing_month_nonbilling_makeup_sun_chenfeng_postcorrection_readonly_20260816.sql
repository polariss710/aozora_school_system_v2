-- Final immutable evidence for the committed exact correction.
\set ON_ERROR_STOP on
\pset pager off
begin transaction isolation level repeatable read read only;

do $final_assert$
declare
  v_wage_count integer;
  v_wage_total numeric;
begin
  if to_regprocedure(
       'public.school_correct_sun_chenfeng_20260811_makeup_v1(timestamp with time zone,timestamp with time zone,text,text)'
     ) is not null then
    raise exception 'SUN_CHENFENG_ONE_SHOT_ENTRYPOINT_REMAINS';
  end if;

  if not exists(select 1 from public.school_lesson_records l
      where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
        and l.status='pending_makeup' and l.student_settlement_month='2026-07')
     or not exists(select 1 from public.school_lesson_records l
      where l.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
        and l.voided_at is not null
        and l.void_reason like '%actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4%')
     or not exists(select 1 from public.school_lesson_records l
      where l.id='ff517a87-39fd-4282-89a9-e4fef28b728c'::uuid
        and l.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
        and l.status='cancelled' and l.lesson_date='2026-08-01'
        and l.start_time='13:00' and l.end_time='15:00'
        and l.actual_minutes=0 and not l.is_billable and l.lesson_fee=0
        and l.student_settlement_month='2026-07'
        and l.teacher_settlement_month='2026-08'
        and l.note like '%actor=25331ae9-3412-48b9-bdc3-e516caeaeba4%')
     or not exists(select 1 from public.school_lesson_records l
      where l.id='e69d9745-884a-401f-a4dc-d6672ea2a602'::uuid
        and l.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
        and l.status='makeup_completed' and l.lesson_date='2026-08-11'
        and l.start_time='13:00' and l.end_time='15:00'
        and l.actual_minutes=120 and not l.is_billable and l.lesson_fee=0
        and l.lesson_content='简谐+万有引力'
        and l.student_settlement_month='2026-07'
        and l.teacher_settlement_month='2026-08'
        and l.note like '%source=8b737b58-cd14-42c5-afd2-34730dcef963%'
        and l.note like '%actor=25331ae9-3412-48b9-bdc3-e516caeaeba4%') then
    raise exception 'SUN_CHENFENG_FINAL_CHAIN_INVALID';
  end if;

  if (select count(*) from public.school_lesson_records l
      where l.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
        and l.voided_at is null)<>2
     or public.school_get_lesson_credit_remaining_hours(
       '8b737b58-cd14-42c5-afd2-34730dcef963'::uuid)<>0
     or public.school_get_lesson_credit_remaining_hours(
       '6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)<>2
     or (select md5(to_jsonb(l)::text) from public.school_lesson_records l
       where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)
        is distinct from '94050771268fa97cda680affb81e9364' then
    raise exception 'SUN_CHENFENG_BALANCE_OR_EXCLUDED_SOURCE_CHANGED';
  end if;

  select count(*),coalesce(sum(c.lesson_wage_jpy),0)
  into v_wage_count,v_wage_total
  from public.school_get_teacher_monthly_wage_generation_candidate_facts(
    '2026-08','edaf30da-1315-4455-99d1-ead1b7147662'::uuid,
    '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid) c;
  if v_wage_count<>5 or v_wage_total<>40000
     or exists(select 1 from public.school_get_teacher_monthly_wage_generation_candidate_facts(
       '2026-08','edaf30da-1315-4455-99d1-ead1b7147662'::uuid,
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid) c
       where c.lesson_record_id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid)
     or not exists(select 1 from public.school_get_teacher_monthly_wage_generation_candidate_facts(
       '2026-08','edaf30da-1315-4455-99d1-ead1b7147662'::uuid,
       '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'::uuid) c
       where c.lesson_record_id='e69d9745-884a-401f-a4dc-d6672ea2a602'::uuid
         and c.lesson_wage_jpy=8000) then
    raise exception 'SUN_CHENFENG_WAGE_FINAL_INVALID';
  end if;

  if (select count(*) from public.school_list_lesson_management_records_authoritative(
       '2026-07',null) r
      where r.id in (
       'ff517a87-39fd-4282-89a9-e4fef28b728c'::uuid,
       'e69d9745-884a-401f-a4dc-d6672ea2a602'::uuid))<>2 then
    raise exception 'SUN_CHENFENG_FORMAL_READER_VISIBILITY_INVALID';
  end if;

  if (select md5(to_jsonb(s)::text) from public.school_student_monthly_settlements s
      where s.id='5e0a23ff-0e1e-48c6-9866-5fc335b3e42d'::uuid)
       is distinct from 'c96670560d491a82b552b32492cd1a55'
     or (select md5(to_jsonb(b)::text) from public.school_student_tuition_bills b
      where b.id='2a9f1c25-a060-461e-ae10-b02295dec381'::uuid)
       is distinct from 'e6f0b5df93101ea1c9f07c9c7aea0e07'
     or (select md5(to_jsonb(bl)::text) from public.school_student_tuition_bill_lessons bl
      where bl.id='ac2caa48-aaeb-c039-19ac-3b3779beb3bf'::uuid)
       is distinct from '355b2c378a9f2d20d03facfbbbe24079'
     or (select md5(to_jsonb(r)::text) from public.school_student_tuition_generation_revisions r
      where r.id='96000000-0000-4000-8000-202608031005'::uuid)
       is distinct from 'cf30373f4e86abe1568c8516ae0c4a7c'
     or (select md5(to_jsonb(i)::text) from public.school_income_records i
      where i.id='468ab75b-312e-4ba0-8d8d-8ae2f6ace00e'::uuid)
       is distinct from '88cd48e56ce1b8637625d0b6b2a22993'
     or (select md5(to_jsonb(e)::text) from public.school_personal_cash_income_linkage_events e
      where e.id='43256fb6-3f6e-41f7-9802-1d1c42a3f2c5'::uuid)
       is distinct from '8ce313f76c78e838d23425ce74801983' then
    raise exception 'SUN_CHENFENG_FINANCE_FINAL_CHANGED';
  end if;
end;
$final_assert$;

select l.id,l.lesson_date,l.start_time,l.end_time,l.status,l.is_billable,
       l.lesson_fee,l.actual_minutes,l.student_settlement_month,
       l.teacher_settlement_month,l.planned_lesson_id,l.lesson_content,
       l.voided_at,l.note,l.void_reason,md5(to_jsonb(l)::text) row_md5
from public.school_lesson_records l
where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
   or l.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
order by l.lesson_date,l.id;

select 'SUN_CHENFENG_POSTCORRECTION_READONLY_PASS' result;
rollback;
