\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset fieldsep '\t'
\pset null ''
\pset footer off

-- Read-only evidence export for the 64 candidates frozen at
-- 2026-08-01 14:22:08.134118+00.
-- Candidate ID set SHA-256:
-- 7e36bc9702bfb9ac16c27bb73045023ccbbaa87a44119b4c36712d5eeb5b4f85
WITH fixed(planned_id, expected_before_row_hash) AS (
  VALUES
    ('01997034-0ea8-432f-a0f5-33cf76446a7d'::uuid,'ffb1692e05c12a94d74254c2bdabec27'),
    ('02c4b099-e6b9-4460-abd3-de94b56fa82f'::uuid,'466fd42147bbdd7b4b836250f4382f9a'),
    ('1121f1aa-12bc-4130-b971-91032beae5ba'::uuid,'8ffa8d41ac02480defc87c725a771986'),
    ('16906a22-08fe-4bd3-a625-a383656d323a'::uuid,'d09026e73b40d33f42169b47b91c2373'),
    ('1d507d2c-530b-4939-9106-bf4ba4c7987c'::uuid,'e2360ebae260ab642f26600461116068'),
    ('2ac7b22a-2058-476c-9adf-4c189c7c5585'::uuid,'b46700a2de737c832ec82224e2d8f329'),
    ('2cdf7693-43cd-4add-b5eb-d06bd140d56b'::uuid,'c6e88d0ba46fb8037e0c81196267141d'),
    ('2e6317f8-04fa-4124-b87e-c2f5938f80bc'::uuid,'e192ee045f01c68f64a42f96ba1271d9'),
    ('54af9e60-4eba-48a8-8143-2007d9cf8a85'::uuid,'f70e14885d78123268ee319047493bac'),
    ('5bd17863-a4cc-434e-9333-5ee9a0a6cb24'::uuid,'c3591aef477d8e3af5f71717f3ed2138'),
    ('60467cdb-84d4-4acf-bff8-1516dd2915d1'::uuid,'1530092f8fc08e52ba5dca4d927a6ed9'),
    ('60c011b3-315d-4c05-9a79-aae8b34569bd'::uuid,'f7fabab0bacc696e48064927c6e4e59b'),
    ('60ea5e21-44e2-4af2-9f01-f817d9c9a431'::uuid,'e75400d113403574f10d8916a9d13668'),
    ('6bcee9d9-850f-4a11-b918-155e4ff80002'::uuid,'94b898d3cba33c03e99739afa637fb90'),
    ('7434a052-2d5e-4adc-b7a2-8ba4ed368e37'::uuid,'4afe0dc57c91b8c07aafaf0792d7079f'),
    ('86ea020e-1596-4abb-bf8b-a3495fce26e7'::uuid,'f8fdfb22f51bf799d09062e5dfc58f4a'),
    ('8af59321-039f-4fea-a3d9-3fad2b724458'::uuid,'2858c945af407a8866bc683f94d1c580'),
    ('8cbac83a-cc19-4a0c-8bc8-398c1cb3eb52'::uuid,'79f4c11d85b491e91ac79803f0e8d750'),
    ('8deb0b45-091a-46ae-8c2d-8cdea0da116e'::uuid,'44dfbb03ad62b98ab8ec9e8bffcecc78'),
    ('923e3dca-dc19-42a4-aa0c-2c27b16ce83c'::uuid,'8157ef0dec1c99d8111d79a6cf614e91'),
    ('97fd81bd-3803-4cdc-8583-fb9514e26439'::uuid,'76bf5f74e77b7d8b805f55f232f87889'),
    ('9c60891b-5c31-4f01-b2ac-30b7071a725f'::uuid,'8fd0d4f4bc40eeb2a58b55da7b9419a5'),
    ('9f145846-5d5f-4168-bdaa-8169e93884dd'::uuid,'6c2f01def8879e16c61b98098b416a4b'),
    ('a452787b-5cd8-4ccd-ac35-d5960db786a5'::uuid,'2e2765c11b954df3164ec729f44b593d'),
    ('a86ca98c-3fd0-4520-b47d-d092d179a38d'::uuid,'9d0b2ccf09425510be9cae7e6e5a131a'),
    ('bb61ec60-e301-46a5-91a4-cdd581a0c0bf'::uuid,'851a3f7a705b00d5a998f9a38e330117'),
    ('d1ca3e0a-8edb-4121-9e45-2de503501ba9'::uuid,'257cdd4fee6bf1156f20cb1ff18558b9'),
    ('d36c5a5c-e333-4db3-a3f0-25e629a6cbdd'::uuid,'2828f9547093f9117d86519ebff208e4'),
    ('e25e88f0-d9b3-4dc2-8247-5d83bd27f344'::uuid,'323f2a197cb8e556b86539339747dc8e'),
    ('fe809b10-7744-4ec2-94e6-836cbf507cdd'::uuid,'51207586d47f36c0209ab8713365ea7e'),
    ('06e49b97-234d-4233-8548-b2636bdf851d'::uuid,'fab4135588ae7eacc92d5a7fd3b02346'),
    ('09a4f5cf-65ae-400f-b7c6-4dd59d27bf3d'::uuid,'de16d789debee3bcde477138dedb4b21'),
    ('0a6a9f56-d2b8-40fd-b0e4-502773f648b6'::uuid,'3858b81e0e874501ea4346e5d7d94943'),
    ('0afbc656-29e8-4583-8ff0-67450623a859'::uuid,'5bafbc7e9539fecfec6300fed76617b3'),
    ('13b08cc6-720b-4002-9207-1f5b8bd64ae5'::uuid,'7d29db37b6c94217f2d7d78f140eb719'),
    ('14e5ac8c-d4f6-4bce-b0d4-28399d5f57cb'::uuid,'64e404d768191960d32ee10e4a38ad1f'),
    ('2073ff43-e70e-4e1f-8097-61ab9e151e11'::uuid,'fdab1e6e7bbf17511b355fe82a564286'),
    ('316fdd57-277c-425a-80ec-39cea197f00a'::uuid,'e25bebfece705af5bddc241691156585'),
    ('4015d1e6-c3bd-4dca-8e0f-4eba15f5252a'::uuid,'65dbd575e19d27bc73817dd821d4507f'),
    ('43a8e403-88cc-4c50-bce5-b6a96df763ae'::uuid,'89e0f3579d7b5fa93c21bb8efcba3d45'),
    ('47d73896-4b17-431e-83ba-38ee36a3fa5b'::uuid,'4d5466da83e0fd6051e53d70e15d36ec'),
    ('4aa7c6ef-ef3f-4c4f-9a52-58948d07aacc'::uuid,'8947869947d7857b4190f6b51b02a3db'),
    ('4e2c7294-6cec-42a4-a91a-5d8c8339e677'::uuid,'2aa32ea381adc25b9f7e1e45bdd2ec8c'),
    ('550553ae-be7c-4577-9f04-43b1feaae48d'::uuid,'8bb33768ff4e20b78181c4794d66b947'),
    ('5dbf82b5-4c85-40f6-80e2-976f6936c64c'::uuid,'505580a47f7b636144485cbca2588ed7'),
    ('5f1babca-be7b-43c8-a7de-2379a6c573aa'::uuid,'8d552c204a2449ec356cd781fbb58538'),
    ('644d3126-d563-48de-97da-b8665d511bd2'::uuid,'458031fecde4d1932e93e39b6bfe6426'),
    ('6c44b0c6-bc45-4262-baa5-fe95c31e3852'::uuid,'30e3c122f2a25ae48ea0cb02da27425c'),
    ('727304b4-19d4-478d-ac5f-700262e09e1d'::uuid,'37987ff1e1c503ab219961eef5ce5349'),
    ('7de38e7a-233a-47e2-b2b8-726ed5a0d37d'::uuid,'26f2c141cd32d12dc77df5d2f2abeee4'),
    ('88995922-a375-427d-a56f-6cd838312c96'::uuid,'4e13532f90f3f09ac59b88feab1cbc6e'),
    ('8a6fad1b-7d34-463b-b2ec-e4c95e68cd24'::uuid,'c01a0afdbf30362fc070fc55e5d6751c'),
    ('8ca07718-b50d-44a6-be39-2b838c13b69b'::uuid,'e5861d4ffad152056e52a5160070ce5f'),
    ('9cea7b9b-7f7a-4c18-be2e-74c8ee68ef6c'::uuid,'d6bc6f9030ca1ddf1e311e017a08b163'),
    ('bf10cbe0-8fd5-4d0a-b2e4-64a2bb65de8e'::uuid,'acc5eeb589121f1698fc81cd43e0523e'),
    ('bfc41de1-f186-4676-9955-e93fc100c6bc'::uuid,'410e796e88d310ef9a32a48471f8cdf9'),
    ('ce991343-9a45-4a77-bd09-bb37a8b7692e'::uuid,'6348367faaf3c7af3f5150a067b1888f'),
    ('e96e59f5-6ec5-49cc-a0b3-33021a0b68fc'::uuid,'c885b893988dda2032ea494af5f464c2'),
    ('ec0610ed-ddf4-4942-bdab-65f69c77274f'::uuid,'60122de1d2119479626e3040e1888a97'),
    ('f495da4a-71c0-49a3-81ed-5834b3b983bb'::uuid,'16e9d57d6a18fd579b082294c8c5ede6'),
    ('f4b7c125-8cba-4654-9657-1ebdfc3520b7'::uuid,'303fb0eec50362edeff20b76befdf05a'),
    ('f8c94de2-92be-4b93-baba-3f70d89e00c4'::uuid,'21ae64997244675da89a405e24541a4b'),
    ('fff47dbd-f4ca-4c3e-b4a9-aa0515655a12'::uuid,'8e9117ec0d40e4c14d321070aab55f11'),
    ('fffb0867-77c3-4643-8969-1d8e2d063ac1'::uuid,'6b566ccf7548a4b7037f7cb53381b179')
),
target AS (
  SELECT f.*,l.*,md5(to_jsonb(l)::text) AS before_row_hash
  FROM fixed f
  JOIN public.school_lesson_records l ON l.id=f.planned_id
  WHERE md5(to_jsonb(l)::text)=f.expected_before_row_hash
),
scopes AS (
  SELECT DISTINCT student_id,business_entity_id,billing_month FROM target
),
charge_candidate AS (
  SELECT c.*
  FROM scopes s
  CROSS JOIN LATERAL public.school_list_student_tuition_charge_candidates(
    s.student_id,s.business_entity_id,s.billing_month,false
  ) c
  JOIN fixed f ON f.planned_id=c.planned_lesson_id
),
actual_agg AS (
  SELECT a.planned_lesson_id,
         count(*)::integer AS linked_actual_count,
         string_agg(a.id::text,',' ORDER BY a.lesson_date,a.id) AS linked_actual_ids,
         string_agg(a.status,',' ORDER BY a.lesson_date,a.id) AS actual_statuses,
         string_agg(a.lesson_date::text,',' ORDER BY a.lesson_date,a.id) AS actual_dates
  FROM public.school_lesson_records a
  JOIN fixed f ON f.planned_id=a.planned_lesson_id
  WHERE a.lesson_type='actual'
  GROUP BY a.planned_lesson_id
),
relation_agg AS (
  SELECT r.planned_lesson_id,count(*)::integer AS bill_relation_count,
         string_agg(r.relation_role,',' ORDER BY r.line_no,r.id) AS bill_relation_roles,
         string_agg(DISTINCT r.tuition_bill_id::text,',' ORDER BY r.tuition_bill_id::text) AS bill_ids
  FROM public.school_student_tuition_bill_lessons r
  JOIN fixed f ON f.planned_id=r.planned_lesson_id
  GROUP BY r.planned_lesson_id
),
same_bill AS (
  SELECT s.student_id,s.business_entity_id,s.billing_month,
         count(*) FILTER (WHERE b.status IN ('draft','income_created'))::integer AS bill_count,
         string_agg(b.id::text,',' ORDER BY b.created_at,b.id)
           FILTER (WHERE b.status IN ('draft','income_created')) AS bill_ids
  FROM scopes s
  LEFT JOIN public.school_student_tuition_bills b
    ON b.student_id=s.student_id AND b.billing_month=s.billing_month
  GROUP BY s.student_id,s.business_entity_id,s.billing_month
),
same_income_rows AS (
  SELECT s.student_id,s.business_entity_id,s.billing_month,
         i.id,i.income_date,i.created_at,i.status,i.currency,i.amount,
         i.description,i.note,i.business_entity_id AS income_business_entity_id
  FROM scopes s
  JOIN public.school_income_records i
    ON i.student_id=s.student_id
   AND i.income_category='tuition'
   AND coalesce(i.settlement_month,i.year_month)=s.billing_month
),
same_income AS (
  SELECT i.student_id,i.business_entity_id,i.billing_month,
         count(*)::integer AS income_count,
         string_agg(i.id::text,',' ORDER BY i.income_date,i.created_at,i.id) AS income_ids,
         string_agg(i.status,',' ORDER BY i.income_date,i.created_at,i.id) AS income_statuses,
         count(DISTINCT e.id)::integer AS cash_linkage_count,
         count(DISTINCT a.id)::integer AS account_transaction_count,
         string_agg(DISTINCT concat(
           'income=',i.id,'[',i.status,',entity=',coalesce(be.name,i.income_business_entity_id::text),
           ',',i.currency,' ',i.amount,
           CASE WHEN coalesce(i.description,i.note) IS NULL THEN ''
                ELSE ','||regexp_replace(coalesce(i.description,i.note),'[\t\r\n]+',' ','g') END,
           ']'),'; ' ORDER BY concat(
           'income=',i.id,'[',i.status,',entity=',coalesce(be.name,i.income_business_entity_id::text),
           ',',i.currency,' ',i.amount,
           CASE WHEN coalesce(i.description,i.note) IS NULL THEN ''
                ELSE ','||regexp_replace(coalesce(i.description,i.note),'[\t\r\n]+',' ','g') END,
           ']'))
         || CASE WHEN count(DISTINCT e.id)>0
                 THEN '; school_cash_linkage_ids='||string_agg(DISTINCT e.id::text,',' ORDER BY e.id::text)
                 ELSE '' END
         || CASE WHEN count(DISTINCT a.id)>0
                 THEN '; account_transaction_ids='||string_agg(DISTINCT a.id::text,',' ORDER BY a.id::text)
                 ELSE '' END AS evidence
  FROM same_income_rows i
  LEFT JOIN public.school_business_entities be ON be.id=i.income_business_entity_id
  LEFT JOIN public.school_personal_cash_income_linkage_events e
    ON e.income_record_id=i.id OR (e.source_table='school_income_records' AND e.source_id=i.id)
  LEFT JOIN public.school_account_transactions a
    ON a.related_table='school_income_records' AND a.related_id=i.id
  GROUP BY i.student_id,i.business_entity_id,i.billing_month
),
rows AS (
  SELECT row_number() OVER (ORDER BY l.billing_month,s.name,l.billing_week_start_date,
                              l.lesson_date,l.start_time NULLS FIRST,sub.name,l.id) AS review_no,
         s.name AS student_name,s.id AS student_id,l.billing_month,
         l.billing_week_start_date,l.lesson_date,l.start_time,l.end_time,
         t.name AS teacher_name,t.id AS teacher_id,sub.name AS subject_name,sub.id AS subject_id,
         l.status,l.lesson_count,c.duration_hours,c.unit_price,
         c.base_lesson_fee_jpy AS base_fee_jpy,c.aircon_fee_jpy,
         c.lesson_total_fee_jpy AS course_total_jpy,l.id AS planned_id,
         be.name AS business_entity,l.import_batch_id AS generation_batch_id,
         regexp_replace(concat_ws(' | ',nullif(l.import_source,''),nullif(l.note,''),
           nullif(l.lesson_content,'')),'[\t\r\n]+',' ','g') AS source_note,
         coalesce(a.linked_actual_count,0) AS linked_actual_count,
         a.linked_actual_ids,a.actual_statuses,a.actual_dates,
         coalesce(r.bill_relation_count,0) AS bill_relation_count,
         r.bill_relation_roles,r.bill_ids,
         coalesce(b.bill_count,0) AS same_month_tuition_bill_count,b.bill_ids AS same_month_tuition_bill_ids,
         coalesce(i.income_count,0) AS same_month_tuition_income_count,i.income_ids AS same_month_tuition_income_ids,
         i.income_statuses AS same_month_tuition_income_statuses,
         coalesce(i.cash_linkage_count,0) AS school_cash_linkage_count,
         coalesce(i.account_transaction_count,0) AS account_transaction_count,
         coalesce(i.evidence,'no School-side same-month tuition income/Cash/account evidence')
           AS legacy_income_or_cash_evidence,
         CASE
           WHEN l.status IN ('voided','cancelled','inactive')
             OR concat_ws(' ',l.import_batch_id,l.import_source,l.note,l.lesson_content)
                ~* '(codex-test|v2-test|sandbox|测试|test|void)'
             THEN 'LIKELY_TEST_OR_VOID'
           WHEN coalesce(i.income_count,0)>0
             AND coalesce(i.cash_linkage_count,0)>0
             AND i.income_statuses LIKE '%received%'
             THEN 'LIKELY_ALREADY_CHARGED'
           WHEN coalesce(r.bill_relation_count,0)>0 OR coalesce(b.bill_count,0)>0
             OR coalesce(i.income_count,0)>0 OR coalesce(i.cash_linkage_count,0)>0
             OR coalesce(i.account_transaction_count,0)>0
             THEN 'NEEDS_MANUAL_REVIEW'
           WHEN coalesce(a.linked_actual_count,0)>0
             AND l.status IN ('planned','completed','pending_makeup')
             THEN 'LIKELY_UNCHARGED'
           ELSE 'NEEDS_MANUAL_REVIEW'
         END AS codex_suggested_classification,
         CASE
           WHEN l.status IN ('voided','cancelled','inactive')
             OR concat_ws(' ',l.import_batch_id,l.import_source,l.note,l.lesson_content)
                ~* '(codex-test|v2-test|sandbox|测试|test|void)'
             THEN '状态或来源含测试/作废信号；须由业务负责人确认排除。'
           WHEN coalesce(i.income_count,0)>0
             AND coalesce(i.cash_linkage_count,0)>0
             AND i.income_statuses LIKE '%received%'
             THEN concat('无planned直接bill relation，但同学生同月有',i.income_count,
                         '条received tuition income及',i.cash_linkage_count,
                         '条School Cash linkage；并有actual履约，强烈提示该月已收费，仍须逐条人工归属。')
           WHEN coalesce(r.bill_relation_count,0)>0 OR coalesce(b.bill_count,0)>0
             OR coalesce(i.income_count,0)>0 OR coalesce(i.cash_linkage_count,0)>0
             OR coalesce(i.account_transaction_count,0)>0
             THEN '收费证据不完整或相互不一致，无法仅凭School侧证据可靠归类。'
           WHEN coalesce(a.linked_actual_count,0)>0
             AND l.status IN ('planned','completed','pending_makeup')
             THEN '存在completed actual履约且为正常历史课时；School侧未见直接relation、同月bill/income、Cash linkage或账户流水，提示可能未收费，但仍需排除系统外或未录入历史收款。'
           ELSE '现有School侧证据不足，需人工核对。'
         END AS suggestion_reason,
         ''::text AS manual_decision,''::text AS manual_note,
         l.before_row_hash
  FROM target l
  JOIN charge_candidate c ON c.planned_lesson_id=l.id
  JOIN public.school_students s ON s.id=l.student_id
  LEFT JOIN public.school_teachers t ON t.id=l.teacher_id
  LEFT JOIN public.school_subjects sub ON sub.id=l.subject_id
  LEFT JOIN public.school_business_entities be ON be.id=l.business_entity_id
  LEFT JOIN actual_agg a ON a.planned_lesson_id=l.id
  LEFT JOIN relation_agg r ON r.planned_lesson_id=l.id
  LEFT JOIN same_bill b ON b.student_id=l.student_id AND b.business_entity_id=l.business_entity_id
                         AND b.billing_month=l.billing_month
  LEFT JOIN same_income i ON i.student_id=l.student_id AND i.business_entity_id=l.business_entity_id
                           AND i.billing_month=l.billing_month
)
SELECT * FROM rows ORDER BY review_no;
