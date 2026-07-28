-- School V2 tuition P0 R1D-C-B-A2: controlled attribution backfill for the fixed R1C-C-B 66.
-- psql variable r1d_c_b_a2_commit: 0 = rollback rehearsal, 1 = formal commit.
-- The UPDATE scope is only the static manifest below. Migration audit rows are
-- cross-check evidence and never a dynamic target selector.

\set ON_ERROR_STOP on
\pset pager off

\if :{?r1d_c_b_a2_commit}
\else
  \set r1d_c_b_a2_commit 0
\endif

begin;
set local lock_timeout = '15s';

create temporary table r1d_c_b_a2_manifest (
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

insert into r1d_c_b_a2_manifest values
  (1, '0386bf22-8619-41f2-be6c-5106b8c17cd0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'a62204a53ef42c843c04580a59178839', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (2, '0624fabe-a3c8-4930-aa41-8ed800a28eea'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '797808a487e2db20d0d4054a382129bb', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (3, '0a3a8c13-12cb-4430-a933-2941221c0c77'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '767cc20ccb3d677ea5d72ee4406d428e', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (4, '0ea530e7-12ac-41fa-9f6e-972b24662a72'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'a45b17af3cb3450be5a51c2bf726de30', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (5, '0f168663-afb1-49a7-90a8-39197ad7729e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '9a4baf9b61b4b98f6687144c1fc29c90', '2026-11', '2026-11-30'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (6, '10b62cc8-dd74-4665-a6cd-02cc02924a65'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '579866221fae12c1b602b57cb159f97a', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (7, '15f8147e-5bb0-4cf9-9ba7-3e12f115774e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '44762f74f46e976931f272c6cd29ca43', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (8, '17e58b7d-3fb8-4874-8071-0b1f808e8430'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'cf6ba5a211000193ddcfb2eab65bc10e', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (9, '1eeb937e-a7ad-4e7c-955d-797b9d979882'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '4d1eacd31e2f3bb1f61803228e29cfc7', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (10, '207430a6-c9cd-4acb-9a7d-962c078b0623'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '1063586abf4c0016beb0ae241081cf7e', '2026-11', '2026-11-09'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (11, '21e97cbd-3e18-4c9e-9790-981f885af03a'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '425f1fa06598bef28ccc425c23f46b2e', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (12, '224015ce-b435-4233-8113-0e6c712b1a18'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '80f479e74ed46a3736e9677fe28f271d', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (13, '297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'c9542833be300c25114796bf51a02784', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (14, '2bd402cb-fc4d-48cc-b166-400ee4945703'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0683e43d58de138c3bd75ce962ed85ae', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (15, '30271ef0-51ee-43ca-9103-1b5ec34255e1'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '46fa9c69eede26dda2dcd4133705ef4e', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (16, '3048b190-31e0-49b1-a255-ce73e6e15fc0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '7b176cfd75085ff489922d09f218ce50', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (17, '371e41c5-a659-44a6-87e0-c3a85c9c1b75'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '26fca610a6fafce1befa7b078b906c72', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (18, '3f5884ea-ca12-41dc-89ce-ebc67db27fe8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '52d36b891f312004659ec88fa3fdd225', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (19, '4254095b-9ec1-4651-a9ff-0dffb3a4520f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'a0a9de7fd44e29a351f236091737b01c', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (20, '4505777b-13e3-4187-9839-618ebe186f22'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'e6f98cd8c08f896714158d99bb988fce', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (21, '5591fb92-2333-460c-95f3-85c6511d6fd4'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '508470750ecc81187b3ef747d3381f3c', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (22, '5666a624-05b5-4408-bc11-5d208851b216'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '697b8b377d7f9c74338c82416e5ba71a', '2026-11', '2026-11-09'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (23, '57948b80-89d9-45f2-a99f-3b92aed9f4e8'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '2e7f3485bec1af2d85a99ad1b67ee8b5', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (24, '584ef4d6-fa9d-4dd8-803c-cab68ac67a67'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'fab5d2a284abd2e3211dfbaea7919a31', '2026-11', '2026-11-23'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (25, '594a4559-c1b1-4ad1-88e6-4c7834052831'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '678eddd7080ef901003ae709869d44fc', '2026-11', '2026-11-30'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (26, '645cccaf-ae0f-41b3-84d1-e40882a8c85f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '3913910c6b371853f5910f21e6b83c13', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (27, '68da4912-72a8-418c-b30b-335bb9896c63'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0d7730cba59d3c156e1fb64f8c4050dd', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (28, '70c31ae5-6083-46cb-90ad-fdc24726b6b6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'f2727783eec851da48f64cd3061a9886', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (29, '73dd0453-aec2-4612-b710-071a372f88ad'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '06c20251dc4859df4b2586944d531260', '2026-11', '2026-11-16'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (30, '7e833e2c-3bc0-4c6d-a1ab-204229f43a77'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'b498c136d181cdf01653b25a8f27bd9e', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (31, '812979d0-43ac-4075-b38f-4c9aa455cd4b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '8928cd931f0d012cecd70ecb8be7fd7f', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (32, '82e81ecc-dd23-471e-8402-a45bd8b20eb1'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'ba7c307daf4ba2e993d5793c278e9b92', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (33, '895ebf6e-6bf0-419d-bf9a-418d048a42a7'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '6948f70ebad670b0426d718138acb79c', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (34, '89797ce3-58e0-4c9d-b107-79eca71e4161'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0ecced3530b402177b97b023a8e347d2', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (35, '92a0f909-6458-4d34-9144-9d60eeede33f'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '082f88238d41d125e8f440777f469643', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (36, '966119c6-09c8-4ac5-9c16-6cda13137d87'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '9da7944cae8e1d2f5c2f135eebcfda66', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (37, 'a3a7dd70-1a1e-4078-bce8-d54f10fc57af'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'dfe60d7025b0da8993e8c3ea6be7b3cc', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (38, 'a42b1b2e-4f55-4915-a20b-bd411b4d81a0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'd424b68e6a388d972b7321e0590100c0', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (39, 'a4cd05e7-47e7-4e0d-8af8-dad6c7505744'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '5a51e623a95ef2ceeb6e8f136f0fec5a', '2026-11', '2026-11-23'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (40, 'a57bf7af-43e1-46ba-9bb6-9ee511b81e05'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '75caedb220d9542b868af681f387d614', '2026-11', '2026-11-09'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (41, 'a9de94c0-954b-452d-95b0-6a8b7d1a5a9e'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '08510ab7b3eafbcd50e3bb7bd3bc9a6d', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (42, 'a9e861d3-6bd6-4b76-ba78-4cc1f3265b43'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'bb9984b92546dbf3e95a6b510ff7e756', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (43, 'aea933f5-5e3b-4476-b1f0-d781d41312a3'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'fd38c737f4c9384d0925821f6606729e', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (44, 'b33f023c-4b0c-495e-8f0b-934ead526421'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '68f418c4edaa1a1b561d420de54caf2d', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (45, 'bc718d5f-dc21-4e7d-914a-dd3a6debaeb6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0032fb14098ab330482b30415b7513d0', '2026-11', '2026-11-16'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (46, 'bf38024e-2a5f-422c-ad41-01ec9922e701'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '203d962c8bfc46bc3b28fa46ebd8b153', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (47, 'c1f5c7e9-70e4-4c2d-99c8-aadd986cda15'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '65a4b556391835654f4b66a4dfcdeaaa', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (48, 'c48478ef-8b3d-4c7f-bd48-cc99659e99f7'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'b0687c8e00264e8168935551b05a6709', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (49, 'c79e2ade-4026-4ab3-a316-ba26354abfe2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '953af0a89508745add3b468b646d535d', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (50, 'cfb5e237-51a3-48b2-a12e-e8f0628e2c51'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '929e5f18ddc60450c4e7c5e66a9122ae', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (51, 'd1961919-8c05-42e8-8a06-4ed1fabb13c0'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'ebdb87e001a29fe2d7cae4cc2aaf830f', '2026-10', '2026-10-19'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (52, 'd2307a35-1f41-4402-ab4d-c03ed4305f50'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '08dc896a689196e1111b69d0cbeb900b', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (53, 'd8ed3671-6865-42b6-a4a2-06b31c9051e6'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '1eba573d744f6f251766d128e65bcb4d', '2026-10', '2026-10-26'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (54, 'd9d11e4b-a01c-4535-93cf-bc51cf08b900'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '1c6489b83ab1c8773bb2f6cd68d56b0d', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (55, 'dadcf864-5343-403d-a111-e68b8617f413'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '6ebb6328821c630bf6332d91e2ded586', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (56, 'dbd6f35a-b0ee-4af8-bcda-e065330f0413'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'fe7f1da4a60471b71fd2de30d9b9e2e1', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (57, 'def65ad3-6f87-4889-802f-202550a9af49'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '926c88d1e2868e06ea12d46581822175', '2026-11', '2026-11-30'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (58, 'eec50614-788d-429b-99a4-fc8938a86dda'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'cb0100bb26a1cf4f8d1163015e64bd3a', '2026-10', '2026-10-12'::date, '2026-10', 'approved_r1c_c_b_manifest'),
  (59, 'f1a321d8-5528-4afe-8fb7-79204f49f3dc'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '1a75b558bcd6354b2ba298d1e3685f99', '2026-11', '2026-11-16'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (60, 'f693a3d9-fada-48f2-8203-bc33d46ee4dd'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '0a5ca13b8b267984bca0bc622223d058', '2026-09', '2026-09-14'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (61, 'f91ecdd8-7442-4879-97b6-67ad8ea99f23'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '3a5c11b62591bc80838b9700bd6ea280', '2026-09', '2026-09-07'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (62, 'fb066255-82b5-4eb1-9f76-a776c04becc2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'cdd9eab094fa0902889f3223c8a4f5c9', '2026-09', '2026-09-21'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (63, 'fc138193-f76a-476c-a394-b49d2e68dde2'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '37552ec3c8ab8727145f138965106c30', '2026-11', '2026-11-23'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (64, 'fd34b0d7-86c2-4d0e-a519-de2317e0ab26'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '69c1b50ee4562515443abdfa35a8e7fe', '2026-11', '2026-11-02'::date, '2026-11', 'approved_r1c_c_b_manifest'),
  (65, 'fd803263-07b6-4b1f-b668-43a482f21c89'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, 'bd23c5764f7d4f263edbff06831a7d38', '2026-09', '2026-09-28'::date, '2026-09', 'approved_r1c_c_b_manifest'),
  (66, 'ff368fb5-94a8-4ea4-b3fc-d62ce499732b'::uuid, '7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid, '5254a3fb-dc38-40c2-9cf3-810a79835275', '2026-07-04 03:43:09.607005+00'::timestamptz, '20a72d271941f1297a31536be4f38444', '2026-10', '2026-10-05'::date, '2026-10', 'approved_r1c_c_b_manifest');

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

create temporary table r1d_c_b_a2_non_target_before on commit drop as
select lesson.id,
       to_jsonb(lesson) as row_snapshot,
       case when exists (
         select 1
         from public.school_business_entity_migration_items item
         where item.batch_id='c1000000-0000-4000-8000-202607279999'
           and item.lesson_record_id=lesson.id
       ) then 'a1' else 'other' end as cohort
from public.school_lesson_records lesson
where not exists (
  select 1 from r1d_c_b_a2_manifest manifest where manifest.lesson_id=lesson.id
);

create temporary table r1d_c_b_a2_business_before (
  object_name text primary key,
  row_count bigint not null,
  business_hash text not null
) on commit drop;

insert into r1d_c_b_a2_business_before
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

create temporary table r1d_c_b_a2_execution_context (
  decided_at timestamptz not null
) on commit drop;

create temporary table r1d_c_b_a2_updated_ids (
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
  from r1d_c_b_a2_manifest;

  if v_count <> 66
     or (select count(distinct lesson_id) from r1d_c_b_a2_manifest) <> 66
     or (select min(item_order) from r1d_c_b_a2_manifest) <> 1
     or (select max(item_order) from r1d_c_b_a2_manifest) <> 66
     or v_hash <> '6d6e0a39969343b18dbfbae5be41ceb4' then
    raise exception 'R1D_C_B_A2_MANIFEST_SHAPE_OR_HASH_MISMATCH: rows=%, hash=%',v_count,v_hash;
  end if;

  if exists (
    select 1 from r1d_c_b_a2_manifest
    where proposed_billing_month not in ('2026-09','2026-10','2026-11')
       or proposed_student_settlement_month <> proposed_billing_month
       or proposed_billing_month_source <> 'approved_r1c_c_b_manifest'
       or extract(isodow from proposed_billing_week_start_date)::integer <> 1
       or to_char(proposed_billing_week_start_date,'YYYY-MM') <> proposed_billing_month
  ) then
    raise exception 'R1D_C_B_A2_MANIFEST_PROPOSED_VALUE_MISMATCH';
  end if;

  if (select count(*) from r1d_c_b_a2_manifest
      where expected_student_id='7aef8061-7037-4881-a847-a2cdb031c0f4') <> 66
     or (select count(*) from r1d_c_b_a2_manifest where proposed_billing_month='2026-09') <> 24
     or (select count(*) from r1d_c_b_a2_manifest where proposed_billing_month='2026-10') <> 24
     or (select count(*) from r1d_c_b_a2_manifest where proposed_billing_month='2026-11') <> 18 then
    raise exception 'R1D_C_B_A2_STUDENT_OR_MONTH_DISTRIBUTION_MISMATCH';
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
    raise exception 'R1D_C_B_A2_SEVEN_CONSTRAINTS_NOT_VALIDATED';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_records_updated_at'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'R1D_C_B_A2_UPDATED_AT_TRIGGER_NOT_ENABLED';
  end if;

  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='validation_preview_only')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked')) <> 3 then
    raise exception 'R1D_C_B_A2_R0_GATE_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items
      where batch_id='c1000000-0000-4000-8000-202607289999') <> 66 then
    raise exception 'R1D_C_B_A2_MIGRATION_BATCH_COUNT_MISMATCH';
  end if;

  if exists (
    select 1
    from r1d_c_b_a2_manifest manifest
    left join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
    left join public.school_business_entity_migration_items item
      on item.batch_id='c1000000-0000-4000-8000-202607289999'
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
    raise exception 'R1D_C_B_A2_FIXED_BEFORE_FINGERPRINT_MISMATCH';
  end if;

  if (select count(*) from public.school_lesson_records lesson
      join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id) <> 66
     or (select sum(lesson.duration_hours) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id) <> 145
     or (select sum(lesson.lesson_fee) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id) <> 1450000
     or (select sum(lesson.duration_hours) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-09') <> 52
     or (select sum(lesson.lesson_fee) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-09') <> 520000
     or (select sum(lesson.duration_hours) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-10') <> 52
     or (select sum(lesson.lesson_fee) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-10') <> 520000
     or (select sum(lesson.duration_hours) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-11') <> 41
     or (select sum(lesson.lesson_fee) from public.school_lesson_records lesson
         join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id
         where manifest.proposed_billing_month='2026-11') <> 410000 then
    raise exception 'R1D_C_B_A2_BUSINESS_SUMMARY_MISMATCH';
  end if;

  if exists (
    select 1
    from public.school_lesson_records actual
    join r1d_c_b_a2_manifest manifest on manifest.lesson_id=actual.planned_lesson_id
    where actual.lesson_type='actual'
  ) then
    raise exception 'R1D_C_B_A2_TARGET_HAS_ACTUAL';
  end if;

  if exists (
    select 1
    from public.school_student_tuition_bill_lessons relation
    join r1d_c_b_a2_manifest manifest on manifest.lesson_id=relation.planned_lesson_id
  ) then
    raise exception 'R1D_C_B_A2_TARGET_HAS_BILL_RELATION';
  end if;

  if (select count(distinct candidate.planned_lesson_id)
      from r1d_c_b_a2_manifest manifest
      join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
      cross join lateral public.school_list_student_tuition_candidates(
        lesson.student_id,lesson.business_entity_id,lesson.year_month,false
      ) candidate
      where candidate.planned_lesson_id=manifest.lesson_id
        and candidate.candidate_status='candidate') <> 66 then
    raise exception 'R1D_C_B_A2_TARGET_CANDIDATE_BASELINE_MISMATCH';
  end if;

  if (select count(*) from r1d_c_b_a2_non_target_before) <> 560
     or (select count(*) from r1d_c_b_a2_non_target_before where cohort='a1') <> 52
     or (select count(*) from r1d_c_b_a2_non_target_before where cohort='other') <> 508 then
    raise exception 'R1D_C_B_A2_NON_TARGET_COHORT_COUNT_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items item
      join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
      where item.batch_id='c1000000-0000-4000-8000-202607279999'
        and lesson.billing_month='2026-08'
        and lesson.billing_week_start_date is not null
        and lesson.student_settlement_month='2026-08'
        and lesson.billing_month_source='approved_r1c_a_manifest'
        and lesson.billing_month_decided_at='2026-07-28 00:27:52.779654+00'::timestamptz
        and lesson.scheduled_lesson_date is null
        and lesson.updated_at=item.original_updated_at
        and (to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at')=item.after_row_snapshot) <> 52 then
    raise exception 'R1D_C_B_A2_A1_52_BASELINE_MISMATCH';
  end if;

  v_decided_at := clock_timestamp();
  if v_decided_at='2026-07-28 00:27:52.779654+00'::timestamptz then
    raise exception 'R1D_C_B_A2_DECIDED_AT_REUSED_A1';
  end if;
  insert into r1d_c_b_a2_execution_context values (v_decided_at);

  execute 'alter table public.school_lesson_records disable trigger trg_school_lesson_records_updated_at';
  begin
    with changed as (
      update public.school_lesson_records lesson
      set billing_month=manifest.proposed_billing_month,
          billing_week_start_date=manifest.proposed_billing_week_start_date,
          student_settlement_month=manifest.proposed_student_settlement_month,
          billing_month_source=manifest.proposed_billing_month_source,
          billing_month_decided_at=v_decided_at
      from r1d_c_b_a2_manifest manifest
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
    insert into r1d_c_b_a2_updated_ids select id from changed;

    get diagnostics v_count = row_count;
    if v_count <> 66 then
      raise exception 'R1D_C_B_A2_UPDATE_COUNT_MISMATCH: expected 66, got %',v_count;
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
  if (select count(*) from r1d_c_b_a2_updated_ids) <> 66
     or exists (
       select lesson_id from r1d_c_b_a2_manifest
       except select lesson_id from r1d_c_b_a2_updated_ids
     )
     or exists (
       select lesson_id from r1d_c_b_a2_updated_ids
       except select lesson_id from r1d_c_b_a2_manifest
     ) then
    raise exception 'R1D_C_B_A2_UPDATED_ID_SET_MISMATCH';
  end if;

  if exists (
    select 1
    from r1d_c_b_a2_manifest manifest
    join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
    cross join r1d_c_b_a2_execution_context execution
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
    raise exception 'R1D_C_B_A2_TARGET_AFTER_MISMATCH';
  end if;

  if (select count(distinct billing_month_decided_at)
      from public.school_lesson_records lesson
      join r1d_c_b_a2_manifest manifest on manifest.lesson_id=lesson.id) <> 1
     or exists (
       select 1 from r1d_c_b_a2_execution_context
       where decided_at='2026-07-28 00:27:52.779654+00'::timestamptz
     ) then
    raise exception 'R1D_C_B_A2_DECIDED_AT_NOT_NEW_AND_UNIFIED';
  end if;

  if exists (
    select 1
    from r1d_c_b_a2_non_target_before before_row
    join public.school_lesson_records lesson on lesson.id=before_row.id
    where to_jsonb(lesson) is distinct from before_row.row_snapshot
  ) or (select count(*) from r1d_c_b_a2_non_target_before) <> 560
    or (select count(*) from r1d_c_b_a2_non_target_before where cohort='a1') <> 52
    or (select count(*) from r1d_c_b_a2_non_target_before where cohort='other') <> 508 then
    raise exception 'R1D_C_B_A2_NON_TARGET_ROW_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records
      where billing_month is not null) <> 118
     or (select count(*) from public.school_lesson_records
         where billing_week_start_date is not null) <> 118
     or (select count(*) from public.school_lesson_records
         where student_settlement_month is not null) <> 118
     or (select count(*) from public.school_lesson_records
         where billing_month_source is not null) <> 118
     or (select count(*) from public.school_lesson_records
         where billing_month_decided_at is not null) <> 118
     or (select count(*) from public.school_lesson_records
         where scheduled_lesson_date is not null) <> 0
     or (select count(distinct billing_month_decided_at)
         from public.school_lesson_records where billing_month_decided_at is not null) <> 2 then
    raise exception 'R1D_C_B_A2_GLOBAL_NEW_FIELD_SCOPE_MISMATCH';
  end if;

  if (select count(*) from public.school_business_entity_migration_items item
      join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
      where item.batch_id='c1000000-0000-4000-8000-202607279999'
        and lesson.billing_month='2026-08'
        and lesson.student_settlement_month='2026-08'
        and lesson.billing_month_source='approved_r1c_a_manifest'
        and lesson.billing_month_decided_at='2026-07-28 00:27:52.779654+00'::timestamptz
        and lesson.scheduled_lesson_date is null
        and lesson.updated_at=item.original_updated_at
        and (to_jsonb(lesson)
          - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
          - 'student_settlement_month' - 'billing_month_source'
          - 'billing_month_decided_at')=item.after_row_snapshot) <> 52 then
    raise exception 'R1D_C_B_A2_A1_52_CHANGED';
  end if;

  if (select count(*) from public.school_lesson_records
      where lesson_type='actual'
        and billing_month is null
        and billing_week_start_date is null
        and scheduled_lesson_date is null
        and student_settlement_month is null
        and billing_month_source is null
        and billing_month_decided_at is null) <> 229 then
    raise exception 'R1D_C_B_A2_ACTUAL_CHANGED';
  end if;

  if not exists (
    select 1 from pg_trigger
    where tgrelid='public.school_lesson_records'::regclass
      and tgname='trg_school_lesson_records_updated_at'
      and tgenabled='O' and not tgisinternal
  ) then
    raise exception 'R1D_C_B_A2_UPDATED_AT_TRIGGER_NOT_REENABLED';
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
    from r1d_c_b_a2_business_before
    where object_name=v_after_business.object_name;
    if v_before_business.row_count is distinct from v_after_business.row_count
       or v_before_business.business_hash is distinct from v_after_business.business_hash then
      raise exception 'R1D_C_B_A2_BUSINESS_BASELINE_CHANGED: %',v_after_business.object_name;
    end if;
  end loop;

  if (select count(*) from public.school_feature_gates
      where (feature_key='student_tuition_preview' and state='validation_preview_only')
         or (feature_key='student_tuition_generate' and state='blocked')
         or (feature_key='student_tuition_cash_submit' and state='blocked')) <> 3 then
    raise exception 'R1D_C_B_A2_R0_GATE_CHANGED';
  end if;
end;
$$;

select
  count(*) as updated_rows,
  min(execution.decided_at) as billing_month_decided_at,
  count(distinct lesson.billing_month_decided_at) as distinct_decided_at,
  count(*) filter(where lesson.scheduled_lesson_date is null) as scheduled_null_rows,
  md5(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text),'' order by lesson.id::text)) as old31_hash
from r1d_c_b_a2_manifest manifest
join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
cross join r1d_c_b_a2_execution_context execution;

select
  lesson.billing_month,
  count(*) as lesson_count,
  sum(lesson.duration_hours) as hours,
  sum(lesson.lesson_fee) as fee_jpy
from r1d_c_b_a2_manifest manifest
join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
group by lesson.billing_month
order by lesson.billing_month;

\if :r1d_c_b_a2_commit
  commit;
\else
  rollback;
\endif
