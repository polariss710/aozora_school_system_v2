-- Exact definition rollback for the 2026-08-16 locked billing-month makeup
-- guard deployment. Safe only before the target correction is applied.
\set ON_ERROR_STOP on
\pset pager off

begin;
set local lock_timeout='10s';
set local statement_timeout='240s';

do $preflight$
begin
  if to_regprocedure(
       'public.school_correct_sun_chenfeng_20260811_makeup_v1(timestamp with time zone,timestamp with time zone,text,text)'
     ) is null
     or (select count(*) from public.school_lesson_records l
         where l.id='8b737b58-cd14-42c5-afd2-34730dcef963'::uuid
           and md5(to_jsonb(l)::text)='07296184e3ffaf443f89109e2b54d9b9')<>1
     or (select count(*) from public.school_lesson_records l
         where l.id='c8e6cf21-850c-4700-af9e-7ebf3c2a577d'::uuid
           and md5(to_jsonb(l)::text)='1086af5afd9a91d3a6a03b2d5b9cc458')<>1 then
    raise exception 'SUN_CHENFENG_EXACT_ROLLBACK_UNSAFE_AFTER_DATA_CORRECTION';
  end if;
end;
$preflight$;

drop function public.school_correct_sun_chenfeng_20260811_makeup_v1(
  timestamptz,timestamptz,text,text
);

\ir school_locked_billing_month_nonbilling_makeup_predeployment_definitions_20260816.sql

do $verify$
begin
  if md5(pg_get_functiondef(
       'public.school_create_lesson_credit_makeup_actual(uuid,date,uuid,uuid,text,text,numeric,text,text,integer,text,text)'::regprocedure
     ))<>'e6de3be6719e88c7da9b451e40f3b7c7'
     or md5(pg_get_functiondef(
       'public.school_enforce_r1d_e_b2_actual_attribution()'::regprocedure
     ))<>'60e380b560b0682dd78aa97139382d65'
     or md5(pg_get_functiondef(
       'public.school_create_cancelled_actual_lesson_from_planned(uuid,date,text,text,numeric,numeric,integer,text,text)'::regprocedure
     ))<>'73ac1abeebb6ce82870f9e0f8240629b'
     or to_regprocedure(
       'public.school_correct_sun_chenfeng_20260811_makeup_v1(timestamp with time zone,timestamp with time zone,text,text)'
     ) is not null then
    raise exception 'SUN_CHENFENG_EXACT_ROLLBACK_DEFINITION_VERIFY_FAILED';
  end if;
end;
$verify$;

notify pgrst,'reload schema';
commit;
select 'SUN_CHENFENG_EXACT_ROLLBACK_COMPLETED' result;
