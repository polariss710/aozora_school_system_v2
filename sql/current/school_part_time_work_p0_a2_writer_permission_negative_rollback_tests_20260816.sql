-- Production-safe PTW-P0-A2 negative writer probes.
-- Calls only authorization-failing paths with synthetic non-business inputs and always rolls back.
\set ON_ERROR_STOP on
\pset pager off

begin;

create temp table ptw_p0_a2_negative_results (
  actor_case text,
  writer text,
  sqlstate text,
  error_marker text
) on commit drop;

create temp table ptw_p0_a2_negative_business_baseline on commit drop as
select 'school_income_records' object_name,count(*)::bigint row_count,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),'')) row_hash
from public.school_income_records x
union all select 'school_part_time_work_income_requests',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_income_requests x
union all select 'school_part_time_work_lessons',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_lessons x
union all select 'school_part_time_work_monthly_settlement_details',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlement_details x
union all select 'school_part_time_work_monthly_settlements',count(*)::bigint,
       md5(coalesce(string_agg(md5(to_jsonb(x)::text),'' order by x.id::text),''))
from public.school_part_time_work_monthly_settlements x;

create function pg_temp.ptw_p0_a2_expect_denied(
  p_actor_case text,
  p_writer text,
  p_sql text,
  p_expected_marker text
) returns void language plpgsql as $function$
declare
  v_state text;
  v_message text;
begin
  begin
    execute p_sql;
    raise exception using errcode='P0001',message='PTW_P0_A2_NEGATIVE_PROBE_UNEXPECTED_SUCCESS',detail=p_writer;
  exception when sqlstate '42501' then
    get stacked diagnostics v_state=returned_sqlstate,v_message=message_text;
    if v_message<>p_expected_marker then
      raise exception using errcode='P0001',message='PTW_P0_A2_NEGATIVE_MARKER_MISMATCH',
        detail=format('writer=%s actual=%s expected=%s',p_writer,v_message,p_expected_marker);
    end if;
    insert into ptw_p0_a2_negative_results values(p_actor_case,p_writer,v_state,v_message);
  end;
end
$function$;

do $preflight$
begin
  if exists (
    select 1 from public.school_app_memberships membership_row
    where membership_row.user_id='a2000000-0000-0000-0000-000000000099'::uuid
  ) then
    raise exception using errcode='P0001',message='PTW_P0_A2_NEGATIVE_SYNTHETIC_USER_COLLISION';
  end if;
end
$preflight$;

select set_config('request.jwt.claims','',true);
select set_config('request.jwt.claim.sub','',true);
select pg_temp.ptw_p0_a2_expect_denied('authless','create_planned',
  $$select * from public.school_create_part_time_work_planned_lesson('2000-01-01','09:00','10:00','诺应教育','EJU文数班课',null,1,0,0,0,null,'codex-test')$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','update_lesson',
  $$select * from public.school_update_part_time_work_lesson('a2000000-0000-0000-0000-000000000098','2000-01-01','09:00','10:00','诺应教育','EJU文数班课',null,1,0,0,0,null)$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','generate_actual',
  $$select * from public.school_generate_part_time_work_actual_from_planned(null,null,null,null,null,null,null,null,null)$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','delete_lesson',
  $$select * from public.school_delete_part_time_work_lesson(null,false)$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','lock_settlement',
  $$select * from public.school_lock_part_time_work_monthly_settlement('2000-01','诺应教育',0,null)$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','unlock_settlement',
  $$select * from public.school_unlock_part_time_work_monthly_settlement(null)$$,
  'PTW_WRITER_AUTH_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('authless','create_income',
  $$select * from public.school_create_part_time_work_income_record(null)$$,
  'PTW_WRITER_AUTH_REQUIRED');

select set_config('request.jwt.claims','{"sub":"a2000000-0000-0000-0000-000000000099","role":"authenticated"}',true);
select set_config('request.jwt.claim.sub','a2000000-0000-0000-0000-000000000099',true);
select pg_temp.ptw_p0_a2_expect_denied('no_membership','create_planned',
  $$select * from public.school_create_part_time_work_planned_lesson('2000-01-01','09:00','10:00','诺应教育','EJU文数班课',null,1,0,0,0,null,'codex-test')$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','update_lesson',
  $$select * from public.school_update_part_time_work_lesson('a2000000-0000-0000-0000-000000000098','2000-01-01','09:00','10:00','诺应教育','EJU文数班课',null,1,0,0,0,null)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','generate_actual',
  $$select * from public.school_generate_part_time_work_actual_from_planned(null,null,null,null,null,null,null,null,null)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','delete_lesson',
  $$select * from public.school_delete_part_time_work_lesson(null,false)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','lock_settlement',
  $$select * from public.school_lock_part_time_work_monthly_settlement('2000-01','诺应教育',0,null)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','unlock_settlement',
  $$select * from public.school_unlock_part_time_work_monthly_settlement(null)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');
select pg_temp.ptw_p0_a2_expect_denied('no_membership','create_income',
  $$select * from public.school_create_part_time_work_income_record(null)$$,
  'PTW_WRITER_MEMBERSHIP_REQUIRED');

do $verify$
declare
  fingerprint_row record;
  v_count bigint;
  v_hash text;
begin
  if (select count(*) from ptw_p0_a2_negative_results)<>14 then
    raise exception using errcode='P0001',message='PTW_P0_A2_NEGATIVE_RESULT_COUNT_MISMATCH';
  end if;
  for fingerprint_row in select * from ptw_p0_a2_negative_business_baseline order by object_name loop
    execute format('select count(*)::bigint,md5(coalesce(string_agg(md5(to_jsonb(x)::text),'''' order by x.id::text),'''')) from public.%I x',fingerprint_row.object_name)
      into v_count,v_hash;
    if (v_count,v_hash) is distinct from (fingerprint_row.row_count,fingerprint_row.row_hash) then
      raise exception using errcode='P0001',message='PTW_P0_A2_NEGATIVE_PROBE_TOUCHED_BUSINESS_DATA',detail=fingerprint_row.object_name;
    end if;
  end loop;
end
$verify$;

select * from ptw_p0_a2_negative_results order by actor_case,writer;
select 'PTW_P0_A2_PRODUCTION_NEGATIVE_ROLLBACK_PASS' as result;
rollback;
