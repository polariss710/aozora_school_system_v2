-- One-shot production execution for the exact approved Sun Chenfeng chain.
-- The owner-only correction function is removed in the same transaction.
\set ON_ERROR_STOP on
\pset pager off
begin;
set local lock_timeout='10s';
set local statement_timeout='120s';

do $preflight$
declare
  v_acl text;
begin
  select coalesce(array_to_string(p.proacl,','),'') into strict v_acl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.oid='public.school_correct_sun_chenfeng_20260811_makeup_v1(timestamp with time zone,timestamp with time zone,text,text)'::regprocedure
    and pg_get_userbyid(p.proowner)='postgres'
    and p.prosecdef
    and p.proconfig=array['search_path=pg_catalog, public']::text[];
  if v_acl<>'postgres=X/postgres' then
    raise exception 'SUN_CHENFENG_CORRECTION_OWNER_ONLY_ACL_CHANGED: %',v_acl;
  end if;

  if (select md5(to_jsonb(l)::text) from public.school_lesson_records l
      where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid)
       is distinct from '07296184e3ffaf443f89109e2b54d9b9'
     or (select md5(to_jsonb(l)::text) from public.school_lesson_records l
      where l.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid)
       is distinct from '1086af5afd9a91d3a6a03b2d5b9cc458'
     or (select md5(to_jsonb(l)::text) from public.school_lesson_records l
      where l.id='6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)
       is distinct from '94050771268fa97cda680affb81e9364'
     or public.school_get_lesson_credit_remaining_hours(
       '6722e5a8-d7a1-453a-93a8-9cbaab227378'::uuid)<>2 then
    raise exception 'SUN_CHENFENG_CORRECTION_TARGET_PREFLIGHT_CHANGED';
  end if;
end;
$preflight$;

select set_config('request.jwt.claims',
  '{"sub":"25331ae9-3412-48b9-bdc3-e516caeaeba4","role":"authenticated"}',true);

create temp table sun_chenfeng_correction_result on commit drop as
select * from public.school_correct_sun_chenfeng_20260811_makeup_v1(
  '2026-08-01 14:02:23.647108+00'::timestamptz,
  '2026-07-31 15:51:01.478823+00'::timestamptz,
  '孙陈锋2026-08-01实际缺课；纠正错误ordinary actual并转待补，2026-08-11由田宇辰完成非计费补课；actor_user_id=25331ae9-3412-48b9-bdc3-e516caeaeba4',
  'CORRECT_SUN_CHENFENG_20260811_MAKEUP'
);

do $result_assert$
begin
  if (select count(*) from sun_chenfeng_correction_result)<>1
     or not exists(
       select 1 from sun_chenfeng_correction_result r
       where r.planned_lesson_id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
         and r.voided_actual_id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
         and r.actor_user_id='25331ae9-3412-48b9-bdc3-e516caeaeba4'::uuid
         and r.remaining_makeup_hours=0
         and r.teacher_settlement_month='2026-08'
         and r.lesson_wage_jpy=8000
         and r.message='SUN_CHENFENG_20260811_MAKEUP_CORRECTION_COMPLETED'
     ) then
    raise exception 'SUN_CHENFENG_CORRECTION_RESULT_INVALID';
  end if;
end;
$result_assert$;

select * from sun_chenfeng_correction_result;

revoke all on function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  timestamptz,timestamptz,text,text
) from public,anon,authenticated,service_role;
drop function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  timestamptz,timestamptz,text,text
);
notify pgrst,'reload schema';

commit;
select 'SUN_CHENFENG_EXACT_CORRECTION_COMMITTED_AND_ENTRYPOINT_REMOVED' result;
