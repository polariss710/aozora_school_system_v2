import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawn, spawnSync } from "node:child_process";

const pgBin = "/opt/homebrew/Cellar/postgresql@17/17.10/bin";
const initdb = join(pgBin, "initdb");
const pgCtl = join(pgBin, "pg_ctl");
const psqlBin = join(pgBin, "psql");
const root = mkdtempSync(join(tmpdir(), "sun-chenfeng-makeup-local-"));
const data = join(root, "data");
const socket = join(root, "socket");
const port = String(55000 + (process.pid % 1000));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", ...options });
  if (result.status !== 0) {
    throw new Error(`${command} failed\n${result.stdout || ""}\n${result.stderr || ""}`);
  }
  return result.stdout;
}

function psql(sql) {
  return run(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", sql], { timeout: 15000 });
}

function psqlAsync(sql) {
  return new Promise((resolve) => {
    const child = spawn(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", sql], {
      stdio: ["ignore", "pipe", "pipe"],
    });
    let output = "";
    let finished = false;
    const finish = (code) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      resolve({ code, output });
    };
    child.stdout.on("data", (chunk) => { output += chunk; });
    child.stderr.on("data", (chunk) => { output += chunk; });
    child.on("error", (error) => { output += String(error); finish(-1); });
    child.on("exit", (code) => {
      child.stdout.destroy();
      child.stderr.destroy();
      finish(code ?? -1);
    });
    const timer = setTimeout(() => {
      output += "\nLOCAL_PSQL_TIMEOUT";
      child.kill("SIGKILL");
      finish(-1);
    }, 15000);
  });
}

let started = false;
let passed = false;
try {
  run(initdb, ["-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"]);
  run("mkdir", [socket]);
  run(pgCtl, ["-D", data, "-o", `-F -p ${port} -k ${socket} -c listen_addresses=''`, "-w", "start"], { stdio: "ignore" });
  started = true;

  psql(`
create role anon nologin;
create role authenticated nologin;
create role service_role nologin;
create schema auth;
create function auth.uid() returns uuid language sql stable as $$
  select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
create table school_app_memberships(user_id uuid primary key,role text not null,is_active boolean not null);
create table local_sources(
  id uuid primary key,source_date date not null,remaining numeric not null,
  student_month_locked boolean not null,wage_month_locked boolean not null
);
create table local_actuals(
  id uuid primary key default gen_random_uuid(),source_id uuid not null,
  actual_date date not null,duration numeric not null,is_billable boolean not null,
  lesson_fee numeric not null
);
create function local_makeup(p_source uuid,p_date date,p_duration numeric)
returns uuid language plpgsql security definer set search_path=pg_catalog,public as $$
declare v_actor uuid:=auth.uid(); v_role text; v_active boolean; v_source local_sources%rowtype; v_id uuid;
begin
  if v_actor is null then raise exception using errcode='42501',message='AUTH_REQUIRED'; end if;
  select role,is_active into v_role,v_active from school_app_memberships where user_id=v_actor;
  if not found then raise exception using errcode='42501',message='MEMBERSHIP_REQUIRED'; end if;
  if v_active is distinct from true then raise exception using errcode='42501',message='ACTIVE_REQUIRED'; end if;
  if v_role not in ('admin','operator') then raise exception using errcode='42501',message='ROLE_REQUIRED'; end if;
  select * into strict v_source from local_sources where id=p_source for update;
  if p_date<v_source.source_date then raise exception 'DATE_BEFORE_SOURCE'; end if;
  if v_source.wage_month_locked then raise exception 'WAGE_LOCKED'; end if;
  if p_duration<=0 or p_duration>v_source.remaining then raise exception 'CREDIT_EXCEEDED'; end if;
  -- student_month_locked deliberately does not block this fixed fee-zero path.
  insert into local_actuals(source_id,actual_date,duration,is_billable,lesson_fee)
  values(p_source,p_date,p_duration,false,0) returning id into v_id;
  update local_sources set remaining=remaining-p_duration where id=p_source;
  return v_id;
end $$;
revoke all on function local_makeup(uuid,date,numeric) from public,anon,authenticated,service_role;
grant execute on function local_makeup(uuid,date,numeric) to authenticated;
insert into school_app_memberships values
 ('a0000000-0000-4000-8000-000000000001','admin',true),
 ('a0000000-0000-4000-8000-000000000002','operator',true),
 ('a0000000-0000-4000-8000-000000000003','read_only',true),
 ('a0000000-0000-4000-8000-000000000004','admin',false);
insert into local_sources values
 ('b0000000-0000-4000-8000-000000000001','2026-08-01',2,true,false),
 ('b0000000-0000-4000-8000-000000000002','2026-08-01',2,true,true),
 ('b0000000-0000-4000-8000-000000000003','2026-08-01',2,true,false);
`);

  const roleCases = [
    ["a0000000-0000-4000-8000-000000000003", "ROLE_REQUIRED"],
    ["a0000000-0000-4000-8000-000000000004", "ACTIVE_REQUIRED"],
    ["a0000000-0000-4000-8000-000000000099", "MEMBERSHIP_REQUIRED"],
  ];
  for (const [actor, expected] of roleCases) {
    const out = spawnSync(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", `set role authenticated; select set_config('request.jwt.claims','{"sub":"${actor}"}',false); select local_makeup('b0000000-0000-4000-8000-000000000001','2026-08-11',2);`], {
      encoding: "utf8",
      timeout: 15000,
    });
    assert.notEqual(out.status, 0);
    assert.match(`${out.stdout}${out.stderr}`, new RegExp(expected));
  }

  const acl = spawnSync(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", "set role anon; select local_makeup('b0000000-0000-4000-8000-000000000001','2026-08-11',2);"], {
    encoding: "utf8",
    timeout: 15000,
  });
  assert.notEqual(acl.status, 0);
  assert.match(`${acl.stdout}${acl.stderr}`, /permission denied/i);

  const negative = spawnSync(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", `set role authenticated; select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001"}',false); select local_makeup('b0000000-0000-4000-8000-000000000002','2026-08-11',2);`], {
    encoding: "utf8",
    timeout: 15000,
  });
  assert.notEqual(negative.status, 0);
  assert.match(`${negative.stdout}${negative.stderr}`, /WAGE_LOCKED/);

  const early = spawnSync(psqlBin, ["-X", "-h", socket, "-p", port, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-At", "-c", `set role authenticated; select set_config('request.jwt.claims','{"sub":"a0000000-0000-4000-8000-000000000001"}',false); select local_makeup('b0000000-0000-4000-8000-000000000001','2026-07-31',2);`], {
    encoding: "utf8",
    timeout: 15000,
  });
  assert.notEqual(early.status, 0);
  assert.match(`${early.stdout}${early.stderr}`, /DATE_BEFORE_SOURCE/);

  const call = (actor) => `begin; set local role authenticated; select set_config('request.jwt.claims','{"sub":"${actor}"}',true); select local_makeup('b0000000-0000-4000-8000-000000000003','2026-08-11',2); commit;`;
  const concurrent = await Promise.all([
    psqlAsync(call("a0000000-0000-4000-8000-000000000001")),
    psqlAsync(call("a0000000-0000-4000-8000-000000000002")),
  ]);
  assert.equal(concurrent.filter((item) => item.code === 0).length, 1);
  assert.equal(concurrent.filter((item) => item.code !== 0 && /CREDIT_EXCEEDED/.test(item.output)).length, 1);
  assert.equal(psql("select remaining from local_sources where id='b0000000-0000-4000-8000-000000000003';").trim(), "0");
  const fact = psql("select count(*)||'|'||bool_and(is_billable)::text||'|'||min(lesson_fee)::text from local_actuals where source_id='b0000000-0000-4000-8000-000000000003';").trim();
  assert.equal(fact, "1|false|0");

  passed = true;
} finally {
  const stopped = !started || spawnSync(pgCtl, ["-D", data, "-m", "immediate", "-w", "stop"], { stdio: "ignore" }).status === 0;
  if (stopped) rmSync(root, { recursive: true, force: true });
}
if (passed) {
  console.log("LOCKED_BILLING_MONTH_NONBILLING_MAKEUP_LOCAL_POSTGRES_PASS");
  process.exit(0);
}
