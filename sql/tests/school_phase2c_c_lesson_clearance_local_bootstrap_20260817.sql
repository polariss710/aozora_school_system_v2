-- Isolated PostgreSQL bootstrap for School V2 Phase 2C-C.
-- Never point this file at production. The harness creates a disposable cluster/database.
\set ON_ERROR_STOP on

create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;
create schema if not exists auth;

do $roles$
begin
  if not exists(select 1 from pg_roles where rolname='postgres') then create role postgres superuser nologin; end if;
  if not exists(select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists(select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
  if not exists(select 1 from pg_roles where rolname='service_role') then create role service_role nologin; end if;
end
$roles$;

create function auth.uid() returns uuid language sql stable as $function$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$function$;
grant usage on schema auth to anon,authenticated,service_role;
grant execute on function auth.uid() to anon,authenticated,service_role;

create table public.school_business_entities(
  id uuid primary key,name text not null
);
create table public.school_students(
  id uuid primary key,business_entity_id uuid not null references public.school_business_entities(id),
  name text not null,status text not null,app_type text not null default 'school'
);
create table public.school_app_memberships(
  user_id uuid primary key,role text not null,is_active boolean not null
);
create table public.school_lesson_records(
  id uuid primary key,
  app_type text not null default 'school',
  lesson_type text not null,
  status text not null,
  student_id uuid not null references public.school_students(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  teacher_id uuid,
  subject_id uuid,
  planned_lesson_id uuid references public.school_lesson_records(id),
  lesson_date date not null,
  start_time text,
  end_time text,
  duration_hours numeric not null,
  actual_minutes integer,
  lesson_count integer,
  unit_price numeric,
  lesson_fee numeric,
  base_lesson_fee_jpy numeric,
  is_billable boolean,
  year_month text,
  student_settlement_month text,
  teacher_settlement_month text,
  lesson_content text,
  note text,
  lesson_delivery_mode text,
  lesson_venue text,
  voided_at timestamptz,
  student_duration_overage_minutes integer,
  student_duration_overage_fee_jpy numeric,
  student_duration_overage_policy_version text,
  student_duration_overage_source text,
  created_at timestamptz not null default transaction_timestamp(),
  updated_at timestamptz not null default transaction_timestamp()
);
create table public.school_student_monthly_settlements(
  id uuid primary key,student_id uuid not null,business_entity_id uuid not null,
  year_month text not null,settlement_status text not null
);
create table public.school_student_settlement_lesson_variance_claims(
  id uuid primary key default gen_random_uuid(),
  claim_status text not null,source_type text not null,
  source_planned_lesson_id uuid,source_actual_lesson_id uuid
);
create table public.school_student_tuition_bills(
  id uuid primary key,student_id uuid,business_entity_id uuid,billing_month text,
  bill_amount_jpy numeric
);
create table public.school_student_tuition_bill_lessons(
  id uuid primary key,tuition_bill_id uuid references public.school_student_tuition_bills(id),
  planned_lesson_id uuid references public.school_lesson_records(id)
);
create table public.school_student_tuition_generation_revisions(
  id uuid primary key,tuition_bill_id uuid references public.school_student_tuition_bills(id),
  lifecycle_status text
);
create table public.school_income_records(
  id uuid primary key,tuition_bill_id uuid references public.school_student_tuition_bills(id),
  amount numeric,status text
);
create table public.school_personal_cash_income_linkage_events(
  id uuid primary key,income_record_id uuid references public.school_income_records(id),
  sync_status text
);
create table public.school_student_package_credit_lots(
  id uuid primary key,
  origin_planned_lesson_id uuid not null references public.school_lesson_records(id),
  student_id uuid not null references public.school_students(id),
  business_entity_id uuid not null references public.school_business_entities(id),
  initial_minutes integer not null,consumed_minutes integer not null default 0,
  remaining_minutes integer generated always as (initial_minutes-consumed_minutes) stored,
  unit_price_jpy numeric not null,total_price_jpy numeric not null,
  student_billing_month text not null,tuition_bill_id uuid not null,
  tuition_revision_id uuid not null,income_record_id uuid not null,
  cash_linkage_event_id uuid not null,cash_request_id_snapshot uuid not null,
  cash_transaction_id_snapshot uuid not null,status text not null,
  classification_reason text not null,origin_lesson_row_md5 text not null,
  evidence_manifest_sha256 text not null,classified_by text not null,
  created_at timestamptz not null default transaction_timestamp()
);
alter table public.school_student_package_credit_lots owner to postgres;
create unique index school_package_credit_lots_active_origin_uidx
  on public.school_student_package_credit_lots(origin_planned_lesson_id)
  where status='active';
create index school_package_credit_lots_student_idx
  on public.school_student_package_credit_lots(
    student_id,business_entity_id,status,created_at,id
  );
alter table public.school_student_package_credit_lots enable row level security;
revoke all on public.school_student_package_credit_lots
  from public,anon,authenticated,service_role;

create function public.school_prevent_package_credit_lot_mutation()
returns trigger language plpgsql security definer
set search_path=pg_catalog,public as $function$
begin
  raise exception using errcode='55000',message='LESSON_PACKAGE_LOT_APPEND_ONLY';
end
$function$;
alter function public.school_prevent_package_credit_lot_mutation() owner to postgres;
revoke all on function public.school_prevent_package_credit_lot_mutation()
  from public,anon,authenticated,service_role;
create trigger school_package_credit_lots_append_only
before update or delete on public.school_student_package_credit_lots
for each row execute function public.school_prevent_package_credit_lot_mutation();
create trigger school_package_credit_lots_truncate_guard
before truncate on public.school_student_package_credit_lots
for each statement execute function public.school_prevent_package_credit_lot_mutation();

create function public.school_is_active_package_credit_origin(p_planned_lesson_id uuid)
returns boolean language sql stable security definer set search_path=pg_catalog,public
as $function$
  select exists(select 1 from public.school_student_package_credit_lots lot
    where lot.origin_planned_lesson_id=p_planned_lesson_id and lot.status='active')
$function$;
create function public.school_list_student_package_credit_lots(p_student_id uuid default null)
returns table(package_lot_id uuid,origin_planned_lesson_id uuid,student_id uuid,
  business_entity_id uuid,initial_minutes integer,consumed_minutes integer,
  remaining_minutes integer,unit_price_jpy numeric,total_price_jpy numeric,
  student_billing_month text,status text,classification_reason text,created_at timestamptz)
language plpgsql stable security definer set search_path=pg_catalog,public as $function$
declare
  v_actor uuid:=auth.uid();
  v_role text;
  v_active boolean;
begin
  if v_actor is null then raise exception using errcode='42501',message='PACKAGE_READER_AUTH_REQUIRED'; end if;
  select membership.role,membership.is_active into v_role,v_active
  from public.school_app_memberships membership where membership.user_id=v_actor;
  if not found then raise exception using errcode='42501',message='PACKAGE_READER_MEMBERSHIP_REQUIRED'; end if;
  if v_active is distinct from true then raise exception using errcode='42501',message='PACKAGE_READER_ACTIVE_MEMBERSHIP_REQUIRED'; end if;
  if v_role not in ('admin','operator','read_only') then
    raise exception using errcode='42501',message='PACKAGE_READER_ROLE_REQUIRED';
  end if;
  return query select lot.id,lot.origin_planned_lesson_id,lot.student_id,
    lot.business_entity_id,lot.initial_minutes,lot.consumed_minutes,
    lot.remaining_minutes,lot.unit_price_jpy,lot.total_price_jpy,
    lot.student_billing_month,lot.status,lot.classification_reason,lot.created_at
  from public.school_student_package_credit_lots lot
  where lot.status='active' and (p_student_id is null or lot.student_id=p_student_id)
  order by lot.student_id,lot.created_at,lot.id;
end
$function$;
alter function public.school_is_active_package_credit_origin(uuid) owner to postgres;
alter function public.school_list_student_package_credit_lots(uuid) owner to postgres;
revoke all on function public.school_is_active_package_credit_origin(uuid)
  from public,anon,authenticated,service_role;
revoke all on function public.school_list_student_package_credit_lots(uuid)
  from public,anon,authenticated,service_role;
grant execute on function public.school_list_student_package_credit_lots(uuid)
  to authenticated;

create function public.school_resolve_r1d_e_c_lesson_student_month(p_lesson_id uuid)
returns text language sql stable as $function$
  select coalesce(lesson.student_settlement_month,lesson.year_month)
  from public.school_lesson_records lesson where lesson.id=p_lesson_id
$function$;
create function public.school_tuition_p0a_lock_settlement_mutation_scope(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text
)
returns void language plpgsql as $function$
begin
  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
    p_student_id::text,p_business_entity_id::text,p_year_month),0));
end
$function$;

create function public.school_get_lesson_credit_raw_remaining_hours(p_planned_lesson_id uuid)
returns numeric language sql stable security definer set search_path=pg_catalog,public as $function$
  select planned.duration_hours-coalesce(sum(actual.duration_hours) filter(
    where actual.lesson_type='actual'
      and actual.status in ('completed','makeup_completed')
      and actual.voided_at is null),0)
  from public.school_lesson_records planned
  left join public.school_lesson_records actual on actual.planned_lesson_id=planned.id
  where planned.id=p_planned_lesson_id and planned.app_type='school'
    and planned.lesson_type='planned'
  group by planned.id,planned.duration_hours
$function$;
create function public.school_get_lesson_credit_remaining_hours(p_planned_lesson_id uuid)
returns numeric language sql stable set search_path=public as $function$
  select greatest(coalesce(planned.duration_hours,0)-coalesce(sum(actual.duration_hours)
    filter(where actual.lesson_type='actual'
      and actual.status in ('completed','makeup_completed')),0),0)
  from public.school_lesson_records planned
  left join public.school_lesson_records actual
    on actual.planned_lesson_id=planned.id and actual.app_type='school'
  where planned.id=p_planned_lesson_id and planned.app_type='school'
    and planned.lesson_type='planned'
  group by planned.id,planned.duration_hours
$function$;
create function public.school_list_student_lesson_credit_balances(p_student_id uuid default null)
returns table(student_id uuid,business_entity_id uuid,open_source_count bigint,
  open_credit_hours numeric,oldest_credit_date date)
language sql stable set search_path=public as $function$
  with sources as (
    select planned.id,planned.student_id,planned.business_entity_id,planned.lesson_date,
      greatest(public.school_get_lesson_credit_raw_remaining_hours(planned.id),0) remaining
    from public.school_lesson_records planned
    where planned.lesson_type='planned' and planned.status='pending_makeup'
      and planned.voided_at is null
      and (p_student_id is null or planned.student_id=p_student_id)
  ) select source.student_id,source.business_entity_id,
    count(*) filter(where source.remaining>0),
    coalesce(sum(source.remaining) filter(where source.remaining>0),0),
    min(source.lesson_date) filter(where source.remaining>0)
  from sources source group by source.student_id,source.business_entity_id
$function$;
create function public.school_get_lesson_credit_summary(
  p_student_id uuid default null,p_business_entity_id uuid default null
)
returns table(open_source_count bigint,open_credit_hours numeric)
language sql stable set search_path=public as $function$
  select coalesce(sum(balance.open_source_count),0)::bigint,
    coalesce(sum(balance.open_credit_hours),0)::numeric
  from public.school_list_student_lesson_credit_balances(p_student_id) balance
  where p_business_entity_id is null
    or balance.business_entity_id is not distinct from p_business_entity_id
$function$;
create function public.school_list_open_lesson_credit_sources(
  p_from_month text,p_to_month text,p_target_month text
)
returns table(id uuid,lesson_date date,year_month text,student_id uuid,teacher_id uuid,
  subject_id uuid,business_entity_id uuid,start_time text,end_time text,duration_hours numeric,
  lesson_content text,note text,lesson_count integer,unit_price numeric,
  lesson_delivery_mode text,lesson_venue text,remaining_hours numeric)
language sql stable security definer set search_path=pg_catalog,public as $function$
  select planned.id,planned.lesson_date,
    public.school_resolve_r1d_e_c_lesson_student_month(planned.id),planned.student_id,
    planned.teacher_id,planned.subject_id,planned.business_entity_id,
    planned.start_time,planned.end_time,planned.duration_hours,planned.lesson_content,
    planned.note,planned.lesson_count,planned.unit_price,
    planned.lesson_delivery_mode,planned.lesson_venue,
    public.school_get_lesson_credit_raw_remaining_hours(planned.id)
  from public.school_lesson_records planned
  where planned.lesson_type='planned' and planned.status='pending_makeup'
    and planned.voided_at is null
    and public.school_resolve_r1d_e_c_lesson_student_month(planned.id)
      between p_from_month and p_to_month
    and public.school_get_lesson_credit_raw_remaining_hours(planned.id)>0
    and not exists(select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_type='unused_planned_credit_v1'
        and claim.source_planned_lesson_id=planned.id)
  order by 3,2,planned.id
$function$;

create function public.school_tuition_p0f_source_lines(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text,
  p_settlement_exchange_rate numeric,p_include_active_claimed boolean default false
)
returns table(source_type text,source_planned_lesson_id uuid,source_actual_lesson_id uuid,
  source_hours numeric,source_amount_jpy numeric,source_amount_cny numeric,
  line_manifest_sha256 text)
language sql stable security definer set search_path=pg_catalog,public as $function$
  select 'unused_planned_credit_v1',planned.id,null::uuid,
    -public.school_get_lesson_credit_remaining_hours(planned.id),
    -round(planned.lesson_fee*public.school_get_lesson_credit_remaining_hours(planned.id)
      /nullif(planned.duration_hours,0),2),
    -round(planned.lesson_fee*public.school_get_lesson_credit_remaining_hours(planned.id)
      /nullif(planned.duration_hours,0)*p_settlement_exchange_rate,2),
    encode(extensions.digest(planned.id::text,'sha256'),'hex')
  from public.school_lesson_records planned
  where planned.student_id=p_student_id and planned.business_entity_id=p_business_entity_id
    and planned.status='pending_makeup' and planned.lesson_type='planned'
    and public.school_resolve_r1d_e_c_lesson_student_month(planned.id)=p_year_month
    and public.school_get_lesson_credit_remaining_hours(planned.id)>0
    and (p_include_active_claimed or not exists(
      select 1 from public.school_student_settlement_lesson_variance_claims claim
      where claim.claim_status='active' and claim.source_planned_lesson_id=planned.id))
$function$;

create function public.school_tuition_p0f_assert_sources_resolved(
  p_student_id uuid,p_business_entity_id uuid,p_year_month text
)
returns void language plpgsql stable security definer
set search_path=pg_catalog,public as $function$
declare v_lesson_id uuid;
begin
  select planned.id into v_lesson_id
  from public.school_lesson_records planned
  where planned.app_type='school' and planned.lesson_type='planned'
    and planned.student_id=p_student_id
    and planned.business_entity_id=p_business_entity_id
    and public.school_resolve_r1d_e_c_lesson_student_month(planned.id)=p_year_month
    and planned.voided_at is null
    and coalesce(planned.is_billable,true) is true
    and planned.status not in (
      'pending_makeup','makeup_completed','completed','cancelled'
    )
    and not exists(
      select 1 from public.school_lesson_records actual_row
      where actual_row.app_type='school' and actual_row.lesson_type='actual'
        and actual_row.planned_lesson_id=planned.id
        and (actual_row.status in ('completed','makeup_completed','cancelled')
          or actual_row.is_billable is false)
    )
  order by planned.id limit 1;
  if v_lesson_id is not null then
    raise exception 'SETTLEMENT_LESSON_SOURCE_UNRESOLVED: %',v_lesson_id;
  end if;
end
$function$;

create function public.school_create_lesson_credit_makeup_actual(
  p_planned_lesson_id uuid,p_lesson_date date,p_teacher_id uuid,p_subject_id uuid,
  p_start_time text,p_end_time text,p_duration_hours numeric,p_lesson_content text,
  p_note text,p_lesson_count integer,p_lesson_delivery_mode text,p_lesson_venue text
)
returns table(lesson_id uuid)
language plpgsql security definer set search_path=pg_catalog,public as $function$
declare v_source public.school_lesson_records%rowtype;v_id uuid:=gen_random_uuid();
begin
  select * into strict v_source from public.school_lesson_records
  where id=p_planned_lesson_id for update;
  if public.school_is_active_package_credit_origin(v_source.id) then
    raise exception using errcode='55000',message='LESSON_PACKAGE_CREDIT_MAKEUP_FORBIDDEN';
  end if;
  insert into public.school_lesson_records(
    id,app_type,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
    planned_lesson_id,lesson_date,start_time,end_time,duration_hours,actual_minutes,
    unit_price,lesson_fee,is_billable,year_month,student_settlement_month,
    teacher_settlement_month,lesson_content,note,lesson_count,
    lesson_delivery_mode,lesson_venue
  ) values (
    v_id,'school','actual','makeup_completed',v_source.student_id,
    v_source.business_entity_id,p_teacher_id,p_subject_id,p_planned_lesson_id,
    p_lesson_date,p_start_time,p_end_time,p_duration_hours,round(p_duration_hours*60),
    0,0,false,to_char(p_lesson_date,'YYYY-MM'),v_source.student_settlement_month,
    to_char(p_lesson_date,'YYYY-MM'),p_lesson_content,p_note,p_lesson_count,
    p_lesson_delivery_mode,p_lesson_venue
  );
  return query select v_id;
end
$function$;

grant execute on function public.school_get_lesson_credit_remaining_hours(uuid),
  public.school_list_student_lesson_credit_balances(uuid),
  public.school_get_lesson_credit_summary(uuid,uuid),
  public.school_list_open_lesson_credit_sources(text,text,text),
  public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)
to anon,authenticated,service_role;
grant execute on function public.school_create_lesson_credit_makeup_actual(
  uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text
) to authenticated;

insert into public.school_business_entities(id,name) values
  ('20000000-0000-4000-8000-000000000001','codex-test Phase2C-A entity A'),
  ('20000000-0000-4000-8000-000000000002','codex-test Phase2C-A entity B'),
  ('2cf7b72f-6e3c-4d09-80f7-7c58593cd466','青空进学塾 fixture');
insert into public.school_students(id,business_entity_id,name,status) values
  ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','codex-test 学生A','active'),
  ('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','codex-test 学生B','active'),
  ('10000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002','codex-test 学生C','active'),
  ('10000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000001','codex-test 暂停学生','paused'),
  ('a7b163a0-201e-4867-9b94-372343356a80','2cf7b72f-6e3c-4d09-80f7-7c58593cd466','李天伦 fixture','active');
insert into public.school_app_memberships(user_id,role,is_active) values
  ('90000000-0000-4000-8000-000000000001','admin',true),
  ('90000000-0000-4000-8000-000000000002','operator',true),
  ('90000000-0000-4000-8000-000000000003','read_only',true),
  ('90000000-0000-4000-8000-000000000004','admin',false);

-- Pending fixtures: P1 is FIFO first; P2 is second and cross teacher/subject;
-- P3 has a different price; P4/P5 violate student/entity; P6 is locked;
-- P7 is paused and supports admin writeoff; P8 has an ordinary makeup consumption.
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,duration_hours,unit_price,lesson_fee,is_billable,year_month,
  student_settlement_month,created_at,updated_at
) values
  ('30000000-0000-4000-8000-000000000001','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-01',2,10000,20000,true,'2026-01','2026-01','2026-01-01 00:00+00','2026-01-02 00:00+00'),
  ('30000000-0000-4000-8000-000000000002','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000002','72000000-0000-4000-8000-000000000002','2026-01-02',2,10000,20000,true,'2026-01','2026-01','2026-01-02 00:00+00','2026-01-03 00:00+00'),
  ('30000000-0000-4000-8000-000000000003','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-03',2,12000,24000,true,'2026-01','2026-01','2026-01-03 00:00+00','2026-01-04 00:00+00'),
  ('30000000-0000-4000-8000-000000000004','planned','pending_makeup','10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-01',2,10000,20000,true,'2026-01','2026-01','2026-01-01 00:00+00','2026-01-02 00:00+00'),
  ('30000000-0000-4000-8000-000000000005','planned','pending_makeup','10000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-01',2,10000,20000,true,'2026-01','2026-01','2026-01-01 00:00+00','2026-01-02 00:00+00'),
  ('30000000-0000-4000-8000-000000000006','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2025-12-15',2,10000,20000,true,'2025-12','2025-12','2025-12-15 00:00+00','2025-12-16 00:00+00'),
  ('30000000-0000-4000-8000-000000000007','planned','pending_makeup','10000000-0000-4000-8000-000000000004','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-04',2,10000,20000,true,'2026-01','2026-01','2026-01-04 00:00+00','2026-01-05 00:00+00'),
  ('30000000-0000-4000-8000-000000000008','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-05',2,10000,20000,true,'2026-01','2026-01','2026-01-05 00:00+00','2026-01-06 00:00+00'),
  ('30000000-0000-4000-8000-000000000009','planned','pending_makeup','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000002','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-01-07',2,10000,20000,true,'2026-01','2026-01','2026-01-07 00:00+00','2026-01-08 00:00+00');

insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  planned_lesson_id,lesson_date,duration_hours,actual_minutes,unit_price,lesson_fee,
  is_billable,year_month,student_settlement_month,created_at,updated_at
) values
  ('40000000-0000-4000-8000-000000000001','actual','cancelled','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000001','2026-01-01',2,0,0,0,false,'2026-01','2026-01','2026-01-02 12:00+00','2026-01-02 12:00+00'),
  ('40000000-0000-4000-8000-000000000008','actual','makeup_completed','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','30000000-0000-4000-8000-000000000008','2026-01-06',0.5,30,0,0,false,'2026-01','2026-01','2026-01-06 12:00+00','2026-01-06 12:00+00');

-- Four available overtime fixtures; O1 crosses teacher/subject and has 120 minutes.
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,duration_hours,actual_minutes,unit_price,lesson_fee,is_billable,
  year_month,student_settlement_month,student_duration_overage_minutes,
  student_duration_overage_fee_jpy,student_duration_overage_policy_version,
  student_duration_overage_source,created_at,updated_at
) values
  ('40000000-0000-4000-8000-000000000101','actual','completed','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000009','72000000-0000-4000-8000-000000000009','2026-02-01',4,240,10000,40000,true,'2026-02','2026-02',120,20000,'student_duration_overage_v1','ordinary_actual_rpc','2026-02-01 12:00+00','2026-02-01 12:00+00'),
  ('40000000-0000-4000-8000-000000000102','actual','completed','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-02-02',3,180,10000,30000,true,'2026-02','2026-02',60,10000,'student_duration_overage_v1','ordinary_actual_rpc','2026-02-02 12:00+00','2026-02-02 12:00+00'),
  ('40000000-0000-4000-8000-000000000103','actual','completed','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-02-03',3,180,12000,36000,true,'2026-02','2026-02',60,12000,'student_duration_overage_v1','ordinary_actual_rpc','2026-02-03 12:00+00','2026-02-03 12:00+00'),
  ('40000000-0000-4000-8000-000000000104','actual','completed','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','71000000-0000-4000-8000-000000000001','72000000-0000-4000-8000-000000000001','2026-02-04',3,180,10000,30000,true,'2026-02','2026-02',60,10000,'student_duration_overage_v1','ordinary_actual_rpc','2026-02-04 12:00+00','2026-02-04 12:00+00');
insert into public.school_student_monthly_settlements values
  ('60000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','2025-12','locked');

-- Exact P002 fixture and immutable financial evidence.
insert into public.school_lesson_records(
  id,lesson_type,status,student_id,business_entity_id,teacher_id,subject_id,
  lesson_date,duration_hours,unit_price,lesson_fee,is_billable,year_month,
  student_settlement_month,created_at,updated_at
) values (
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9','planned','pending_makeup',
  'a7b163a0-201e-4867-9b94-372343356a80','2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd','ed258e2b-81e4-4268-9682-124f310fbdf9',
  '2026-07-06',20,13000,260000,true,'2026-07','2026-07',
  '2026-07-06 06:40:40.441162+00','2026-08-01 14:02:23.647108+00'
);
insert into public.school_student_tuition_bills values
  ('07a02092-9503-47d1-9000-106f7e3de7e5','a7b163a0-201e-4867-9b94-372343356a80',
   '2cf7b72f-6e3c-4d09-80f7-7c58593cd466','2026-07',260000);
insert into public.school_student_tuition_bill_lessons values
  ('de834352-7387-f856-e8ee-213b7419210d','07a02092-9503-47d1-9000-106f7e3de7e5',
   '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9');
insert into public.school_student_tuition_generation_revisions values
  ('96000000-0000-4000-8000-202608031004','07a02092-9503-47d1-9000-106f7e3de7e5','active');
insert into public.school_income_records values
  ('91756564-c48d-4a1d-b6bc-88a041660e46','07a02092-9503-47d1-9000-106f7e3de7e5',260000,'received');
insert into public.school_personal_cash_income_linkage_events values
  ('9de972ff-8e66-470a-8b05-e430ef51562f','91756564-c48d-4a1d-b6bc-88a041660e46','synced');
insert into public.school_student_package_credit_lots(
  id,origin_planned_lesson_id,student_id,business_entity_id,
  initial_minutes,consumed_minutes,unit_price_jpy,total_price_jpy,
  student_billing_month,tuition_bill_id,tuition_revision_id,income_record_id,
  cash_linkage_event_id,cash_request_id_snapshot,cash_transaction_id_snapshot,
  status,classification_reason,origin_lesson_row_md5,evidence_manifest_sha256,
  classified_by
) values (
  '2a000000-0000-4000-8000-202608170002',
  '8b9ea410-19cf-4ed9-b1ec-c2cb5dddd7f9',
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  1200,0,13000,260000,'2026-07',
  '07a02092-9503-47d1-9000-106f7e3de7e5',
  '96000000-0000-4000-8000-202608031004',
  '91756564-c48d-4a1d-b6bc-88a041660e46',
  '9de972ff-8e66-470a-8b05-e430ef51562f',
  'a0bee5be-761b-4bc0-a666-411f033e1eba',
  'f500dbe4-07a9-4a4d-ac99-e68592a8af6a','active',
  'P002 package fixture',md5('fixture'),repeat('a',64),
  'business_owner_phase2i_a_20260817'
);

grant select on all tables in schema public to authenticated,anon,service_role;
