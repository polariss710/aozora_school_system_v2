-- School V2 tuition P0 R1C-A: fixed 52-ID planned-lesson business-entity migration.
-- Required psql variable: r1c_commit=0 for rollback rehearsal or 1 for formal execution.
-- This file never selects migration targets dynamically. Every row is identified
-- by a fixed UUID and must match its complete pre-migration row hash.

\set ON_ERROR_STOP on

begin;

create temporary table r1c_a_manifest (
  item_order integer not null,
  planned_lesson_id uuid primary key,
  expected_student_id uuid not null,
  expected_source_batch_id text not null,
  expected_from_business_entity_id uuid not null,
  expected_lesson_date date not null,
  expected_year_month text not null,
  expected_teacher_id uuid not null,
  expected_subject_id uuid not null,
  expected_lesson_count integer not null,
  expected_duration_hours numeric not null,
  expected_unit_price numeric not null,
  expected_lesson_fee numeric not null,
  expected_status text not null,
  expected_created_at timestamptz not null,
  expected_updated_at timestamptz not null,
  expected_row_hash text not null
) on commit drop;

insert into r1c_a_manifest values
  (1, '23d4b46b-eb1c-48b7-8001-d208ce14f08d'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '993e3806558cc2d230dbfa84d7cc33d2'),
  (2, '637ba833-830f-42a6-81ed-47a6f9902523'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'e056bd171ba1f6f6c72c85296188b79a'),
  (3, '7175780c-b179-4f96-a42e-99ba11bdaed8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'eb8addbd2c972d08f4c6135980df8152'),
  (4, '80384c28-5044-4c56-94cd-5099aa852032'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'b42a13fccc8a05054dcc00bb658eb55e'),
  (5, '920808f2-5629-4fcc-957c-6bdcee48808e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '599bcf87c019542f2d56576817d1effe'),
  (6, 'd06f136e-d4c5-44fb-ae5e-d87efa26bbfb'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'b34ee38a48cfcb6c63fba63538f9ecbf'),
  (7, '3db3ad8b-44b6-4be7-a3ea-611362b82488'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '948983a8ec5663b44ffe044fe76e0384'),
  (8, '6997acdc-fec4-4e14-a22b-d9f5291b1e0b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'dad81e74f73063d9a299991e46673256'),
  (9, '69ecc019-9f8f-474e-8dc9-1dced16e41a6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '5e70c72de955da2b6b27e17953a9f69e'),
  (10, '72ffebba-ecb3-4a96-9550-f02a5f64cf62'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '8c56632af91fde27fc8e95c93b1f5286'),
  (11, 'c0e9fd95-7833-44ef-a282-61611976b089'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '559f7fd6a2f485ea8ccca1b3274b82d1'),
  (12, 'e6aaf546-bb9c-4e71-980e-40f78f2e1e11'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '9242057cb858c5714a9d70fc4e8b6d18'),
  (13, '12d70ee9-8221-4b8e-a01c-61548340c42d'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'e4284f940fdca2a631c8196ff084efeb'),
  (14, '1927b6ba-6ca6-4ef9-b1c0-0246067c7d41'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'ec1b3e0f77b80fdbfd4d9b4f7a6d0a6c'),
  (15, '3920fdea-2f9d-4b17-abd0-f788b0d7d29e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '10d7c9c2795c6d675784d817d7c238ea'),
  (16, '95dff1ab-544d-43be-bc0e-a95232f06935'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'fee1dc2f588daf41d2d8e28de57d3580'),
  (17, 'a10744fc-173a-4b25-9bc3-99d6437797c5'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2001ad1047d7472eac01b7d73604f499'),
  (18, 'a601916b-6add-4be6-adcc-5c232425f686'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '9db9d6e9363a39204c8408ab3f383ab3'),
  (19, '286344d1-c603-4990-aba3-814996535319'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '40820046da11f4e07acce87ccb2eecaf'),
  (20, '9a76aed4-058f-4801-90b5-b2637387fb3e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'fe36193df43f2e02bfc7c50ea0540879'),
  (21, '9f755093-8f4d-4337-80ed-23d0e555c835'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '0955171430d89a6ac42b64fbc37904c6'),
  (22, 'e2540bb3-5c1f-45bc-b964-9727a6ed3e48'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'e85e6cda3434165afeaf8e5e54d36b0b'),
  (23, 'ee6c1383-4259-44e0-923c-1ee6b8749820'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2fcaa752eaa6b385fbd8bb261e024ebc'),
  (24, 'ee86e691-2c96-48c2-ad57-512f9eef4b3c'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'c1fe954541c2e97d0296a3f21990262d'),
  (25, '01490eb7-1bd7-430a-ba26-3ccc81d45796'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '69dbe9547f3b31e364b0abb9133a3ffc'),
  (26, '80e03531-5eaa-40e1-a435-0132dd62d5c0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2d5bd00a308f24f21c9b27038713fa20'),
  (27, '8c6da1a7-69a9-45b6-9a77-daa2bfd7f9e9'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '52a501d8db610126eb739d589e3b13db'),
  (28, '9efe2def-ff59-467a-bb76-a49537ec8e0f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, '168bcf37eb802c26944803750dce1aff'),
  (29, 'adc0b06c-eee3-40ca-8992-592f5d4b009b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'dad17b279a05cc120d59553b35c6fbda'),
  (30, 'dbe16731-803b-49db-8cc0-f826e911bb41'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04T03:43:09.607005+00:00'::timestamptz, '2026-07-04T03:43:09.607005+00:00'::timestamptz, 'b7ce2baa5664d7052af448cc1a7ff680'),
  (31, '222c4ad5-b6fe-4e4e-b192-8db8c65b61fa'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'ffc18c002597b77a3ed1f2037b08a844'),
  (32, '6c70c4c1-1895-453d-b9b0-591e9f004f86'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2e980717dfc30cc996101436d5e961d4'),
  (33, '89da310d-4f17-4a40-8315-659838aec59c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'f0aa0d0e5b14f4bf2183263e00f607c9'),
  (34, '9efb8862-e8c5-4f3d-9d55-b0be4317ad19'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-03'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'aa0728c018de3513dae269cb27a59d49'),
  (35, '37a2083e-bb28-45d1-802a-f98f4564887f'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '90a653a4d812c68afb54e4b1ad8d14ef'),
  (36, '63ca3a2b-7c2f-4eed-a997-71840357f8f6'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'e4fa8f0dbd1118796a0666614ad48a0e'),
  (37, 'a3ee5595-6dd5-4737-8605-ff5a8d7d0333'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '0f2a5b895356f26573c033b343561a7d'),
  (38, 'ea766c1d-f152-4b3f-9400-0d5b5aa64614'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'a5ddee910333c337e4d157aff64d9eb4'),
  (39, 'fcbf1be4-567b-4876-9cc6-19cd0d395da0'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-10'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '763c934627f53dad6f92b55d8ba20975'),
  (40, '1df61ad9-742f-4fd6-b883-b3a8bbb0c4e8'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '0b6966ead96429c691fcdea8bb445d8c'),
  (41, '68bbce4e-f6bb-45c6-9798-ee72b6f75179'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '95f8bfe2b386158b0451e5db2171b7e7'),
  (42, '9bdb88c1-9c08-4716-b146-e98cf149978b'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'd45ab80204a907a66fce42550f94c31a'),
  (43, 'fa7883c8-35e6-40bd-92d1-70adcdcce078'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-17'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'e67c1bac7414a05e07edd2f73777b50d'),
  (44, '1f9c027a-6db2-4aa2-8bef-215f3ed2bbb9'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '38d6ca8cba05411142f19eb78dc8076f'),
  (45, '475853f0-2004-4375-ae72-013c5a86987c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'c0cc01721dc09c2e80a30fe71510d7bb'),
  (46, '6e005bee-2d14-4722-8b76-9dbe7f836e12'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2af021da7e2fd3b3c699d33d0cfc8ddb'),
  (47, 'cde683d3-06f2-46ec-8b8a-4f2ed4b4962e'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2a6c1e964d62ba4d111162b88c9502cd'),
  (48, 'e65b7d1d-45b2-4485-ae6d-7000fe92ce78'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-24'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, 'ffd7b8d4927c5bd693f823391ffab117'),
  (49, '02b9e85e-2e03-404d-93a6-9bfef3bf186d'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '9b7d5836597c9394c1716bbf97c3e03f'),
  (50, '0d048cbf-a5f5-458c-88aa-ce0c3a1c667c'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '50ba8a5847efff298560079e94c14ddd'),
  (51, '196c9d86-500b-4687-a051-88dcc12fa2a9'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '94ee81c0c92d6ec41b8f6d09c3a53663'),
  (52, 'aa55dc2e-3b1b-4d2d-863f-9f64e84b8578'::uuid, 'b17abc58-2f64-4bad-bf20-c9643ead60bc'::uuid, '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-08-31'::date, '2026-08', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 8500, 17000, 'planned', '2026-07-08T06:50:55.529737+00:00'::timestamptz, '2026-07-08T06:50:55.529737+00:00'::timestamptz, '80d49b953d7f75c847ec84437b9ab95f');

lock table public.school_lesson_records in access exclusive mode;
lock table
  public.school_feature_gates,
  public.school_business_entities,
  public.school_students,
  public.school_student_tuition_bills,
  public.school_student_tuition_bill_lessons,
  public.school_income_records,
  public.school_personal_cash_income_linkage_events,
  public.school_account_transactions,
  public.school_student_monthly_settlements,
  public.school_teacher_wage_locks,
  public.school_teacher_wage_lock_details
in share mode;
lock table
  public.school_business_entity_migration_batches,
  public.school_business_entity_migration_items
in row exclusive mode;

do $$
declare
  v_count integer;
  v_hash text;
begin
  select count(*)::integer into v_count from r1c_a_manifest;
  if v_count <> 52
     or (select count(distinct item_order) from r1c_a_manifest) <> 52
     or (select min(item_order) from r1c_a_manifest) <> 1
     or (select max(item_order) from r1c_a_manifest) <> 52 then
    raise exception 'R1C_A_MANIFEST_COUNT_MISMATCH: expected fixed item orders 1..52, got % rows.', v_count;
  end if;

  select md5(string_agg(expected_row_hash, '' order by planned_lesson_id::text))
  into v_hash
  from r1c_a_manifest;
  if v_hash <> '698f2bcb8f1fbc947b1f9785b5041b9a' then
    raise exception 'R1C_A_MANIFEST_HASH_MISMATCH: %', v_hash;
  end if;

  if (select count(*) from r1c_a_manifest
      where expected_student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
        and expected_source_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275') <> 30
     or (select sum(expected_duration_hours) from r1c_a_manifest
         where expected_student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4') <> 65
     or (select sum(expected_lesson_fee) from r1c_a_manifest
         where expected_student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4') <> 650000 then
    raise exception 'R1C_A_ZHANG_MANIFEST_SUMMARY_MISMATCH';
  end if;

  if (select count(*) from r1c_a_manifest
      where expected_student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
        and expected_source_batch_id = '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c') <> 22
     or (select sum(expected_duration_hours) from r1c_a_manifest
         where expected_student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc') <> 44
     or (select sum(expected_lesson_fee) from r1c_a_manifest
         where expected_student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc') <> 374000 then
    raise exception 'R1C_A_SUN_MANIFEST_SUMMARY_MISMATCH';
  end if;

  if (select sum(expected_duration_hours) from r1c_a_manifest) <> 109
     or (select sum(expected_lesson_fee) from r1c_a_manifest) <> 1024000
     or exists (
       select 1 from r1c_a_manifest
       where expected_year_month <> '2026-08'
          or expected_from_business_entity_id <> '886a8f7c-0fea-45ac-97d2-15c976ede996'
          or expected_status <> 'planned'
     ) then
    raise exception 'R1C_A_MANIFEST_TOTAL_OR_SCOPE_MISMATCH';
  end if;

  if exists (
    select 1 from r1c_a_manifest
    where planned_lesson_id in (
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
  ) then
    raise exception 'R1C_A_CROSS_MONTH_LESSON_IN_MANIFEST';
  end if;

  if not exists (
    select 1 from public.school_business_entities
    where id = '886a8f7c-0fea-45ac-97d2-15c976ede996'
      and name = '个人名义'
      and entity_type = 'personal'
      and is_active is true
  ) or not exists (
    select 1 from public.school_business_entities
    where id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      and name = '青空进学塾'
      and entity_type = 'company'
      and is_active is true
  ) then
    raise exception 'R1C_A_BUSINESS_ENTITY_IDENTITY_MISMATCH';
  end if;

  if (select count(*) from public.school_students
      where id in (
        '7aef8061-7037-4881-a847-a2cdb031c0f4',
        'b17abc58-2f64-4bad-bf20-c9643ead60bc'
      )
        and business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        and status = 'active') <> 2 then
    raise exception 'R1C_A_STUDENT_TARGET_ENTITY_OR_STATUS_MISMATCH';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'R1C_A_R0_GATE_MISMATCH';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_lesson_records'::regclass
      and tgname = 'trg_school_lesson_records_updated_at'
      and tgenabled = 'O'
      and not tgisinternal
  ) then
    raise exception 'R1C_A_UPDATED_AT_TRIGGER_NOT_ENABLED';
  end if;

  if exists (
    select 1
    from r1c_a_manifest m
    left join public.school_lesson_records l on l.id = m.planned_lesson_id
    where l.id is null
       or md5(to_jsonb(l)::text) <> m.expected_row_hash
       or l.student_id is distinct from m.expected_student_id
       or l.import_batch_id is distinct from m.expected_source_batch_id
       or l.business_entity_id is distinct from m.expected_from_business_entity_id
       or l.lesson_date is distinct from m.expected_lesson_date
       or l.year_month is distinct from m.expected_year_month
       or l.teacher_id is distinct from m.expected_teacher_id
       or l.subject_id is distinct from m.expected_subject_id
       or l.lesson_count is distinct from m.expected_lesson_count
       or l.duration_hours is distinct from m.expected_duration_hours
       or l.unit_price is distinct from m.expected_unit_price
       or l.lesson_fee is distinct from m.expected_lesson_fee
       or l.status is distinct from m.expected_status
       or l.created_at is distinct from m.expected_created_at
       or l.updated_at is distinct from m.expected_updated_at
       or l.app_type <> 'school'
       or l.lesson_type <> 'planned'
       or l.planned_lesson_id is not null
       or l.is_billable is not true
       or l.voided_at is not null
  ) then
    raise exception 'R1C_A_FIXED_ROW_FINGERPRINT_MISMATCH';
  end if;

  if (select count(*) from public.school_lesson_records l
      where (
        l.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
        and l.import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
        and l.year_month = '2026-08'
      ) or (
        l.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
        and l.import_batch_id = '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c'
        and l.year_month = '2026-08'
      )) <> 52
     or exists (
       select 1
       from public.school_lesson_records l
       where (
         (
           l.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
           and l.import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
           and l.year_month = '2026-08'
         ) or (
           l.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
           and l.import_batch_id = '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c'
           and l.year_month = '2026-08'
         )
       )
       and not exists (
         select 1 from r1c_a_manifest m where m.planned_lesson_id = l.id
       )
     ) then
    raise exception 'R1C_A_SOURCE_BATCH_MONTH_COMPLETENESS_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_student_tuition_bill_lessons rel
    join r1c_a_manifest m on m.planned_lesson_id = rel.planned_lesson_id
  ) or exists (
    select 1 from public.school_student_tuition_bills b
    join r1c_a_manifest m
      on (b.source_snapshot -> 'planned_lesson_ids') ? m.planned_lesson_id::text
  ) then
    raise exception 'R1C_A_TARGET_HAS_TUITION_BILL_RELATION';
  end if;

  if exists (
    select 1 from public.school_lesson_records actual
    join r1c_a_manifest m on m.planned_lesson_id = actual.planned_lesson_id
    where actual.lesson_type = 'actual'
      and actual.voided_at is null
  ) then
    raise exception 'R1C_A_TARGET_HAS_ACTUAL_LESSON';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details detail
    join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
    where wage.status <> 'void'
      and (
        exists (
          select 1 from r1c_a_manifest m
          where m.planned_lesson_id = detail.lesson_record_id
        )
        or exists (
          select 1
          from public.school_lesson_records actual
          join r1c_a_manifest m on m.planned_lesson_id = actual.planned_lesson_id
          where actual.id = detail.lesson_record_id
        )
      )
  ) then
    raise exception 'R1C_A_TARGET_HAS_EFFECTIVE_WAGE_DETAIL';
  end if;

  if exists (
    select 1
    from public.school_student_monthly_settlements settlement
    where settlement.student_id in (
      '7aef8061-7037-4881-a847-a2cdb031c0f4',
      'b17abc58-2f64-4bad-bf20-c9643ead60bc'
    )
      and settlement.year_month = '2026-08'
  ) then
    raise exception 'R1C_A_TARGET_MONTH_HAS_SETTLEMENT';
  end if;

  if exists (
    select 1 from public.school_income_records income
    join r1c_a_manifest m on to_jsonb(income)::text like '%' || m.planned_lesson_id::text || '%'
  ) or exists (
    select 1 from public.school_personal_cash_income_linkage_events linkage
    join r1c_a_manifest m on to_jsonb(linkage)::text like '%' || m.planned_lesson_id::text || '%'
  ) or exists (
    select 1 from public.school_account_transactions transaction_row
    join r1c_a_manifest m on to_jsonb(transaction_row)::text like '%' || m.planned_lesson_id::text || '%'
  ) then
    raise exception 'R1C_A_TARGET_HAS_INCOME_CASH_OR_ACCOUNT_REFERENCE';
  end if;

  if (select count(*) from public.school_lesson_records l
      where l.id in (
        '8b737b58-cd14-42c5-afd2-34730dcef963',
        '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
      )
        and l.student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
        and l.business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        and l.duration_hours = 2
        and l.unit_price = 8500
        and l.lesson_fee = 17000
        and (
          (l.id = '8b737b58-cd14-42c5-afd2-34730dcef963' and l.lesson_date = '2026-08-01')
          or (l.id = '685ad45e-b5da-42ca-8f43-7732e8d6e40d' and l.lesson_date = '2026-08-02')
        )) <> 2
     or exists (
       select 1 from public.school_lesson_records l
       where (l.id = '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
              and md5(to_jsonb(l)::text) <> '2d52e778bfb59a27bb3b28506232217d')
          or (l.id = '8b737b58-cd14-42c5-afd2-34730dcef963'
              and md5(to_jsonb(l)::text) <> '21f83674162b1b1ca485912a048bac3c')
     )
     or (select count(*) from public.school_student_tuition_bill_lessons rel
         where rel.planned_lesson_id in (
           '8b737b58-cd14-42c5-afd2-34730dcef963',
           '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
         )
           and rel.tuition_bill_id = '2a9f1c25-a060-461e-ae10-b02295dec381'
           and rel.relation_role = 'canonical_charge') <> 2 then
    raise exception 'R1C_A_CROSS_MONTH_CANONICAL_EVIDENCE_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_business_entity_migration_batches
    where id = 'c1000000-0000-4000-8000-202607279999'
       or migration_key = 'r1c-a:2026-08:planned-business-entity:personal-to-aosora'
  ) or exists (
    select 1 from public.school_business_entity_migration_items item
    join r1c_a_manifest m on m.planned_lesson_id = item.lesson_record_id
  ) then
    raise exception 'R1C_A_AUDIT_ALREADY_EXISTS';
  end if;
end;
$$;

create temporary table r1c_a_before_rows on commit drop as
select
  m.*,
  to_jsonb(l) as original_row_snapshot
from r1c_a_manifest m
join public.school_lesson_records l on l.id = m.planned_lesson_id;

create temporary table r1c_a_school_baseline (
  object_name text primary key,
  row_count bigint not null,
  object_hash text not null
) on commit drop;

insert into r1c_a_school_baseline
select 'tuition_bills', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_bills t
union all
select 'income_records', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_income_records t
union all
select 'billing_identities', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_billing_identities t
union all
select 'bill_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_bill_lessons t
union all
select 'cash_linkage', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_personal_cash_income_linkage_events t
union all
select 'account_transactions', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_account_transactions t
union all
select 'actual_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_lesson_records t where t.lesson_type = 'actual'
union all
select 'settlements', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_monthly_settlements t
union all
select 'wage_locks', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_teacher_wage_locks t
union all
select 'wage_details', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_teacher_wage_lock_details t
union all
select
  'lesson_records_authorized_projection',
  count(*),
  md5(coalesce(string_agg(md5(
    case
      when exists (select 1 from r1c_a_manifest m where m.planned_lesson_id = t.id)
        then (to_jsonb(t) - 'business_entity_id')::text
      else to_jsonb(t)::text
    end
  ), '' order by t.id::text), ''))
from public.school_lesson_records t;

do $$
declare
  v_updated_count integer;
begin
  execute 'alter table public.school_lesson_records disable trigger trg_school_lesson_records_updated_at';
  begin
    update public.school_lesson_records lesson
    set business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
    from r1c_a_manifest manifest
    where lesson.id = manifest.planned_lesson_id;

    get diagnostics v_updated_count = row_count;
    if v_updated_count <> 52 then
      raise exception 'R1C_A_UPDATE_COUNT_MISMATCH: expected 52, got %.', v_updated_count;
    end if;
  exception when others then
    execute 'alter table public.school_lesson_records enable trigger trg_school_lesson_records_updated_at';
    raise;
  end;
  execute 'alter table public.school_lesson_records enable trigger trg_school_lesson_records_updated_at';
end;
$$;

do $$
begin
  if exists (
    select 1
    from r1c_a_before_rows before_row
    join public.school_lesson_records lesson
      on lesson.id = before_row.planned_lesson_id
    where lesson.business_entity_id <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
       or (to_jsonb(lesson) - 'business_entity_id')
          is distinct from (before_row.original_row_snapshot - 'business_entity_id')
       or lesson.updated_at is distinct from before_row.expected_updated_at
  ) then
    raise exception 'R1C_A_UNAUTHORIZED_LESSON_FIELD_CHANGE';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid = 'public.school_lesson_records'::regclass
      and tgname = 'trg_school_lesson_records_updated_at'
      and tgenabled = 'O'
      and not tgisinternal
  ) then
    raise exception 'R1C_A_UPDATED_AT_TRIGGER_NOT_REENABLED';
  end if;
end;
$$;

create temporary table r1c_a_execution_context on commit drop as
select statement_timestamp() as executed_at;

insert into public.school_business_entity_migration_batches (
  id,
  migration_key,
  migration_type,
  target_year_month,
  from_business_entity_id,
  to_business_entity_id,
  source_generation_batches,
  expected_lesson_count,
  expected_duration_hours,
  expected_lesson_fee_jpy,
  manifest_hash,
  evidence_source,
  approval_information,
  execution_status,
  executed_at,
  failure_reason,
  created_at,
  created_by
)
select
  'c1000000-0000-4000-8000-202607279999',
  'r1c-a:2026-08:planned-business-entity:personal-to-aosora',
  'planned_lesson_business_entity',
  '2026-08',
  '886a8f7c-0fea-45ac-97d2-15c976ede996',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  jsonb_build_object(
    '张倬闻', '5254a3fb-dc38-40c2-9cf3-810a79835275',
    '孙陈锋', '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c'
  ),
  52,
  109,
  1024000,
  '698f2bcb8f1fbc947b1f9785b5041b9a',
  'R0 August audit + R1A/R1B normalized billing evidence + fixed complete lesson-row fingerprints',
  jsonb_build_object(
    'approved_by', 'business_owner',
    'approved_scope', 'R1C-A fixed 52 future planned lessons only',
    'approval_date', '2026-07-27',
    'cross_month_exclusions', jsonb_build_array(
      '8b737b58-cd14-42c5-afd2-34730dcef963',
      '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
    )
  ),
  'executed',
  context.executed_at,
  null,
  context.executed_at,
  'codex-r1c-a-20260727'
from r1c_a_execution_context context;

insert into public.school_business_entity_migration_items (
  id,
  batch_id,
  item_order,
  lesson_record_id,
  student_id,
  target_year_month,
  source_generation_batch_id,
  from_business_entity_id,
  to_business_entity_id,
  original_row_snapshot,
  before_hash,
  original_updated_at,
  evidence_source,
  approval_information,
  execution_status,
  after_row_snapshot,
  after_hash,
  executed_at,
  failure_reason,
  created_at,
  created_by
)
select
  (
    substr(md5('c1000000-0000-4000-8000-202607279999:' || before_row.planned_lesson_id || ':r1c-a'), 1, 8)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607279999:' || before_row.planned_lesson_id || ':r1c-a'), 9, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607279999:' || before_row.planned_lesson_id || ':r1c-a'), 13, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607279999:' || before_row.planned_lesson_id || ':r1c-a'), 17, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607279999:' || before_row.planned_lesson_id || ':r1c-a'), 21, 12)
  )::uuid,
  'c1000000-0000-4000-8000-202607279999',
  before_row.item_order,
  before_row.planned_lesson_id,
  before_row.expected_student_id,
  before_row.expected_year_month,
  before_row.expected_source_batch_id,
  before_row.expected_from_business_entity_id,
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  before_row.original_row_snapshot,
  before_row.expected_row_hash,
  before_row.expected_updated_at,
  'Fixed UUID manifest with complete pre-migration row hash and downstream-zero proof',
  jsonb_build_object(
    'approved_by', 'business_owner',
    'approved_scope', 'R1C-A fixed 52 future planned lessons only',
    'student_id', before_row.expected_student_id,
    'source_generation_batch_id', before_row.expected_source_batch_id
  ),
  'executed',
  to_jsonb(lesson),
  md5(to_jsonb(lesson)::text),
  context.executed_at,
  null,
  context.executed_at,
  'codex-r1c-a-20260727'
from r1c_a_before_rows before_row
join public.school_lesson_records lesson on lesson.id = before_row.planned_lesson_id
cross join r1c_a_execution_context context
order by before_row.item_order;

set constraints all immediate;

create temporary table r1c_a_school_after (
  object_name text primary key,
  row_count bigint not null,
  object_hash text not null
) on commit drop;

insert into r1c_a_school_after
select 'tuition_bills', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_bills t
union all
select 'income_records', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_income_records t
union all
select 'billing_identities', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_billing_identities t
union all
select 'bill_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_tuition_bill_lessons t
union all
select 'cash_linkage', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_personal_cash_income_linkage_events t
union all
select 'account_transactions', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_account_transactions t
union all
select 'actual_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_lesson_records t where t.lesson_type = 'actual'
union all
select 'settlements', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_student_monthly_settlements t
union all
select 'wage_locks', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_teacher_wage_locks t
union all
select 'wage_details', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), ''))
from public.school_teacher_wage_lock_details t
union all
select
  'lesson_records_authorized_projection',
  count(*),
  md5(coalesce(string_agg(md5(
    case
      when exists (select 1 from r1c_a_manifest m where m.planned_lesson_id = t.id)
        then (to_jsonb(t) - 'business_entity_id')::text
      else to_jsonb(t)::text
    end
  ), '' order by t.id::text), ''))
from public.school_lesson_records t;

do $$
begin
  if exists (
    select 1
    from r1c_a_school_baseline before_state
    full join r1c_a_school_after after_state using (object_name)
    where before_state.object_name is null
       or after_state.object_name is null
       or before_state.row_count is distinct from after_state.row_count
       or before_state.object_hash is distinct from after_state.object_hash
  ) then
    raise exception 'R1C_A_NONAUTHORIZED_BASELINE_CHANGED';
  end if;

  if (select count(*) from public.school_business_entity_migration_batches
      where id = 'c1000000-0000-4000-8000-202607279999'
        and execution_status = 'executed'
        and manifest_hash = '698f2bcb8f1fbc947b1f9785b5041b9a') <> 1
     or (select count(*) from public.school_business_entity_migration_items
         where batch_id = 'c1000000-0000-4000-8000-202607279999'
           and execution_status = 'executed') <> 52 then
    raise exception 'R1C_A_AUDIT_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_business_entity_migration_items item
    where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
      and (
        md5(item.original_row_snapshot::text) <> item.before_hash
        or md5(item.after_row_snapshot::text) <> item.after_hash
        or (item.original_row_snapshot - 'business_entity_id')
           is distinct from (item.after_row_snapshot - 'business_entity_id')
        or item.original_row_snapshot ->> 'business_entity_id'
           <> '886a8f7c-0fea-45ac-97d2-15c976ede996'
        or item.after_row_snapshot ->> 'business_entity_id'
           <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
        or item.original_updated_at::text
           is distinct from (item.after_row_snapshot ->> 'updated_at')::timestamptz::text
      )
  ) then
    raise exception 'R1C_A_AUDIT_SNAPSHOT_MISMATCH';
  end if;

  if (select count(*) from r1c_a_manifest m
      join public.school_lesson_records l on l.id = m.planned_lesson_id
      where l.business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466') <> 52
     or (select count(*) from r1c_a_manifest m
         join public.school_lesson_records l on l.id = m.planned_lesson_id
         where l.business_entity_id = '886a8f7c-0fea-45ac-97d2-15c976ede996') <> 0 then
    raise exception 'R1C_A_TARGET_ENTITY_ACCEPTANCE_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_lesson_records l
    where (l.id = '685ad45e-b5da-42ca-8f43-7732e8d6e40d'
           and md5(to_jsonb(l)::text) <> '2d52e778bfb59a27bb3b28506232217d')
       or (l.id = '8b737b58-cd14-42c5-afd2-34730dcef963'
           and md5(to_jsonb(l)::text) <> '21f83674162b1b1ca485912a048bac3c')
  ) then
    raise exception 'R1C_A_CROSS_MONTH_ROWS_CHANGED';
  end if;
end;
$$;

select
  coalesce(student.display_name, student.name) as student_name,
  count(*) as migrated_lesson_count,
  sum((item.original_row_snapshot ->> 'duration_hours')::numeric) as duration_hours,
  sum((item.original_row_snapshot ->> 'lesson_fee')::numeric) as lesson_fee_jpy,
  count(*) filter (
    where item.original_updated_at = (item.after_row_snapshot ->> 'updated_at')::timestamptz
  ) as updated_at_unchanged
from public.school_business_entity_migration_items item
join public.school_students student on student.id = item.student_id
where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
group by student.display_name, student.name
order by student_name;

select
  item.item_order,
  item.lesson_record_id,
  item.student_id,
  item.source_generation_batch_id,
  item.before_hash,
  item.after_hash
from public.school_business_entity_migration_items item
where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
order by item.item_order;

\if :r1c_commit
  commit;
\else
  rollback;

  select
    (select count(*) from public.school_business_entity_migration_batches
     where id = 'c1000000-0000-4000-8000-202607279999') as batch_residue,
    (select count(*) from public.school_business_entity_migration_items
     where batch_id = 'c1000000-0000-4000-8000-202607279999') as item_residue,
    (select count(*) from public.school_lesson_records
     where business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
       and (
         (student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
          and import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
          and year_month = '2026-08')
         or
         (student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
          and import_batch_id = '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c'
          and year_month = '2026-08')
       )) as migrated_target_scope_residue;

  select
    count(*) as original_personal_scope_count,
    sum(duration_hours) as original_hours,
    sum(lesson_fee) as original_fee_jpy
  from public.school_lesson_records
  where business_entity_id = '886a8f7c-0fea-45ac-97d2-15c976ede996'
    and (
      (student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
       and import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
       and year_month = '2026-08')
      or
      (student_id = 'b17abc58-2f64-4bad-bf20-c9643ead60bc'
       and import_batch_id = '2ad82d0e-a5e0-4c62-b6d1-e23f46ac442c'
       and year_month = '2026-08')
    );
\endif
