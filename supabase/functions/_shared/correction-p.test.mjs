import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import {
  assertHomePrepared,
  assertSchoolEvidence,
  assertSourceMatchesTarget,
  buildHomeCompleteArgs,
  buildHomePrepareArgs,
  buildSchoolFinalizeArgs,
  callCorrectionRpc,
  correctionPClientError,
  CorrectionPError,
  recoverWriterWithStatus,
  rpcTransportError,
  requireCorrectionTarget,
} from "./correction-p.js";

const target = requireCorrectionTarget({
  operation_id: "c0de0000-0000-4000-8000-000000000001",
  original_home_request_id: "ea5a7ce2-1b7a-44f3-8db7-22bb73c963bc",
  original_home_transaction_id: "01e910b8-bf54-486c-a13a-597ca9dbf684",
  school_expense_id: "ed23a346-2ba5-47fb-a496-4c4ba781ec86",
  school_attempt_id: "b6c8a4ca-0a27-4e4c-aae3-7498d0c18cd5",
});
const actor = "25331ae9-3412-48b9-bdc3-e516caeaeba4";
const source = {
  ok: true,school_expense_id: target.school_expense_id,
  school_attempt_id: target.school_attempt_id,
  original_home_request_id: target.original_home_request_id,
  original_home_transaction_id: target.original_home_transaction_id,
  school_event_id: "fa3aad38-5886-4154-a7d4-8c8331fb71fe",
  school_idempotency_key: "attempt:1",
  school_fingerprint: "a".repeat(64),
  amount: 202991,
  currency: "JPY",
  charge_date: "2026-08-13",
  actor_id: actor,
  expense_snapshot: { id: target.school_expense_id },
  attempt_snapshot: { id: target.school_attempt_id },
};
assertSourceMatchesTarget(source, target);
const prepare = buildHomePrepareArgs(source,target,actor);
assert.deepEqual(Object.keys(prepare).sort(),[
  "p_actor_id","p_operation_id","p_original_home_request_id",
  "p_original_home_transaction_id","p_school_attempt_id",
  "p_school_expense_id","p_school_fingerprint",
].sort());
for (const field of Object.keys(target)) {
  const invalid={...target};
  delete invalid[field];
  assert.throws(() => requireCorrectionTarget(invalid),(error) =>
    error instanceof CorrectionPError && error.code === "CORRECTION_P_INVALID_TARGET");
}
assert.throws(() => requireCorrectionTarget({...target,operation_id:"not-a-uuid"}),(error) =>
  error instanceof CorrectionPError && error.code === "CORRECTION_P_INVALID_TARGET");
for (const field of [
  "amount","currency","date","account_id","accounting_scope","external_event_id",
  "external_reference_id","idempotency_key","card_instrument_id","payment_channel_id",
  "payment_group","fixed_month","due_date","actor_id","school_fingerprint",
]) {
  const invalid={...target,[field]: actor};
  assert.throws(() => requireCorrectionTarget(invalid),(error) =>
    error instanceof CorrectionPError && error.code === "CORRECTION_P_INVALID_TARGET");
}

const home = {
  ok: true,status: "prepared",...target,
  correction_id: "c0de0000-0000-4000-8000-000000000101",
  balance_effect_id: "c0de0000-0000-4000-8000-000000000102",
  replacement_request_id: "c0de0000-0000-4000-8000-000000000103",
  replacement_fixed_item_id: "c0de0000-0000-4000-8000-000000000104",
  replacement_projection_id: "c0de0000-0000-4000-8000-000000000105",
  amount: 202991,currency: "JPY",original_effective_date: "2026-08-13",
  accounting_scope: "school",external_event_id: source.school_event_id,
  original_idempotency_key: source.school_idempotency_key,
  school_fingerprint: "a".repeat(64),home_payload_hash: "b".repeat(32),
  replacement_fingerprint: "c".repeat(64),
  actor_id: actor,
};
assertHomePrepared(home,target);
assert.throws(() => assertHomePrepared({...home,school_expense_id:"c0de0000-0000-4000-8000-000000000099"},target),
  (error) => error instanceof CorrectionPError && error.code === "CORRECTION_P_INTERNAL_ERROR");
const finalize = buildSchoolFinalizeArgs(home,actor);
assert.deepEqual(finalize.p_home_prepared_snapshot,home);

const evidence = {
  ok: true,operation_id: target.operation_id,home_correction_id: home.correction_id,
  school_expense_id: target.school_expense_id,school_attempt_id: target.school_attempt_id,
  actor_id: actor,school_evidence_id: "c0de0000-0000-4000-8000-000000000201",
  school_finalized_at: "2026-08-22T00:00:00.000000Z",
  school_evidence_fingerprint: "d".repeat(64),
};
assertSchoolEvidence(evidence,home,actor);
assert.throws(() => assertSchoolEvidence({...evidence,operation_id:"c0de0000-0000-4000-8000-000000000099"},home,actor),
  (error) => error instanceof CorrectionPError && error.code === "CORRECTION_P_INTERNAL_ERROR");
assert.equal(buildHomeCompleteArgs(home,evidence,actor).p_school_evidence_snapshot,evidence);

const envelopes=[];
const clientFor=(data,error=null) => ({
  rpc: async (name,args) => {
    envelopes.push({name,args});
    return {data,error};
  },
});
const sourceCall={
  name:"school_get_expense_cash_correction_source_v1",
  args:{p_school_expense_id:target.school_expense_id,p_school_attempt_id:target.school_attempt_id,p_actor_id:actor},
};
const homeStatusCall={name:"home_get_external_transaction_correction_p",args:{p_operation_id:target.operation_id}};
const homePrepareCall={name:"home_prepare_external_transaction_correction_p",args:prepare};
const schoolStatusCall={name:"school_get_expense_cash_correction_p",args:{p_operation_id:target.operation_id}};
const schoolFinalizeCall={name:"school_finalize_expense_cash_correction_p",args:finalize};
const homeCompleteCall={name:"home_complete_external_transaction_correction_p",args:buildHomeCompleteArgs(home,evidence,actor)};
for (const [call,data] of [
  [sourceCall,source],[homeStatusCall,home],[homePrepareCall,home],
  [schoolStatusCall,evidence],[schoolFinalizeCall,evidence],
  [homeCompleteCall,{...home,status:"completed"}],
]) {
  const result=await callCorrectionRpc(clientFor(data),call);
  assert.equal(result.ok,true);
}
assert.deepEqual(envelopes.map(({name})=>name),[
  "school_get_expense_cash_correction_source_v1",
  "home_get_external_transaction_correction_p",
  "home_prepare_external_transaction_correction_p",
  "school_get_expense_cash_correction_p",
  "school_finalize_expense_cash_correction_p",
  "home_complete_external_transaction_correction_p",
]);
assert.deepEqual(Object.keys(envelopes[0].args).sort(),Object.keys(sourceCall.args).sort());
assert.deepEqual(Object.keys(envelopes[2].args).sort(),Object.keys(prepare).sort());
assert.deepEqual(Object.keys(envelopes[4].args).sort(),Object.keys(finalize).sort());
assert.deepEqual(Object.keys(envelopes[5].args).sort(),Object.keys(homeCompleteCall.args).sort());

const internalFailure=(category) => (error) =>
  error instanceof CorrectionPError && error.code === "CORRECTION_P_INTERNAL_ERROR" &&
  (!category || error.internalCategory === category);
await assert.rejects(callCorrectionRpc({},homeStatusCall),internalFailure("RPC_CLIENT_CONTRACT"));
await assert.rejects(callCorrectionRpc({rpc:async()=>{throw new Error("network secret")}},homeStatusCall),
  internalFailure("RPC_TRANSPORT"));
await assert.rejects(callCorrectionRpc(clientFor(null),homeStatusCall),internalFailure("RPC_MALFORMED_RESULT"));
for (const raw of [[],"bad",7,{}, {ok:"true"}, {ok:true}, {...home,status:"unknown"}]) {
  await assert.rejects(callCorrectionRpc(clientFor(raw),homeStatusCall),internalFailure());
}
await assert.rejects(callCorrectionRpc(clientFor({...home,operation_id:"c0de0000-0000-4000-8000-000000000099"}),homeStatusCall),
  internalFailure("RPC_OPERATION_IDENTITY"));
await assert.rejects(callCorrectionRpc(clientFor({...home,details:"secret table"}),homeStatusCall),
  internalFailure("RPC_RESULT_EXTRA_FIELD"));
await assert.rejects(callCorrectionRpc(clientFor(home,{message:"raw sql",details:"secret",hint:"constraint"}),homeStatusCall),
  internalFailure("RPC_TRANSPORT"));
await assert.rejects(callCorrectionRpc(clientFor(home),{name:"unknown_rpc",args:{}}),
  internalFailure("RPC_NAME_CONTRACT"));
await assert.rejects(callCorrectionRpc(clientFor(home),{...homeStatusCall,args:{p_operation_id:target.operation_id,extra:actor}}),
  internalFailure("RPC_ARGS_CONTRACT"));
const knownFailure=await callCorrectionRpc(clientFor({ok:false,
  code:"HOME_CORRECTION_ROUTE_POLICY_NOT_CONFIGURED",message:"not configured"}),homeStatusCall);
assert.equal(knownFailure.code,"HOME_CORRECTION_ROUTE_POLICY_NOT_CONFIGURED");
assert.deepEqual(Object.keys(knownFailure).sort(),["code","message","ok"]);

for (const raw of [
  null,[],"bad",7,{}, {ok:"true"}, {ok:true},
  {ok:false,code:"X"}, {ok:false,message:"raw"},
]) {
  const response=correctionPClientError(await callCorrectionRpc(clientFor(raw),homeStatusCall)
    .then(()=>new Error("unexpected success"),error=>error));
  assert.equal(response.body.code,"CORRECTION_P_INTERNAL_ERROR");
  assert.doesNotMatch(JSON.stringify(response.body),/raw|secret|constraint|sql/i);
}

let reads=0;
const recoveredPrepare = await recoverWriterWithStatus(
  async () => { throw new Error("HOME_PREPARE_RESPONSE_LOST"); },
  async () => { reads++; return home; },
  "CORRECTION_P_HOME_PREPARE_RECOVERABLE",
);
assert.equal(recoveredPrepare.correction_id,home.correction_id);
assert.equal(reads,1);
const recoveredSchool = await recoverWriterWithStatus(
  async () => { throw new Error("SCHOOL_FINALIZE_RESPONSE_LOST"); },
  async () => evidence,
  "CORRECTION_P_SCHOOL_FINALIZE_RECOVERABLE",
);
assert.equal(recoveredSchool.school_evidence_id,evidence.school_evidence_id);
const completed = { ...home,status: "completed",school_evidence_id: evidence.school_evidence_id };
const recoveredComplete = await recoverWriterWithStatus(
  async () => { throw new Error("HOME_COMPLETE_RESPONSE_LOST"); },
  async () => completed,
  "CORRECTION_P_HOME_COMPLETE_RECOVERABLE",
);
assert.equal(recoveredComplete.status,"completed");
await assert.rejects(
  recoverWriterWithStatus(
    async () => { throw new Error("WRITER_FAILED"); },
    async () => ({ ok: false,code: "NOT_FOUND" }),
  ),
  (error) => error instanceof CorrectionPError &&
    error.code === "CORRECTION_P_INTERNAL_ERROR",
);
await assert.rejects(
  recoverWriterWithStatus(
    async () => ({ok:false,code:"HOME_CORRECTION_ROUTE_POLICY_NOT_CONFIGURED"}),
    async () => ({ok:false,code:"HOME_CORRECTION_NOT_FOUND"}),
    "CORRECTION_P_HOME_PREPARE_RECOVERABLE",
  ),
  (error) => error instanceof CorrectionPError &&
    error.code === "HOME_CORRECTION_ROUTE_POLICY_NOT_CONFIGURED",
);
await assert.rejects(
  recoverWriterWithStatus(
    async () => ({ok:false,code:"SCHOOL_CORRECTION_P_TERMINAL_CONFLICT"}),
    async () => ({ok:false,code:"SCHOOL_CORRECTION_P_NOT_FOUND"}),
    "CORRECTION_P_SCHOOL_FINALIZE_RECOVERABLE",
  ),
  (error) => error instanceof CorrectionPError &&
    error.code === "SCHOOL_CORRECTION_P_TERMINAL_CONFLICT",
);

for (const raw of [
  new Error('duplicate key violates constraint "secret_constraint"'),
  new Error("select * from public.secret_table"),
  { message: "network ECONNRESET public.school_expense_records" },
  rpcTransportError(),
]) {
  const response = correctionPClientError(raw);
  const serialized = JSON.stringify(response.body);
  assert.equal(response.body.code,"CORRECTION_P_INTERNAL_ERROR");
  assert.doesNotMatch(serialized,/secret_constraint|select \*|secret_table|ECONNRESET|school_expense_records/i);
}
const malformed = correctionPClientError(new CorrectionPError("NOT_A_PUBLIC_CODE","RPC_MALFORMED_RESULT"));
assert.equal(malformed.body.code,"CORRECTION_P_INTERNAL_ERROR");
const invalidJson = correctionPClientError(new CorrectionPError("CORRECTION_P_INVALID_JSON"));
assert.deepEqual(invalidJson,{status:400,body:{ok:false,code:"CORRECTION_P_INVALID_JSON",message:"请求JSON无效。"}});
for (const code of ["METHOD_NOT_ALLOWED","SCHOOL_AUTH_REQUIRED","SCHOOL_AUTH_INVALID","P0G1_ACTIVE_ADMIN_REQUIRED"]) {
  const response=correctionPClientError(new CorrectionPError(code));
  assert.equal(response.body.code,code);
  assert.equal(typeof response.body.message,"string");
}

const edgeSource=await readFile(new URL("../correct-cash-expense-route/index.ts",import.meta.url),"utf8");
for (const required of [
  'get("authorization")','school.auth.getUser(bearer)',
  'scopedSchool.rpc("school_require_current_app_admin")','const actorId = userData.user.id',
]) assert.match(edgeSource,new RegExp(required.replace(/[.*+?^${}()|[\]\\]/g,"\\$&")));
assert.ok(edgeSource.indexOf('school.auth.getUser(bearer)') < edgeSource.indexOf('requireCorrectionTarget(body)'));
assert.ok(edgeSource.indexOf('requireCorrectionTarget(body)') < edgeSource.indexOf('school_get_expense_cash_correction_source_v1'));
assert.ok(edgeSource.indexOf('home_prepare_external_transaction_correction_p') < edgeSource.indexOf('school_finalize_expense_cash_correction_p'));
assert.ok(edgeSource.indexOf('school_finalize_expense_cash_correction_p') < edgeSource.indexOf('home_complete_external_transaction_correction_p'));
assert.doesNotMatch(edgeSource,/error\.(message|details|hint)|console\.(log|error)\([^\n]*(userError|adminError)/);

console.log("Correction-P coordinator mapper/RPC/recovery contract: PASS");
