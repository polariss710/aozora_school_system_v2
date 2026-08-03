-- Fixed 15-chain production metadata registration. Included inside the migration transaction.
create temporary table tuition_revision_registration_manifest(
  generation_identity_id uuid primary key,
  generation_revision_id uuid not null unique,
  legacy_identity_id uuid not null unique,
  expected_bill_id uuid not null unique,
  expected_income_id uuid not null unique,
  manifest_kind text not null,
  expected_manifest text not null
) on commit drop;

insert into tuition_revision_registration_manifest values
('96000000-0000-4000-8000-202608030001','96000000-0000-4000-8000-202608031001','5d583e44-253d-4e48-8cde-54f498aa35e4','00c956f1-19fb-4e79-9c4b-0570c8d7c3b1','4a6efa01-82c4-4e61-b4ff-d558e52c1f16','atomic_generation_v1','bf9e1d59396ad63222b57d69f7f90010799888ab7f7f174983d8f0ecc149753b'),
('96000000-0000-4000-8000-202608030002','96000000-0000-4000-8000-202608031002','b1000000-0000-4000-8000-202607270002','fdf3cdfe-f715-4814-b500-9ff2bfe77a63','f86ac9db-effd-402e-a320-1e4b6846a9c7','historical_registration_v1','d89b886f6a3e9247c8dbe66e881bcd5b14679f827e1ab5af946098ee087585b4'),
('96000000-0000-4000-8000-202608030003','96000000-0000-4000-8000-202608031003','b1000000-0000-4000-8000-202607270005','2608806a-283a-4919-a851-b25962f2c0b2','4a63f0ca-450f-4306-9e39-6d43172b3cf8','historical_registration_v1','f17053c1d1916da5d35d95ac0174cfd37fe7da2abdc28b28837933482396f282'),
('96000000-0000-4000-8000-202608030004','96000000-0000-4000-8000-202608031004','b1000000-0000-4000-8000-202607270004','07a02092-9503-47d1-9000-106f7e3de7e5','91756564-c48d-4a1d-b6bc-88a041660e46','historical_registration_v1','9b2ee3da8fbd2c22aacb03e9ee795fa16f9ffc2eb4a55d07a6cd02f3a5c37ad0'),
('96000000-0000-4000-8000-202608030005','96000000-0000-4000-8000-202608031005','b1000000-0000-4000-8000-202607270001','2a9f1c25-a060-461e-ae10-b02295dec381','468ab75b-312e-4ba0-8d8d-8ae2f6ace00e','historical_registration_v1','74a2308525cf2f4c00065c06463f79a9c2e8ad8169fec389a815e7145d34ea78'),
('96000000-0000-4000-8000-202608030006','96000000-0000-4000-8000-202608031006','b1000000-0000-4000-8000-202607270003','2a0948e0-9015-4b18-848c-8c397e0bc2a0','09fa4398-9d20-494b-8ab5-8f7c3cafa414','historical_registration_v1','0a0328496f3448d00355b87bd6e7ce28e59872ef8461ca819d351e028b850635'),
('96000000-0000-4000-8000-202608030007','96000000-0000-4000-8000-202608031007','b1000000-0000-4000-8000-202607270007','7472f73f-fa19-4565-9180-a517c7151835','3a5542c5-5397-4688-999e-a08bb678f40d','historical_registration_v1','daff5bee69dba2eaca4ff05e10cac90300d42b0c59c5d7541e8b98a26fb76897'),
('96000000-0000-4000-8000-202608030008','96000000-0000-4000-8000-202608031008','30564170-f39a-40b5-9ea8-96d02f5bb54f','13bc7bc1-4f93-4b7c-b447-a8ec595953d1','54b281ee-78ce-47ab-8fd2-f17791230698','atomic_generation_v1','3cc65ce369515ca320e4ee30b09eaf3dbe6c8a04c04b4e0c2707e2b14dbf0904'),
('96000000-0000-4000-8000-202608030009','96000000-0000-4000-8000-202608031009','361ed1c1-8e69-4842-810b-6b3f7f9b11e9','553a24ba-81cf-4af0-b723-169a09914c79','be64a9e2-f15e-44b0-a9de-2ee91bdf9567','atomic_generation_v1','3aaa288b6b4edfcd3c897f36c7f6ffb638553ed9e566a68041457036a9773f38'),
('96000000-0000-4000-8000-202608030010','96000000-0000-4000-8000-202608031010','b1000000-0000-4000-8000-202607270006','1b546782-1b39-4c73-a85d-27ab1e5086ad','cdf3da68-e578-4f1b-b759-2fff394e1906','historical_registration_v1','47d0c3ed5d8ea7b8207229f6292cb3c908b2b2af0af19eb15325a7133b499ac7'),
('96000000-0000-4000-8000-202608030011','96000000-0000-4000-8000-202608031011','45b7ebb6-c991-4f04-b85b-40ecd5adb6ff','5e032651-f3b0-40f9-b1ad-6bcce4e6fb93','1de45ea6-6cf7-45d9-9df5-1275bf5051d4','atomic_generation_v1','bf7d219c70cf8904824a5a318a46ef90ed0b02a198921624b6682ec61eed702e'),
('96000000-0000-4000-8000-202608030012','96000000-0000-4000-8000-202608031012','84450d79-a43d-4186-8ca2-11ac9139eb30','7d764343-8aef-4905-999a-24e07c34e2f4','ae9e2400-8987-493c-907d-3ca5bfb50b79','atomic_generation_v1','eecea1533b2928d18e3f131d34cbd0fe3166eaa7e12984b19e0d51fba4a56e69'),
('96000000-0000-4000-8000-202608030013','96000000-0000-4000-8000-202608031013','2dd30b2f-45ea-431f-893b-d294a767266a','1e02dc09-8f42-4a93-85c6-e27809d68a83','ae4d8b66-491b-4db2-ac91-86765f56155c','atomic_generation_v1','1e75fd1456114d53b5c575d27d103ec4c038675b35586576d4ec40a28c91d801'),
('96000000-0000-4000-8000-202608030014','96000000-0000-4000-8000-202608031014','c55365e2-f7dc-43e6-9e24-5bf6c96ec81c','51f746c5-cede-4609-b845-06ba10d17de5','895a7be3-7a38-4744-94f7-e2ac7fdb7cef','atomic_generation_v1','126f9d969944ced91651e4cd8bafcfe6ebf1fa81773c4cfa9201ae4b20578f56'),
('96000000-0000-4000-8000-202608030015','96000000-0000-4000-8000-202608031015','03a363f3-d0db-4e8e-91e5-a2f67e243843','3435cbac-adc5-4bec-a54c-cefaab593359','004c7eeb-94c8-4312-aa2c-1ab44baa70dd','atomic_generation_v1','0823f0df7d4b8aaf82495178ff6a19f9239009aea35d98d3adee7010854141ac');

do $verify_manifest$
declare r record; v_actual text;
begin
  if (select count(*) from tuition_revision_registration_manifest)<>15 then
    raise exception 'TUITION_REGISTRATION_MANIFEST_COUNT_INVALID';
  end if;
  for r in select m.*,i.student_id,s.business_entity_id,i.billing_month,i.source,
                  i.canonical_bill_id,b.income_record_id,i.evidence,
                  b.source_snapshot as bill_source_snapshot,
                  inc.source_snapshot as income_source_snapshot
           from tuition_revision_registration_manifest m
           join public.school_student_tuition_billing_identities i on i.id=m.legacy_identity_id
           join public.school_students s on s.id=i.student_id
           join public.school_student_tuition_bills b on b.id=i.canonical_bill_id
           join public.school_income_records inc on inc.id=b.income_record_id
  loop
    if r.canonical_bill_id<>r.expected_bill_id or r.income_record_id<>r.expected_income_id then
      raise exception 'TUITION_REGISTRATION_CHAIN_ID_DRIFT: %',r.legacy_identity_id;
    end if;
    perform public.school_validate_tuition_identity_for_bill(r.expected_bill_id);
    perform public.school_validate_tuition_bill_income_for_bill(r.expected_bill_id);
    perform public.school_validate_tuition_bill_lessons_for_bill(r.expected_bill_id);
    if r.manifest_kind='historical_registration_v1' then
      v_actual:=public.school_compute_historical_tuition_registration_manifest(r.legacy_identity_id);
    else
      if r.source<>'atomic_charge' then raise exception 'TUITION_ATOMIC_REGISTRATION_SOURCE_DRIFT'; end if;
      v_actual:=coalesce(r.evidence->>'generation_manifest_sha256',
                         r.bill_source_snapshot->>'generation_manifest_sha256');
      if v_actual is distinct from r.income_source_snapshot->>'generation_manifest_sha256' then
        raise exception 'TUITION_ATOMIC_REGISTRATION_MANIFEST_CHAIN_DRIFT';
      end if;
    end if;
    if v_actual is distinct from r.expected_manifest then
      raise exception 'TUITION_REGISTRATION_MANIFEST_DRIFT: %',r.legacy_identity_id;
    end if;
  end loop;
end;
$verify_manifest$;

insert into public.school_student_tuition_generation_identities(
  id,student_id,business_entity_id,billing_month,legacy_billing_identity_id,
  created_at,created_by_authority
)
select m.generation_identity_id,i.student_id,s.business_entity_id,
       to_date(i.billing_month||'-01','YYYY-MM-DD'),i.id,now(),
       'service_role_v2_operations_v1'
from tuition_revision_registration_manifest m
join public.school_student_tuition_billing_identities i on i.id=m.legacy_identity_id
join public.school_students s on s.id=i.student_id
order by m.generation_identity_id
on conflict (id) do nothing;

insert into public.school_student_tuition_generation_revisions(
  id,generation_identity_id,tuition_bill_id,revision_no,previous_revision_id,
  generation_manifest_sha256,manifest_kind,lifecycle_status,created_at,created_by_authority,
  activated_at,voided_at,voided_by_authority
)
select m.generation_revision_id,m.generation_identity_id,m.expected_bill_id,1,null,
       m.expected_manifest,m.manifest_kind,'active',now(),'service_role_v2_operations_v1',
       now(),null,null
from tuition_revision_registration_manifest m order by m.generation_revision_id
on conflict (id) do nothing;

do $registration_assert$
begin
  if (select count(*) from public.school_student_tuition_generation_identities)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions)<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where lifecycle_status='active')<>15
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='atomic_generation_v1')<>8
     or (select count(*) from public.school_student_tuition_generation_revisions where manifest_kind='historical_registration_v1')<>7
     or (select count(*) from public.school_student_tuition_generation_void_events)<>0 then
    raise exception 'TUITION_FIXED_15_REGISTRATION_ASSERT_FAILED';
  end if;
  if exists(select 1 from tuition_revision_registration_manifest m
    left join public.school_student_tuition_generation_identities g on g.id=m.generation_identity_id
    left join public.school_student_tuition_generation_revisions r on r.id=m.generation_revision_id
    where g.legacy_billing_identity_id is distinct from m.legacy_identity_id
       or r.generation_manifest_sha256 is distinct from m.expected_manifest
       or r.manifest_kind is distinct from m.manifest_kind
       or r.lifecycle_status<>'active' or r.revision_no<>1) then
    raise exception 'TUITION_FIXED_15_REGISTRATION_ROW_MISMATCH';
  end if;
end;
$registration_assert$;

-- New active-claim constraint triggers are installed and validated before the old
-- permanent historical unique index is removed. This DROP is in the same migration transaction.
set constraints school_enforce_active_tuition_lesson_claim_on_relation,
                school_enforce_active_tuition_lesson_claim_on_revision immediate;
do $active_claim_assert$
declare v_lesson uuid; v_settlement uuid;
begin
  for v_lesson in
    select distinct rel.planned_lesson_id
    from public.school_student_tuition_bill_lessons rel
    join public.school_student_tuition_generation_revisions rev
      on rev.tuition_bill_id=rel.tuition_bill_id and rev.lifecycle_status='active'
    where rel.relation_role='canonical_charge'
    order by rel.planned_lesson_id
  loop perform public.school_assert_active_tuition_lesson_claim(v_lesson); end loop;
  for v_settlement in
    select distinct bill.previous_settlement_id
    from public.school_student_tuition_generation_revisions rev
    join public.school_student_tuition_bills bill on bill.id=rev.tuition_bill_id
    where rev.lifecycle_status='active' and bill.previous_settlement_id is not null
    order by bill.previous_settlement_id
  loop perform public.school_assert_active_tuition_carryover_claim(v_settlement); end loop;
end;
$active_claim_assert$;
drop index public.school_tuition_bill_lessons_canonical_planned_key;
