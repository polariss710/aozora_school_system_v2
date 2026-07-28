-- School V2 tuition P0 R1D-C-B-A1: controlled attribution backfill for the fixed R1C-A 52.
-- psql variable r1d_c_b_a1_commit: 0 = rollback rehearsal, 1 = formal commit.
-- Scope is the static manifest below. The migration audit batch is evidence only,
-- never the selector that expands the UPDATE scope.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_c_b_a1_commit}
\else
  \set r1d_c_b_a1_commit 0
\endif

begin;
set local lock_timeout = '15s';

create temporary table r1d_c_b_a1_manifest (
  item_order integer primary key,
  lesson_id uuid unique not null,
  expected_student_id uuid not null,
  expected_generation_batch_id text not null,
  expected_updated_at timestamptz not null,
  expected_old31_hash text not null,
  proposed_billing_month text not null,
  proposed_billing_week_start_date date not null,
  proposed_student_settlement_month text not null,
  proposed_billing_month_source text not null
) on commit drop;

insert into r1d_c_b_a1_manifest values
  (1, '01490eb7-1bd7-430a-ba26-3ccc81d45796'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '6ba501bf72878203f293c4821d019494', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (2, '02b9e85e-2e03-404d-93a6-9bfef3bf186d'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '97859198c48319c595151f196e69658e', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (3, '0d048cbf-a5f5-458c-88aa-ce0c3a1c667c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '9495019b53f7886326bebecd05cf82f6', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (4, '12d70ee9-8221-4b8e-a01c-61548340c42d'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '9e5e1b32b7ff05f9ba75822778a22494', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (5, '1927b6ba-6ca6-4ef9-b1c0-0246067c7d41'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '1b6b35329424bb24f844068b5243036a', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (6, '196c9d86-500b-4687-a051-88dcc12fa2a9'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '424950f7daac4d7eedcdd3f4eca6fb60', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (7, '1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'dec5deb37f67b542ff310c49a0bdb90e', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (8, '1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'ab9ab3490a90d6d5bfab34cdbd2280cb', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (9, '222c4ad5-b6fe-4e4e-b192-8db8c65b61fa'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '0014416a4051f46a7fd07a4f71e41de2', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (10, '23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '60667e3f5fb3ddfa3796e07f3f3645f3', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (11, '286344d1-c603-4990-aba3-814996535319'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '167d2e907f667f2dfd5ca92fd4cfb435', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (12, '37a2083e-bb28-45d1-802a-f98f4564887f'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '9e9a881a7806fdf426e366d338876261', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (13, '3920fdea-2f9d-4b17-abd0-f788b0d7d29e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'ebb7e88a6fa5ad369859efc3966e49ec', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (14, '3db3ad8b-44b6-4be7-a3ea-611362b82488'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'bc2287e7ce197859ff3fa73332caf41c', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (15, '475853f0-2004-4375-ae72-013c5a86987c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'c3a48c6abbd59c5e10d4b04e4b62fc66', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (16, '637ba833-830f-42a6-81ed-47a6f9902523'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'dbb535a333addb86ecd83b4cb6fbcff6', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (17, '63ca3a2b-7c2f-4eed-a997-71840357f8f6'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'b46a16a5f0de3c1cd896303538d712f2', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (18, '68bbce4e-f6bb-45c6-9798-ee72b6f75179'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '851bdaae3b3703e230437742df826520', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (19, '6997acdc-fec4-4e14-a22b-d9f5291b1e0b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '7e6e7e978dc8433e0ee465d1a4f4e05d', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (20, '69ecc019-9f8f-474e-8dc9-1dced16e41a6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0a39f71c6df5e5bccc344fa5101412b3', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (21, '6c70c4c1-1895-453d-b9b0-591e9f004f86'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'f88202deb10b60d6f1612cf9661730d3', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (22, '6e005bee-2d14-4722-8b76-9dbe7f836e12'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'eece63758002053465f946f5bd5b4105', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (23, '7175780c-b179-4f96-a42e-99ba11bdaed8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '5568b41d3d9c0b0133dd501e20c48382', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (24, '72ffebba-ecb3-4a96-9550-f02a5f64cf62'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '03e0174b4c28df8d635eb432cb41a7e6', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (25, '80384c28-5044-4c56-94cd-5099aa852032'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'eba29c21e1d79c11ae5364582bffff34', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (26, '80e03531-5eaa-40e1-a435-0132dd62d5c0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'b413d8c982c8368cefbf8a0a47672b74', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (27, '89da310d-4f17-4a40-8315-659838aec59c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'e6d7847c7691e950099d2c520ab44aec', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (28, '8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '27bcd0e8f131c12c6d375cef53ff6347', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (29, '920808f2-5629-4fcc-957c-6bdcee48808e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'cf47dc2d414bf6b736fd5058bf038df5', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (30, '95dff1ab-544d-43be-bc0e-a95232f06935'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'ea9d9fd665cc3a7ef6e2493680f66db2', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (31, '9a76aed4-058f-4801-90b5-b2637387fb3e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '477a49ddac54932b9334dc0f12fe5e42', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (32, '9bdb88c1-9c08-4716-b146-e98cf149978b'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '410bf116cd304cd5bb22ec60ff2448db', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (33, '9efb8862-e8c5-4f3d-9d55-b0be4317ad19'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '9f51c2218f3805be27ecbc5bda4bc191', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (34, '9efe2def-ff59-467a-bb76-a49537ec8e0f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '29dc74af0aec4a60eba6ccebffad665e', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (35, '9f755093-8f4d-4337-80ed-23d0e555c835'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'f797392620206bbdd3d35fa9d276e3a1', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (36, 'a10744fc-173a-4b25-9bc3-99d6437797c5'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'e9a768129fcb0e4cb977b744c3a3a96f', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (37, 'a3ee5595-6dd5-4737-8605-ff5a8d7d0333'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'c542f4265f6bbe681fbdd3b510a86883', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (38, 'a601916b-6add-4be6-adcc-5c232425f686'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'f2c8eee04068ff6e648e40e4c82fa646', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (39, 'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '4f15f0bcf098dadfcf7ee8d670f73dc8', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (40, 'adc0b06c-eee3-40ca-8992-592f5d4b009b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '57a0fadf5053d0e540fc1d6562881e07', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (41, 'c0e9fd95-7833-44ef-a282-61611976b089'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'e499ac539cbc95b351e8963f37016e05', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (42, 'cde683d3-06f2-46ec-8b8a-4f2ed4b4962e'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'e1a2cfb4a976dd64384368031a40d28f', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (43, 'd06f136e-d4c5-44fb-ae5e-d87efa26bbfb'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '4d633181526cdef0005f4cd17ef3b414', '2026-08', '2026-08-03'::date, '2026-08', 'approved_r1c_a_manifest'),
  (44, 'dbe16731-803b-49db-8cc0-f826e911bb41'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'b1b11ae5bb742c836d48a15b54575171', '2026-08', '2026-08-31'::date, '2026-08', 'approved_r1c_a_manifest'),
  (45, 'e2540bb3-5c1f-45bc-b964-9727a6ed3e48'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'cc6bed2d4eaa3907d9ac125cefe52c1b', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (46, 'e65b7d1d-45b2-4485-ae6d-7000fe92ce78'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, 'e2efc97bf67d8a3c0f729f3b0e51a216', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (47, 'e6aaf546-bb9c-4e71-980e-40f78f2e1e11'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'b90fe0304a37cb79c7ed83c90e71fd6a', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (48, 'ea766c1d-f152-4b3f-9400-0d5b5aa64614'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '6103122f8d4f4a13d9ef07bab70b3d61', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest'),
  (49, 'ee6c1383-4259-44e0-923c-1ee6b8749820'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'e8b971b3871ec05c09c750d4bd4338c8', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (50, 'ee86e691-2c96-48c2-ad57-512f9eef4b3c'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'a50a1de81b6533685ee915826c907038', '2026-08', '2026-08-24'::date, '2026-08', 'approved_r1c_a_manifest'),
  (51, 'fa7883c8-35e6-40bd-92d1-70adcdcce078'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '31cacf444480ecb300293d7b53ca726e', '2026-08', '2026-08-17'::date, '2026-08', 'approved_r1c_a_manifest'),
  (52, 'fcbf1be4-567b-4876-9cc6-19cd0d395da0'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '2026-07-08 06:50:55.529737+00'::timestamptz, '924654ee6eaf547bd826ee1254972d6c', '2026-08', '2026-08-10'::date, '2026-08', 'approved_r1c_a_manifest');

lock table public.school_lesson_records in access exclusive mode;
lock table
  public.school_feature_gates,
  public.school_student_tuition_bills,
  public.school_income_records,
  public.school_student_tuition_billing_identities,
  public.school_student_tuition_bill_lessons,
  public.school_business_entity_migration_batches,
  public.school_business_entity_migration_items,
  public.school_personal_cash_income_linkage_events,
  public.school_account_transactions,
  public.school_student_monthly_settlements,
  public.school_teacher_wage_locks,
  public.school_teacher_wage_lock_details,
  public.school_tuition_billing_attribution_override_audit
in share mode;

create temporary table r1d_c_b_a1_non_target_before on commit drop as
select lesson.id, to_jsonb(lesson) as row_snapshot
from public.school_lesson_records lesson
where not exists (
  select 1 from r1d_c_b_a1_manifest manifest where manifest.lesson_id = lesson.id
);

create temporary table r1d_c_b_a1_business_before (
  object_name text primary key,
  row_count bigint not null,
  business_hash text not null
) on commit drop;

insert into r1d_c_b_a1_business_before
select 'tuition_bill',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_student_tuition_bills t
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
union all select 'feature_gate',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by feature_key),'')) from public.school_feature_gates t
union all select 'override_audit',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_tuition_billing_attribution_override_audit t;

create temporary table r1d_c_b_a1_execution_context (
  decided_at timestamptz not null
) on commit drop;

create temporary table r1d_c_b_a1_updated_ids (
  lesson_id uuid primary key
) on commit drop;

do $$
declare
  v_count integer;
  v_hash text;
  v_decided_at timestamptz;
begin
  select count(*)::integer,
         md5(string_agg(expected_old31_hash,'' order by lesson_id::text))
  into v_count,v_hash
  from r1d_c_b_a1_manifest;

  if v_count <> 52
     or (select count(distinct lesson_id) from r1d_c_b_a1_manifest) <> 52
     or (select min(item_order) from r1d_c_b_a1_manifest) <> 1
     or (select max(item_order) from r1d_c_b_a1_manifest) <> 52
     or v_hash <> '13c3217f56b10166770bd0ee15b28e15' then
    raise exception 'R1D_C_B_A1_MANIFEST_SHAPE_OR_HASH_MISMATCH: rows=%, hash=%',v_count,v_hash;
  end if;

  if exists (
    select 1 from r1d_c_b_a1_manifest
    where proposed_billing_month <> '2026-08'
       or proposed_student_settlement_month <> proposed_billing_month
       or proposed_billing_month_source <> 'approved_r1c_a_manifest'
       or extract(isodow from proposed_billing_week_start_date)::integer <> 1
       or to_char(proposed_billing_week_start_date,'YYYY-MM') <> proposed_billing_month
  ) then
    raise exception 'R1D_C_B_A1_MANIFEST_PROPOSED_VALUE_MISMATCH';
  end if;

  if (select count(*) from r1d_c_b_a1_manifest
      where expected_student_id='7aef8061-7037-4881-a847-a2cdb031c0f4') <> 30
     or (select count(*) from r1d_c_b_a1_manifest
         where expected_student_id='b17abc58-2f64-4bad-bf20-c9643ead60bc') <> 22 then
    raise exception 'R1D_C_B_A1_STUDENT_DISTRIBUTION_MISMATCH';
  end if;

  if (select count(*) from pg_constraint
      where conrelid='public.school_lesson_records'::regclass
        and convalidated
        and conname in (
          'school_lesson_records_billing_month_format_chk',
          'school_lesson_records_student_settlement_month_format_chk',
          'school_lesson_records_billing_pair_complete_chk',
          'school_lesson_records_billing_week_monday_chk',
          'school_lesson_records_billing_month_week_match_chk',
          'school_lesson_records_planned_attribution_fields_chk',
          'school_lesson_records_billing_source_metadata_chk'
        )) <> 7 then
    raise exception 'R1D_C_B_A1_SEVEN_CONSTRAINTS_NOT_VALIDATED';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_records_updated_at'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'R1D_C_B_A1_UPDATED_AT_TRIGGER_NOT_ENABLED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='validation_preview_only')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked')) <> 3 then
    raise exception 'R1D_C_B_A1_R0_GATE_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id='c1000000-0000-4000-8000-202607279999') <> 52 then
    raise exception 'R1D_C_B_A1_MIGRATION_BATCH_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from r1d_c_b_a1_manifest manifest
    left join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
    left join public.school_business_entity_migration_items item
      on item.batch_id='c1000000-0000-4000-8000-202607279999'
     and item.lesson_record_id=manifest.lesson_id
    where lesson.id is null
       or item.id is null
       or lesson.lesson_type is distinct from 'planned'
       or lesson.app_type is distinct from 'school'
       or lesson.student_id is distinct from manifest.expected_student_id
       or lesson.import_batch_id is distinct from manifest.expected_generation_batch_id
       or lesson.updated_at is distinct from manifest.expected_updated_at
       or md5((to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at')::text) <> manifest.expected_old31_hash
       or (to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at') is distinct from item.after_row_snapshot
       or item.original_updated_at is distinct from manifest.expected_updated_at
       or item.student_id is distinct from manifest.expected_student_id
       or item.source_generation_batch_id is distinct from manifest.expected_generation_batch_id
       or lesson.billing_month is not null
       or lesson.billing_week_start_date is not null
       or lesson.scheduled_lesson_date is not null
       or lesson.student_settlement_month is not null
       or lesson.billing_month_source is not null
       or lesson.billing_month_decided_at is not null
  ) then
    raise exception 'R1D_C_B_A1_FIXED_BEFORE_FINGERPRINT_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_lesson_records actual
    join r1d_c_b_a1_manifest manifest on manifest.lesson_id=actual.planned_lesson_id
    where actual.lesson_type='actual'
  ) then
    raise exception 'R1D_C_B_A1_TARGET_HAS_ACTUAL';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bill_lessons relation
    join r1d_c_b_a1_manifest manifest on manifest.lesson_id=relation.planned_lesson_id
  ) then
    raise exception 'R1D_C_B_A1_TARGET_HAS_BILL_RELATION';
  end if;

  if (select count(distinct candidate.planned_lesson_id)
      from r1d_c_b_a1_manifest manifest
      join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
      cross join lateral public.school_list_student_tuition_candidates(
        lesson.student_id,lesson.business_entity_id,lesson.year_month,false
      ) candidate
      where candidate.planned_lesson_id=manifest.lesson_id
        and candidate.candidate_status='candidate') <> 52 then
    raise exception 'R1D_C_B_A1_TARGET_CANDIDATE_BASELINE_MISMATCH';
  end if;

  if (select count(*) from r1d_c_b_a1_non_target_before) <> 574 then
    raise exception 'R1D_C_B_A1_NON_TARGET_COUNT_MISMATCH';
  end if;

  v_decided_at := clock_timestamp();
  insert into r1d_c_b_a1_execution_context values (v_decided_at);

  execute 'alter table public.school_lesson_records disable trigger trg_school_lesson_records_updated_at';
  begin
    with changed as (
      update public.school_lesson_records lesson
      set billing_month=manifest.proposed_billing_month,
          billing_week_start_date=manifest.proposed_billing_week_start_date,
          student_settlement_month=manifest.proposed_student_settlement_month,
          billing_month_source=manifest.proposed_billing_month_source,
          billing_month_decided_at=v_decided_at
      from r1d_c_b_a1_manifest manifest
      where lesson.id=manifest.lesson_id
        and lesson.updated_at=manifest.expected_updated_at
        and md5((to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at')::text)=manifest.expected_old31_hash
        and lesson.billing_month is null
        and lesson.billing_week_start_date is null
        and lesson.scheduled_lesson_date is null
        and lesson.student_settlement_month is null
        and lesson.billing_month_source is null
        and lesson.billing_month_decided_at is null
      returning lesson.id
    )
    insert into r1d_c_b_a1_updated_ids select id from changed;

    get diagnostics v_count = row_count;
    if v_count <> 52 then
      raise exception 'R1D_C_B_A1_UPDATE_COUNT_MISMATCH: expected 52, got %',v_count;
    end if;
  exception when others then
    execute 'alter table public.school_lesson_records enable trigger trg_school_lesson_records_updated_at';
    raise;
  end;
  execute 'alter table public.school_lesson_records enable trigger trg_school_lesson_records_updated_at';
end;
$$;

set constraints all immediate;

do $$
declare
  v_after_business record;
  v_before_business record;
begin
  if (select count(*) from r1d_c_b_a1_updated_ids) <> 52
     or exists (
       select lesson_id from r1d_c_b_a1_manifest
       except select lesson_id from r1d_c_b_a1_updated_ids
     )
     or exists (
       select lesson_id from r1d_c_b_a1_updated_ids
       except select lesson_id from r1d_c_b_a1_manifest
     ) then
    raise exception 'R1D_C_B_A1_UPDATED_ID_SET_MISMATCH';
  end if;

  if exists (
    select 1
    from r1d_c_b_a1_manifest manifest
    join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
    cross join r1d_c_b_a1_execution_context execution
    where lesson.billing_month is distinct from manifest.proposed_billing_month
       or lesson.billing_week_start_date is distinct from manifest.proposed_billing_week_start_date
       or lesson.student_settlement_month is distinct from manifest.proposed_student_settlement_month
       or lesson.billing_month_source is distinct from manifest.proposed_billing_month_source
       or lesson.billing_month_decided_at is distinct from execution.decided_at
       or lesson.scheduled_lesson_date is not null
       or lesson.lesson_type is distinct from 'planned'
       or lesson.updated_at is distinct from manifest.expected_updated_at
       or md5((to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at')::text) <> manifest.expected_old31_hash
  ) then
    raise exception 'R1D_C_B_A1_TARGET_AFTER_MISMATCH';
  end if;

  if (select count(distinct billing_month_decided_at)
      from public.school_lesson_records lesson
      join r1d_c_b_a1_manifest manifest on manifest.lesson_id=lesson.id) <> 1 then
    raise exception 'R1D_C_B_A1_DECIDED_AT_NOT_UNIFIED';
  end if;

  if exists (
    select 1
    from r1d_c_b_a1_non_target_before before_row
    join public.school_lesson_records lesson on lesson.id=before_row.id
    where to_jsonb(lesson) is distinct from before_row.row_snapshot
  ) or (select count(*) from r1d_c_b_a1_non_target_before) <> 574 then
    raise exception 'R1D_C_B_A1_NON_TARGET_ROW_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records
      where billing_month is not null) <> 52
     or (select count(*) from public.school_lesson_records
         where billing_week_start_date is not null) <> 52
     or (select count(*) from public.school_lesson_records
         where student_settlement_month is not null) <> 52
     or (select count(*) from public.school_lesson_records
         where billing_month_source is not null) <> 52
     or (select count(*) from public.school_lesson_records
         where billing_month_decided_at is not null) <> 52
     or (select count(*) from public.school_lesson_records
         where scheduled_lesson_date is not null) <> 0 then
    raise exception 'R1D_C_B_A1_GLOBAL_NEW_FIELD_SCOPE_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items item
      join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
      where item.batch_id='c1000000-0000-4000-8000-202607289999'
        and lesson.billing_month is null
        and lesson.billing_week_start_date is null
        and lesson.scheduled_lesson_date is null
        and lesson.student_settlement_month is null
        and lesson.billing_month_source is null
        and lesson.billing_month_decided_at is null) <> 66 then
    raise exception 'R1D_C_B_A1_R1C_C_B_66_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records
      where lesson_type='actual'
        and billing_month is null
        and billing_week_start_date is null
        and scheduled_lesson_date is null
        and student_settlement_month is null
        and billing_month_source is null
        and billing_month_decided_at is null) <> 229 then
    raise exception 'R1D_C_B_A1_ACTUAL_CHANGED';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_records_updated_at'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'R1D_C_B_A1_UPDATED_AT_TRIGGER_NOT_REENABLED';
  end if;

  for v_after_business in
    select 'tuition_bill' object_name,count(*) row_count,md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) business_hash from public.school_student_tuition_bills t
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
    union all select 'feature_gate',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by feature_key),'')) from public.school_feature_gates t
    union all select 'override_audit',count(*),md5(coalesce(string_agg(md5(to_jsonb(t)::text),'' order by id::text),'')) from public.school_tuition_billing_attribution_override_audit t
  loop
    select * into v_before_business
    from r1d_c_b_a1_business_before
    where object_name=v_after_business.object_name;
    if v_before_business.row_count is distinct from v_after_business.row_count
       or v_before_business.business_hash is distinct from v_after_business.business_hash then
      raise exception 'R1D_C_B_A1_BUSINESS_BASELINE_CHANGED: %',v_after_business.object_name;
    end if;
  end loop;

  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='validation_preview_only')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked')) <> 3 then
    raise exception 'R1D_C_B_A1_R0_GATE_CHANGED';
  end if;
end;
$$;

select
  count(*) as updated_rows,
  min(execution.decided_at) as billing_month_decided_at,
  count(distinct lesson.billing_month_decided_at) as distinct_decided_at,
  count(*) filter (where lesson.scheduled_lesson_date is null) as scheduled_null_rows,
  md5(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text),'' order by lesson.id::text)) as old31_hash
from r1d_c_b_a1_manifest manifest
join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
cross join r1d_c_b_a1_execution_context execution;

select
  lesson.billing_week_start_date,
  count(*) as lesson_count,
  sum(lesson.duration_hours) as hours,
  sum(lesson.lesson_fee) as fee_jpy
from r1d_c_b_a1_manifest manifest
join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
group by lesson.billing_week_start_date
order by lesson.billing_week_start_date;

\if :r1d_c_b_a1_commit
  commit;
\else
  rollback;
\endif
