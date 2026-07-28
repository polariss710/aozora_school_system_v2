-- R1D-C-B-A1 postdeploy verification. SELECT-only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select clock_timestamp() as postdeploy_started_at,
       current_setting('transaction_isolation') as isolation,
       current_setting('transaction_read_only') as read_only;

with manifest(lesson_id,student_id,generation_batch_id,expected_updated_at,expected_old31_hash,billing_month,billing_week) as (
  values
    ('01490eb7-1bd7-430a-ba26-3ccc81d45796'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'6ba501bf72878203f293c4821d019494','2026-08','2026-08-31'::date),
    ('02b9e85e-2e03-404d-93a6-9bfef3bf186d'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'97859198c48319c595151f196e69658e','2026-08','2026-08-31'::date),
    ('0d048cbf-a5f5-458c-88aa-ce0c3a1c667c'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'9495019b53f7886326bebecd05cf82f6','2026-08','2026-08-31'::date),
    ('12d70ee9-8221-4b8e-a01c-61548340c42d'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'9e5e1b32b7ff05f9ba75822778a22494','2026-08','2026-08-17'::date),
    ('1927b6ba-6ca6-4ef9-b1c0-0246067c7d41'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'1b6b35329424bb24f844068b5243036a','2026-08','2026-08-17'::date),
    ('196c9d86-500b-4687-a051-88dcc12fa2a9'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'424950f7daac4d7eedcdd3f4eca6fb60','2026-08','2026-08-31'::date),
    ('1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'dec5deb37f67b542ff310c49a0bdb90e','2026-08','2026-08-17'::date),
    ('1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'ab9ab3490a90d6d5bfab34cdbd2280cb','2026-08','2026-08-24'::date),
    ('222c4ad5-b6fe-4e4e-b192-8db8c65b61fa'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'0014416a4051f46a7fd07a4f71e41de2','2026-08','2026-08-03'::date),
    ('23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'60667e3f5fb3ddfa3796e07f3f3645f3','2026-08','2026-08-03'::date),
    ('286344d1-c603-4990-aba3-814996535319'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'167d2e907f667f2dfd5ca92fd4cfb435','2026-08','2026-08-24'::date),
    ('37a2083e-bb28-45d1-802a-f98f4564887f'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'9e9a881a7806fdf426e366d338876261','2026-08','2026-08-10'::date),
    ('3920fdea-2f9d-4b17-abd0-f788b0d7d29e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'ebb7e88a6fa5ad369859efc3966e49ec','2026-08','2026-08-17'::date),
    ('3db3ad8b-44b6-4be7-a3ea-611362b82488'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'bc2287e7ce197859ff3fa73332caf41c','2026-08','2026-08-10'::date),
    ('475853f0-2004-4375-ae72-013c5a86987c'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'c3a48c6abbd59c5e10d4b04e4b62fc66','2026-08','2026-08-24'::date),
    ('637ba833-830f-42a6-81ed-47a6f9902523'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'dbb535a333addb86ecd83b4cb6fbcff6','2026-08','2026-08-03'::date),
    ('63ca3a2b-7c2f-4eed-a997-71840357f8f6'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'b46a16a5f0de3c1cd896303538d712f2','2026-08','2026-08-10'::date),
    ('68bbce4e-f6bb-45c6-9798-ee72b6f75179'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'851bdaae3b3703e230437742df826520','2026-08','2026-08-17'::date),
    ('6997acdc-fec4-4e14-a22b-d9f5291b1e0b'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'7e6e7e978dc8433e0ee465d1a4f4e05d','2026-08','2026-08-10'::date),
    ('69ecc019-9f8f-474e-8dc9-1dced16e41a6'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0a39f71c6df5e5bccc344fa5101412b3','2026-08','2026-08-10'::date),
    ('6c70c4c1-1895-453d-b9b0-591e9f004f86'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'f88202deb10b60d6f1612cf9661730d3','2026-08','2026-08-03'::date),
    ('6e005bee-2d14-4722-8b76-9dbe7f836e12'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'eece63758002053465f946f5bd5b4105','2026-08','2026-08-24'::date),
    ('7175780c-b179-4f96-a42e-99ba11bdaed8'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'5568b41d3d9c0b0133dd501e20c48382','2026-08','2026-08-03'::date),
    ('72ffebba-ecb3-4a96-9550-f02a5f64cf62'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'03e0174b4c28df8d635eb432cb41a7e6','2026-08','2026-08-10'::date),
    ('80384c28-5044-4c56-94cd-5099aa852032'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'eba29c21e1d79c11ae5364582bffff34','2026-08','2026-08-03'::date),
    ('80e03531-5eaa-40e1-a435-0132dd62d5c0'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'b413d8c982c8368cefbf8a0a47672b74','2026-08','2026-08-31'::date),
    ('89da310d-4f17-4a40-8315-659838aec59c'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'e6d7847c7691e950099d2c520ab44aec','2026-08','2026-08-03'::date),
    ('8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'27bcd0e8f131c12c6d375cef53ff6347','2026-08','2026-08-31'::date),
    ('920808f2-5629-4fcc-957c-6bdcee48808e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'cf47dc2d414bf6b736fd5058bf038df5','2026-08','2026-08-03'::date),
    ('95dff1ab-544d-43be-bc0e-a95232f06935'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'ea9d9fd665cc3a7ef6e2493680f66db2','2026-08','2026-08-17'::date),
    ('9a76aed4-058f-4801-90b5-b2637387fb3e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'477a49ddac54932b9334dc0f12fe5e42','2026-08','2026-08-24'::date),
    ('9bdb88c1-9c08-4716-b146-e98cf149978b'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'410bf116cd304cd5bb22ec60ff2448db','2026-08','2026-08-17'::date),
    ('9efb8862-e8c5-4f3d-9d55-b0be4317ad19'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'9f51c2218f3805be27ecbc5bda4bc191','2026-08','2026-08-03'::date),
    ('9efe2def-ff59-467a-bb76-a49537ec8e0f'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'29dc74af0aec4a60eba6ccebffad665e','2026-08','2026-08-31'::date),
    ('9f755093-8f4d-4337-80ed-23d0e555c835'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'f797392620206bbdd3d35fa9d276e3a1','2026-08','2026-08-24'::date),
    ('a10744fc-173a-4b25-9bc3-99d6437797c5'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'e9a768129fcb0e4cb977b744c3a3a96f','2026-08','2026-08-17'::date),
    ('a3ee5595-6dd5-4737-8605-ff5a8d7d0333'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'c542f4265f6bbe681fbdd3b510a86883','2026-08','2026-08-10'::date),
    ('a601916b-6add-4be6-adcc-5c232425f686'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'f2c8eee04068ff6e648e40e4c82fa646','2026-08','2026-08-17'::date),
    ('aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'4f15f0bcf098dadfcf7ee8d670f73dc8','2026-08','2026-08-31'::date),
    ('adc0b06c-eee3-40ca-8992-592f5d4b009b'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'57a0fadf5053d0e540fc1d6562881e07','2026-08','2026-08-31'::date),
    ('c0e9fd95-7833-44ef-a282-61611976b089'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'e499ac539cbc95b351e8963f37016e05','2026-08','2026-08-10'::date),
    ('cde683d3-06f2-46ec-8b8a-4f2ed4b4962e'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'e1a2cfb4a976dd64384368031a40d28f','2026-08','2026-08-24'::date),
    ('d06f136e-d4c5-44fb-ae5e-d87efa26bbfb'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'4d633181526cdef0005f4cd17ef3b414','2026-08','2026-08-03'::date),
    ('dbe16731-803b-49db-8cc0-f826e911bb41'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'b1b11ae5bb742c836d48a15b54575171','2026-08','2026-08-31'::date),
    ('e2540bb3-5c1f-45bc-b964-9727a6ed3e48'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'cc6bed2d4eaa3907d9ac125cefe52c1b','2026-08','2026-08-24'::date),
    ('e65b7d1d-45b2-4485-ae6d-7000fe92ce78'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'e2efc97bf67d8a3c0f729f3b0e51a216','2026-08','2026-08-24'::date),
    ('e6aaf546-bb9c-4e71-980e-40f78f2e1e11'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'b90fe0304a37cb79c7ed83c90e71fd6a','2026-08','2026-08-10'::date),
    ('ea766c1d-f152-4b3f-9400-0d5b5aa64614'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'6103122f8d4f4a13d9ef07bab70b3d61','2026-08','2026-08-10'::date),
    ('ee6c1383-4259-44e0-923c-1ee6b8749820'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'e8b971b3871ec05c09c750d4bd4338c8','2026-08','2026-08-24'::date),
    ('ee86e691-2c96-48c2-ad57-512f9eef4b3c'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'a50a1de81b6533685ee915826c907038','2026-08','2026-08-24'::date),
    ('fa7883c8-35e6-40bd-92d1-70adcdcce078'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'31cacf444480ecb300293d7b53ca726e','2026-08','2026-08-17'::date),
    ('fcbf1be4-567b-4876-9cc6-19cd0d395da0'::uuid,'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid,'2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c','2026-07-08 06:50:55.529737+00'::timestamptz,'924654ee6eaf547bd826ee1254972d6c','2026-08','2026-08-10'::date)
), checked as (
  select manifest.*,
         lesson.id as matched_lesson_id,
         lesson.student_id as current_student_id,
         lesson.import_batch_id as current_generation_batch_id,
         lesson.updated_at as current_updated_at,
         lesson.billing_month as current_billing_month,
         lesson.billing_week_start_date as current_billing_week,
         lesson.student_settlement_month as current_student_settlement_month,
         lesson.billing_month_source as current_source,
         lesson.billing_month_decided_at as current_decided_at,
         lesson.scheduled_lesson_date as current_scheduled_lesson_date,
         md5((to_jsonb(lesson)
           - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
           - 'student_settlement_month' - 'billing_month_source'
           - 'billing_month_decided_at')::text) current_old31_hash
  from manifest join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
)
select
  (select count(*) from manifest) as manifest_rows,
  count(*) as matched_rows,
  count(*) filter (where checked.current_student_id=checked.student_id) as student_matches,
  count(*) filter (where checked.current_generation_batch_id=checked.generation_batch_id) as generation_batch_matches,
  count(*) filter (where checked.current_updated_at=checked.expected_updated_at) as updated_at_matches,
  count(*) filter (where checked.current_old31_hash=checked.expected_old31_hash) as old31_hash_matches,
  count(*) filter (where checked.current_billing_month=checked.billing_month
    and checked.current_billing_week=checked.billing_week
    and checked.current_student_settlement_month=checked.billing_month
    and checked.current_source='approved_r1c_a_manifest'
    and checked.current_decided_at is not null
    and checked.current_scheduled_lesson_date is null) as attribution_matches,
  count(distinct checked.current_decided_at) as decided_at_distinct,
  min(checked.current_decided_at) as billing_month_decided_at,
  md5(string_agg(checked.current_old31_hash,'' order by checked.lesson_id::text)) as target_old31_hash
from checked;

select
  count(*) as lesson_count,
  count(*) filter (where lesson_type='planned') as planned_count,
  count(*) filter (where lesson_type='actual') as actual_count,
  count(*) filter (where billing_month is not null) as billing_month_nonnull,
  count(*) filter (where billing_week_start_date is not null) as billing_week_nonnull,
  count(*) filter (where scheduled_lesson_date is not null) as scheduled_nonnull,
  count(*) filter (where student_settlement_month is not null) as settlement_nonnull,
  count(*) filter (where billing_month_source is not null) as source_nonnull,
  count(*) filter (where billing_month_decided_at is not null) as decided_nonnull,
  md5(coalesce(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text),'' order by id::text),'')) as old31_hash,
  md5(coalesce(string_agg(md5(to_jsonb(lesson)::text),'' order by id::text),'')) as raw37_hash
from public.school_lesson_records lesson;

select item.batch_id,count(*) as item_count,
       count(*) filter (where lesson.billing_month is null
         and lesson.billing_week_start_date is null
         and lesson.scheduled_lesson_date is null
         and lesson.student_settlement_month is null
         and lesson.billing_month_source is null
         and lesson.billing_month_decided_at is null) as six_null_count,
       count(*) filter (where lesson.updated_at=item.original_updated_at) as updated_at_match_count,
       count(*) filter (where (to_jsonb(lesson)
         - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
         - 'student_settlement_month' - 'billing_month_source'
         - 'billing_month_decided_at')=item.after_row_snapshot) as old31_snapshot_match_count,
       md5(string_agg(md5((to_jsonb(lesson)
         - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
         - 'student_settlement_month' - 'billing_month_source'
         - 'billing_month_decided_at')::text),'' order by lesson.id::text)) as old31_hash
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
where item.batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
group by item.batch_id order by item.batch_id;

select
  count(*) filter (where lesson.lesson_type='actual') as actual_rows,
  count(*) filter (where lesson.lesson_type='actual'
    and lesson.billing_month is null
    and lesson.billing_week_start_date is null
    and lesson.scheduled_lesson_date is null
    and lesson.student_settlement_month is null
    and lesson.billing_month_source is null
    and lesson.billing_month_decided_at is null) as actual_six_null_rows,
  count(*) filter (where relation.relation_role='canonical_charge') as historical_canonical_rows,
  count(*) filter (where relation.relation_role='incident_duplicate') as historical_incident_rows,
  count(*) filter (where relation.relation_role='legacy_cancelled') as historical_legacy_rows,
  count(*) filter (where relation.id is not null
    and lesson.billing_month is null
    and lesson.billing_week_start_date is null
    and lesson.scheduled_lesson_date is null
    and lesson.student_settlement_month is null
    and lesson.billing_month_source is null
    and lesson.billing_month_decided_at is null) as historical_six_null_rows
from public.school_lesson_records lesson
left join public.school_student_tuition_bill_lessons relation on relation.planned_lesson_id=lesson.id;

with current_candidates as (
  select distinct candidate.planned_lesson_id
  from public.school_students student
  join (select distinct student_id,year_month from public.school_lesson_records
        where app_type='school' and lesson_type='planned') scope on scope.student_id=student.id
  cross join lateral public.school_list_student_tuition_candidates(
    student.id,student.business_entity_id,scope.year_month,false) candidate
  where candidate.candidate_status='candidate'
), proposed_candidates as (
  select lesson_record_id planned_lesson_id
  from public.school_business_entity_migration_items
  where batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
), current_only as (
  select * from current_candidates except select * from proposed_candidates
), proposed_only as (
  select * from proposed_candidates except select * from current_candidates
)
select (select count(*) from current_candidates) current_candidate_rows,
       (select count(*) from proposed_candidates) proposed_candidate_rows,
       (select count(*) from current_only) current_only_rows,
       (select count(*) from proposed_only) proposed_only_rows;

select relation.relation_role,count(*) relation_rows,
       count(*) filter(where candidate.candidate_status='candidate') candidate_rows,
       count(*) filter(where candidate.candidate_status='excluded') excluded_rows
from public.school_student_tuition_bill_lessons relation
join public.school_lesson_records lesson on lesson.id=relation.planned_lesson_id
cross join lateral public.school_list_student_tuition_candidates(
  lesson.student_id,lesson.business_entity_id,lesson.year_month,true) candidate
where candidate.planned_lesson_id=lesson.id
group by relation.relation_role order by relation.relation_role;

select 'tuition_bill' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) hash from public.school_student_tuition_bills t
union all select 'income',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_income_records t
union all select 'identity',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_student_tuition_billing_identities t
union all select 'relation',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_student_tuition_bill_lessons t
union all select 'migration_batch',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_business_entity_migration_batches t
union all select 'migration_item',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_business_entity_migration_items t
union all select 'cash_linkage',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_personal_cash_income_linkage_events t
union all select 'account_transaction',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_account_transactions t
union all select 'settlement',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_student_monthly_settlements t
union all select 'wage_lock',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_teacher_wage_locks t
union all select 'wage_detail',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_teacher_wage_lock_details t
union all select 'feature_gate',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by feature_key),'')) from public.school_feature_gates t;

select
  count(*) as bill_count,
  count(*) filter (where bill.income_record_id=income.id
    and income.tuition_bill_id=bill.id
    and income.source_type='student_tuition_bill'
    and income.source_id=bill.id) as exact_bill_income_pairs
from public.school_student_tuition_bills bill
join public.school_income_records income on income.id=bill.income_record_id;

select count(*) as relation_rows,
       count(*) filter(where
         relation.relation_role=bill.billing_role
         and relation.student_id_snapshot=bill.student_id
         and relation.business_entity_id_snapshot is not distinct from bill.business_entity_id
         and relation.billing_month_snapshot=bill.billing_month
         and relation.line_no <= jsonb_array_length(coalesce(bill.source_snapshot->'planned_lesson_ids','[]'::jsonb))
         and (bill.source_snapshot->'planned_lesson_ids'->>(relation.line_no-1))::uuid=relation.planned_lesson_id
       ) as json_matches,
       count(*) filter(where relation.scheduled_lesson_date_snapshot is null
         and relation.week_start_date_snapshot is null) as historical_snapshot_null_rows
from public.school_student_tuition_bill_lessons relation
join public.school_student_tuition_bills bill on bill.id=relation.tuition_bill_id;

select count(*) as override_audit_rows
from public.school_tuition_billing_attribution_override_audit;

select tgname,tgenabled
from pg_trigger
where tgrelid='public.school_lesson_records'::regclass
  and not tgisinternal
order by tgname;

select feature_key,state
from public.school_feature_gates
order by feature_key;

select clock_timestamp() as postdeploy_finished_at;
commit;
