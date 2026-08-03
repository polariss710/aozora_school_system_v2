-- P0-F exact manifest correction: normalize numeric rate scale before hashing.
\set ON_ERROR_STOP on
begin;
do $correction$
declare v_definition text; v_corrected text;
begin
  select pg_get_functiondef(
    'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
  ) into v_definition;
  if position('p_settlement_exchange_rate::text' in v_definition)=0
     or position('FM999999990.000000' in v_definition)>0 then
    raise exception 'P0F_RATE_HASH_CORRECTION_SOURCE_DRIFT';
  end if;
  v_corrected:=replace(v_definition,'p_settlement_exchange_rate::text',
    'to_char(p_settlement_exchange_rate,''FM999999990.000000'')');
  execute v_corrected;
  if position('FM999999990.000000' in pg_get_functiondef(
       'public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)'::regprocedure
     ))=0 then
    raise exception 'P0F_RATE_HASH_CORRECTION_FAILED';
  end if;
end
$correction$;
revoke all on function public.school_tuition_p0f_source_lines(uuid,uuid,text,numeric,boolean)
  from public,anon,authenticated,service_role;
commit;
