-- Included by school_tuition_p0c_atomic_void_reissue_20260803.sql.
-- No transaction boundary in this fragment.

alter table public.school_tuition_atomic_writer_context
  drop constraint school_tuition_atomic_writer_context_source_check;
alter table public.school_tuition_atomic_writer_context
  add constraint school_tuition_atomic_writer_context_source_check
  check (writer_source in (
    'student_tuition_atomic_generate_v1','legacy_tuition_cancel',
    'student_tuition_atomic_void_v1'
  ));

create table public.school_student_tuition_generation_identities (
  id uuid primary key,
  student_id uuid not null references public.school_students(id) on delete restrict,
  business_entity_id uuid not null references public.school_business_entities(id) on delete restrict,
  billing_month date not null,
  legacy_billing_identity_id uuid not null unique
    references public.school_student_tuition_billing_identities(id) on delete restrict,
  created_at timestamptz not null,
  created_by_authority text not null,
  constraint school_tuition_generation_identity_month_start
    check (billing_month=date_trunc('month',billing_month)::date),
  constraint school_tuition_generation_identity_creator_nonblank
    check (btrim(created_by_authority)<>'') ,
  constraint school_tuition_generation_identity_natural_key
    unique(student_id,business_entity_id,billing_month)
);

create table public.school_student_tuition_generation_revisions (
  id uuid primary key,
  generation_identity_id uuid not null
    references public.school_student_tuition_generation_identities(id) on delete restrict,
  tuition_bill_id uuid not null unique
    references public.school_student_tuition_bills(id) on delete restrict,
  revision_no integer not null check (revision_no>0),
  previous_revision_id uuid null unique
    references public.school_student_tuition_generation_revisions(id) on delete restrict,
  generation_manifest_sha256 text not null
    check (generation_manifest_sha256~'^[0-9a-f]{64}$'),
  manifest_kind text not null
    check (manifest_kind in ('atomic_generation_v1','historical_registration_v1')),
  lifecycle_status text not null check (lifecycle_status in ('active','voided')),
  created_at timestamptz not null,
  created_by_authority text not null check (btrim(created_by_authority)<>''),
  activated_at timestamptz not null,
  voided_at timestamptz null,
  voided_by_authority text null,
  constraint school_tuition_generation_revision_lifecycle_audit_check check (
    (lifecycle_status='active' and voided_at is null and voided_by_authority is null)
    or
    (lifecycle_status='voided' and voided_at is not null
      and nullif(btrim(voided_by_authority),'') is not null)
  ),
  constraint school_tuition_generation_revision_number_key
    unique(generation_identity_id,revision_no)
);

create unique index school_tuition_generation_revisions_one_active_key
  on public.school_student_tuition_generation_revisions(generation_identity_id)
  where lifecycle_status='active';

create index school_tuition_generation_revisions_bill_status_idx
  on public.school_student_tuition_generation_revisions(tuition_bill_id,lifecycle_status);

create table public.school_student_tuition_generation_void_events (
  id uuid primary key,
  generation_identity_id uuid not null
    references public.school_student_tuition_generation_identities(id) on delete restrict,
  generation_revision_id uuid not null unique
    references public.school_student_tuition_generation_revisions(id) on delete restrict,
  tuition_bill_id uuid not null unique
    references public.school_student_tuition_bills(id) on delete restrict,
  income_record_id uuid not null unique
    references public.school_income_records(id) on delete restrict,
  expected_generation_manifest_sha256 text not null
    check (expected_generation_manifest_sha256~'^[0-9a-f]{64}$'),
  reason text not null check (btrim(reason)<>''),
  operator_authority text not null check (btrim(operator_authority)<>''),
  precondition_evidence jsonb not null check (jsonb_typeof(precondition_evidence)='object'),
  result_evidence jsonb not null check (jsonb_typeof(result_evidence)='object'),
  created_at timestamptz not null
);

alter table public.school_student_tuition_generation_identities enable row level security;
alter table public.school_student_tuition_generation_revisions enable row level security;
alter table public.school_student_tuition_generation_void_events enable row level security;

revoke all on public.school_student_tuition_generation_identities from public,anon,authenticated,service_role;
revoke all on public.school_student_tuition_generation_revisions from public,anon,authenticated,service_role;
revoke all on public.school_student_tuition_generation_void_events from public,anon,authenticated,service_role;
grant select on public.school_student_tuition_generation_identities to service_role;
grant select on public.school_student_tuition_generation_revisions to service_role;
grant select on public.school_student_tuition_generation_void_events to service_role;

create function public.school_guard_p0c_generation_direct_delete()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if session_user='postgres'
     and current_setting('tuition.p0c_fixture_cleanup',true)
       ='codex-test atomic-void-reissue-p0c-20260803' then
    return null;
  end if;
  raise exception 'TUITION_P0C_DIRECT_DELETE_FORBIDDEN';
end;
$function$;
revoke all on function public.school_guard_p0c_generation_direct_delete()
  from public,anon,authenticated,service_role;
create trigger school_tuition_generation_identity_delete_statement_guard
before delete on public.school_student_tuition_generation_identities
for each statement execute function public.school_guard_p0c_generation_direct_delete();
create trigger school_tuition_generation_revision_delete_statement_guard
before delete on public.school_student_tuition_generation_revisions
for each statement execute function public.school_guard_p0c_generation_direct_delete();
create trigger school_tuition_generation_void_event_delete_statement_guard
before delete on public.school_student_tuition_generation_void_events
for each statement execute function public.school_guard_p0c_generation_direct_delete();

create function public.school_lock_student_tuition_operation(
  p_student_id uuid,p_business_entity_id uuid,p_billing_month date
) returns void
language plpgsql security definer
set search_path=pg_catalog,public
as $function$
begin
  if p_student_id is null or p_business_entity_id is null or p_billing_month is null
     or p_billing_month<>date_trunc('month',p_billing_month)::date then
    raise exception 'TUITION_OPERATION_LOCK_KEY_INVALID';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(concat_ws('|',
    'student_tuition_operation_v1',p_student_id::text,p_business_entity_id::text,
    to_char(p_billing_month,'YYYY-MM')),0));
end;
$function$;
revoke all on function public.school_lock_student_tuition_operation(uuid,uuid,date)
  from public,anon,authenticated,service_role;

create function public.school_compute_historical_tuition_registration_manifest(
  p_legacy_billing_identity_id uuid
) returns text
language plpgsql stable security definer
set search_path=pg_catalog,public
as $function$
declare
  v_identity public.school_student_tuition_billing_identities%rowtype;
  v_bill public.school_student_tuition_bills%rowtype;
  v_income public.school_income_records%rowtype;
  v_entity uuid;
  v_relation_hashes jsonb;
  v_payload jsonb;
begin
  if p_legacy_billing_identity_id not in (
    'b1000000-0000-4000-8000-202607270001'::uuid,
    'b1000000-0000-4000-8000-202607270002'::uuid,
    'b1000000-0000-4000-8000-202607270003'::uuid,
    'b1000000-0000-4000-8000-202607270004'::uuid,
    'b1000000-0000-4000-8000-202607270005'::uuid,
    'b1000000-0000-4000-8000-202607270006'::uuid,
    'b1000000-0000-4000-8000-202607270007'::uuid
  ) then
    raise exception 'TUITION_HISTORICAL_REGISTRATION_ID_NOT_APPROVED';
  end if;
  select i.* into strict v_identity
  from public.school_student_tuition_billing_identities i
  where i.id=p_legacy_billing_identity_id and i.source='historical_backfill';
  select b.* into strict v_bill from public.school_student_tuition_bills b
  where b.id=v_identity.canonical_bill_id;
  select inc.* into strict v_income from public.school_income_records inc
  where inc.id=v_bill.income_record_id;
  select s.business_entity_id into strict v_entity
  from public.school_students s where s.id=v_identity.student_id;
  if v_identity.evidence->>'generation_manifest_sha256' is not null
     or v_bill.source_snapshot->>'generation_manifest_sha256' is not null
     or v_income.source_snapshot->>'generation_manifest_sha256' is not null then
    raise exception 'TUITION_HISTORICAL_SOURCE_MANIFEST_UNEXPECTED';
  end if;
  select coalesce(jsonb_agg(encode(sha256(convert_to(to_jsonb(r)::text,'UTF8')),'hex')
           order by r.line_no,r.id),'[]'::jsonb)
  into v_relation_hashes
  from public.school_student_tuition_bill_lessons r
  where r.tuition_bill_id=v_bill.id;
  if jsonb_array_length(v_relation_hashes)<>v_bill.planned_lesson_count then
    raise exception 'TUITION_HISTORICAL_RELATION_SET_INCOMPLETE';
  end if;
  v_payload:=jsonb_build_object(
    'version','historical_registration_manifest_v1',
    'legacy_billing_identity_id',v_identity.id::text,
    'student_id',v_identity.student_id::text,
    'business_entity_id',v_entity::text,
    'billing_month',(v_identity.billing_month||'-01'),
    'bill_id',v_bill.id::text,
    'income_id',v_income.id::text,
    'legacy_identity_row_sha256',encode(sha256(convert_to(to_jsonb(v_identity)::text,'UTF8')),'hex'),
    'bill_row_sha256',encode(sha256(convert_to(to_jsonb(v_bill)::text,'UTF8')),'hex'),
    'income_row_sha256',encode(sha256(convert_to(to_jsonb(v_income)::text,'UTF8')),'hex'),
    'normalized_relation_row_sha256s',v_relation_hashes
  );
  return encode(sha256(convert_to(v_payload::text,'UTF8')),'hex');
end;
$function$;
revoke all on function public.school_compute_historical_tuition_registration_manifest(uuid)
  from public,anon,authenticated,service_role;

create function public.school_guard_tuition_generation_identity_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres'
     and current_setting('tuition.p0c_fixture_cleanup',true)
       ='codex-test atomic-void-reissue-p0c-20260803'
     and old.id='c0c00000-0000-4000-8000-000000003001'::uuid then
    return old;
  end if;
  raise exception 'TUITION_GENERATION_IDENTITY_IMMUTABLE';
end;
$function$;
revoke all on function public.school_guard_tuition_generation_identity_immutable()
  from public,anon,authenticated,service_role;
create trigger school_tuition_generation_identity_immutable
before update or delete on public.school_student_tuition_generation_identities
for each row execute function public.school_guard_tuition_generation_identity_immutable();
create trigger school_tuition_generation_identity_truncate_forbidden
before truncate on public.school_student_tuition_generation_identities
for each statement execute function public.school_guard_tuition_generation_identity_immutable();

create function public.school_guard_tuition_generation_revision()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare
  v_previous public.school_student_tuition_generation_revisions%rowtype;
  v_context_ok boolean;
begin
  if tg_op='DELETE' then
    if session_user='postgres'
       and current_setting('tuition.p0c_fixture_cleanup',true)
         ='codex-test atomic-void-reissue-p0c-20260803'
       and old.id='c0c00000-0000-4000-8000-000000004001'::uuid then
      return old;
    end if;
    raise exception 'TUITION_GENERATION_REVISION_DELETE_FORBIDDEN';
  end if;
  if tg_op='UPDATE' then
    select exists(select 1 from public.school_tuition_atomic_writer_context c
      where c.backend_pid=pg_backend_pid() and c.transaction_id=txid_current()
        and c.writer_source='student_tuition_atomic_void_v1') into v_context_ok;
    if not v_context_ok or old.lifecycle_status<>'active' or new.lifecycle_status<>'voided'
       or new.voided_at is null or nullif(btrim(new.voided_by_authority),'') is null
       or (to_jsonb(new)-array['lifecycle_status','voided_at','voided_by_authority'])
          is distinct from
          (to_jsonb(old)-array['lifecycle_status','voided_at','voided_by_authority']) then
      raise exception 'TUITION_GENERATION_REVISION_MUTATION_FORBIDDEN';
    end if;
    return new;
  end if;
  if new.revision_no=1 then
    if new.previous_revision_id is not null then
      raise exception 'TUITION_GENERATION_REVISION_ONE_PREVIOUS_FORBIDDEN';
    end if;
  else
    select r.* into v_previous from public.school_student_tuition_generation_revisions r
    where r.id=new.previous_revision_id for share;
    if not found or v_previous.generation_identity_id<>new.generation_identity_id
       or v_previous.revision_no<>new.revision_no-1 or v_previous.lifecycle_status<>'voided'
       or new.manifest_kind<>'atomic_generation_v1' then
      raise exception 'TUITION_GENERATION_REVISION_CHAIN_INVALID';
    end if;
  end if;
  if new.manifest_kind='historical_registration_v1' and new.revision_no<>1 then
    raise exception 'TUITION_HISTORICAL_REVISION_NEXT_FORBIDDEN';
  end if;
  return new;
end;
$function$;
revoke all on function public.school_guard_tuition_generation_revision()
  from public,anon,authenticated,service_role;
create trigger school_tuition_generation_revision_guard
before insert or update or delete on public.school_student_tuition_generation_revisions
for each row execute function public.school_guard_tuition_generation_revision();
create trigger school_tuition_generation_revision_truncate_forbidden
before truncate on public.school_student_tuition_generation_revisions
for each statement execute function public.school_guard_tuition_generation_revision();

create function public.school_guard_tuition_generation_void_event_immutable()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op='DELETE' and session_user='postgres'
     and current_setting('tuition.p0c_fixture_cleanup',true)
       ='codex-test atomic-void-reissue-p0c-20260803'
     and old.id='c0c00000-0000-4000-8000-000000008001'::uuid then
    return old;
  end if;
  raise exception 'TUITION_GENERATION_VOID_EVENT_IMMUTABLE';
end;
$function$;
revoke all on function public.school_guard_tuition_generation_void_event_immutable()
  from public,anon,authenticated,service_role;
create trigger school_tuition_generation_void_event_immutable
before update or delete on public.school_student_tuition_generation_void_events
for each row execute function public.school_guard_tuition_generation_void_event_immutable();
create trigger school_tuition_generation_void_event_truncate_forbidden
before truncate on public.school_student_tuition_generation_void_events
for each statement execute function public.school_guard_tuition_generation_void_event_immutable();

create view public.school_active_student_tuition_bill_lessons
with (security_invoker=true) as
select rel.*
from public.school_student_tuition_bill_lessons rel
join public.school_student_tuition_generation_revisions revision
  on revision.tuition_bill_id=rel.tuition_bill_id
 and revision.lifecycle_status='active';
revoke all on public.school_active_student_tuition_bill_lessons from public,anon,authenticated;
grant select on public.school_active_student_tuition_bill_lessons to service_role;

create function public.school_assert_active_tuition_lesson_claim(p_planned_lesson_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_count integer;
begin
  if p_planned_lesson_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'student_tuition_lesson_claim_v1|'||p_planned_lesson_id::text,0));
  select count(distinct revision.id)::integer into v_count
  from public.school_student_tuition_bill_lessons rel
  join public.school_student_tuition_generation_revisions revision
    on revision.tuition_bill_id=rel.tuition_bill_id
   and revision.lifecycle_status='active'
  where rel.planned_lesson_id=p_planned_lesson_id
    and rel.relation_role='canonical_charge';
  if v_count>1 then raise exception 'TUITION_ACTIVE_LESSON_CLAIM_CONFLICT: %',p_planned_lesson_id; end if;
end;
$function$;
revoke all on function public.school_assert_active_tuition_lesson_claim(uuid)
  from public,anon,authenticated,service_role;

create function public.school_enforce_active_tuition_lesson_claim_on_relation()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
begin
  if tg_op in ('UPDATE','DELETE') then
    perform public.school_assert_active_tuition_lesson_claim(old.planned_lesson_id);
  end if;
  if tg_op in ('INSERT','UPDATE') then
    perform public.school_assert_active_tuition_lesson_claim(new.planned_lesson_id);
  end if;
  return null;
end;
$function$;
revoke all on function public.school_enforce_active_tuition_lesson_claim_on_relation()
  from public,anon,authenticated,service_role;
create constraint trigger school_enforce_active_tuition_lesson_claim_on_relation
after insert or update or delete on public.school_student_tuition_bill_lessons
deferrable initially deferred for each row
execute function public.school_enforce_active_tuition_lesson_claim_on_relation();

create function public.school_enforce_active_tuition_lesson_claim_on_revision()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_bill_id uuid;
begin
  if tg_op in ('UPDATE','DELETE') then v_bill_id:=old.tuition_bill_id;
  else v_bill_id:=new.tuition_bill_id; end if;
  perform public.school_assert_active_tuition_lesson_claim(rel.planned_lesson_id)
  from public.school_student_tuition_bill_lessons rel
  where rel.tuition_bill_id=v_bill_id and rel.relation_role='canonical_charge'
  order by rel.planned_lesson_id;
  return null;
end;
$function$;
revoke all on function public.school_enforce_active_tuition_lesson_claim_on_revision()
  from public,anon,authenticated,service_role;
create constraint trigger school_enforce_active_tuition_lesson_claim_on_revision
after insert or update or delete on public.school_student_tuition_generation_revisions
deferrable initially deferred for each row
execute function public.school_enforce_active_tuition_lesson_claim_on_revision();

create function public.school_assert_active_tuition_carryover_claim(p_previous_settlement_id uuid)
returns void language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_count integer;
begin
  if p_previous_settlement_id is null then return; end if;
  perform pg_advisory_xact_lock(hashtextextended(
    'student_tuition_carryover_claim_v1|'||p_previous_settlement_id::text,0));
  select count(distinct revision.id)::integer into v_count
  from public.school_student_tuition_generation_revisions revision
  join public.school_student_tuition_bills bill on bill.id=revision.tuition_bill_id
  where revision.lifecycle_status='active'
    and bill.previous_settlement_id=p_previous_settlement_id;
  if v_count>1 then
    raise exception 'TUITION_ACTIVE_CARRYOVER_CLAIM_CONFLICT: %',p_previous_settlement_id;
  end if;
end;
$function$;
revoke all on function public.school_assert_active_tuition_carryover_claim(uuid)
  from public,anon,authenticated,service_role;

create function public.school_enforce_active_tuition_carryover_claim_on_revision()
returns trigger language plpgsql security definer set search_path=pg_catalog,public
as $function$
declare v_bill_id uuid; v_settlement_id uuid;
begin
  if tg_op in ('UPDATE','DELETE') then v_bill_id:=old.tuition_bill_id;
  else v_bill_id:=new.tuition_bill_id; end if;
  select bill.previous_settlement_id into v_settlement_id
  from public.school_student_tuition_bills bill where bill.id=v_bill_id;
  perform public.school_assert_active_tuition_carryover_claim(v_settlement_id);
  return null;
end;
$function$;
revoke all on function public.school_enforce_active_tuition_carryover_claim_on_revision()
  from public,anon,authenticated,service_role;
create constraint trigger school_enforce_active_tuition_carryover_claim_on_revision
after insert or update or delete on public.school_student_tuition_generation_revisions
deferrable initially deferred for each row
execute function public.school_enforce_active_tuition_carryover_claim_on_revision();

comment on table public.school_student_tuition_generation_identities is
  'Sole stable student + business entity + billing month authority for tuition generations.';
comment on table public.school_student_tuition_generation_revisions is
  'Immutable tuition generation revisions; exactly one active revision per generation identity.';
comment on table public.school_student_tuition_generation_void_events is
  'Append-only authority for dedicated Atomic Tuition void audit events.';
