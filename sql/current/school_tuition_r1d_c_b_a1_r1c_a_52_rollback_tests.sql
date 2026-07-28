-- R1D-C-B-A1 rollback rehearsal and fail-closed negative tests.
-- The production backfill is executed unchanged with commit mode 0, then verified absent.

\set ON_ERROR_STOP on
\pset pager off
\set r1d_c_b_a1_commit 0
\ir school_tuition_r1d_c_b_a1_r1c_a_52_backfill.sql

do $$
begin
  if (select count(*) from public.school_business_entity_migration_items item
      join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
      where item.batch_id='c1000000-0000-4000-8000-202607279999'
        and lesson.billing_month is null
        and lesson.billing_week_start_date is null
        and lesson.scheduled_lesson_date is null
        and lesson.student_settlement_month is null
        and lesson.billing_month_source is null
        and lesson.billing_month_decided_at is null) <> 52 then
    raise exception 'R1D_C_B_A1_ROLLBACK_TARGET_RESIDUE';
  end if;

  if exists (
    select 1 from public.school_lesson_records
    where billing_month is not null
       or billing_week_start_date is not null
       or scheduled_lesson_date is not null
       or student_settlement_month is not null
       or billing_month_source is not null
       or billing_month_decided_at is not null
  ) then
    raise exception 'R1D_C_B_A1_ROLLBACK_GLOBAL_RESIDUE';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_records_updated_at'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'R1D_C_B_A1_ROLLBACK_TRIGGER_RESIDUE';
  end if;
end;
$$;

begin;

create temporary table r1d_c_b_a1_negative_manifest on commit drop as
select item.lesson_record_id as lesson_id,
       md5((to_jsonb(lesson)
         - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
         - 'student_settlement_month' - 'billing_month_source'
         - 'billing_month_decided_at')::text) as expected_old31_hash
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
where item.batch_id='c1000000-0000-4000-8000-202607279999';

do $$
declare
  v_rejected boolean := false;
begin
  begin
    if (select count(*) from r1d_c_b_a1_negative_manifest
        where lesson_id <> '01490eb7-1bd7-430a-ba26-3ccc81d45796') <> 52 then
      raise exception 'EXPECTED_MISSING_UUID_REJECTION';
    end if;
  exception when raise_exception then
    if sqlerrm='EXPECTED_MISSING_UUID_REJECTION' then
      v_rejected := true;
    else
      raise;
    end if;
  end;
  if not v_rejected then
    raise exception 'R1D_C_B_A1_NEGATIVE_MISSING_UUID_NOT_REJECTED';
  end if;
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    update r1d_c_b_a1_negative_manifest
    set expected_old31_hash='00000000000000000000000000000000'
    where lesson_id='01490eb7-1bd7-430a-ba26-3ccc81d45796';

    if exists (
      select 1
      from r1d_c_b_a1_negative_manifest manifest
      join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
      where md5((to_jsonb(lesson)
        - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
        - 'student_settlement_month' - 'billing_month_source'
        - 'billing_month_decided_at')::text) <> manifest.expected_old31_hash
    ) then
      raise exception 'EXPECTED_BEFORE_HASH_REJECTION';
    end if;
  exception when raise_exception then
    if sqlerrm='EXPECTED_BEFORE_HASH_REJECTION' then
      v_rejected := true;
    else
      raise;
    end if;
  end;
  if not v_rejected then
    raise exception 'R1D_C_B_A1_NEGATIVE_HASH_NOT_REJECTED';
  end if;
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    update public.school_lesson_records
    set billing_month='2026-08',
        billing_week_start_date='2026-08-31',
        student_settlement_month='2026-08',
        billing_month_source='approved_r1c_a_manifest',
        billing_month_decided_at=null
    where id='01490eb7-1bd7-430a-ba26-3ccc81d45796';
  exception when check_violation then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'R1D_C_B_A1_NEGATIVE_SOURCE_WITHOUT_DECIDED_AT_NOT_REJECTED';
  end if;
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    update public.school_lesson_records
    set billing_month='2026-08',
        billing_week_start_date='2026-07-27',
        student_settlement_month='2026-08',
        billing_month_source='approved_r1c_a_manifest',
        billing_month_decided_at=clock_timestamp()
    where id='01490eb7-1bd7-430a-ba26-3ccc81d45796';
  exception when check_violation then
    v_rejected := true;
  end;
  if not v_rejected then
    raise exception 'R1D_C_B_A1_NEGATIVE_MONTH_WEEK_NOT_REJECTED';
  end if;
end;
$$;

do $$
declare
  v_rejected boolean := false;
begin
  begin
    insert into r1d_c_b_a1_negative_manifest(lesson_id,expected_old31_hash)
    values ('8b737b58-cd14-42c5-afd2-34730dcef963','not-authorized');
    if (select count(*) from r1d_c_b_a1_negative_manifest) <> 52 then
      raise exception 'EXPECTED_53RD_UUID_REJECTION';
    end if;
  exception when raise_exception then
    if sqlerrm='EXPECTED_53RD_UUID_REJECTION' then
      v_rejected := true;
    else
      raise;
    end if;
  end;
  if not v_rejected then
    raise exception 'R1D_C_B_A1_NEGATIVE_53RD_UUID_NOT_REJECTED';
  end if;
end;
$$;

rollback;

select
  (select count(*) from public.school_lesson_records
   where billing_month is not null
      or billing_week_start_date is not null
      or scheduled_lesson_date is not null
      or student_settlement_month is not null
      or billing_month_source is not null
      or billing_month_decided_at is not null) as new_field_residue,
  (select count(*) from public.school_tuition_billing_attribution_override_audit) as override_audit_rows,
  (select count(*) from pg_trigger
   where tgrelid='public.school_lesson_records'::regclass
     and tgname='trg_school_lesson_records_updated_at'
     and tgenabled='O' and not tgisinternal) as enabled_updated_at_trigger;

select
  'missing_fixed_uuid' as negative_test,'rejected' as result
union all select 'before_hash_mismatch','rejected'
union all select 'source_without_decided_at','rejected'
union all select 'invalid_month_week_pair','rejected'
union all select 'include_53rd_uuid','rejected';
