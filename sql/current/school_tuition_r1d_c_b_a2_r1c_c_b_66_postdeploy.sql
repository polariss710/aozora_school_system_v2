-- R1D-C-B-A2 postdeploy verification. SELECT-only.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

select clock_timestamp() as postdeploy_started_at,
       current_setting('transaction_isolation') as isolation,
       current_setting('transaction_read_only') as read_only;

with manifest(lesson_id,student_id,generation_batch_id,expected_updated_at,expected_old31_hash,billing_month,billing_week) as (
  values
    ('0386bf22-8619-41f2-be6c-5106b8c17cd0'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'a62204a53ef42c843c04580a59178839','2026-10','2026-10-05'::date),
    ('0624fabe-a3c8-4930-aa41-8ed800a28eea'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'797808a487e2db20d0d4054a382129bb','2026-11','2026-11-02'::date),
    ('0a3a8c13-12cb-4430-a933-2941221c0c77'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'767cc20ccb3d677ea5d72ee4406d428e','2026-10','2026-10-26'::date),
    ('0ea530e7-12ac-41fa-9f6e-972b24662a72'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'a45b17af3cb3450be5a51c2bf726de30','2026-10','2026-10-19'::date),
    ('0f168663-afb1-49a7-90a8-39197ad7729e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'9a4baf9b61b4b98f6687144c1fc29c90','2026-11','2026-11-30'::date),
    ('10b62cc8-dd74-4665-a6cd-02cc02924a65'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'579866221fae12c1b602b57cb159f97a','2026-09','2026-09-14'::date),
    ('15f8147e-5bb0-4cf9-9ba7-3e12f115774e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'44762f74f46e976931f272c6cd29ca43','2026-09','2026-09-07'::date),
    ('17e58b7d-3fb8-4874-8071-0b1f808e8430'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'cf6ba5a211000193ddcfb2eab65bc10e','2026-10','2026-10-12'::date),
    ('1eeb937e-a7ad-4e7c-955d-797b9d979882'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'4d1eacd31e2f3bb1f61803228e29cfc7','2026-09','2026-09-28'::date),
    ('207430a6-c9cd-4acb-9a7d-962c078b0623'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'1063586abf4c0016beb0ae241081cf7e','2026-11','2026-11-09'::date),
    ('21e97cbd-3e18-4c9e-9790-981f885af03a'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'425f1fa06598bef28ccc425c23f46b2e','2026-09','2026-09-28'::date),
    ('224015ce-b435-4233-8113-0e6c712b1a18'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'80f479e74ed46a3736e9677fe28f271d','2026-09','2026-09-07'::date),
    ('297c7ed8-4aca-40d5-b4de-5fcb3e2ddb83'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'c9542833be300c25114796bf51a02784','2026-10','2026-10-19'::date),
    ('2bd402cb-fc4d-48cc-b166-400ee4945703'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0683e43d58de138c3bd75ce962ed85ae','2026-09','2026-09-07'::date),
    ('30271ef0-51ee-43ca-9103-1b5ec34255e1'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'46fa9c69eede26dda2dcd4133705ef4e','2026-10','2026-10-12'::date),
    ('3048b190-31e0-49b1-a255-ce73e6e15fc0'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'7b176cfd75085ff489922d09f218ce50','2026-10','2026-10-19'::date),
    ('371e41c5-a659-44a6-87e0-c3a85c9c1b75'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'26fca610a6fafce1befa7b078b906c72','2026-09','2026-09-28'::date),
    ('3f5884ea-ca12-41dc-89ce-ebc67db27fe8'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'52d36b891f312004659ec88fa3fdd225','2026-11','2026-11-02'::date),
    ('4254095b-9ec1-4651-a9ff-0dffb3a4520f'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'a0a9de7fd44e29a351f236091737b01c','2026-10','2026-10-05'::date),
    ('4505777b-13e3-4187-9839-618ebe186f22'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'e6f98cd8c08f896714158d99bb988fce','2026-10','2026-10-26'::date),
    ('5591fb92-2333-460c-95f3-85c6511d6fd4'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'508470750ecc81187b3ef747d3381f3c','2026-09','2026-09-21'::date),
    ('5666a624-05b5-4408-bc11-5d208851b216'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'697b8b377d7f9c74338c82416e5ba71a','2026-11','2026-11-09'::date),
    ('57948b80-89d9-45f2-a99f-3b92aed9f4e8'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'2e7f3485bec1af2d85a99ad1b67ee8b5','2026-09','2026-09-14'::date),
    ('584ef4d6-fa9d-4dd8-803c-cab68ac67a67'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'fab5d2a284abd2e3211dfbaea7919a31','2026-11','2026-11-23'::date),
    ('594a4559-c1b1-4ad1-88e6-4c7834052831'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'678eddd7080ef901003ae709869d44fc','2026-11','2026-11-30'::date),
    ('645cccaf-ae0f-41b3-84d1-e40882a8c85f'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'3913910c6b371853f5910f21e6b83c13','2026-09','2026-09-21'::date),
    ('68da4912-72a8-418c-b30b-335bb9896c63'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0d7730cba59d3c156e1fb64f8c4050dd','2026-09','2026-09-14'::date),
    ('70c31ae5-6083-46cb-90ad-fdc24726b6b6'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'f2727783eec851da48f64cd3061a9886','2026-10','2026-10-19'::date),
    ('73dd0453-aec2-4612-b710-071a372f88ad'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'06c20251dc4859df4b2586944d531260','2026-11','2026-11-16'::date),
    ('7e833e2c-3bc0-4c6d-a1ab-204229f43a77'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'b498c136d181cdf01653b25a8f27bd9e','2026-10','2026-10-05'::date),
    ('812979d0-43ac-4075-b38f-4c9aa455cd4b'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'8928cd931f0d012cecd70ecb8be7fd7f','2026-10','2026-10-19'::date),
    ('82e81ecc-dd23-471e-8402-a45bd8b20eb1'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'ba7c307daf4ba2e993d5793c278e9b92','2026-09','2026-09-21'::date),
    ('895ebf6e-6bf0-419d-bf9a-418d048a42a7'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'6948f70ebad670b0426d718138acb79c','2026-10','2026-10-26'::date),
    ('89797ce3-58e0-4c9d-b107-79eca71e4161'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0ecced3530b402177b97b023a8e347d2','2026-11','2026-11-02'::date),
    ('92a0f909-6458-4d34-9144-9d60eeede33f'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'082f88238d41d125e8f440777f469643','2026-10','2026-10-26'::date),
    ('966119c6-09c8-4ac5-9c16-6cda13137d87'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'9da7944cae8e1d2f5c2f135eebcfda66','2026-09','2026-09-28'::date),
    ('a3a7dd70-1a1e-4078-bce8-d54f10fc57af'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'dfe60d7025b0da8993e8c3ea6be7b3cc','2026-10','2026-10-12'::date),
    ('a42b1b2e-4f55-4915-a20b-bd411b4d81a0'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'d424b68e6a388d972b7321e0590100c0','2026-11','2026-11-02'::date),
    ('a4cd05e7-47e7-4e0d-8af8-dad6c7505744'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'5a51e623a95ef2ceeb6e8f136f0fec5a','2026-11','2026-11-23'::date),
    ('a57bf7af-43e1-46ba-9bb6-9ee511b81e05'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'75caedb220d9542b868af681f387d614','2026-11','2026-11-09'::date),
    ('a9de94c0-954b-452d-95b0-6a8b7d1a5a9e'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'08510ab7b3eafbcd50e3bb7bd3bc9a6d','2026-09','2026-09-14'::date),
    ('a9e861d3-6bd6-4b76-ba78-4cc1f3265b43'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'bb9984b92546dbf3e95a6b510ff7e756','2026-09','2026-09-28'::date),
    ('aea933f5-5e3b-4476-b1f0-d781d41312a3'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'fd38c737f4c9384d0925821f6606729e','2026-10','2026-10-05'::date),
    ('b33f023c-4b0c-495e-8f0b-934ead526421'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'68f418c4edaa1a1b561d420de54caf2d','2026-10','2026-10-05'::date),
    ('bc718d5f-dc21-4e7d-914a-dd3a6debaeb6'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0032fb14098ab330482b30415b7513d0','2026-11','2026-11-16'::date),
    ('bf38024e-2a5f-422c-ad41-01ec9922e701'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'203d962c8bfc46bc3b28fa46ebd8b153','2026-09','2026-09-21'::date),
    ('c1f5c7e9-70e4-4c2d-99c8-aadd986cda15'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'65a4b556391835654f4b66a4dfcdeaaa','2026-09','2026-09-07'::date),
    ('c48478ef-8b3d-4c7f-bd48-cc99659e99f7'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'b0687c8e00264e8168935551b05a6709','2026-10','2026-10-26'::date),
    ('c79e2ade-4026-4ab3-a316-ba26354abfe2'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'953af0a89508745add3b468b646d535d','2026-09','2026-09-14'::date),
    ('cfb5e237-51a3-48b2-a12e-e8f0628e2c51'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'929e5f18ddc60450c4e7c5e66a9122ae','2026-10','2026-10-12'::date),
    ('d1961919-8c05-42e8-8a06-4ed1fabb13c0'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'ebdb87e001a29fe2d7cae4cc2aaf830f','2026-10','2026-10-19'::date),
    ('d2307a35-1f41-4402-ab4d-c03ed4305f50'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'08dc896a689196e1111b69d0cbeb900b','2026-11','2026-11-02'::date),
    ('d8ed3671-6865-42b6-a4a2-06b31c9051e6'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'1eba573d744f6f251766d128e65bcb4d','2026-10','2026-10-26'::date),
    ('d9d11e4b-a01c-4535-93cf-bc51cf08b900'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'1c6489b83ab1c8773bb2f6cd68d56b0d','2026-10','2026-10-12'::date),
    ('dadcf864-5343-403d-a111-e68b8617f413'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'6ebb6328821c630bf6332d91e2ded586','2026-09','2026-09-07'::date),
    ('dbd6f35a-b0ee-4af8-bcda-e065330f0413'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'fe7f1da4a60471b71fd2de30d9b9e2e1','2026-09','2026-09-21'::date),
    ('def65ad3-6f87-4889-802f-202550a9af49'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'926c88d1e2868e06ea12d46581822175','2026-11','2026-11-30'::date),
    ('eec50614-788d-429b-99a4-fc8938a86dda'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'cb0100bb26a1cf4f8d1163015e64bd3a','2026-10','2026-10-12'::date),
    ('f1a321d8-5528-4afe-8fb7-79204f49f3dc'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'1a75b558bcd6354b2ba298d1e3685f99','2026-11','2026-11-16'::date),
    ('f693a3d9-fada-48f2-8203-bc33d46ee4dd'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'0a5ca13b8b267984bca0bc622223d058','2026-09','2026-09-14'::date),
    ('f91ecdd8-7442-4879-97b6-67ad8ea99f23'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'3a5c11b62591bc80838b9700bd6ea280','2026-09','2026-09-07'::date),
    ('fb066255-82b5-4eb1-9f76-a776c04becc2'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'cdd9eab094fa0902889f3223c8a4f5c9','2026-09','2026-09-21'::date),
    ('fc138193-f76a-476c-a394-b49d2e68dde2'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'37552ec3c8ab8727145f138965106c30','2026-11','2026-11-23'::date),
    ('fd34b0d7-86c2-4d0e-a519-de2317e0ab26'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'69c1b50ee4562515443abdfa35a8e7fe','2026-11','2026-11-02'::date),
    ('fd803263-07b6-4b1f-b668-43a482f21c89'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'bd23c5764f7d4f263edbff06831a7d38','2026-09','2026-09-28'::date),
    ('ff368fb5-94a8-4ea4-b3fc-d62ce499732b'::uuid,'7aef8061-7037-4881-a847-a2cdb031c0f4'::uuid,'5254a3fb-dc38-40c2-9cf3-810a79835275','2026-07-04 03:43:09.607005+00'::timestamptz,'20a72d271941f1297a31536be4f38444','2026-10','2026-10-05'::date)
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
           - 'billing_month_decided_at')::text) as current_old31_hash
  from manifest
  join public.school_lesson_records lesson on lesson.id=manifest.lesson_id
)
select
  (select count(*) from manifest) as manifest_rows,
  count(*) as matched_rows,
  count(*) filter(where checked.current_student_id=checked.student_id) as student_matches,
  count(*) filter(where checked.current_generation_batch_id=checked.generation_batch_id) as generation_batch_matches,
  count(*) filter(where checked.current_updated_at=checked.expected_updated_at) as updated_at_matches,
  count(*) filter(where checked.current_old31_hash=checked.expected_old31_hash) as old31_hash_matches,
  count(*) filter(where checked.current_billing_month=checked.billing_month
    and checked.current_billing_week=checked.billing_week
    and checked.current_student_settlement_month=checked.billing_month
    and checked.current_source='approved_r1c_c_b_manifest'
    and checked.current_decided_at is not null
    and checked.current_decided_at<>'2026-07-28 00:27:52.779654+00'::timestamptz
    and checked.current_scheduled_lesson_date is null
    and public.school_is_valid_tuition_billing_period(
      checked.current_billing_month,checked.current_billing_week)) as attribution_matches,
  count(distinct checked.current_decided_at) as decided_at_distinct,
  min(checked.current_decided_at) as billing_month_decided_at,
  md5(string_agg(checked.current_old31_hash,'' order by checked.lesson_id::text)) as target_old31_hash
from checked;

select lesson.billing_month,
       count(*) as lesson_count,
       sum(lesson.duration_hours) as hours,
       sum(lesson.lesson_fee) as fee_jpy,
       count(*) filter(where public.school_is_valid_tuition_billing_period(
         lesson.billing_month,lesson.billing_week_start_date)) as valid_period_rows
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
where item.batch_id='c1000000-0000-4000-8000-202607289999'
group by lesson.billing_month
order by lesson.billing_month;

select
  count(*) as lesson_count,
  count(*) filter(where lesson_type='planned') as planned_count,
  count(*) filter(where lesson_type='actual') as actual_count,
  count(*) filter(where billing_month is not null) as billing_month_nonnull,
  count(*) filter(where billing_week_start_date is not null) as billing_week_nonnull,
  count(*) filter(where scheduled_lesson_date is not null) as scheduled_nonnull,
  count(*) filter(where student_settlement_month is not null) as settlement_nonnull,
  count(*) filter(where billing_month_source is not null) as source_nonnull,
  count(*) filter(where billing_month_decided_at is not null) as decided_nonnull,
  count(distinct billing_month_decided_at) filter(where billing_month_decided_at is not null) as decided_at_distinct,
  md5(coalesce(string_agg(md5((to_jsonb(lesson)
    - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
    - 'student_settlement_month' - 'billing_month_source'
    - 'billing_month_decided_at')::text),'' order by id::text),'')) as old31_hash,
  md5(coalesce(string_agg(md5(to_jsonb(lesson)::text),'' order by id::text),'')) as raw37_hash
from public.school_lesson_records lesson;

select item.batch_id,count(*) as item_count,
       count(*) filter(where lesson.billing_month is null
         and lesson.billing_week_start_date is null
         and lesson.scheduled_lesson_date is null
         and lesson.student_settlement_month is null
         and lesson.billing_month_source is null
         and lesson.billing_month_decided_at is null) as six_null_count,
       count(*) filter(where lesson.updated_at=item.original_updated_at) as updated_at_match_count,
       count(*) filter(where (to_jsonb(lesson)
         - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
         - 'student_settlement_month' - 'billing_month_source'
         - 'billing_month_decided_at')=item.after_row_snapshot) as old31_snapshot_match_count,
       md5(string_agg(md5((to_jsonb(lesson)
         - 'billing_month' - 'billing_week_start_date' - 'scheduled_lesson_date'
         - 'student_settlement_month' - 'billing_month_source'
         - 'billing_month_decided_at')::text),'' order by lesson.id::text)) as old31_hash,
       count(distinct lesson.billing_month_decided_at) as decided_at_distinct,
       min(lesson.billing_month_decided_at) as billing_month_decided_at
from public.school_business_entity_migration_items item
join public.school_lesson_records lesson on lesson.id=item.lesson_record_id
where item.batch_id in ('c1000000-0000-4000-8000-202607279999','c1000000-0000-4000-8000-202607289999')
group by item.batch_id
order by item.batch_id;

select
  count(*) filter(where lesson.lesson_type='actual') as actual_rows,
  count(*) filter(where lesson.lesson_type='actual'
    and lesson.billing_month is null
    and lesson.billing_week_start_date is null
    and lesson.scheduled_lesson_date is null
    and lesson.student_settlement_month is null
    and lesson.billing_month_source is null
    and lesson.billing_month_decided_at is null) as actual_six_null_rows,
  count(*) filter(where relation.relation_role='canonical_charge') as historical_canonical_rows,
  count(*) filter(where relation.relation_role='incident_duplicate') as historical_incident_rows,
  count(*) filter(where relation.relation_role='legacy_cancelled') as historical_legacy_rows,
  count(*) filter(where relation.id is not null
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

select count(*) as bill_count,
       count(*) filter(where bill.income_record_id=income.id
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
