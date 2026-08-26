import assert from "node:assert/strict";

import {
  ADJUSTMENT_DRAFT_ID,
  AUTHORITATIVE_CARRY,
  BUSINESS_ENTITY_ID,
  CORRELATION_ID,
  PREVIEW_RPC,
  STATUS_RPC,
  STUDENT_ID,
  YEAR_MONTH,
  containsDeep,
  previewRow,
  settlementApi,
  statusRow,
  stub,
} from "./lib/settlement-lock-authority.mjs";

// P0 金额边界：DB 权威事实 → 页面层 input → API 层最终提交给 Edge 的 body。
//
// 设计依据：docs/school-v2-settlement-phase-d-lock-ui-design-20260825.md 第 6.1 节。
//
// 本文件的链路起点是 RPC 返回值，不是手写的快照对象。这一点是 2026-08-26 的
// 改动带来的：权威快照的登记入口已收进 js/api/settlement-api.js 的模块作用域，
// 常规执行环境下没有导出路径能自行登记一个对象。想要拿到 builder 认可的快照，
// 只能经 fetchAuthoritativeLockFacts 真实走一遍 API 层。
//
// 但要清楚本文件证明的范围：它走的是「权威快照 → builder → writer」这条正常
// 路径。2026-08-26 审查指出，调用方完全可以不走 builder——直接把改过的对象交给
// 公开的 lockStudentSettlementOnline，脏值照样进 body。本文件的 T1-T7 全绿并
// 不意味着 P0 已闭合。
//
// 早先的版本在这里用页面层导出的 freezeAuthoritativeSnapshot 直接造 fixture，
// 于是「快照来自 DB」这件事本身从未被测试触及——测试和被绕过的攻击路径用的是
// 同一个公开登记入口。
//
// 加载方式：js/supabase-client.js 从 https://esm.sh 远程导入 createClient，
// node 默认加载器不支持 https:，因此用模块解析钩子把它映射到本地捕获桩。
// 除该远程依赖外，链路上的代码全部是生产实现，没有替身。

const { lockStudentSettlementOnline } = await import(
  "../js/api/student-settlement-online-api.js"
);
const { buildOnlineDraftLockInput, lockConfirmationAccepted } =
  await import("../js/pages/settlement-online-state.js");

const { invocations, setRpcResponse, lastRpcArgs, resetCapture } = stub;
const { fetchAuthoritativeLockFacts } = settlementApi;

const TYPED_EQUIVALENT = "40000.000";

// ---------------------------------------------------------------------------
// 取权威事实：经真实 API 层，快照在那一层被深拷贝、递归冻结并登记
// ---------------------------------------------------------------------------
resetCapture();
setRpcResponse(STATUS_RPC, statusRow());
setRpcResponse(PREVIEW_RPC, previewRow());

const { status, preview } = await fetchAuthoritativeLockFacts(STUDENT_ID, YEAR_MONTH);

// ---------------------------------------------------------------------------
// 走完整链路：闸门放行 → 构造 input → 真实 API → 捕获提交体
//
// 用「等值但字符串不同」这一组：40000.000 与 40000.00 经 canonicalDecimal 判等，
// 闸门会放行，因此能真正走到提交。若两串完全相同，误用 DOM 值在结果上无法辨识，
// 这一组是最合适的可辨识场景（其他尾零形式等价）。
// ---------------------------------------------------------------------------
assert.equal(
  lockConfirmationAccepted(TYPED_EQUIVALENT, AUTHORITATIVE_CARRY), true,
  "等值不同串未被闸门放行，本测试将无法走到提交",
);

const lockInput = buildOnlineDraftLockInput({
  row: { student_id: STUDENT_ID, year_month: YEAR_MONTH },
  status,
  previewResult: preview,
  membershipRole: "admin",
  note: "月结锁定备注",
  clientCorrelationId: CORRELATION_ID,
});

invocations.length = 0;
await lockStudentSettlementOnline(lockInput);

// ---------------------------------------------------------------------------
// T1  确实调用了锁定 Edge，且只调用一次
// ---------------------------------------------------------------------------
assert.equal(invocations.length, 1, `期望一次 Edge 调用，实际 ${invocations.length} 次`);
assert.equal(
  invocations[0].functionName, "lock-student-settlement",
  "调用了错误的 Edge 函数",
);

const body = invocations[0].body;
assert.ok(body && typeof body === "object", "提交体不是对象");

// ---------------------------------------------------------------------------
// T2  最终提交的结转金额是 DB 原值，且用户输入的字符串不在 body 的任何层级
// ---------------------------------------------------------------------------
assert.equal(
  body.expected_final_carryover_cny, AUTHORITATIVE_CARRY,
  "提交给 Edge 的结转金额不是 DB 原值",
);
assert.equal(
  containsDeep(body, TYPED_EQUIVALENT), false,
  `提交体中出现了用户输入的字符串 ${TYPED_EQUIVALENT}`,
);

// ---------------------------------------------------------------------------
// T3  body 的键集与 Edge 契约完全一致，不多不少
//
//     这一层是 snake_case，与页面层的 camelCase 是两套键名；页面层的
//     exact-key 断言证明不了这里。
// ---------------------------------------------------------------------------
{
  const expectedKeys = [
    "student_id", "settlement_month",
    "expected_source_treatment_draft_id", "expected_source_treatment_draft_updated_at",
    "expected_adjustment_draft_id", "expected_adjustment_draft_updated_at",
    "expected_preview_manifest_sha256", "expected_lesson_variance_manifest_sha256",
    "expected_source_count",
    "expected_unused_planned_credit_jpy", "expected_overage_charge_jpy",
    "expected_net_lesson_variance_jpy", "expected_net_lesson_variance_cny",
    "expected_system_difference_cny", "expected_final_carryover_cny",
    "note", "confirm_lock", "client_correlation_id",
  ].sort();
  assert.deepEqual(Object.keys(body).sort(), expectedKeys, "提交体键集与契约不符");
}

// ---------------------------------------------------------------------------
// T4  确认相关字段一律不得出现在提交体中
//
//     canonical_confirmation 由 DB 内部生成、浏览器不得提交；确认输入本身
//     更不该出现。
// ---------------------------------------------------------------------------
for (const forbidden of [
  "canonical_confirmation", "canonicalConfirmation",
  "confirmation_amount", "confirmationAmount", "typed_carryover",
]) {
  assert.ok(!(forbidden in body), `提交体不应包含 ${forbidden}`);
}

// ---------------------------------------------------------------------------
// T5  confirm_lock 必须为 true —— API 层对此有硬校验，漏传会直接抛错
// ---------------------------------------------------------------------------
assert.equal(body.confirm_lock, true, "confirm_lock 未置为 true");

// ---------------------------------------------------------------------------
// T6  自行构造的对象进不了 builder —— 无论它是否处于冻结状态
//
//     这里替换的是一个空转的旧断言：它清空调用记录、调一次纯函数、再断言记录
//     仍为空，中间没有任何东西会产生调用，因而必然通过。
//
//     现在测的是真问题：调用方能不能绕过 API 层，自己弄出一个 builder 认可的
//     快照。三种形态——普通对象、Object.freeze 的对象、以及从权威快照
//     structuredClone 出来的副本——都必须被拒绝。第三种尤其重要：它的内容与
//     权威快照完全一致，只是丢了登记。
// ---------------------------------------------------------------------------
{
  const poisoned = { ...previewRow(TYPED_EQUIVALENT) };
  const attempts = [
    ["普通对象", poisoned],
    ["手工 Object.freeze", Object.freeze({ ...poisoned })],
    ["权威快照的 structuredClone 副本", structuredClone(preview)],
  ];
  for (const [label, candidate] of attempts) {
    assert.throws(
      () => buildOnlineDraftLockInput({
        row: { student_id: STUDENT_ID, year_month: YEAR_MONTH },
        status,
        previewResult: candidate,
        membershipRole: "admin",
        note: "",
        clientCorrelationId: CORRELATION_ID,
      }),
      /authoritative snapshot/,
      `${label} 未被 builder 拒绝`,
    );
  }
}

// ---------------------------------------------------------------------------
// T7  锁定预览的 RPC 取参全部来自 status 草稿
//
//     这一条盯的是 A' 之前真实存在的绕法：锁定预览曾经过
//     fetchStudentSettlementAdjustmentDialogPreview，那个入口的 payload 带
//     explicitUserAmountCny，直通 p_explicit_user_amount_cny。调整对话框正是
//     拿 DOM 值走这条路，因此只要取参留在页面层，DOM 值就能经一次 DB 往返影响
//     projected_final_carryover_cny。
//
//     现在取参在 API 层完成，入口只收 scope。用 manual_adjustment 这一组来验：
//     金额必须等于 status 草稿里的值，而调用方没有任何参数可以改变它。
// ---------------------------------------------------------------------------
{
  const DRAFT_AMOUNT = "123.45";
  const INTRUDER_AMOUNT = "999999.99";
  resetCapture();
  setRpcResponse(STATUS_RPC, statusRow({
    adjustment_draft: {
      draft_id: ADJUSTMENT_DRAFT_ID,
      status: "active",
      updated_at: "2026-09-07T01:00:00Z",
      adjustment_mode: "manual_adjustment",
      adjustment_amount_cny: DRAFT_AMOUNT,
    },
  }));
  setRpcResponse(PREVIEW_RPC, previewRow());

  // 多传的实参是入口签名之外的，进不了函数体
  await fetchAuthoritativeLockFacts(
    STUDENT_ID, YEAR_MONTH,
    { explicitUserAmountCny: INTRUDER_AMOUNT },
    INTRUDER_AMOUNT,
  );

  const args = lastRpcArgs(PREVIEW_RPC);
  assert.ok(args, "未调用锁定预览 RPC");
  assert.equal(
    args.p_explicit_user_amount_cny, DRAFT_AMOUNT,
    "锁定预览的金额取参不是 status 草稿里的值",
  );
  assert.equal(
    containsDeep(args, INTRUDER_AMOUNT), false,
    `多传的实参出现在了预览 RPC 入参中：${INTRUDER_AMOUNT}`,
  );
  assert.equal(
    args.p_business_entity_id, BUSINESS_ENTITY_ID,
    "business_entity_id 未取自 status",
  );
  // 入口的形参只有 scope 两个。多一个形参就多一条调用方能操纵的通道。
  assert.equal(
    fetchAuthoritativeLockFacts.length, 2,
    `权威读取入口的形参必须只有 scope 两个，实际 ${fetchAuthoritativeLockFacts.length} 个`,
  );
}

console.log("settlement lock edge body: T1-T7 全部通过");

// ===========================================================================
// 本文件未覆盖的部分，如实记录
// ===========================================================================
//
// DOM → handler 这一段仍未端到端驱动：本文件从 fetchAuthoritativeLockFacts
// 起步，没有渲染对话框、没有触发 click。handleLockSubmit 是 settlement-page.js
// 的模块私有函数，要驱动它必须先 initSettlementPage 并备齐整套 DOM，而本项目
// 无 package.json、不引入 jsdom，那需要自建相当规模的 DOM 桩。
//
// 需要说清楚的是这段现在的风险性质已经变了。Codex 在 2026-08-25 指出的具体
// 绕法是「用 DOM 值构造 preview → 调用公开的 freezeAuthoritativeSnapshot 登记
// → 传给 builder」，它依赖一个页面可达的登记入口；该入口已收进 API 层模块
// 作用域，这条路不再存在（T6 覆盖了「自造对象一律被拒」这一面）。
//
// 剩下的是覆盖率问题而非那条绕法：没有测试证明 handleLockSubmit 确实把闸门
// 结果当作提交前提。这一条目前仍只有静态断言看着
// （见 settlement-lock-amount-boundary-test 场景 5），若将来引入 DOM 测试
// 基础设施，应补上真正的端到端驱动。
