-- School V2 tuition P0 R1C-C-B: fixed 66-ID Zhang future planned-lesson entity migration.
-- Required psql variable: r1c_c_b_commit=0 for rollback rehearsal or 1 for formal execution.
-- Execution targets are only the literal UUID/hash manifest below. Student/month/batch
-- predicates are completeness assertions and never select rows for UPDATE.

\set ON_ERROR_STOP on

begin;

create temporary table r1c_c_b_manifest (
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

insert into r1c_c_b_manifest values
  (1, '15f8147e-5bb0-4cf9-9ba7-3e12f115774e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '12d56243c2e3d2f086a61b8304cc1cbc'),
  (2, '224015ce-b435-4233-8113-0e6c712b1a18'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '2aacfa73b5c5a25cc37bbfd4bf8fe0a5'),
  (3, '2bd402cb-fc4d-48cc-b166-400ee4945703'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '8932c8024e3c49fd8ab06cb3b7858a52'),
  (4, 'c1f5c7e9-70e4-4c2d-99c8-aadd986cda15'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '10fee537e26570a52cf1044bd4b9c9b8'),
  (5, 'dadcf864-5343-403d-a111-e68b8617f413'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '8d3cea4cb6c5b4cb5151364ff6bd32d2'),
  (6, 'f91ecdd8-7442-4879-97b6-67ad8ea99f23'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-07'::date, '2026-09', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '0f7cce6422795daf71d2830add38f174'),
  (7, '10b62cc8-dd74-4665-a6cd-02cc02924a65'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '7e033b5989da8caa26a3b6f086a303cf'),
  (8, '57948b80-89d9-45f2-a99f-3b92aed9f4e8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '599cec021da9e901d19db3f4f7b932f4'),
  (9, '68da4912-72a8-418c-b30b-335bb9896c63'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '48350b8a77c2297e9c4acaeeb7d6ad91'),
  (10, 'a9de94c0-954b-452d-95b0-6a8b7d1a5a9e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '5747f991ad01590c0ffcd704f3146939'),
  (11, 'c79e2ade-4026-4ab3-a316-ba26354abfe2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'd4cbb87a047e2e6c3bb7d94a68c1d9ba'),
  (12, 'f693a3d9-fada-48f2-8203-bc33d46ee4dd'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-14'::date, '2026-09', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'cf007f7c0625bbfc7a1139ce3f43b659'),
  (13, '5591fb92-2333-460c-95f3-85c6511d6fd4'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '0894065af86da5bec68678c74f5d4cff'),
  (14, '645cccaf-ae0f-41b3-84d1-e40882a8c85f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '451e0fb9f6b74a5f685fccd3754138e9'),
  (15, '82e81ecc-dd23-471e-8402-a45bd8b20eb1'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'fc2d60a9be10b69e1d25249b16b07404'),
  (16, 'bf38024e-2a5f-422c-ad41-01ec9922e701'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '902b580a174a5664d8823d27514f1e09'),
  (17, 'dbd6f35a-b0ee-4af8-bcda-e065330f0413'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '8659c0ed70029c760346bbc7344bc307'),
  (18, 'fb066255-82b5-4eb1-9f76-a776c04becc2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-21'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '94d1df8602d5593bee66b6b37e1b7363'),
  (19, '1eeb937e-a7ad-4e7c-955d-797b9d979882'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '4ea590fe3dac3991c493c6916c789494'),
  (20, '21e97cbd-3e18-4c9e-9790-981f885af03a'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'ad86fd528a4991e917231679b663846c'),
  (21, '371e41c5-a659-44a6-87e0-c3a85c9c1b75'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '90211e1db2b192c40d2260dfd38e701f'),
  (22, '966119c6-09c8-4ac5-9c16-6cda13137d87'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '61b63b68c6d0998f0da5359b6eaef9d8'),
  (23, 'a9e861d3-6bd6-4b76-ba78-4cc1f3265b43'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'e0aae4aaaeea5b0e69a28fc1ef76a1f2'),
  (24, 'fd803263-07b6-4b1f-b668-43a482f21c89'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-09-28'::date, '2026-09', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '34c41fd38bca354f180e0f0ee207bb02'),
  (25, '0386bf22-8619-41f2-be6c-5106b8c17cd0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '8ab86cc4ab0063f9a5a005dd862b5713'),
  (26, '4254095b-9ec1-4651-a9ff-0dffb3a4520f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'd6cb7d5196a6d4aba0151ceb286803eb'),
  (27, '7e833e2c-3bc0-4c6d-a1ab-204229f43a77'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '93db4186a63a86332c069db26b2d7585'),
  (28, 'aea933f5-5e3b-4476-b1f0-d781d41312a3'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'de7821d7572d507fe39904e8bec6dbae'),
  (29, 'b33f023c-4b0c-495e-8f0b-934ead526421'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '9247dff70d9393390f8b0967276c2866'),
  (30, 'ff368fb5-94a8-4ea4-b3fc-d62ce499732b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-05'::date, '2026-10', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '64dbe380f64c2aab2e5a32e3fcd1a5ef'),
  (31, '17e58b7d-3fb8-4874-8071-0b1f808e8430'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'd82ba0a4a270059cbbb1b42e2fdb3a8e'),
  (32, '30271ef0-51ee-43ca-9103-1b5ec34255e1'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '8b7053df33b58e2115861b8acfef9725'),
  (33, 'a3a7dd70-1a1e-4078-bce8-d54f10fc57af'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'c94841a426d3533769296bb36b59d27c'),
  (34, 'cfb5e237-51a3-48b2-a12e-e8f0628e2c51'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '7a10d184831c000dd0b118b952adc4d3'),
  (35, 'd9d11e4b-a01c-4535-93cf-bc51cf08b900'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'b69a7d189dbc6ed9ff042cf44115c7c4'),
  (36, 'eec50614-788d-429b-99a4-fc8938a86dda'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-12'::date, '2026-10', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'bd72d1e53f349a42c0e7559165ddad53'),
  (37, '0ea530e7-12ac-41fa-9f6e-972b24662a72'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'd06b0ea5ac3615e1d65288889c482cd7'),
  (38, '297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '37ca5cf9752262c7decc6c407f84379f'),
  (39, '3048b190-31e0-49b1-a255-ce73e6e15fc0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'ed179234d3e62ac4e6d126e53d8c27a6'),
  (40, '70c31ae5-6083-46cb-90ad-fdc24726b6b6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '4302180a1a22a2acf07fb4d59c622505'),
  (41, '812979d0-43ac-4075-b38f-4c9aa455cd4b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'da74fc4325fa48b71bdb343da2831e8d'),
  (42, 'd1961919-8c05-42e8-8a06-4ed1fabb13c0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-19'::date, '2026-10', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '0df9d034ec2481a7ede96d1be7235ad6'),
  (43, '0a3a8c13-12cb-4430-a933-2941221c0c77'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '3a22cba84e5d83a88385f7ef77bd8351'),
  (44, '4505777b-13e3-4187-9839-618ebe186f22'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '746814ad793791e7db81f3bbe7c10167'),
  (45, '895ebf6e-6bf0-419d-bf9a-418d048a42a7'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '5f4b890353690103d5098ce3b7ab8401'),
  (46, '92a0f909-6458-4d34-9144-9d60eeede33f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'bc536f2a8a45ef3aa28d25be5afc2326'),
  (47, 'c48478ef-8b3d-4c7f-bd48-cc99659e99f7'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '5b54dd3614dd950ed4f8380819507212'),
  (48, 'd8ed3671-6865-42b6-a4a2-06b31c9051e6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-10-26'::date, '2026-10', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '5ea1c950e30ba5dc6d620481985d3429'),
  (49, '0624fabe-a3c8-4930-aa41-8ed800a28eea'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'cbcefbb0cc47f8047a2ae90d548476a3'),
  (50, '3f5884ea-ca12-41dc-89ce-ebc67db27fe8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', 'edaf30da-1315-4455-99d1-ead1b7147662'::uuid, '14257e03-4d08-478e-b1dc-33c685c3d8f9'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '0e1ea770f87e86d096f0eaf2d9db17ee'),
  (51, '89797ce3-58e0-4c9d-b107-79eca71e4161'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'f47da6a3b28c1341a43e9219fe94678e'),
  (52, 'a42b1b2e-4f55-4915-a20b-bd411b4d81a0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '11d4891fb37f950cf87870fcdfbf07c7'),
  (53, 'd2307a35-1f41-4402-ab4d-c03ed4305f50'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', 'c92ffb8f-c2af-48cd-99b1-2a2a75d70384'::uuid, '7cde0b12-6557-4fb5-8a27-804a03ff34e4'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '0541832b36c9a3549e2f2a626e64f166'),
  (54, 'fd34b0d7-86c2-4d0e-a519-de2317e0ab26'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-02'::date, '2026-11', 'bbc3d827-ba8b-4ded-a5ac-cafca88f26bd'::uuid, '20efb4d9-7e58-42a9-85bb-e34c3e1a7c90'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'd1d4c58bf0d7464f6e9b15a5a70045c9'),
  (55, '207430a6-c9cd-4acb-9a7d-962c078b0623'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-09'::date, '2026-11', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'a26f9291604e01fd05be81bdf631324d'),
  (56, '5666a624-05b5-4408-bc11-5d208851b216'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-09'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '722d1f66f1c56d6bd4f6fa10a3a89639'),
  (57, 'a57bf7af-43e1-46ba-9bb6-9ee511b81e05'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-09'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'ea7de78a84743f3237721844f561067c'),
  (58, '73dd0453-aec2-4612-b710-071a372f88ad'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-16'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'a42c9901944444fda961027d8522659a'),
  (59, 'bc718d5f-dc21-4e7d-914a-dd3a6debaeb6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-16'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'df597794e4861f4b4f54031ec238d1a0'),
  (60, 'f1a321d8-5528-4afe-8fb7-79204f49f3dc'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-16'::date, '2026-11', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '26b108cf2118b114e96ce604ad4cd87b'),
  (61, '584ef4d6-fa9d-4dd8-803c-cab68ac67a67'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-23'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '19d23787c86a9266631a777c45dc4f6f'),
  (62, 'a4cd05e7-47e7-4e0d-8af8-dad6c7505744'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-23'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'ec215c024147f0c57930e7db9b4cd0a6'),
  (63, 'fc138193-f76a-476c-a394-b49d2e68dde2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-23'::date, '2026-11', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'c632647833f336de856cd06345695c20'),
  (64, '0f168663-afb1-49a7-90a8-39197ad7729e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-30'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 1, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '9718ffd90f1709b57483f8fb8ebdb708'),
  (65, '594a4559-c1b1-4ad1-88e6-4c7834052831'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-30'::date, '2026-11', 'ea58874b-3656-4b14-8977-dc8bf9423997'::uuid, 'a7f9faaa-4480-44c0-9b66-fd70379ab7cb'::uuid, 2, 2, 10000, 20000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, 'bcee1559efcdb98b26265d9cebecb7c2'),
  (66, 'def65ad3-6f87-4889-802f-202550a9af49'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '886a8f7c-0fea-45ac-97d2-15c976ede996'::uuid, '2026-11-30'::date, '2026-11', '1ed3ef4e-4168-425d-a264-0fa3747e7448'::uuid, 'e0879c05-cd4d-4eba-98c6-2cd236ccdf33'::uuid, 1, 3, 10000, 30000, 'planned', '2026-07-04 03:43:09.607005+00'::timestamptz, '2026-07-04 03:43:09.607005+00'::timestamptz, '603d28c1b5776e086c453623e10ff665');

create temporary table r1c_c_b_li_exclusions (
  lesson_record_id uuid primary key,
  expected_row_hash text not null
) on commit drop;

insert into r1c_c_b_li_exclusions values
  ('f256bca9-fac5-4909-b113-8077efd27d65', '39a3d5ccc1755499b54595b303c49cc5'),
  ('a722a49e-dbe5-447d-8068-fd5fb743f6ab', 'f7b3636134ebd23191c5b6ea37c0d204'),
  ('265f4d3d-2372-42e3-aec3-b963bbdddf95', '6620ad1a8085077dbb8e4d4317f0af8f'),
  ('e890424d-407d-4fc2-b8ad-84745b242cdd', 'b707e69e1ece74e9b6edf2e44483f512'),
  ('552c54e3-2d0c-4607-962d-aad39dfff7f7', '82a2d4d62f96c07a3bb65a2c2e8b92a1'),
  ('b186fa1c-a56b-4ed7-b566-178a5708ae96', '3ac247e72ba1e8e55484d5bb96052a9c'),
  ('ac16b068-a58b-4ca5-be95-7c57c3f1b82b', '0c32bffa1f171517a1c034b0cb6d1195'),
  ('39aa30ab-d66c-43c0-bbde-3b3a35d71fb7', 'c46cc189dac5ac53ba455838af5859e0'),
  ('f759623b-ce28-4c5f-8556-95c4381b6b1b', '4fff65ea2500ba5613d3927f2cd8042c'),
  ('c582a187-32f6-4a24-bb7b-d590b25c1854', '91679ca8877c299bf02faaf56fdfee8c'),
  ('dc06b98c-360f-4661-a294-52ecb82830a7', '04099067c0430d749487c2170b1ec5d8');

lock table public.school_lesson_records in access exclusive mode;
lock table
  public.school_feature_gates,
  public.school_business_entities,
  public.school_students,
  public.school_student_tuition_bills,
  public.school_student_tuition_bill_lessons,
  public.school_student_tuition_billing_identities,
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
in share row exclusive mode;

create temporary table r1c_c_b_candidate_before on commit drop as
select candidate.*
from (values ('2026-09'), ('2026-10'), ('2026-11')) month_scope(year_month)
cross join lateral public.school_list_student_tuition_candidates(
  '7aef8061-7037-4881-a847-a2cdb031c0f4',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  month_scope.year_month,
  true
) candidate;

do $$
declare
  v_count integer;
  v_hash text;
begin
  select count(*)::integer,
         md5(string_agg(expected_row_hash, '' order by planned_lesson_id::text))
  into v_count, v_hash
  from r1c_c_b_manifest;

  if v_count <> 66
     or (select count(distinct item_order) from r1c_c_b_manifest) <> 66
     or (select min(item_order) from r1c_c_b_manifest) <> 1
     or (select max(item_order) from r1c_c_b_manifest) <> 66 then
    raise exception 'R1C_C_B_MANIFEST_COUNT_MISMATCH';
  end if;
  if v_hash <> 'ee7c476c9c56c926eda083008197450a' then
    raise exception 'R1C_C_B_MANIFEST_HASH_MISMATCH: %', v_hash;
  end if;

  if exists (
    select 1 from r1c_c_b_manifest
    where expected_student_id <> '7aef8061-7037-4881-a847-a2cdb031c0f4'
       or expected_source_batch_id <> '5254a3fb-dc38-40c2-9cf3-810a79835275'
       or expected_from_business_entity_id <> '886a8f7c-0fea-45ac-97d2-15c976ede996'
       or expected_year_month not in ('2026-09', '2026-10', '2026-11')
       or expected_status <> 'planned'
       or expected_lesson_fee <> expected_duration_hours * expected_unit_price
  ) then
    raise exception 'R1C_C_B_MANIFEST_SCOPE_MISMATCH';
  end if;

  if (select count(*) from r1c_c_b_manifest where expected_year_month = '2026-09') <> 24
     or (select sum(expected_duration_hours) from r1c_c_b_manifest where expected_year_month = '2026-09') <> 52
     or (select sum(expected_lesson_fee) from r1c_c_b_manifest where expected_year_month = '2026-09') <> 520000
     or (select count(*) from r1c_c_b_manifest where expected_year_month = '2026-10') <> 24
     or (select sum(expected_duration_hours) from r1c_c_b_manifest where expected_year_month = '2026-10') <> 52
     or (select sum(expected_lesson_fee) from r1c_c_b_manifest where expected_year_month = '2026-10') <> 520000
     or (select count(*) from r1c_c_b_manifest where expected_year_month = '2026-11') <> 18
     or (select sum(expected_duration_hours) from r1c_c_b_manifest where expected_year_month = '2026-11') <> 41
     or (select sum(expected_lesson_fee) from r1c_c_b_manifest where expected_year_month = '2026-11') <> 410000
     or (select sum(expected_duration_hours) from r1c_c_b_manifest) <> 145
     or (select sum(expected_lesson_fee) from r1c_c_b_manifest) <> 1450000 then
    raise exception 'R1C_C_B_MANIFEST_SUMMARY_MISMATCH';
  end if;

  if (select count(*) from r1c_c_b_li_exclusions) <> 11
     or exists (
       select 1 from r1c_c_b_li_exclusions li
       join r1c_c_b_manifest manifest on manifest.planned_lesson_id = li.lesson_record_id
     ) then
    raise exception 'R1C_C_B_LI_EXCLUSION_MANIFEST_MISMATCH';
  end if;

  if not exists (
    select 1 from public.school_business_entities
    where id = '886a8f7c-0fea-45ac-97d2-15c976ede996'
      and name = '个人名义' and entity_type = 'personal' and is_active
  ) or not exists (
    select 1 from public.school_business_entities
    where id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      and name = '青空进学塾' and entity_type = 'company' and is_active
  ) then
    raise exception 'R1C_C_B_BUSINESS_ENTITY_IDENTITY_MISMATCH';
  end if;

  if not exists (
    select 1 from public.school_students
    where id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
      and business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      and status = 'active'
  ) then
    raise exception 'R1C_C_B_STUDENT_TARGET_ENTITY_OR_STATUS_MISMATCH';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3 then
    raise exception 'R1C_C_B_R0_GATE_MISMATCH';
  end if;

  if (select count(*) from pg_trigger
      where tgrelid = 'public.school_lesson_records'::regclass
        and tgname = 'trg_school_lesson_records_updated_at'
        and tgenabled = 'O' and not tgisinternal) <> 1 then
    raise exception 'R1C_C_B_UPDATED_AT_TRIGGER_NOT_ENABLED';
  end if;

  if exists (
    select 1
    from r1c_c_b_manifest manifest
    left join public.school_lesson_records lesson on lesson.id = manifest.planned_lesson_id
    where lesson.id is null
       or md5(to_jsonb(lesson)::text) <> manifest.expected_row_hash
       or lesson.student_id is distinct from manifest.expected_student_id
       or lesson.import_batch_id is distinct from manifest.expected_source_batch_id
       or lesson.business_entity_id is distinct from manifest.expected_from_business_entity_id
       or lesson.lesson_date is distinct from manifest.expected_lesson_date
       or lesson.year_month is distinct from manifest.expected_year_month
       or lesson.teacher_id is distinct from manifest.expected_teacher_id
       or lesson.subject_id is distinct from manifest.expected_subject_id
       or lesson.lesson_count is distinct from manifest.expected_lesson_count
       or lesson.duration_hours is distinct from manifest.expected_duration_hours
       or lesson.unit_price is distinct from manifest.expected_unit_price
       or lesson.lesson_fee is distinct from manifest.expected_lesson_fee
       or lesson.status is distinct from manifest.expected_status
       or lesson.created_at is distinct from manifest.expected_created_at
       or lesson.updated_at is distinct from manifest.expected_updated_at
       or lesson.app_type <> 'school' or lesson.lesson_type <> 'planned'
       or lesson.planned_lesson_id is not null or lesson.is_billable is not true
       or lesson.voided_at is not null
  ) then
    raise exception 'R1C_C_B_FIXED_ROW_FINGERPRINT_MISMATCH';
  end if;

  if (select count(*) from public.school_lesson_records
      where student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
        and import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
        and year_month in ('2026-09', '2026-10', '2026-11')) <> 66
     or exists (
       select 1 from public.school_lesson_records lesson
       where lesson.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
         and lesson.import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
         and lesson.year_month in ('2026-09', '2026-10', '2026-11')
         and not exists (
           select 1 from r1c_c_b_manifest manifest where manifest.planned_lesson_id = lesson.id
         )
     ) then
    raise exception 'R1C_C_B_SOURCE_BATCH_MONTH_COMPLETENESS_MISMATCH';
  end if;

  if (select count(*) from r1c_c_b_candidate_before candidate
      join r1c_c_b_manifest manifest on manifest.planned_lesson_id = candidate.planned_lesson_id
      where candidate.candidate_status = 'excluded'
        and candidate.exclusion_reason = 'scope_mismatch'
        and candidate.has_normalized_bill_relation is false
        and candidate.has_bill_snapshot_evidence is false
        and candidate.bill_evidence_conflict is false) <> 66
     or exists (
       select 1 from r1c_c_b_manifest manifest
       left join r1c_c_b_candidate_before candidate
         on candidate.planned_lesson_id = manifest.planned_lesson_id
       where candidate.planned_lesson_id is null
     ) then
    raise exception 'R1C_C_B_PRE_CANDIDATE_REASON_MISMATCH';
  end if;

  if exists (
    select 1 from r1c_c_b_li_exclusions li
    left join public.school_lesson_records lesson on lesson.id = li.lesson_record_id
    where lesson.id is null or md5(to_jsonb(lesson)::text) <> li.expected_row_hash
  ) then
    raise exception 'R1C_C_B_LI_FIXED_ROW_FINGERPRINT_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_student_tuition_bill_lessons relation
    join r1c_c_b_manifest manifest on manifest.planned_lesson_id = relation.planned_lesson_id
  ) or exists (
    select 1 from public.school_student_tuition_bills bill
    join r1c_c_b_manifest manifest
      on (bill.source_snapshot -> 'planned_lesson_ids') ? manifest.planned_lesson_id::text
  ) then
    raise exception 'R1C_C_B_TARGET_HAS_TUITION_BILL_EVIDENCE';
  end if;

  if exists (
    select 1 from public.school_lesson_records actual
    join r1c_c_b_manifest manifest on manifest.planned_lesson_id = actual.planned_lesson_id
    where actual.lesson_type = 'actual' and actual.voided_at is null
  ) then
    raise exception 'R1C_C_B_TARGET_HAS_ACTUAL_LESSON';
  end if;

  if exists (
    select 1
    from public.school_teacher_wage_lock_details detail
    join public.school_teacher_wage_locks wage on wage.id = detail.lock_id
    where wage.status <> 'void' and (
      exists (select 1 from r1c_c_b_manifest manifest where manifest.planned_lesson_id = detail.lesson_record_id)
      or exists (
        select 1 from public.school_lesson_records actual
        join r1c_c_b_manifest manifest on manifest.planned_lesson_id = actual.planned_lesson_id
        where actual.id = detail.lesson_record_id
      )
    )
  ) then
    raise exception 'R1C_C_B_TARGET_HAS_EFFECTIVE_WAGE_DETAIL';
  end if;

  if exists (
    select 1 from public.school_student_monthly_settlements settlement
    where settlement.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
      and settlement.business_entity_id in (
        '886a8f7c-0fea-45ac-97d2-15c976ede996',
        '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      )
      and settlement.year_month in ('2026-09', '2026-10', '2026-11')
      and settlement.settlement_status = 'locked'
  ) then
    raise exception 'R1C_C_B_TARGET_MONTH_HAS_LOCKED_SETTLEMENT';
  end if;

  if exists (
    select 1 from public.school_income_records income
    join r1c_c_b_manifest manifest on to_jsonb(income)::text like '%' || manifest.planned_lesson_id::text || '%'
  ) or exists (
    select 1 from public.school_personal_cash_income_linkage_events linkage
    join r1c_c_b_manifest manifest on to_jsonb(linkage)::text like '%' || manifest.planned_lesson_id::text || '%'
  ) or exists (
    select 1 from public.school_account_transactions transaction_row
    join r1c_c_b_manifest manifest on to_jsonb(transaction_row)::text like '%' || manifest.planned_lesson_id::text || '%'
  ) then
    raise exception 'R1C_C_B_TARGET_HAS_FINANCIAL_REFERENCE';
  end if;

  if exists (
    select 1 from public.school_business_entity_migration_batches
    where id = 'c1000000-0000-4000-8000-202607289999'
       or migration_key = 'r1c-c-b:2026-09-11:zhang-planned-business-entity:personal-to-aosora'
  ) or exists (
    select 1 from public.school_business_entity_migration_items item
    join r1c_c_b_manifest manifest on manifest.planned_lesson_id = item.lesson_record_id
  ) then
    raise exception 'R1C_C_B_AUDIT_ALREADY_EXISTS';
  end if;
end;
$$;

create temporary table r1c_c_b_before_rows on commit drop as
select manifest.*, to_jsonb(lesson) as original_row_snapshot
from r1c_c_b_manifest manifest
join public.school_lesson_records lesson on lesson.id = manifest.planned_lesson_id;

create temporary table r1c_c_b_li_before on commit drop as
select li.*, to_jsonb(lesson) as original_row_snapshot
from r1c_c_b_li_exclusions li
join public.school_lesson_records lesson on lesson.id = li.lesson_record_id;

create temporary table r1c_c_b_school_baseline (
  object_name text primary key,
  row_count bigint not null,
  object_hash text not null
) on commit drop;

insert into r1c_c_b_school_baseline
select 'tuition_bills', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bills t
union all select 'income_records', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_income_records t
union all select 'billing_identities', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_billing_identities t
union all select 'bill_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bill_lessons t
union all select 'cash_linkage', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_personal_cash_income_linkage_events t
union all select 'account_transactions', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_account_transactions t
union all select 'actual_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t where t.lesson_type = 'actual'
union all select 'settlements', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_monthly_settlements t
union all select 'wage_locks', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_locks t
union all select 'wage_details', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_lock_details t
union all select 'r1c_a_batch', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_batches t where t.id = 'c1000000-0000-4000-8000-202607279999'
union all select 'r1c_a_items', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_items t where t.batch_id = 'c1000000-0000-4000-8000-202607279999'
union all
select 'lesson_records_authorized_projection', count(*),
  md5(coalesce(string_agg(md5(case
    when exists (select 1 from r1c_c_b_manifest manifest where manifest.planned_lesson_id = t.id)
      then (to_jsonb(t) - 'business_entity_id')::text
    else to_jsonb(t)::text end), '' order by t.id::text), ''))
from public.school_lesson_records t;

do $$
declare
  v_updated_count integer;
begin
  execute 'alter table public.school_lesson_records disable trigger trg_school_lesson_records_updated_at';
  begin
    update public.school_lesson_records lesson
       set business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      from r1c_c_b_manifest manifest
     where lesson.id = manifest.planned_lesson_id;
    get diagnostics v_updated_count = row_count;
    if v_updated_count <> 66 then
      raise exception 'R1C_C_B_UPDATE_COUNT_MISMATCH: expected 66, got %', v_updated_count;
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
    select 1 from r1c_c_b_before_rows before_row
    join public.school_lesson_records lesson on lesson.id = before_row.planned_lesson_id
    where lesson.business_entity_id <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
       or (to_jsonb(lesson) - 'business_entity_id')
          is distinct from (before_row.original_row_snapshot - 'business_entity_id')
       or lesson.updated_at is distinct from before_row.expected_updated_at
  ) then
    raise exception 'R1C_C_B_UNAUTHORIZED_LESSON_FIELD_CHANGE';
  end if;
  if (select count(*) from pg_trigger
      where tgrelid = 'public.school_lesson_records'::regclass
        and tgname = 'trg_school_lesson_records_updated_at'
        and tgenabled = 'O' and not tgisinternal) <> 1 then
    raise exception 'R1C_C_B_UPDATED_AT_TRIGGER_NOT_REENABLED';
  end if;
end;
$$;

create temporary table r1c_c_b_execution_context on commit drop as
select statement_timestamp() as executed_at;

insert into public.school_business_entity_migration_batches (
  id, migration_key, migration_type, target_year_month,
  from_business_entity_id, to_business_entity_id, source_generation_batches,
  expected_lesson_count, expected_duration_hours, expected_lesson_fee_jpy,
  manifest_hash, evidence_source, approval_information, execution_status,
  executed_at, failure_reason, created_at, created_by
)
select
  'c1000000-0000-4000-8000-202607289999',
  'r1c-c-b:2026-09-11:zhang-planned-business-entity:personal-to-aosora',
  'planned_lesson_business_entity',
  '2026-09',
  '886a8f7c-0fea-45ac-97d2-15c976ede996',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  jsonb_build_object('张倬闻', '5254a3fb-dc38-40c2-9cf3-810a79835275', 'months', jsonb_build_array('2026-09', '2026-10', '2026-11')),
  66, 145, 1450000,
  'ee7c476c9c56c926eda083008197450a',
  'R1C-C-A report sections 6.1-6.3 fixed 66 UUIDs + complete current row fingerprints + downstream-zero proof',
  jsonb_build_object(
    'approved_by', 'business_owner',
    'approval_date', '2026-07-28',
    'approved_scope', 'R1C-C-B Zhang Zhuowen fixed 66 future planned lessons only',
    'course_plan_evidence', 'courses sent to student; plan confirmed locked and currently valid',
    'approved_change', 'business_entity_id only: personal to Aozora',
    'li_tianlun_exclusion', 'all fixed 11 IDs explicitly excluded; no cleanup or repair authorized',
    'historical_68', '68-ID manifest unavailable and not an authorization source'
  ),
  'executed', context.executed_at, null, context.executed_at,
  'codex-r1c-c-b-20260728'
from r1c_c_b_execution_context context;

insert into public.school_business_entity_migration_items (
  id, batch_id, item_order, lesson_record_id, student_id, target_year_month,
  source_generation_batch_id, from_business_entity_id, to_business_entity_id,
  original_row_snapshot, before_hash, original_updated_at, evidence_source,
  approval_information, execution_status, after_row_snapshot, after_hash,
  executed_at, failure_reason, created_at, created_by
)
select
  (
    substr(md5('c1000000-0000-4000-8000-202607289999:' || before_row.planned_lesson_id || ':r1c-c-b'), 1, 8)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607289999:' || before_row.planned_lesson_id || ':r1c-c-b'), 9, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607289999:' || before_row.planned_lesson_id || ':r1c-c-b'), 13, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607289999:' || before_row.planned_lesson_id || ':r1c-c-b'), 17, 4)
    || '-' || substr(md5('c1000000-0000-4000-8000-202607289999:' || before_row.planned_lesson_id || ':r1c-c-b'), 21, 12)
  )::uuid,
  'c1000000-0000-4000-8000-202607289999',
  before_row.item_order, before_row.planned_lesson_id, before_row.expected_student_id,
  before_row.expected_year_month, before_row.expected_source_batch_id,
  before_row.expected_from_business_entity_id,
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  before_row.original_row_snapshot, before_row.expected_row_hash,
  before_row.expected_updated_at,
  'R1C-C-A fixed UUID plus complete pre-migration row hash',
  jsonb_build_object(
    'approved_by', 'business_owner',
    'approved_scope', 'R1C-C-B Zhang Zhuowen fixed 66 only',
    'student_id', before_row.expected_student_id,
    'source_generation_batch_id', before_row.expected_source_batch_id,
    'li_tianlun_excluded', true,
    'historical_68_authority', false
  ),
  'executed', to_jsonb(lesson), md5(to_jsonb(lesson)::text),
  context.executed_at, null, context.executed_at,
  'codex-r1c-c-b-20260728'
from r1c_c_b_before_rows before_row
join public.school_lesson_records lesson on lesson.id = before_row.planned_lesson_id
cross join r1c_c_b_execution_context context
order by before_row.item_order;

set constraints all immediate;

create temporary table r1c_c_b_candidate_after on commit drop as
select candidate.*
from (values ('2026-09'), ('2026-10'), ('2026-11')) month_scope(year_month)
cross join lateral public.school_list_student_tuition_candidates(
  '7aef8061-7037-4881-a847-a2cdb031c0f4',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  month_scope.year_month,
  true
) candidate;

create temporary table r1c_c_b_august_candidates on commit drop as
select '张倬闻'::text as student_name, candidate.*
from public.school_list_student_tuition_candidates(
  '7aef8061-7037-4881-a847-a2cdb031c0f4',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466', '2026-08', false
) candidate
union all
select '孙陈锋'::text, candidate.*
from public.school_list_student_tuition_candidates(
  'b17abc58-2f64-4bad-bf20-c9643ead60bc',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466', '2026-08', false
) candidate;

create temporary table r1c_c_b_li_candidate_after on commit drop as
select candidate.*
from (values ('2026-10'), ('2026-11')) month_scope(year_month)
cross join lateral public.school_list_student_tuition_candidates(
  'a7b163a0-201e-4867-9b94-372343356a80',
  '2cf7b72f-6e3c-4d09-80f7-7c58593cd466',
  month_scope.year_month,
  true
) candidate;

create temporary table r1c_c_b_school_after (
  object_name text primary key,
  row_count bigint not null,
  object_hash text not null
) on commit drop;

insert into r1c_c_b_school_after
select 'tuition_bills', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bills t
union all select 'income_records', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_income_records t
union all select 'billing_identities', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_billing_identities t
union all select 'bill_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_tuition_bill_lessons t
union all select 'cash_linkage', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_personal_cash_income_linkage_events t
union all select 'account_transactions', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_account_transactions t
union all select 'actual_lessons', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_lesson_records t where t.lesson_type = 'actual'
union all select 'settlements', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_student_monthly_settlements t
union all select 'wage_locks', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_locks t
union all select 'wage_details', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_teacher_wage_lock_details t
union all select 'r1c_a_batch', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_batches t where t.id = 'c1000000-0000-4000-8000-202607279999'
union all select 'r1c_a_items', count(*), md5(coalesce(string_agg(md5(to_jsonb(t)::text), '' order by id::text), '')) from public.school_business_entity_migration_items t where t.batch_id = 'c1000000-0000-4000-8000-202607279999'
union all
select 'lesson_records_authorized_projection', count(*),
  md5(coalesce(string_agg(md5(case
    when exists (select 1 from r1c_c_b_manifest manifest where manifest.planned_lesson_id = t.id)
      then (to_jsonb(t) - 'business_entity_id')::text
    else to_jsonb(t)::text end), '' order by t.id::text), ''))
from public.school_lesson_records t;

do $$
begin
  if exists (
    select 1 from r1c_c_b_school_baseline before_state
    full join r1c_c_b_school_after after_state using (object_name)
    where before_state.object_name is null or after_state.object_name is null
       or before_state.row_count is distinct from after_state.row_count
       or before_state.object_hash is distinct from after_state.object_hash
  ) then
    raise exception 'R1C_C_B_NONAUTHORIZED_BASELINE_CHANGED';
  end if;

  if (select count(*) from public.school_business_entity_migration_batches
      where id = 'c1000000-0000-4000-8000-202607289999'
        and migration_key = 'r1c-c-b:2026-09-11:zhang-planned-business-entity:personal-to-aosora'
        and execution_status = 'executed' and expected_lesson_count = 66
        and expected_duration_hours = 145 and expected_lesson_fee_jpy = 1450000
        and manifest_hash = 'ee7c476c9c56c926eda083008197450a') <> 1
     or (select count(*) from public.school_business_entity_migration_items
         where batch_id = 'c1000000-0000-4000-8000-202607289999'
           and execution_status = 'executed') <> 66 then
    raise exception 'R1C_C_B_AUDIT_COUNT_MISMATCH';
  end if;

  if exists (
    select 1 from public.school_business_entity_migration_items item
    where item.batch_id = 'c1000000-0000-4000-8000-202607289999' and (
      md5(item.original_row_snapshot::text) <> item.before_hash
      or md5(item.after_row_snapshot::text) <> item.after_hash
      or (item.original_row_snapshot - 'business_entity_id')
         is distinct from (item.after_row_snapshot - 'business_entity_id')
      or item.original_row_snapshot ->> 'business_entity_id' <> '886a8f7c-0fea-45ac-97d2-15c976ede996'
      or item.after_row_snapshot ->> 'business_entity_id' <> '2cf7b72f-6e3c-4d09-80f7-7c58593cd466'
      or item.original_updated_at is distinct from (item.after_row_snapshot ->> 'updated_at')::timestamptz
    )
  ) then
    raise exception 'R1C_C_B_AUDIT_SNAPSHOT_MISMATCH';
  end if;

  if (select count(*) from r1c_c_b_candidate_after candidate
      join r1c_c_b_manifest manifest on manifest.planned_lesson_id = candidate.planned_lesson_id
      where candidate.candidate_status = 'candidate' and candidate.exclusion_reason is null) <> 66
     or exists (
       select 1 from r1c_c_b_candidate_after candidate
       where candidate.candidate_status = 'candidate'
         and not exists (select 1 from r1c_c_b_manifest manifest where manifest.planned_lesson_id = candidate.planned_lesson_id)
     ) then
    raise exception 'R1C_C_B_POST_CANDIDATE_SET_MISMATCH';
  end if;

  if (select count(*) from r1c_c_b_august_candidates where student_name = '张倬闻') <> 30
     or (select sum(duration_hours) from r1c_c_b_august_candidates where student_name = '张倬闻') <> 65
     or (select sum(lesson_fee) from r1c_c_b_august_candidates where student_name = '张倬闻') <> 650000
     or (select count(*) from r1c_c_b_august_candidates where student_name = '孙陈锋') <> 22
     or (select sum(duration_hours) from r1c_c_b_august_candidates where student_name = '孙陈锋') <> 44
     or (select sum(lesson_fee) from r1c_c_b_august_candidates where student_name = '孙陈锋') <> 374000
     or exists (
       select 1 from r1c_c_b_august_candidates candidate
       where not exists (
         select 1 from public.school_business_entity_migration_items item
         where item.batch_id = 'c1000000-0000-4000-8000-202607279999'
           and item.lesson_record_id = candidate.planned_lesson_id
       )
     ) then
    raise exception 'R1C_C_B_AUGUST_CANDIDATE_REGRESSION';
  end if;

  if (select count(*) from r1c_c_b_li_candidate_after candidate
      join r1c_c_b_li_exclusions li on li.lesson_record_id = candidate.planned_lesson_id) <> 11
     or exists (
       select 1 from r1c_c_b_li_candidate_after candidate
       join r1c_c_b_li_exclusions li on li.lesson_record_id = candidate.planned_lesson_id
       where candidate.candidate_status = 'candidate'
          or candidate.exclusion_reason <> 'scope_mismatch'
     ) then
    raise exception 'R1C_C_B_LI_CANDIDATE_EXCLUSION_CHANGED';
  end if;

  if exists (
    select 1 from r1c_c_b_li_before before_row
    join public.school_lesson_records lesson on lesson.id = before_row.lesson_record_id
    where to_jsonb(lesson) is distinct from before_row.original_row_snapshot
       or md5(to_jsonb(lesson)::text) <> before_row.expected_row_hash
  ) then
    raise exception 'R1C_C_B_LI_ROW_CHANGED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key = 'student_tuition_preview' and state = 'validation_preview_only')
         or (feature_key = 'student_tuition_generate' and state = 'blocked')
         or (feature_key = 'student_tuition_cash_submit' and state = 'blocked')) <> 3
     or (select count(*) from pg_trigger
         where tgrelid = 'public.school_lesson_records'::regclass
           and tgname = 'trg_school_lesson_records_updated_at'
           and tgenabled = 'O' and not tgisinternal) <> 1 then
    raise exception 'R1C_C_B_TRIGGER_OR_GATE_CHANGED';
  end if;
end;
$$;

select
  manifest.expected_year_month as year_month,
  count(*) as migrated_lesson_count,
  sum(manifest.expected_duration_hours) as duration_hours,
  sum(manifest.expected_lesson_fee) as lesson_fee_jpy,
  count(*) filter (where lesson.updated_at = manifest.expected_updated_at) as updated_at_unchanged
from r1c_c_b_manifest manifest
join public.school_lesson_records lesson on lesson.id = manifest.planned_lesson_id
group by manifest.expected_year_month
order by manifest.expected_year_month;

select item.item_order, item.lesson_record_id, item.target_year_month,
       item.before_hash, item.after_hash, item.original_updated_at
from public.school_business_entity_migration_items item
where item.batch_id = 'c1000000-0000-4000-8000-202607289999'
order by item.item_order;

\if :r1c_c_b_commit
  commit;
\else
  rollback;

  select
    (select count(*) from public.school_business_entity_migration_batches
     where id = 'c1000000-0000-4000-8000-202607289999') as batch_residue,
    (select count(*) from public.school_business_entity_migration_items
     where batch_id = 'c1000000-0000-4000-8000-202607289999') as item_residue,
    (select count(*) from public.school_lesson_records
     where student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
       and import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
       and year_month in ('2026-09', '2026-10', '2026-11')
       and business_entity_id = '2cf7b72f-6e3c-4d09-80f7-7c58593cd466') as target_entity_residue,
    (select count(*) from public.school_lesson_records
     where student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
       and import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
       and year_month in ('2026-09', '2026-10', '2026-11')
       and business_entity_id = '886a8f7c-0fea-45ac-97d2-15c976ede996') as original_personal_count,
    (select md5(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text))
     from public.school_lesson_records lesson
     where lesson.student_id = '7aef8061-7037-4881-a847-a2cdb031c0f4'
       and lesson.import_batch_id = '5254a3fb-dc38-40c2-9cf3-810a79835275'
       and lesson.year_month in ('2026-09', '2026-10', '2026-11')) as restored_full_row_hash;

  select
    count(*) as li_count,
    md5(string_agg(md5(to_jsonb(lesson)::text), '' order by lesson.id::text)) as li_full_row_hash
  from public.school_lesson_records lesson
  where lesson.id in (
    'f256bca9-fac5-4909-b113-8077efd27d65', 'a722a49e-dbe5-447d-8068-fd5fb743f6ab',
    '265f4d3d-2372-42e3-aec3-b963bbdddf95', 'e890424d-407d-4fc2-b8ad-84745b242cdd',
    '552c54e3-2d0c-4607-962d-aad39dfff7f7', 'b186fa1c-a56b-4ed7-b566-178a5708ae96',
    'ac16b068-a58b-4ca5-be95-7c57c3f1b82b', '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7',
    'f759623b-ce28-4c5f-8556-95c4381b6b1b', 'c582a187-32f6-4a24-bb7b-d590b25c1854',
    'dc06b98c-360f-4661-a294-52ecb82830a7'
  );

  select tgname, tgenabled
  from pg_trigger
  where tgrelid = 'public.school_lesson_records'::regclass
    and tgname = 'trg_school_lesson_records_updated_at'
    and not tgisinternal;
\endif
