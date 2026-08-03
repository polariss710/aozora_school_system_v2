\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='8s';
set local statement_timeout='120s';

create temp table p0b1_results(test_name text primary key,passed boolean,detail text) on commit drop;

insert into public.school_subjects(id,name,note)
values('b1b10000-0000-4000-8000-000000000002','codex-test P0-B1 subject','codex-test tuition-p0b1-lesson-authority-20260803');
insert into public.school_teachers(id,teacher_code,name,default_subject_id,default_business_entity_id,note)
values('b1b10000-0000-4000-8000-000000000003','codex-p0b1','codex-test P0-B1 teacher','b1b10000-0000-4000-8000-000000000002',public.school_primary_business_entity_id(),'codex-test tuition-p0b1-lesson-authority-20260803');
insert into public.school_students(id,student_code,name,business_entity_id,note)
values('b1b10000-0000-4000-8000-000000000004','codex-p0b1','codex-test P0-B1 student',public.school_primary_business_entity_id(),'codex-test tuition-p0b1-lesson-authority-20260803');

do $test$
declare
  v_id uuid;
  v_source uuid;
  v_actual uuid;
  v_updated timestamptz;
  v_fee numeric;
  v_month text;
  v_week date;
  v_client numeric;
  v_i integer:=0;
  v_before integer;
begin
  -- Tamper values are ignored; the persisted fee is always DB round(2*2000).
  foreach v_client in array array[3999::numeric,4001,0,999999999,3999.4,null] loop
    v_i:=v_i+1;
    select lesson_id into strict v_id
    from public.school_create_planned_lesson_record(
      date '2035-07-30'+v_i,'b1b10000-0000-4000-8000-000000000004',
      'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
      public.school_primary_business_entity_id(),'09:00','11:00',2,2000,v_client,
      'planned',1,'P0-B1 tamper test','codex-test tuition-p0b1-lesson-authority-20260803'
    );
    select lesson_fee,billing_month,billing_week_start_date into v_fee,v_month,v_week
    from public.school_lesson_records where id=v_id;
    if v_fee<>4000 then raise exception 'P0B1_TAMPER_SAVED: %, %',v_client,v_fee; end if;
    if v_month<>to_char(v_week,'YYYY-MM') then raise exception 'P0B1_WEEK_MONTH_MISMATCH'; end if;
  end loop;
  insert into p0b1_results values('client_fee_tamper',true,'-1/+1/0/huge/decimal/null did not decide saved fee');

  select count(*) into v_before from public.school_lesson_records
  where note='codex-test P0-B1 negative fee';
  begin
    perform * from public.school_create_planned_lesson_record(
      '2035-08-13','b1b10000-0000-4000-8000-000000000004',
      'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
      public.school_primary_business_entity_id(),'09:00','11:00',2,2000,-1,
      'planned',1,'negative','codex-test P0-B1 negative fee'
    );
    raise exception 'P0B1_NEGATIVE_CLIENT_NOT_REJECTED';
  exception when others then
    if sqlerrm='P0B1_NEGATIVE_CLIENT_NOT_REJECTED' then raise; end if;
  end;
  if (select count(*) from public.school_lesson_records where note='codex-test P0-B1 negative fee')<>v_before then
    raise exception 'P0B1_NEGATIVE_CLIENT_PARTIAL_WRITE';
  end if;
  insert into p0b1_results values('negative_fee_fail_closed',true,'negative compatibility input rejected without write');

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2035-08-20','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,
    'planned',1,'edit','codex-test tuition-p0b1-lesson-authority-20260803');
  select updated_at into v_updated from public.school_lesson_records where id=v_id;
  perform * from public.school_update_lesson_record_guarded(
    v_id,v_updated,'2035-08-20','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','12:00',3,2000,1,
    'planned',true,1,'edit','codex-test tuition-p0b1-lesson-authority-20260803');
  if (select lesson_fee from public.school_lesson_records where id=v_id)<>6000 then
    raise exception 'P0B1_EDIT_FEE_NOT_DB_AUTHORITY';
  end if;
  insert into p0b1_results values('planned_edit_recalculation',true,'duration edit persisted DB fee 6000');

  update public.school_lesson_records set lesson_fee=1 where id=v_id;
  if (select lesson_fee from public.school_lesson_records where id=v_id)<>6000 then
    raise exception 'P0B1_OWNER_FEE_FORGERY_SAVED';
  end if;
  begin
    update public.school_lesson_records set aircon_fee_jpy=999 where id=v_id;
    raise exception 'P0B1_AIRCON_FORGERY_NOT_REJECTED';
  exception when others then
    if sqlerrm='P0B1_AIRCON_FORGERY_NOT_REJECTED' then raise; end if;
  end;
  insert into p0b1_results values('table_guard',true,'owner fee forgery ignored; aircon forgery rejected');

  -- Ordinary actual uses the same DB fee authority.
  select lesson_id into strict v_source from public.school_create_planned_lesson_record(
    '2026-08-03','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,
    'planned',1,'ordinary source','codex-test tuition-p0b1-lesson-authority-20260803');
  select lesson_id into strict v_actual from public.school_create_actual_lesson_from_planned(
    v_source,'2026-08-03','09:00','11:00',2,2000,1,1,'ordinary','codex-test tuition-p0b1-lesson-authority-20260803');
  if (select lesson_fee from public.school_lesson_records where id=v_actual)<>4000 then
    raise exception 'P0B1_ORDINARY_ACTUAL_FEE';
  end if;
  insert into p0b1_results values('ordinary_actual',true,'client 1, DB persisted 4000');

  -- Cancelled actual is non-billable and DB persists zero.
  select lesson_id into strict v_source from public.school_create_planned_lesson_record(
    '2026-07-20','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,null,
    'planned',1,'cancel source','codex-test tuition-p0b1-lesson-authority-20260803');
  select lesson_id into strict v_actual from public.school_create_cancelled_actual_lesson_from_planned(
    v_source,'2026-07-20','09:00','11:00',2,2000,1,'cancel','codex-test tuition-p0b1-lesson-authority-20260803');
  if exists(select 1 from public.school_lesson_records where id=v_actual and (lesson_fee<>0 or is_billable)) then
    raise exception 'P0B1_CANCELLED_ACTUAL_FEE';
  end if;
  insert into p0b1_results values('cancelled_actual',true,'non-billable and zero persisted');

  -- Partial actual uses actual duration and source unit price.
  select lesson_id into strict v_source from public.school_create_planned_lesson_record(
    '2026-07-06','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,null,
    'planned',1,'partial source','codex-test tuition-p0b1-lesson-authority-20260803');
  select id into strict v_actual from public.school_create_partial_completed_actual_from_planned(
    v_source,'2026-07-06','09:00','10:30',1.5,'partial','codex-test tuition-p0b1-lesson-authority-20260803');
  if (select lesson_fee from public.school_lesson_records where id=v_actual)<>3000 then
    raise exception 'P0B1_PARTIAL_ACTUAL_FEE';
  end if;
  insert into p0b1_results values('partial_actual',true,'1.5h persisted DB fee 3000');

  -- Overage remains the existing frozen bundle; aircon is not added to actual.
  select lesson_id into strict v_source from public.school_create_planned_lesson_record(
    '2026-07-13','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,null,
    'planned',1,'overage source','codex-test tuition-p0b1-lesson-authority-20260803');
  select lesson_id into strict v_actual from public.school_create_actual_lesson_from_planned(
    v_source,'2026-07-13','09:00','11:30',2.5,2000,1,1,'overage','codex-test tuition-p0b1-lesson-authority-20260803');
  if not exists(select 1 from public.school_lesson_records where id=v_actual
    and lesson_fee=5000 and student_duration_overage_minutes=30
    and student_duration_overage_fee_jpy=1000 and aircon_fee_jpy is null
    and lesson_total_fee_jpy is null) then
    raise exception 'P0B1_OVERAGE_BUNDLE';
  end if;
  insert into p0b1_results values('ordinary_actual_overage',true,'DB fee 5000; existing 30min/1000 bundle frozen; no aircon');

  -- Makeup consumes credit as a non-billable fulfillment fact.
  select lesson_id into strict v_source from public.school_create_planned_lesson_record(
    '2026-07-27','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,null,
    'pending_makeup',1,'makeup source','codex-test tuition-p0b1-lesson-authority-20260803');
  select id into strict v_actual from public.school_create_lesson_credit_makeup_actual(
    v_source,'2026-08-03','b1b10000-0000-4000-8000-000000000003',
    'b1b10000-0000-4000-8000-000000000002','09:00','11:00',2,'makeup',
    'codex-test tuition-p0b1-lesson-authority-20260803',1,null,null);
  if exists(select 1 from public.school_lesson_records where id=v_actual and (lesson_fee<>0 or is_billable)) then
    raise exception 'P0B1_MAKEUP_ACTUAL_FEE';
  end if;
  insert into p0b1_results values('makeup_actual',true,'credit fulfillment non-billable and zero');

  -- Existing aircon calculator remains the only bundle authority.
  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2026-08-08','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,'planned',1,
    'weekend aircon','codex-test tuition-p0b1-lesson-authority-20260803');
  update public.school_lesson_records set lesson_delivery_mode='onsite',lesson_venue='Regus办公室',
    lesson_venue_id='f2ff0000-0000-4000-8000-202608010001',aircon_unit_price_jpy_snapshot=500 where id=v_id;
  if not exists(select 1 from public.school_lesson_records where id=v_id
    and lesson_fee=4000 and aircon_fee_jpy=1000 and lesson_total_fee_jpy=5000
    and aircon_billable_hours_snapshot=2) then raise exception 'P0B1_WEEKEND_AIRCON'; end if;
  insert into p0b1_results values('weekend_aircon',true,'2 whole hours x 500; total 5000');

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2026-08-10','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,'planned',1,
    'weekday aircon','codex-test tuition-p0b1-lesson-authority-20260803');
  update public.school_lesson_records set lesson_delivery_mode='onsite',lesson_venue='Regus办公室',
    lesson_venue_id='f2ff0000-0000-4000-8000-202608010001',aircon_unit_price_jpy_snapshot=500 where id=v_id;
  if not exists(select 1 from public.school_lesson_records where id=v_id
    and aircon_fee_jpy=0 and lesson_total_fee_jpy=4000 and fee_block_reason_code='AIRCON_WEEKDAY') then
    raise exception 'P0B1_WEEKDAY_AIRCON'; end if;
  insert into p0b1_results values('weekday_aircon',true,'weekday fee zero; total base only');

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2026-08-09','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,'planned',1,
    'zero aircon','codex-test tuition-p0b1-lesson-authority-20260803');
  update public.school_lesson_records set lesson_delivery_mode='onsite',lesson_venue='Regus办公室',
    lesson_venue_id='f2ff0000-0000-4000-8000-202608010001',aircon_unit_price_jpy_snapshot=0 where id=v_id;
  if not exists(select 1 from public.school_lesson_records where id=v_id
    and aircon_fee_jpy=0 and aircon_charge_status='configured_zero') then raise exception 'P0B1_ZERO_AIRCON'; end if;
  insert into p0b1_results values('zero_rate_aircon',true,'configured zero preserved by DB calculator');

  select lesson_id into strict v_id from public.school_create_planned_lesson_record(
    '2026-08-16','b1b10000-0000-4000-8000-000000000004',
    'b1b10000-0000-4000-8000-000000000003','b1b10000-0000-4000-8000-000000000002',
    public.school_primary_business_entity_id(),'09:00','11:00',2,2000,1,'planned',1,
    'no aircon','codex-test tuition-p0b1-lesson-authority-20260803');
  update public.school_lesson_records set lesson_delivery_mode='onsite',lesson_venue='Regus公共区',
    lesson_venue_id='f2ff0000-0000-4000-8000-202608010002',aircon_unit_price_jpy_snapshot=500 where id=v_id;
  if not exists(select 1 from public.school_lesson_records where id=v_id
    and aircon_fee_jpy=0 and fee_block_reason_code='AIRCON_VENUE_NOT_ELIGIBLE') then
    raise exception 'P0B1_NON_ELIGIBLE_AIRCON'; end if;
  insert into p0b1_results values('noneligible_aircon',true,'noneligible venue fee zero');

  -- A source consumed by actual permits note-only maintenance but freezes charge facts.
  update public.school_lesson_records set note=note || ' note-only' where id=v_source;
  begin
    update public.school_lesson_records set unit_price=unit_price+1 where id=v_source;
    raise exception 'P0B1_ACTUAL_CONSUMED_MUTATION_NOT_REJECTED';
  exception when others then
    if sqlerrm='P0B1_ACTUAL_CONSUMED_MUTATION_NOT_REJECTED' then raise; end if;
    if position('LESSON_FINANCIAL_FACT_IMMUTABLE' in sqlerrm)=0 then raise; end if;
  end;
  insert into p0b1_results values('actual_consumed_freeze',true,'note-only allowed; charge mutation stable rejected');

  if (select count(*) from public.school_legacy_actual_settlement_evidence)=0 then
    raise exception 'P0B1_LEGACY_ACTUAL_EVIDENCE_MISSING';
  end if;
  insert into p0b1_results values('legacy_actual_read',true,'legacy evidence remains readable without rewrite');

  -- Natural-week authority across month/year boundaries.
  if to_char(date_trunc('week',date '2026-08-02'::timestamp),'YYYY-MM')<>'2026-07'
     or to_char(date_trunc('week',date '2026-09-06'::timestamp),'YYYY-MM')<>'2026-08'
     or to_char(date_trunc('week',date '2027-01-03'::timestamp),'YYYY-MM')<>'2026-12' then
    raise exception 'P0B1_NATURAL_WEEK_BOUNDARY';
  end if;
  insert into p0b1_results values('natural_week_boundaries',true,'three required cross-month/year weeks');
end
$test$;

do $acl$
declare r name;
begin
  foreach r in array array['anon'::name,'authenticated'::name,'service_role'::name] loop
    if has_table_privilege(r,'public.school_lesson_records','INSERT')
       or has_table_privilege(r,'public.school_lesson_records','UPDATE')
       or has_table_privilege(r,'public.school_lesson_records','DELETE')
       or has_table_privilege(r,'public.school_lesson_records','TRUNCATE') then
      raise exception 'P0B1_DIRECT_DML_REMAINS: %',r;
    end if;
    if not has_table_privilege(r,'public.school_lesson_records','SELECT') then
      raise exception 'P0B1_SELECT_MISSING: %',r;
    end if;
    if has_function_privilege(r,'public.school_tuition_p0b1_lock_lesson_scopes(jsonb)','EXECUTE') then
      raise exception 'P0B1_HELPER_EXPOSED: %',r;
    end if;
    if has_function_privilege(r,'public.school_import_lesson_records_batch(uuid,text,text,jsonb,text)','EXECUTE') then
      raise exception 'P0B1_HISTORICAL_IMPORT_EXPOSED: %',r;
    end if;
  end loop;
  insert into p0b1_results values('acl_roles',true,'anon/authenticated/service direct DML 0, SELECT yes, helper no');
end
$acl$;

do $catalog$
begin
  if (select count(*) from pg_policy where polrelid='public.school_lesson_records'::regclass
      and polcmd='r' and pg_get_expr(polqual,polrelid)='true')<>1
     or exists(select 1 from pg_policy where polrelid='public.school_lesson_records'::regclass and polcmd='*') then
    raise exception 'P0B1_RLS_POLICY_INVALID';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='public' and p.proname in (
        'school_create_actual_lesson_from_planned','school_create_cancelled_actual_lesson_from_planned',
        'school_create_lesson_credit_makeup_actual','school_create_partial_completed_actual_from_planned',
        'school_create_planned_lesson_record','school_delete_fresh_planned_lesson',
        'school_generate_planned_lessons_batch','school_update_lesson_record_guarded',
        'school_update_lesson_record_guarded_with_venue','school_void_planned_lesson')
      and pg_get_functiondef(p.oid) like '%school_tuition_p0b1_lock_%')<9
     or position('school_void_planned_lesson_after_tuition_void' in pg_get_functiondef(
       'public.school_void_planned_lesson(uuid,timestamp with time zone,text)'::regprocedure))=0
     or position('school_tuition_p0a_lock_settlement_mutation_scope' in pg_get_functiondef(
       'public.school_void_planned_lesson_after_tuition_void(uuid,timestamp with time zone,text,text)'::regprocedure))=0 then
    raise exception 'P0B1_WRITER_LOCK_COVERAGE';
  end if;
  insert into p0b1_results values('catalog_contract',true,'SELECT-only RLS and lock injection present');
end
$catalog$;

select * from p0b1_results order by test_name;
rollback;
