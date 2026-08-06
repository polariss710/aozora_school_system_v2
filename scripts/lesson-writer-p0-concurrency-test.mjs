import { spawn, spawnSync } from 'node:child_process';

const dbUrl = process.env.SCHOOL_SUPABASE_DB_URL;
if (!dbUrl) throw new Error('SCHOOL_SUPABASE_DB_URL_REQUIRED');

const marker = 'codex-test lesson writer p0 concurrency';
const actor = 'be120000-0000-4000-8000-000000000001';
const subject = 'be120000-0000-4000-8000-00000000d001';
const teacher = 'be120000-0000-4000-8000-000000007001';
const student = 'be120000-0000-4000-8000-00000000a001';
const planned = 'be120000-0000-4000-8000-000000001101';

function psql(sql) {
  const result = spawnSync('psql', [dbUrl, '-X', '-v', 'ON_ERROR_STOP=1', '-P', 'pager=off'], {
    input: sql,
    encoding: 'utf8',
    env: process.env,
  });
  if (result.status !== 0) {
    throw new Error(`PSQL_FAILED\n${result.stderr || result.stdout}`);
  }
  return result.stdout;
}

function psqlAsync(sql) {
  return new Promise((resolve) => {
    const child = spawn('psql', [dbUrl, '-X', '-v', 'ON_ERROR_STOP=1', '-P', 'pager=off'], {
      env: process.env,
      stdio: ['pipe', 'pipe', 'pipe'],
    });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('close', (code) => resolve({ code, output: `${stdout}\n${stderr}` }));
    child.stdin.end(sql);
  });
}

const cleanupSql = `
begin;
delete from public.school_lesson_records
 where planned_lesson_id='${planned}'::uuid and note='${marker}';
delete from public.school_lesson_records
 where id='${planned}'::uuid and note='${marker}';
delete from public.school_students where id='${student}'::uuid and note='${marker}';
delete from public.school_teachers where id='${teacher}'::uuid and note='${marker}';
delete from public.school_subjects where id='${subject}'::uuid and note='${marker}';
delete from public.school_app_memberships where user_id='${actor}'::uuid and note='${marker}';
delete from auth.users where id='${actor}'::uuid
  and raw_user_meta_data->>'codex_test'='lesson-p0-concurrency';
commit;
do $verify$
begin
  if exists(select 1 from auth.users where id='${actor}'::uuid)
     or exists(select 1 from public.school_lesson_records where id='${planned}'::uuid or planned_lesson_id='${planned}'::uuid)
     or exists(select 1 from public.school_students where id='${student}'::uuid)
     or exists(select 1 from public.school_teachers where id='${teacher}'::uuid)
     or exists(select 1 from public.school_subjects where id='${subject}'::uuid) then
    raise exception 'LESSON_WRITER_P0_CONCURRENCY_CLEANUP_FAILED';
  end if;
end;
$verify$;
select 'LESSON_WRITER_P0_CONCURRENCY_CLEANUP_PASS' result;
`;

const setupSql = `
begin;
do $preflight$
begin
  if exists(select 1 from auth.users where id='${actor}'::uuid)
     or exists(select 1 from public.school_lesson_records where id='${planned}'::uuid or planned_lesson_id='${planned}'::uuid)
     or exists(select 1 from public.school_students where id='${student}'::uuid)
     or exists(select 1 from public.school_teachers where id='${teacher}'::uuid)
     or exists(select 1 from public.school_subjects where id='${subject}'::uuid) then
    raise exception 'LESSON_WRITER_P0_CONCURRENCY_FIXTURE_COLLISION';
  end if;
end;
$preflight$;
insert into auth.users(id,aud,role,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
values('${actor}','authenticated','authenticated','{"provider":"email","providers":["email"]}',
  '{"codex_test":"lesson-p0-concurrency"}',now(),now());
insert into public.school_app_memberships(user_id,role,is_active,created_by_user_id,updated_by_user_id,note)
values('${actor}','operator',true,'${actor}','${actor}','${marker}');
insert into public.school_subjects(id,name,category,is_active,note,primary_category)
values('${subject}','codex-test lesson writer P0 concurrency subject','codex-test',true,'${marker}','班课');
insert into public.school_teachers(
 id,teacher_code,name,display_name,default_subject_id,default_business_entity_id,status,note,app_type
) values('${teacher}','codex-lesson-p0-concurrency','codex-test lesson writer P0 concurrency teacher',
 'codex-test lesson writer P0 concurrency teacher','${subject}',
 public.school_primary_business_entity_id(),'active','${marker}','school');
insert into public.school_students(
 id,student_code,name,display_name,business_entity_id,status,app_type,preset_exchange_rate,previous_balance_cny,note
) values('${student}','codex-lesson-p0-concurrency','codex-test lesson writer P0 concurrency student',
 'codex-test lesson writer P0 concurrency student',public.school_primary_business_entity_id(),
 'active','school',0.05,0,'${marker}');
insert into public.school_lesson_records(
 id,lesson_type,lesson_date,year_month,student_id,teacher_id,subject_id,business_entity_id,
 start_time,end_time,duration_hours,lesson_content,status,is_billable,app_type,unit_price,
 lesson_fee,lesson_count,lesson_delivery_mode,lesson_venue,note
) values('${planned}','planned','2020-05-06','2020-05','${student}','${teacher}','${subject}',
 public.school_primary_business_entity_id(),'09:00','11:00',2,'codex-test concurrency source',
 'pending_makeup',true,'school',1000,2000,1,'online','Zoom','${marker}');
commit;
`;

const callSql = `
begin;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"${actor}","role":"authenticated"}',true);
select id from public.school_create_lesson_credit_makeup_actual(
 '${planned}','2020-05-06','${teacher}','${subject}','09:00','10:30',null,
 'codex-test concurrent makeup','${marker}',1,'online','Zoom');
commit;
`;

let setupDone = false;
try {
  psql(setupSql);
  setupDone = true;
  const results = await Promise.all([psqlAsync(callSql), psqlAsync(callSql)]);
  const successCount = results.filter((result) => result.code === 0).length;
  const exceededCount = results.filter((result) =>
    result.code !== 0 && result.output.includes('LESSON_MAKEUP_CREDIT_EXCEEDED')).length;
  if (successCount !== 1 || exceededCount !== 1) {
    throw new Error(`CONCURRENCY_RESULT_INVALID:${JSON.stringify(results)}`);
  }
  const winnerOutput = results.find((result) => result.code === 0)?.output ?? '';
  const winnerIds = winnerOutput.match(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/gi) ?? [];
  const fixedIds = new Set([actor, subject, teacher, student, planned]);
  const winnerId = winnerIds.findLast((id) => !fixedIds.has(id.toLowerCase()));
  if (!winnerId) throw new Error('CONCURRENCY_WINNER_ID_MISSING');
  process.stdout.write(`LESSON_WRITER_P0_CONCURRENCY_WINNER_ID=${winnerId}\n`);
  const verification = psql(`
do $verify$
declare
  v_count integer;
  v_duration numeric;
  v_minutes integer;
  v_status text;
  v_billable boolean;
  v_fee numeric;
begin
  select count(*),min(duration_hours),min(actual_minutes),min(status),bool_or(is_billable),min(lesson_fee)
    into v_count,v_duration,v_minutes,v_status,v_billable,v_fee
  from public.school_lesson_records
  where planned_lesson_id='${planned}'::uuid and note='${marker}';
  if v_count<>1 or v_duration<>1.5 or v_minutes<>90
     or v_status<>'makeup_completed' or v_billable or v_fee<>0 then
    raise exception 'LESSON_WRITER_P0_CONCURRENCY_WINNER_FAILED';
  end if;
  if public.school_get_lesson_credit_raw_remaining_hours('${planned}'::uuid)<>0.5 then
    raise exception 'LESSON_WRITER_P0_CONCURRENCY_REMAINING_FAILED';
  end if;
end;
$verify$;
select 'LESSON_WRITER_P0_CONCURRENCY_WINNER_PASS' result;
select 'LESSON_WRITER_P0_CONCURRENCY_REMAINING_PASS' result;
`);
  process.stdout.write(verification);
  process.stdout.write('LESSON_WRITER_P0_CONCURRENCY_PASS\n');
} finally {
  if (setupDone) process.stdout.write(psql(cleanupSql));
}
