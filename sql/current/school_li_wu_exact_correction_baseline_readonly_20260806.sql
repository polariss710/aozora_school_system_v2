-- School V2 Li Tianlun + Wu Feng exact correction production baseline.
-- SELECT only. Does not lock or modify production business data.
\set ON_ERROR_STOP on
\pset pager off

begin transaction isolation level repeatable read read only;

with manifest(ordinal,lesson_id,expected_row_md5) as (values
  (1, 'f256bca9-fac5-4909-b113-8077efd27d65'::uuid, '3726481d8f512e47dba1c34efa276701'),
  (2, 'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid, '30349b3e50ed4c3fdf22e34e8dcd9c43'),
  (3, '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid, '96ff1feca91a4fa49003fb3727b1da8c'),
  (4, '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid, '4b6143e1ab2de6db0b4f6f9e50f1c792'),
  (5, 'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid, '68a2e384c0da181bbc514899899e1bf1'),
  (6, 'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid, 'a1597f23dbc50a1f4597cb0498de8dc8'),
  (7, 'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid, '97667b2d7b8bd485e7571c7ca12306d8'),
  (8, 'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid, '0483222ed7058a4a6107579de796d8ba'),
  (9, '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid, 'f4006e9086cedf5ff0f378fe0ca7987f'),
  (10, 'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid, 'b111085217eff6410f34895722068117'),
  (11, 'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid, '34ecb1210e1c65d2e35f0b8165b97d06')
), live as (
  select m.ordinal,m.lesson_id,m.expected_row_md5,
         md5(to_jsonb(l)::text) live_row_md5,l.voided_at,l.void_reason
  from manifest m
  left join public.school_lesson_records l on l.id=m.lesson_id
)
select *,expected_row_md5=live_row_md5 row_hash_matches
from live order by ordinal;

with manifest(ordinal,lesson_id) as (values
  (1, 'f256bca9-fac5-4909-b113-8077efd27d65'::uuid),
  (2, 'a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid),
  (3, '265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid),
  (4, '552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid),
  (5, 'e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid),
  (6, 'ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid),
  (7, 'b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid),
  (8, 'f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid),
  (9, '39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid),
  (10, 'dc06b98c-360f-4661-a294-52ecb82830a7'::uuid),
  (11, 'c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid)
), live as (
  select m.ordinal,m.lesson_id,md5(to_jsonb(l)::text) row_md5
  from manifest m
  join public.school_lesson_records l on l.id=m.lesson_id
)
select count(*) manifest_count,
       md5(string_agg(row_md5,'' order by ordinal)) combined_by_approved_order,
       md5(string_agg(row_md5,'' order by lesson_id::text)) combined_by_uuid,
       md5(string_agg(lesson_id::text || row_md5,'' order by lesson_id::text)) combined_id_hash_by_uuid,
       md5(string_agg(lesson_id::text || '|' || row_md5,E'\n' order by lesson_id::text)) combined_lines_by_uuid
from live;

with manifest(lesson_id) as (values
  ('f256bca9-fac5-4909-b113-8077efd27d65'::uuid),('a722a49e-dbe5-447d-8068-fd5fb743f6ab'::uuid),
  ('265f4d3d-2372-42e3-aec3-b963bbdddf95'::uuid),('552c54e3-2d0c-4607-962d-aad39dfff7f7'::uuid),
  ('e890424d-407d-4fc2-b8ad-84745b242cdd'::uuid),('ac16b068-a58b-4ca5-be95-7c57c3f1b82b'::uuid),
  ('b186fa1c-a56b-4ed7-b566-178a5708ae96'::uuid),('f759623b-ce28-4c5f-8556-95c4381b6b1b'::uuid),
  ('39aa30ab-d66c-43c0-bbde-3b3a35d71fb7'::uuid),('dc06b98c-360f-4661-a294-52ecb82830a7'::uuid),
  ('c582a187-32f6-4a24-bb7b-d590b25c1854'::uuid)
)
select 'planned_legacy_evidence' object_name,count(*) row_count,
       md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' order by e.planned_lesson_id::text),'')) row_hash
from public.school_legacy_planned_settlement_evidence e
join manifest m on m.lesson_id=e.planned_lesson_id
union all
select 'actual_legacy_evidence',count(*),
       md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' order by e.actual_lesson_id::text),''))
from public.school_legacy_actual_settlement_evidence e
join manifest m on m.lesson_id=e.actual_lesson_id
order by object_name;

select feature_key,state,updated_at
from public.school_feature_gates
where feature_key in ('student_tuition_preview','student_tuition_generate','student_tuition_cash_submit')
order by feature_key;

select 'LI_WU_EXACT_CORRECTION_BASELINE_READONLY_PASS' result;
rollback;
