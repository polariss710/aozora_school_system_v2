-- School V2 Li Tianlun + Wu Feng 11-ID exact correction trigger/RPC v6.
-- Status: v6 deployed and rollback-rehearsal verified, 2026-08-06.
-- Business expansion approval: continuation task sections 3-6, 8, and 15.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $preflight$
begin
  if to_regclass('public.school_lesson_exact_correction_events') is null
     or to_regprocedure('public.school_require_current_app_admin()') is null
     or md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     ))<>'60e380b560b0682dd78aa97139382d65'
     or md5(pg_get_functiondef(
       'public.school_enforce_r1d_f1_planned_attribution()'::regprocedure
     ))<>'3651e01ad3f475a1b4ebe5cd28c26355'
     or md5(pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure
     )) not in ('eea6c17ea506359563fc18ef446e3310',
                'e5ed12c9897e802fbcc8da699cc9ef5f')
     or md5(pg_get_functiondef(
       'public.school_sync_lesson_actual_minutes()'::regprocedure
     )) not in ('db4f27badd7f5394aef95ada41ae8494',
                '87e7587d601f3fe1b2abdec35742e2cc')
     or md5(pg_get_functiondef(
       'public.school_tuition_p0b1_lesson_financial_authority()'::regprocedure
     )) not in ('f30523fc1220c4a05e9459481fd1798e',
                'dbc0e193fdd42b940beae7677e1681a6')
     or md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     )) not in ('0a9ed8ad8f2b8015fe5979a15e5e0e69',
                'd8a1f092429f9c4ad6918ee680514e4b')
     or md5(pg_get_functiondef(
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)'::regprocedure
     )) not in ('b857e77cdc16f3d8ff5f54852cce986f',
                '3203a0d520a0dbfd62f2c9234509f928',
                '4a78235e83e7b8b93aa79891069fefe5',
                '0a9f3807dc9a1c87c44cb74a9d9e06b8',
                '02240223f82a28820cfc7309c1fd49e6') then
    raise exception 'LI_WU_CORRECTION_V4_PREFLIGHT_DRIFT';
  end if;
end;
$preflight$;

-- Preserve legacy fee/minutes/billable only for the approved 4-Actual
-- exact-void context. There is deliberately no early RETURN: source locking,
-- proposed-state credit checks, and every later trigger still execute.
do $lesson_writer_p0_exact_void_contract_v3$
declare
  v_definition text;
  v_current_hash text;
  v_old_declaration text:='  v_total_consumed numeric;';
  v_new_declaration text:=
$new$  v_total_consumed numeric;
  v_is_exact_correction boolean:=false;$new$;
  v_old_context text:='  v_new_source:=new.planned_lesson_id;';
  v_new_context text:=
$new$  v_new_source:=new.planned_lesson_id;

  if tg_op='UPDATE' then
    v_is_exact_correction:=
      current_setting('app.school_lesson_exact_correction_context',true)
        ='li_wu_2026_09_11_test_lessons_void_v1_20260806'
      and current_setting('app.school_lesson_exact_correction_manifest',true)
        ='e2bc9f4380f5bf5a95ff0341ae47183b'
      and current_setting('app.school_lesson_exact_correction_action',true)
        ='exact_void_correction'
      and current_setting('app.school_lesson_exact_correction_actor',true)=auth.uid()::text
      and exists(select 1 from public.school_app_memberships m
        where m.user_id=auth.uid() and m.role='admin' and m.is_active)
      and old.id=any(array[
        'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
        'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
        'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
        'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
      ])
      and md5(to_jsonb(old)::text)=case old.id
        when 'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid then '68a2e384c0da181bbc514899899e1bf1'
        when 'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid then '97667b2d7b8bd485e7571c7ca12306d8'
        when 'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid then 'b111085217eff6410f34895722068117'
        when 'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid then '34ecb1210e1c65d2e35f0b8165b97d06'
      end
      and old.voided_at is null and old.void_reason is null
      and new.voided_at is not null
      and new.void_reason=
        '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。'
      and (to_jsonb(new)-array['voided_at','void_reason','updated_at'])
          is not distinct from
          (to_jsonb(old)-array['voided_at','void_reason','updated_at']);
  end if;$new$;
  v_old_normalization text:=
$old$    if new.status='cancelled' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      new.actual_minutes:=0;
    elsif new.status='makeup_completed' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      if v_time_changed then new.actual_minutes:=v_minutes; end if;
    end if;$old$;
  v_new_normalization text:=
$new$    if v_is_exact_correction then
      new.is_billable:=old.is_billable;
      new.lesson_fee:=old.lesson_fee;
      new.actual_minutes:=old.actual_minutes;
    elsif new.status='cancelled' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      new.actual_minutes:=0;
    elsif new.status='makeup_completed' then
      new.is_billable:=false;
      new.lesson_fee:=0;
      if v_time_changed then new.actual_minutes:=v_minutes; end if;
    end if;$new$;
begin
  select pg_get_functiondef(
    'public.school_lesson_writer_p0_validate_row()'::regprocedure
  ) into strict v_definition;
  v_current_hash:=md5(v_definition);
  if v_current_hash='e5ed12c9897e802fbcc8da699cc9ef5f' then
    null;
  elsif v_current_hash<>'eea6c17ea506359563fc18ef446e3310'
     or position(v_old_declaration in v_definition)=0
     or position(v_old_context in v_definition)=0
     or position(v_old_normalization in v_definition)=0 then
    raise exception 'LI_WU_CORRECTION_V3_P0_SOURCE_DRIFT';
  else
    v_definition:=replace(v_definition,v_old_declaration,v_new_declaration);
    v_definition:=replace(v_definition,v_old_context,v_new_context);
    v_definition:=replace(v_definition,v_old_normalization,v_new_normalization);
    execute v_definition;
  end if;
end;
$lesson_writer_p0_exact_void_contract_v3$;

-- The actual-minutes sync trigger executes before legacy/P0 guards. Reject an
-- explicit minutes mutation in the exact context before it can be normalized
-- back to OLD and become invisible to later trigger comparisons.
do $actual_minutes_sync_exact_void_contract_v4$
declare
  v_definition text;
  v_current_hash text;
  v_old_entry text:=
$old$begin
  if coalesce(new.app_type, '') = 'school'$old$;
  v_new_entry text:=
$new$begin
  if tg_op='UPDATE'
     and current_setting('app.school_lesson_exact_correction_context',true)
       ='li_wu_2026_09_11_test_lessons_void_v1_20260806'
     and current_setting('app.school_lesson_exact_correction_manifest',true)
       ='e2bc9f4380f5bf5a95ff0341ae47183b'
     and current_setting('app.school_lesson_exact_correction_action',true)
       ='exact_void_correction'
     and current_setting('app.school_lesson_exact_correction_actor',true)=auth.uid()::text
     and exists(select 1 from public.school_app_memberships m
       where m.user_id=auth.uid() and m.role='admin' and m.is_active)
     and old.id=any(array[
       'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
       'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
       'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
       'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
     ])
     and (
       (old.id='e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid
         and md5(to_jsonb(old)::text)='68a2e384c0da181bbc514899899e1bf1')
       or (old.id='b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid
         and md5(to_jsonb(old)::text)='97667b2d7b8bd485e7571c7ca12306d8')
       or (old.id='dc06b98c-360f-4661-a294-52ecb82830a7'::uuid
         and md5(to_jsonb(old)::text)='b111085217eff6410f34895722068117')
       or (old.id='c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
         and md5(to_jsonb(old)::text)='34ecb1210e1c65d2e35f0b8165b97d06')
     )
     and old.voided_at is null and old.void_reason is null
     and new.voided_at is not null
     and new.void_reason=
       '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。'
     and new.actual_minutes is distinct from old.actual_minutes then
    raise exception using errcode='22023',
      message='LI_WU_EXACT_CORRECTION_ACTUAL_MINUTES_MUTATION_REJECTED';
  end if;

  if coalesce(new.app_type, '') = 'school'$new$;
begin
  select pg_get_functiondef(
    'public.school_sync_lesson_actual_minutes()'::regprocedure
  ) into strict v_definition;
  v_current_hash:=md5(v_definition);
  if v_current_hash='87e7587d601f3fe1b2abdec35742e2cc' then
    null;
  elsif v_current_hash<>'db4f27badd7f5394aef95ada41ae8494'
     or position(v_old_entry in v_definition)=0 then
    raise exception 'LI_WU_CORRECTION_V4_MINUTES_SYNC_SOURCE_DRIFT';
  else
    execute replace(v_definition,v_old_entry,v_new_entry);
  end if;
end;
$actual_minutes_sync_exact_void_contract_v4$;

-- The financial-authority trigger intentionally restores direct fee input to
-- OLD. In the exact correction context, reject that input before restoration
-- so a fee mutation cannot be hidden from the later manifest comparisons.
do $lesson_fee_exact_void_contract_v5$
declare
  v_definition text;
  v_current_hash text;
  v_old_entry text:=
$old$begin
  if tg_op='DELETE' then$old$;
  v_new_entry text:=
$new$begin
  if tg_op='UPDATE'
     and current_setting('app.school_lesson_exact_correction_context',true)
       ='li_wu_2026_09_11_test_lessons_void_v1_20260806'
     and current_setting('app.school_lesson_exact_correction_manifest',true)
       ='e2bc9f4380f5bf5a95ff0341ae47183b'
     and current_setting('app.school_lesson_exact_correction_action',true)
       ='exact_void_correction'
     and current_setting('app.school_lesson_exact_correction_actor',true)=auth.uid()::text
     and exists(select 1 from public.school_app_memberships m
       where m.user_id=auth.uid() and m.role='admin' and m.is_active)
     and old.id=any(array[
       'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
       'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
       'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
       'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
     ])
     and (
       (old.id='e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid
         and md5(to_jsonb(old)::text)='68a2e384c0da181bbc514899899e1bf1')
       or (old.id='b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid
         and md5(to_jsonb(old)::text)='97667b2d7b8bd485e7571c7ca12306d8')
       or (old.id='dc06b98c-360f-4661-a294-52ecb82830a7'::uuid
         and md5(to_jsonb(old)::text)='b111085217eff6410f34895722068117')
       or (old.id='c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
         and md5(to_jsonb(old)::text)='34ecb1210e1c65d2e35f0b8165b97d06')
     )
     and old.voided_at is null and old.void_reason is null
     and new.voided_at is not null
     and new.void_reason=
       '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。'
     and new.lesson_fee is distinct from old.lesson_fee then
    raise exception using errcode='22023',
      message='LI_WU_EXACT_CORRECTION_LESSON_FEE_MUTATION_REJECTED';
  end if;

  if tg_op='DELETE' then$new$;
begin
  select pg_get_functiondef(
    'public.school_tuition_p0b1_lesson_financial_authority()'::regprocedure
  ) into strict v_definition;
  v_current_hash:=md5(v_definition);
  if v_current_hash='dbc0e193fdd42b940beae7677e1681a6' then
    null;
  elsif v_current_hash<>'f30523fc1220c4a05e9459481fd1798e'
     or position(v_old_entry in v_definition)=0 then
    raise exception 'LI_WU_CORRECTION_V5_FINANCIAL_SOURCE_DRIFT';
  else
    execute replace(v_definition,v_old_entry,v_new_entry);
  end if;
end;
$lesson_fee_exact_void_contract_v5$;

-- Active Actual rows still require an active source. A voided Actual may resolve
-- its immutable month through the same evidence when its source is also voided;
-- all identity/evidence checks remain unchanged.
do $voided_actual_month_reader_contract_v6$
declare
  v_definition text;
  v_current_hash text;
  v_old_condition constant text:='OR v_source.voided_at IS NOT NULL';
  v_new_condition constant text:=
    'OR (v_source.voided_at IS NOT NULL AND v_lesson.voided_at IS NULL)';
begin
  select pg_get_functiondef(
    'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
  ) into strict v_definition;
  v_current_hash:=md5(v_definition);
  if v_current_hash='d8a1f092429f9c4ad6918ee680514e4b' then
    null;
  elsif v_current_hash<>'0a9ed8ad8f2b8015fe5979a15e5e0e69'
     or (length(v_definition)-length(replace(v_definition,v_old_condition,'')))
        <>2*length(v_old_condition) then
    raise exception 'LI_WU_CORRECTION_V6_READER_SOURCE_DRIFT';
  else
    execute replace(v_definition,v_old_condition,v_new_condition);
  end if;
end;
$voided_actual_month_reader_contract_v6$;

create or replace function public.school_correct_li_wu_test_lessons_v1(
  p_correction_batch_id text,
  p_reason text,
  p_expected_manifest_md5 text
)
returns table(
  correction_batch_id text,
  status text,
  lesson_id uuid,
  action text,
  before_hash text,
  after_hash text,
  voided_at timestamptz,
  message text
)
language plpgsql
security definer
set search_path=pg_catalog,public
as $function$
declare
  v_actor uuid;
  v_batch constant text:=
    'li_wu_2026_09_11_test_lessons_void_v1_20260806';
  v_reason constant text:=
    '业务负责人确认：李天伦＋吴峰2026年9–11月11条课时均为历史测试或误建数据，不属于真实预定或实际授课；保留legacy evidence并以前向Void/Correction排除业务候选。';
  v_manifest_hash constant text:='e2bc9f4380f5bf5a95ff0341ae47183b';
  v_student constant uuid:='a7b163a0-201e-4867-9b94-372343356a80';
  v_teacher constant uuid:='bbc3d827-ba8b-4ded-a5ac-cafca88f26bd';
  v_subject constant uuid:='20efb4d9-7e58-42a9-85bb-e34c3e1a7c90';
  v_actual_ids constant uuid[]:=array[
    'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid,
    'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid,
    'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid,
    'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid
  ];
  v_linked_planned_ids constant uuid[]:=array[
    '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid,
    'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid,
    'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid
  ];
  v_independent_planned_ids constant uuid[]:=array[
    'f256bca9-fac5-4909-b113-8077efd27d65'::uuid,
    'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid,
    '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid,
    '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid
  ];
  v_all_ids uuid[];
  v_expected_row_hashes text[]:=array[
    '96ff1feca91a4fa49003fb3727b1da8c',
    'f4006e9086cedf5ff0f378fe0ca7987f',
    '4b6143e1ab2de6db0b4f6f9e50f1c792',
    '30349b3e50ed4c3fdf22e34e8dcd9c43',
    'a1597f23dbc50a1f4597cb0498de8dc8',
    '97667b2d7b8bd485e7571c7ca12306d8',
    '34ecb1210e1c65d2e35f0b8165b97d06',
    'b111085217eff6410f34895722068117',
    '68a2e384c0da181bbc514899899e1bf1',
    '3726481d8f512e47dba1c34efa276701',
    '0483222ed7058a4a6107579de796d8ba'
  ];
  v_ids_sorted uuid[];
  v_row_hashes text[];
  v_combined text;
  v_event_count integer;
  v_before jsonb;
  v_after jsonb;
  v_before_hash text;
  v_after_hash text;
  v_id uuid;
  v_now timestamptz:=transaction_timestamp();
  v_table text;
  v_has_ref boolean;
  v_lesson_id_patterns text[];
  v_source_id uuid;
  v_raw_before numeric;
  v_raw_after numeric;
begin
  v_actor:=public.school_require_current_app_admin();

  if nullif(trim(coalesce(p_correction_batch_id,'')),'') is null
     or p_correction_batch_id<>v_batch then
    raise exception using errcode='22023',message='REJECTED_MANIFEST_DRIFT:BATCH_ID';
  end if;
  if nullif(trim(coalesce(p_reason,'')),'') is null or p_reason<>v_reason then
    raise exception using errcode='22023',message='REJECTED_MANIFEST_DRIFT:REASON';
  end if;
  if p_expected_manifest_md5 is distinct from v_manifest_hash then
    raise exception using errcode='22023',message='REJECTED_MANIFEST_DRIFT:COMBINED_MD5';
  end if;

  v_all_ids:=v_actual_ids||v_linked_planned_ids||v_independent_planned_ids;
  select array_agg(x order by x::text) into v_ids_sorted
  from unnest(v_all_ids) x;
  if cardinality(v_ids_sorted)<>11
     or (select count(distinct x) from unnest(v_ids_sorted) x)<>11 then
    raise exception 'REJECTED_MANIFEST_DRIFT:INTERNAL_ID_SET';
  end if;
  select array_agg('%'||x::text||'%') into v_lesson_id_patterns
  from unnest(v_ids_sorted) x;

  select count(*) into v_event_count
  from public.school_lesson_exact_correction_events e
  where e.lesson_id=any(v_ids_sorted);
  if v_event_count>0 then
    if v_event_count=11
       and (select count(*) from public.school_lesson_exact_correction_events e
            join public.school_lesson_records l on l.id=e.lesson_id
            where e.lesson_id=any(v_ids_sorted)
              and e.correction_batch_id=v_batch
              and e.action='exact_void_correction'
              and e.reason=v_reason
              and e.manifest_hash=v_manifest_hash
              and e.after_hash=md5(to_jsonb(l)::text)
              and l.voided_at is not null
              and l.void_reason=v_reason)=11 then
      return query
      select e.correction_batch_id,'already_applied'::text,e.lesson_id,e.action,
        e.before_hash,e.after_hash,l.voided_at,'same batch already applied'::text
      from public.school_lesson_exact_correction_events e
      join public.school_lesson_records l on l.id=e.lesson_id
      where e.lesson_id=any(v_ids_sorted)
      order by e.lesson_id::text;
      return;
    end if;
    raise exception using errcode='55000',
      message='REJECTED_MANIFEST_DRIFT:EXISTING_CORRECTION_EVENT';
  end if;

  perform 1 from public.school_lesson_records l
  where l.id=any(v_ids_sorted) order by l.id::text for update;
  if (select count(*) from public.school_lesson_records l
      where l.id=any(v_ids_sorted))<>11 then
    raise exception 'REJECTED_MANIFEST_DRIFT:LESSON_COUNT';
  end if;

  select array_agg(md5(to_jsonb(l)::text) order by l.id::text),
         md5(string_agg(md5(to_jsonb(l)::text),'' order by l.id::text))
  into v_row_hashes,v_combined
  from public.school_lesson_records l where l.id=any(v_ids_sorted);
  if v_row_hashes is distinct from v_expected_row_hashes
     or v_combined<>v_manifest_hash
     or exists(select 1 from public.school_lesson_records l
       where l.id=any(v_ids_sorted)
         and (l.student_id<>v_student or l.teacher_id<>v_teacher
              or l.subject_id<>v_subject or l.voided_at is not null
              or l.void_reason is not null)) then
    raise exception using errcode='55000',message='REJECTED_MANIFEST_DRIFT:LESSON_ROWS';
  end if;

  perform 1 from public.school_legacy_planned_settlement_evidence e
  where e.planned_lesson_id=any(v_ids_sorted)
  order by e.planned_lesson_id::text for share;
  perform 1 from public.school_legacy_actual_settlement_evidence e
  where e.actual_lesson_id=any(v_ids_sorted)
  order by e.actual_lesson_id::text for share;
  if (select count(*) from public.school_legacy_planned_settlement_evidence e
      where e.planned_lesson_id=any(v_ids_sorted))<>7
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.planned_lesson_id::text))
         from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=any(v_ids_sorted))<>'11b2bfdadaf78e6b4d853044c64f576d'
     or (select count(*) from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids_sorted))<>4
     or (select md5(string_agg(md5(to_jsonb(e)::text),''
          order by e.actual_lesson_id::text))
         from public.school_legacy_actual_settlement_evidence e
         where e.actual_lesson_id=any(v_ids_sorted))<>'f5c2e715af4180af16576c32eb46f0ad' then
    raise exception using errcode='55000',message='REJECTED_MANIFEST_DRIFT:LEGACY_EVIDENCE';
  end if;

  if not exists(select 1 from pg_trigger where tgrelid=
       'public.school_lesson_records'::regclass
       and tgname='trg_school_lesson_writer_p0_validate' and tgenabled='O')
     or md5(pg_get_functiondef(
       'public.school_lesson_writer_p0_validate_row()'::regprocedure
     ))<>'e5ed12c9897e802fbcc8da699cc9ef5f'
     or md5(pg_get_functiondef(
       'public.school_sync_lesson_actual_minutes()'::regprocedure
     ))<>'87e7587d601f3fe1b2abdec35742e2cc'
     or md5(pg_get_functiondef(
       'public.school_tuition_p0b1_lesson_financial_authority()'::regprocedure
     ))<>'dbc0e193fdd42b940beae7677e1681a6'
     or md5(pg_get_functiondef(
       'public.school_resolve_r1d_e_c_lesson_student_month(uuid)'::regprocedure
     ))<>'d8a1f092429f9c4ad6918ee680514e4b'
     or (select relacl from pg_class where oid='public.school_lesson_records'::regclass)
       <>array['postgres=arwdDxtm/postgres','anon=r/postgres',
         'authenticated=r/postgres','service_role=r/postgres']::aclitem[] then
    raise exception using errcode='55000',message='REJECTED_DOWNSTREAM_DRIFT:P0_OR_ACL';
  end if;

  foreach v_table in array array[
    'school_business_entity_migration_items','school_planned_writer_commands',
    'school_student_settlement_lesson_variance_claims',
    'school_student_tuition_bill_lessons',
    'school_student_tuition_historical_lesson_exclusions',
    'school_tuition_billing_attribution_override_audit',
    'school_teacher_wage_lock_details','school_teacher_wage_detail_adjustments',
    'school_personal_cash_linkage_events','school_personal_cash_income_linkage_events',
    'school_account_transactions','school_expense_attachments'
  ] loop
    execute format(
      'select exists(select 1 from public.%I x where to_jsonb(x)::text like any($1))',
      v_table
    ) into v_has_ref using v_lesson_id_patterns;
    if v_has_ref then
      raise exception using errcode='55000',
        message='REJECTED_DOWNSTREAM_DRIFT:LESSON_REFERENCE:'||v_table;
    end if;
  end loop;

  if exists(select 1 from public.school_student_monthly_settlements x
       where x.student_id=v_student and x.year_month between '2026-09' and '2026-11')
     or exists(select 1 from public.school_student_settlement_adjustments x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_student_settlement_adjustment_drafts x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_student_settlement_carryovers x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_student_settlement_source_treatment_drafts x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_student_tuition_bills x
       where x.student_id=v_student and x.billing_month between '2026-09' and '2026-11')
     or exists(select 1 from public.school_student_tuition_billing_identities x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_student_tuition_generation_identities x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_income_records x
       where to_jsonb(x)::text like '%'||v_student::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%') then
    raise exception using errcode='55000',
      message='REJECTED_DOWNSTREAM_DRIFT:STUDENT_FINANCE';
  end if;

  if exists(select 1 from public.school_teacher_wage_locks x
       where x.teacher_id=v_teacher and x.settlement_month between '2026-09' and '2026-11')
     or exists(select 1 from public.school_salary_payments x
       where to_jsonb(x)::text like '%'||v_teacher::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_payment_requests x
       where to_jsonb(x)::text like '%'||v_teacher::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%')
     or exists(select 1 from public.school_expense_records x
       where to_jsonb(x)::text like '%'||v_teacher::text||'%'
         and to_jsonb(x)::text similar to '%2026-(09|10|11)%') then
    raise exception using errcode='55000',
      message='REJECTED_DOWNSTREAM_DRIFT:TEACHER_WAGE_OR_PAYMENT';
  end if;

  if exists(select 1 from public.school_import_batches x where
       to_jsonb(x)::text like '%lesson_import_20260526104852595_ztof7o%'
       or to_jsonb(x)::text like '%lesson_import_20260526010525470_q14wle%')
     or exists(select 1 from public.school_import_errors x where
       to_jsonb(x)::text like '%lesson_import_20260526104852595_ztof7o%'
       or to_jsonb(x)::text like '%lesson_import_20260526010525470_q14wle%') then
    raise exception using errcode='55000',message='REJECTED_DOWNSTREAM_DRIFT:IMPORT_BATCH';
  end if;

  perform set_config('app.school_lesson_exact_correction_context',v_batch,true);
  perform set_config('app.school_lesson_exact_correction_manifest',v_manifest_hash,true);
  perform set_config('app.school_lesson_exact_correction_action','exact_void_correction',true);
  perform set_config('app.school_lesson_exact_correction_actor',v_actor::text,true);

  foreach v_id in array v_actual_ids loop
    select to_jsonb(l),md5(to_jsonb(l)::text) into strict v_before,v_before_hash
    from public.school_lesson_records l where l.id=v_id;
    v_source_id:=(v_before->>'planned_lesson_id')::uuid;
    v_raw_before:=public.school_get_lesson_credit_raw_remaining_hours(v_source_id);
    update public.school_lesson_records l
    set voided_at=v_now,void_reason=v_reason
    where l.id=v_id;
    select to_jsonb(l),md5(to_jsonb(l)::text) into strict v_after,v_after_hash
    from public.school_lesson_records l where l.id=v_id;
    v_raw_after:=public.school_get_lesson_credit_raw_remaining_hours(v_source_id);
    if (v_after-array['voided_at','void_reason','updated_at'])
       is distinct from
       (v_before-array['voided_at','void_reason','updated_at']) then
      raise exception 'REJECTED_MANIFEST_DRIFT:UNEXPECTED_ACTUAL_MUTATION:%',v_id;
    end if;
    if v_raw_after<v_raw_before
       or (v_raw_before>=0 and v_raw_after<0) then
      raise exception using errcode='55000',
        message='REJECTED_MANIFEST_DRIFT:RAW_REMAINING_NOT_MONOTONIC:'||v_id,
        detail=format('source=%s before=%s after=%s',
          v_source_id,v_raw_before,v_raw_after);
    end if;
    insert into public.school_lesson_exact_correction_events(
      correction_batch_id,lesson_id,action,reason,before_row,after_row,
      before_hash,after_hash,manifest_hash,actor_user_id,created_at
    ) values(v_batch,v_id,'exact_void_correction',v_reason,v_before,v_after,
      v_before_hash,v_after_hash,v_manifest_hash,v_actor,v_now);
  end loop;

  if public.school_get_lesson_credit_raw_remaining_hours(
       'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid
     ) is distinct from 2::numeric then
    raise exception 'REJECTED_MANIFEST_DRIFT:INTERMEDIATE_REMAINING_HOURS';
  end if;

  foreach v_id in array v_linked_planned_ids||v_independent_planned_ids loop
    select to_jsonb(l),md5(to_jsonb(l)::text) into strict v_before,v_before_hash
    from public.school_lesson_records l where l.id=v_id;
    update public.school_lesson_records l
    set voided_at=v_now,void_reason=v_reason
    where l.id=v_id;
    select to_jsonb(l),md5(to_jsonb(l)::text) into strict v_after,v_after_hash
    from public.school_lesson_records l where l.id=v_id;
    if (v_after-array['voided_at','void_reason','updated_at'])
       is distinct from
       (v_before-array['voided_at','void_reason','updated_at']) then
      raise exception 'REJECTED_MANIFEST_DRIFT:UNEXPECTED_PLANNED_MUTATION:%',v_id;
    end if;
    insert into public.school_lesson_exact_correction_events(
      correction_batch_id,lesson_id,action,reason,before_row,after_row,
      before_hash,after_hash,manifest_hash,actor_user_id,created_at
    ) values(v_batch,v_id,'exact_void_correction',v_reason,v_before,v_after,
      v_before_hash,v_after_hash,v_manifest_hash,v_actor,v_now);
  end loop;

  if (select count(*) from public.school_lesson_exact_correction_events e
      where e.correction_batch_id=v_batch)<>11
     or (select count(*) from public.school_lesson_records l
         where l.id=any(v_ids_sorted) and l.voided_at=v_now
           and l.void_reason=v_reason)<>11 then
    raise exception 'REJECTED_MANIFEST_DRIFT:FINAL_WRITE_COUNT';
  end if;

  return query
  select e.correction_batch_id,'applied'::text,e.lesson_id,e.action,
    e.before_hash,e.after_hash,l.voided_at,'exact correction applied'::text
  from public.school_lesson_exact_correction_events e
  join public.school_lesson_records l on l.id=e.lesson_id
  where e.correction_batch_id=v_batch
  order by e.lesson_id::text;
end;
$function$;

alter function public.school_correct_li_wu_test_lessons_v1(text,text,text)
  owner to postgres;
revoke all on function public.school_correct_li_wu_test_lessons_v1(text,text,text)
  from public,anon,authenticated,service_role;
grant execute on function public.school_correct_li_wu_test_lessons_v1(text,text,text)
  to authenticated;

comment on function public.school_correct_li_wu_test_lessons_v1(text,text,text) is
  'Forward-only active-admin correction for the approved fixed 11-ID Li Tianlun + Wu Feng test lesson manifest. Preserves UUIDs, links, and immutable legacy evidence; no generic rollback/unvoid path.';

do $verify$
begin
  if pg_get_userbyid((select proowner from pg_proc where oid=
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)'::regprocedure))
       <>'postgres'
     or not (select prosecdef from pg_proc where oid=
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)'::regprocedure)
     or (select proconfig from pg_proc where oid=
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)'::regprocedure)
       <>array['search_path=pg_catalog, public']::text[]
     or has_function_privilege('public',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or has_function_privilege('anon',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or not has_function_privilege('authenticated',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or has_function_privilege('service_role',
       'public.school_correct_li_wu_test_lessons_v1(text,text,text)','execute')
     or (select count(*) from pg_trigger where tgrelid=
       'public.school_lesson_exact_correction_events'::regclass
       and tgname in (
         'trg_school_lesson_exact_correction_events_immutable_row',
         'trg_school_lesson_exact_correction_events_immutable_truncate'
       ) and tgenabled='O')<>2 then
    raise exception 'LI_WU_CORRECTION_RPC_CATALOG_VERIFY_FAILED';
  end if;
end;
$verify$;

commit;
select 'LI_WU_CORRECTION_TRIGGER_RPC_V6_DEPLOYED' result;
