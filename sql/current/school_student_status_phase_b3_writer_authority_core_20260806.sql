-- School V2 student monthly status Phase B3 writer authority cutover, 2026-08-06.
-- Reuses Phase A status resolver and existing DB billing-month authority.
-- Changes function definitions/comments/ACL only; no business-row DML.

create or replace function public.school_assert_student_active_at_business_month_v1(
  p_student_id uuid,
  p_target_month date,
  p_operation text default null
)
returns void
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $function$
declare
  v_status record;
begin
  select * into strict v_status
  from public.school_resolve_student_status_at_month_core_v1(
    p_student_id,
    p_target_month
  );

  if not v_status.is_active then
    raise exception using
      errcode = '22023',
      message = 'STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH',
      detail = format(
        'student_id=%s target_month=%s resolved_status=%s operation=%s',
        p_student_id,
        p_target_month,
        v_status.resolved_status,
        coalesce(nullif(trim(p_operation), ''), 'unspecified')
      );
  end if;
end;
$function$;

revoke all on function public.school_assert_student_active_at_business_month_v1(uuid,date,text)
  from public, anon, authenticated, service_role;

comment on function public.school_assert_student_active_at_business_month_v1(uuid,date,text) is
  'Phase B3 owner-only assertion over the Phase A sole-authority month resolver. It creates no second status authority and uses the approved no-event active fallback.';

create or replace function pg_temp.school_b3_replace_function_fragments(
  p_signature regprocedure,
  p_expected_md5 text,
  p_old_fragments text[],
  p_new_fragments text[]
)
returns text
language plpgsql
set search_path = pg_catalog, public
as $function$
declare
  v_definition text;
  v_index integer;
  v_occurrences integer;
begin
  if cardinality(p_old_fragments) is distinct from cardinality(p_new_fragments)
     or cardinality(p_old_fragments) is null then
    raise exception 'STUDENT_STATUS_B3_REPLACEMENT_ARRAY_INVALID:%', p_signature;
  end if;

  select pg_get_functiondef(p_signature::oid) into strict v_definition;
  if md5(v_definition) is distinct from p_expected_md5 then
    raise exception 'STUDENT_STATUS_B3_PREDEFINITION_DRIFT:%:%',
      p_signature, md5(v_definition);
  end if;

  for v_index in 1..cardinality(p_old_fragments) loop
    if p_old_fragments[v_index] is null or p_old_fragments[v_index] = '' then
      raise exception 'STUDENT_STATUS_B3_EMPTY_REPLACEMENT:%:%',p_signature,v_index;
    end if;
    v_occurrences := (
      length(v_definition) - length(replace(v_definition,p_old_fragments[v_index],''))
    ) / length(p_old_fragments[v_index]);
    if v_occurrences <> 1 then
      raise exception 'STUDENT_STATUS_B3_REPLACEMENT_COUNT:%:%:%',
        p_signature,v_index,v_occurrences;
    end if;
    v_definition := replace(
      v_definition,
      p_old_fragments[v_index],
      coalesce(p_new_fragments[v_index],'')
    );
  end loop;

  execute v_definition;
  return md5(pg_get_functiondef(p_signature::oid));
end;
$function$;

select pg_temp.school_b3_replace_function_fragments(
  'public.school_build_student_tuition_generation_snapshot(uuid,text,numeric)'::regprocedure,
  '083bcb58c2b92f34ded07dceafbbbbfe',
  array[$old$
  IF coalesce(v_student.status,'') IN ('inactive','disabled','archived') THEN
    RAISE EXCEPTION 'R2_F_B_STUDENT_INACTIVE';
  END IF;$old$],
  array['']
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text)'::regprocedure,
  '5cd35ca2bcbeff1f0b32e46e89d4a2cb',
  array[$old$
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');$old$],
  array[$new$
    and s.app_type = 'school';$new$]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure,
  '726c3f76786167bc70cb40b0ec9be613',
  array[$old$
    and student.app_type = 'school'
    and coalesce(student.status, 'active') not in ('inactive', 'graduated');$old$],
  array[$new$
    and student.app_type = 'school';$new$]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure,
  'e46c39ab2b35f9cc69b358402350ca17',
  array[$old$
      AND coalesce(s.status,'active') NOT IN ('inactive','graduated')$old$],
  array['']
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text)'::regprocedure,
  '5e9138050f2c1a83bbca9eb605dde9ea',
  array[$old$
      and coalesce(s.status, 'active') not in ('inactive', 'graduated')$old$],
  array['']
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text)'::regprocedure,
  'f969a00b87a6e584d4b0696f8076208f',
  array[
    $old$  v_student_business_entity_id uuid;$old$,
    $old$
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');$old$,
    $old$
  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null$old$,
    $old$ SET search_path TO 'public'$old$
  ],
  array[
    $new$  v_student_business_entity_id uuid;
  v_student_status_month text;$new$,
    $new$
    and s.app_type = 'school';$new$,
    $new$
  if not found then
    raise exception '学生无效或不可用。';
  end if;

  select attribution.billing_month into strict v_student_status_month
  from public.school_resolve_planned_billing_attribution(p_lesson_date,null) attribution;
  perform public.school_assert_student_active_at_business_month_v1(
    p_student_id,
    to_date(v_student_status_month || '-01','YYYY-MM-DD'),
    format('planned_create lesson_date=%s billing_month=%s',p_lesson_date,v_student_status_month)
  );

  if v_student_business_entity_id is not null$new$,
    $new$ SET search_path TO 'pg_catalog', 'public'$new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure,
  '09095668a484d00b9776f90d9f290610',
  array[
    $old$
      and coalesce(s.app_type, '') = 'school'
      and coalesce(s.status, '') not in ('inactive', 'graduated', 'withdrawn')$old$,
    $old$
  ) then
    raise exception '学生不存在或不可用于新增工资规则。';
  end if;

  if exists ($old$
  ],
  array[
    $new$
      and coalesce(s.app_type, '') = 'school'$new$,
    $new$
  ) then
    raise exception '学生不存在或不可用于新增工资规则。';
  end if;

  perform public.school_assert_student_active_at_business_month_v1(
    p_student_id,
    date_trunc('month',clock_timestamp() at time zone 'Asia/Tokyo')::date,
    'teacher_wage_rule_create'
  );

  if exists ($new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text)'::regprocedure,
  'c4f710f9599140d443b8213ebab3855e',
  array[
    $old$
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');$old$,
    $old$
  if v_row_count > 500 then
    raise exception '单次最多生成 500 条预定课时。';
  end if;

  update planned_lesson_generation_rows r
  set errors = r.errors || array['目标学生月度结算已锁定，不能生成预定课时。']$old$,
    $old$ SET search_path TO 'public'$old$
  ],
  array[
    $new$
    and s.app_type = 'school';$new$,
    $new$
  if v_row_count > 500 then
    raise exception '单次最多生成 500 条预定课时。';
  end if;

  with inactive_occurrences as (
    select r.row_index,r.lesson_date,attribution.billing_month,status.resolved_status
    from planned_lesson_generation_rows r
    cross join lateral public.school_resolve_planned_billing_attribution(null,r.lesson_date) attribution
    cross join lateral public.school_resolve_student_status_at_month_core_v1(
      p_student_id,
      to_date(attribution.billing_month || '-01','YYYY-MM-DD')
    ) status
    where not status.is_active
  )
  update planned_lesson_generation_rows r
  set errors = r.errors || array[format(
    'STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH student_id=%s lesson_date=%s billing_month=%s resolved_status=%s',
    p_student_id,i.lesson_date,i.billing_month,i.resolved_status
  )]
  from inactive_occurrences i
  where i.row_index=r.row_index;

  update planned_lesson_generation_rows r
  set errors = r.errors || array['目标学生月度结算已锁定，不能生成预定课时。']$new$,
    $new$ SET search_path TO 'pg_catalog', 'public'$new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text)'::regprocedure,
  '95030c052cdc39dd4f73344869509239',
  array[
    $old$
        and s.app_type = 'school'
        and coalesce(s.status, 'active') not in ('inactive', 'graduated')$old$,
    $old$
      and s.app_type = 'school'
      and coalesce(s.status, 'active') not in ('inactive', 'graduated')
      and s.business_entity_id is not null$old$,
    $old$
  update lesson_import_rows r
  set errors = r.errors || array['老师无效或不可用。']$old$,
    $old$ SET search_path TO 'public'$old$
  ],
  array[
    $new$
        and s.app_type = 'school'$new$,
    $new$
      and s.app_type = 'school'
      and s.business_entity_id is not null$new$,
    $new$
  with inactive_import_rows as (
    select r.ctid as row_tid,r.student_id,r.lesson_date,
           attribution.billing_month,status.resolved_status
    from lesson_import_rows r
    cross join lateral public.school_resolve_planned_billing_attribution(r.lesson_date,null) attribution
    cross join lateral public.school_resolve_student_status_at_month_core_v1(
      r.student_id,
      to_date(attribution.billing_month || '-01','YYYY-MM-DD')
    ) status
    where r.student_id is not null
      and r.lesson_date is not null
      and exists (
        select 1 from public.school_students s
        where s.id=r.student_id and s.app_type='school'
      )
      and not status.is_active
  )
  update lesson_import_rows r
  set errors = r.errors || array[format(
    'STUDENT_NOT_ACTIVE_AT_BUSINESS_MONTH student_id=%s lesson_date=%s billing_month=%s resolved_status=%s',
    i.student_id,i.lesson_date,i.billing_month,i.resolved_status
  )]
  from inactive_import_rows i
  where r.ctid=i.row_tid;

  update lesson_import_rows r
  set errors = r.errors || array['老师无效或不可用。']$new$,
    $new$ SET search_path TO 'pg_catalog', 'public'$new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_preview_student_tuition_bill(uuid,text,numeric)'::regprocedure,
  '8e9496463c1d54247f25042be3f6e5c5',
  array[
    $old$
  IF coalesce(v_student.status,'') IN ('inactive','disabled','archived') THEN
    RAISE EXCEPTION '学生已停用，不能生成学费应收。';
  END IF;$old$,
    $old$ SET search_path TO 'public'$old$
  ],
  array[
    '',
    $new$ SET search_path TO 'pg_catalog', 'public'$new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text)'::regprocedure,
  'f0f003006e6989c046a8139f7b123795',
  array[
    $old$  v_student_business_entity_id uuid;$old$,
    $old$
    if exists (
         select 1 from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_active_student_tuition_bill_lessons r
         where r.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_student_tuition_bills b
         where (b.source_snapshot -> 'planned_lesson_ids') ? v_lesson.id::text
       ) then
      v_year_month := v_old_year_month;
    else
      v_year_month := to_char(p_lesson_date, 'YYYY-MM');
    end if;$old$,
    $old$
    and s.app_type = 'school'
    and coalesce(s.status, 'active') not in ('inactive', 'graduated');$old$,
    $old$
  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_student_business_entity_id is not null$old$
  ],
  array[
    $new$  v_student_business_entity_id uuid;
  v_target_student_status_month text;$new$,
    $new$
    if exists (
         select 1 from public.school_legacy_planned_settlement_evidence e
         where e.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_active_student_tuition_bill_lessons r
         where r.planned_lesson_id=v_lesson.id
       ) or exists (
         select 1 from public.school_student_tuition_bills b
         where (b.source_snapshot -> 'planned_lesson_ids') ? v_lesson.id::text
       ) then
      v_year_month := v_old_year_month;
      v_target_student_status_month := v_old_year_month;
    else
      v_year_month := to_char(p_lesson_date, 'YYYY-MM');
      select attribution.billing_month into strict v_target_student_status_month
      from public.school_resolve_planned_billing_attribution(p_lesson_date,null) attribution;
    end if;$new$,
    $new$
    and s.app_type = 'school';$new$,
    $new$
  if not found then
    raise exception '学生无效或不可用。';
  end if;

  if v_lesson.lesson_type='planned'
     and (
       p_student_id is distinct from v_lesson.student_id
       or v_target_student_status_month is distinct from v_old_year_month
     ) then
    perform public.school_assert_student_active_at_business_month_v1(
      p_student_id,
      to_date(v_target_student_status_month || '-01','YYYY-MM-DD'),
      format(
        'planned_update lesson_id=%s lesson_date=%s billing_month=%s',
        v_lesson.id,p_lesson_date,v_target_student_status_month
      )
    );
  end if;

  if v_student_business_entity_id is not null$new$
  ]
);

select pg_temp.school_b3_replace_function_fragments(
  'public.school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text)'::regprocedure,
  'ed1929ef774f1d7f244222512bf54d44',
  array[
    $old$
      and coalesce(s.app_type, '') = 'school'
      and coalesce(s.status, '') not in ('inactive', 'graduated', 'withdrawn')$old$,
    $old$
  if p_student_id = v_rule.student_id and not exists (
    select 1
    from public.school_students s
    where s.id = p_student_id
      and coalesce(s.app_type, '') = 'school'
  ) then
    raise exception '学生不存在。';
  end if;

  if ($old$
  ],
  array[
    $new$
      and coalesce(s.app_type, '') = 'school'$new$,
    $new$
  if p_student_id = v_rule.student_id and not exists (
    select 1
    from public.school_students s
    where s.id = p_student_id
      and coalesce(s.app_type, '') = 'school'
  ) then
    raise exception '学生不存在。';
  end if;

  if p_student_id is distinct from v_rule.student_id
     or (v_rule.is_active is not true and p_is_active is true) then
    perform public.school_assert_student_active_at_business_month_v1(
      p_student_id,
      date_trunc('month',clock_timestamp() at time zone 'Asia/Tokyo')::date,
      case
        when p_student_id is distinct from v_rule.student_id then 'teacher_wage_rule_change_student'
        else 'teacher_wage_rule_reactivate'
      end
    );
  end if;

  if ($new$
  ]
);

comment on function public.school_create_planned_lesson_record_r1d_f1_legacy_core(date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,integer,text,text) is
  'Phase B3: new planned fact requires resolver-active at its DB billing month; all prior fee, attribution, settlement and lock contracts remain.';
comment on function public.school_generate_planned_lessons_batch_r1d_f1_legacy_core(uuid,uuid,uuid,date,date,jsonb,jsonb,text) is
  'Phase B3: every expanded occurrence independently resolves its DB billing month and must be active; any error keeps the whole batch uncommitted.';
comment on function public.school_import_lesson_records_batch_r1d_f1_legacy_core(uuid,text,text,jsonb,text) is
  'Phase B3: every planned import row independently resolves its DB billing month and must be active; any error keeps the whole import uncommitted.';
comment on function public.school_update_lesson_record_guarded(uuid,timestamp with time zone,date,uuid,uuid,uuid,uuid,text,text,numeric,numeric,numeric,text,boolean,integer,text,text) is
  'Phase B3: planned student/month changes require resolver-active at the target DB billing month; same-student same-month historical correction and linked actual correction are not status-gated.';
comment on function public.school_create_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,numeric,integer,text,text) is
  'Phase B3: fulfils an existing planned fact without consulting frozen school_students.status; existing locks, attribution and overage contracts remain.';
comment on function public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text) is
  'Phase B3: cancellation fulfils an existing planned fact without student-status gating; Phase 20260806 admin/operator, DB-duration, zero-fee, pending-makeup and concurrency contracts remain.';
comment on function public.school_create_partial_completed_actual_from_planned(uuid,date,text,text,numeric,text,text) is
  'Phase B3: partial completion of an existing planned fact is not student-status-gated; existing locks and credit contracts remain.';
comment on function public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text) is
  'Phase B3: makeup fulfilment of an existing planned/source fact is not student-status-gated; student month stays source-owned and teacher month stays actual-date-owned.';
comment on function public.school_create_teacher_wage_rule_config(uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text) is
  'Phase B3: every new wage rule requires resolver-active student at the DB Tokyo current month; permission and financial contracts remain.';
comment on function public.school_update_teacher_wage_rule_config(uuid,uuid,uuid,uuid,uuid,text,numeric,numeric,numeric,numeric,numeric,boolean,text) is
  'Phase B3: changing student or reactivating a wage rule requires resolver-active at DB Tokyo current month; same-student correction and deactivation remain allowed.';
comment on function public.school_build_student_tuition_generation_snapshot(uuid,text,numeric) is
  'Phase B3: existing tuition facts are governed by lesson, settlement, bill, income, immutable and Gate contracts; frozen legacy student status is not an eligibility authority.';
comment on function public.school_preview_student_tuition_bill(uuid,text,numeric) is
  'Phase B3: tuition preview and financial closeout are not blocked by paused/left status; existing candidate, settlement, bill, income and Gate contracts remain.';

notify pgrst, 'reload schema';
