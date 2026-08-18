import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const pgBin = "/opt/homebrew/Cellar/postgresql@17/17.10/bin";
const initdb = join(pgBin, "initdb");
const pgCtl = join(pgBin, "pg_ctl");
const psql = join(pgBin, "psql");
const repo = resolve(import.meta.dirname, "..");
const root = mkdtempSync(join(tmpdir(), "school-clearance-overage-"));
const data = join(root, "data");
const socket = join(root, "socket");
const port = String(57900 + (process.pid % 100));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: "utf8", ...options });
  if (result.status !== 0) {
    throw new Error(`${command} failed\n${result.stdout || ""}\n${result.stderr || ""}`);
  }
  return `${result.stdout || ""}${result.stderr || ""}`;
}

let started = false;
try {
  run(initdb, ["-D", data, "--no-locale", "--encoding=UTF8", "--auth=trust"]);
  run("mkdir", [socket]);
  run(pgCtl, ["-D", data, "-o", `-F -p ${port} -k ${socket} -c listen_addresses=''`, "-w", "start"], { stdio: "ignore" });
  started = true;
  const output = run(psql, [
    "-X", "-h", socket, "-p", port, "-d", "postgres",
    "-v", "ON_ERROR_STOP=1",
    "-f", join(repo, "sql/tests/school_duration_overage_clearance_aware_aggregate_local_20260818.sql"),
  ], { timeout: 60000 });
  const md5Match = output.match(/CLEARANCE_AWARE_OVERAGE_LOCAL_PASS passed_assertions=10 new_md5=([0-9a-f]{32})/);
  assert.ok(md5Match, "new function MD5 was not reported");
  assert.match(output, /CLEARANCE_AWARE_OVERAGE_LOCAL_EXACT_ROLLBACK_PASS/);
  console.log(`SCHOOL_DURATION_OVERAGE_CLEARANCE_AWARE_LOCAL_POSTGRES_PASS new_md5=${md5Match[1]}`);
} finally {
  if (started) spawnSync(pgCtl, ["-D", data, "-m", "immediate", "-w", "stop"], { stdio: "ignore" });
  rmSync(root, { recursive: true, force: true });
}
