-- Exact correction permission and audit immutability matrix. All fixtures rollback.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $preflight$
begin
  if exists(select 1 from auth.users where id::text like 'be130000-%')
     or exists(select 1 from public.school_app_memberships
       where user_id::text like 'be130000-%') then
    raise exception 'LI_WU_CORRECTION_ROLE_FIXTURE_COLLISION';
  end if;
end;
$preflight$;

insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values
 ('be130000-0000-4000-8000-000000000001','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"li-wu-correction-admin"}',now(),now()),
 ('be130000-0000-4000-8000-000000000002','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"li-wu-correction-operator"}',now(),now()),
 ('be130000-0000-4000-8000-000000000003','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"li-wu-correction-read-only"}',now(),now()),
 ('be130000-0000-4000-8000-000000000004','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"li-wu-correction-inactive"}',now(),now()),
 ('be130000-0000-4000-8000-000000000005','authenticated','authenticated','{"provider":"email","providers":["email"]}','{"codex_test":"li-wu-correction-no-membership"}',now(),now());

insert into public.school_app_memberships(
  user_id,role,is_active,created_by_user_id,updated_by_user_id,note
) values
 ('be130000-0000-4000-8000-000000000001','admin',true,'be130000-0000-4000-8000-000000000001','be130000-0000-4000-8000-000000000001','codex-test li-wu correction'),
 ('be130000-0000-4000-8000-000000000002','operator',true,'be130000-0000-4000-8000-000000000001','be130000-0000-4000-8000-000000000001','codex-test li-wu correction'),
 ('be130000-0000-4000-8000-000000000003','read_only',true,'be130000-0000-4000-8000-000000000001','be130000-0000-4000-8000-000000000001','codex-test li-wu correction'),
 ('be130000-0000-4000-8000-000000000004','admin',false,'be130000-0000-4000-8000-000000000001','be130000-0000-4000-8000-000000000001','codex-test li-wu correction');

set local role anon;
do $anon$
begin
  begin
    perform * from public.school_correct_li_wu_test_lessons_v1(null,null,null);
    raise exception 'LI_WU_CORRECTION_ANON_ALLOWED';
  exception when insufficient_privilege then null;
  end;
end;
$anon$;
reset role;

set local role service_role;
do $service$
begin
  begin
    perform * from public.school_correct_li_wu_test_lessons_v1(null,null,null);
    raise exception 'LI_WU_CORRECTION_SERVICE_ALLOWED';
  exception when insufficient_privilege then null;
  end;
end;
$service$;
reset role;

set local role authenticated;
do $authenticated_matrix$
declare v_actor uuid; v_error text;
begin
  for v_actor in select unnest(array[
    'be130000-0000-4000-8000-000000000002'::uuid,
    'be130000-0000-4000-8000-000000000003'::uuid,
    'be130000-0000-4000-8000-000000000004'::uuid,
    'be130000-0000-4000-8000-000000000005'::uuid
  ]) loop
    perform set_config('request.jwt.claims',
      jsonb_build_object('sub',v_actor,'role','authenticated')::text,true);
    v_error:=null;
    begin
      perform * from public.school_correct_li_wu_test_lessons_v1(
        'li_wu_2026_09_11_test_lessons_void_v1_20260806',
        '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',
        'e2bc9f4380f5bf5a95ff0341ae47183b');
    exception when others then v_error:=sqlerrm;
    end;
    if position('P0G1_ACTIVE_ADMIN_REQUIRED' in coalesce(v_error,''))=0 then
      raise exception 'LI_WU_CORRECTION_ROLE_NOT_REJECTED:%:%',v_actor,v_error;
    end if;
  end loop;

  perform set_config('request.jwt.claims','{"role":"authenticated"}',true);
  v_error:=null;
  begin
    perform * from public.school_correct_li_wu_test_lessons_v1(null,null,null);
  exception when others then v_error:=sqlerrm;
  end;
  if position('P0G1_AUTH_REQUIRED' in coalesce(v_error,''))=0 then
    raise exception 'LI_WU_CORRECTION_NO_AUTH_NOT_REJECTED:%',v_error;
  end if;

  perform set_config('request.jwt.claims',
    '{"sub":"be130000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  v_error:=null;
  begin
    perform * from public.school_correct_li_wu_test_lessons_v1(
      'wrong_batch','业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',
      'e2bc9f4380f5bf5a95ff0341ae47183b');
  exception when others then v_error:=sqlerrm;
  end;
  if position('REJECTED_MANIFEST_DRIFT:BATCH_ID' in coalesce(v_error,''))=0 then
    raise exception 'LI_WU_CORRECTION_WRONG_BATCH_NOT_REJECTED:%',v_error;
  end if;
  v_error:=null;
  begin
    perform * from public.school_correct_li_wu_test_lessons_v1(
      'li_wu_2026_09_11_test_lessons_void_v1_20260806',
      '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',
      '00000000000000000000000000000000');
  exception when others then v_error:=sqlerrm;
  end;
  if position('REJECTED_MANIFEST_DRIFT:COMBINED_MD5' in coalesce(v_error,''))=0 then
    raise exception 'LI_WU_CORRECTION_WRONG_MANIFEST_NOT_REJECTED:%',v_error;
  end if;

  begin
    update public.school_lesson_records set voided_at=now(),void_reason='forged'
    where id='e890424d-407d-4fc2-b8ad-84745b242cdd';
    raise exception 'LI_WU_CORRECTION_AUTHENTICATED_DIRECT_LESSON_DML_ALLOWED';
  exception when insufficient_privilege then null;
  end;

  begin
    insert into public.school_lesson_exact_correction_events(
      correction_batch_id,lesson_id,action,reason,before_row,after_row,
      before_hash,after_hash,manifest_hash,actor_user_id
    ) values('forbidden','f256bca9-fac5-4909-b113-8077efd27d65',
      'exact_void_correction','forbidden','{}','{}',md5('{}'),md5('{}'),
      'e2bc9f4380f5bf5a95ff0341ae47183b',
      'be130000-0000-4000-8000-000000000001');
    raise exception 'LI_WU_CORRECTION_DIRECT_AUDIT_INSERT_ALLOWED';
  exception when insufficient_privilege then null;
  end;
end;
$authenticated_matrix$;
reset role;

-- Owner-session trigger attacks: even exact GUC values cannot authorize any
-- business-field mutation. Each statement runs in a rolled-back subtransaction.
do $trigger_attack_matrix$
declare v_sql text; v_denied boolean;
begin
  perform set_config('request.jwt.claims',
    '{"sub":"be130000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  perform set_config('app.school_lesson_exact_correction_context',
    'li_wu_2026_09_11_test_lessons_void_v1_20260806',true);
  perform set_config('app.school_lesson_exact_correction_manifest',
    'e2bc9f4380f5bf5a95ff0341ae47183b',true);
  perform set_config('app.school_lesson_exact_correction_action',
    'exact_void_correction',true);
  perform set_config('app.school_lesson_exact_correction_actor',
    'be130000-0000-4000-8000-000000000001',true);

  for v_sql in select unnest(array[
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',status='makeup_completed' where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',duration_hours=duration_hours+0.25 where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',actual_minutes=actual_minutes+15 where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',lesson_fee=lesson_fee+1 where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',is_billable=false where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',planned_lesson_id='f759623b-ce28-4c5f-8556-95c4381b6b1b' where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',student_settlement_month='2026-10' where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$,
    $q$update public.school_lesson_records set voided_at=now(),void_reason='业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。',teacher_settlement_month='2026-10' where id='e890424d-407d-4fc2-b8ad-84745b242cdd'$q$
  ]) loop
    v_denied:=false;
    begin execute v_sql; exception when others then v_denied:=true; end;
    if not v_denied then
      raise exception 'LI_WU_CORRECTION_TRIGGER_ATTACK_ALLOWED:%',v_sql;
    end if;
  end loop;
end;
$trigger_attack_matrix$;

do $static_downstream_contract$
declare v_definition text:=pg_get_functiondef(
  'public.school_correct_li_wu_test_lessons_v1(text,text,text)'::regprocedure);
begin
  if position('school_student_monthly_settlements' in v_definition)=0
     or position('school_student_tuition_bill_lessons' in v_definition)=0
     or position('school_teacher_wage_locks' in v_definition)=0
     or position('school_teacher_wage_lock_details' in v_definition)=0
     or position('school_student_settlement_lesson_variance_claims' in v_definition)=0
     or position('trg_school_lesson_writer_p0_validate' in v_definition)=0 then
    raise exception 'LI_WU_CORRECTION_DOWNSTREAM_GUARD_MISSING';
  end if;
end;
$static_downstream_contract$;

do $acl$
begin
  if has_function_privilege('public',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or has_function_privilege('anon',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or has_function_privilege('service_role',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or not has_function_privilege('authenticated',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute') then
    raise exception 'LI_WU_CORRECTION_ACL_MATRIX_INVALID';
  end if;
end;
$acl$;

select 'LI_WU_CORRECTION_ROLE_ROLLBACK_TEST_PASS' result;
rollback;
