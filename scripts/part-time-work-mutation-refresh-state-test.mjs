import assert from "node:assert/strict";
import fs from "node:fs";
import { preservePartTimeWorkCollapseState } from "../js/utils/part-time-work-filter-state.js";

const page = fs.readFileSync("js/pages/part-time-work-page.js", "utf8");
const api = fs.readFileSync("js/api/part-time-work-api.js", "utf8");
const workplaces = ["诺应教育", "致远教育", "新领域"];
const refreshFailureMessage = "保存已成功，但页面刷新失败。请重新查询确认，不要重复提交。";

function cloneState(state) {
  return {
    ...state,
    appliedFilters: { ...state.appliedFilters },
    expandedLessonWorkplaces: [...state.expandedLessonWorkplaces],
    collapsedWageWorkplaces: [...state.collapsedWageWorkplaces],
    lessonWorkplaceKeys: [...state.lessonWorkplaceKeys],
    wageWorkplaceKeys: [...state.wageWorkplaceKeys],
    lessons: [...state.lessons],
  };
}

async function submitMutationAndRefresh({ state, writer, readers }) {
  const before = cloneState(state);
  await writer();
  try {
    const [lessons] = await Promise.all(readers.map((reader) => reader()));
    const collapseState = preservePartTimeWorkCollapseState({
      previousLessonWorkplaceKeys: before.lessonWorkplaceKeys,
      previousWageWorkplaceKeys: before.wageWorkplaceKeys,
      expandedLessonWorkplaces: before.expandedLessonWorkplaces,
      collapsedWageWorkplaces: before.collapsedWageWorkplaces,
      nextLessonWorkplaceKeys: workplaces,
      nextWageWorkplaceKeys: workplaces,
    });
    return {
      ...before,
      ...collapseState,
      lessonWorkplaceKeys: workplaces,
      wageWorkplaceKeys: workplaces,
      lessons,
      message: "",
    };
  } catch {
    return { ...before, message: refreshFailureMessage };
  }
}

const initialState = {
  url: "https://school.example/part-time-work.html?view=lessons&year=2026&month=08",
  view: "lessons",
  appliedFilters: { yearMonth: "2026-08", workplaceName: "", classDescription: "" },
  expandedLessonWorkplaces: ["诺应教育"],
  collapsedWageWorkplaces: ["致远教育", "新领域"],
  lessonWorkplaceKeys: workplaces,
  wageWorkplaceKeys: workplaces,
  lessons: [{ id: "planned-1", record_kind: "planned", workplace_name: "诺应教育" }],
};

let writerCalls = 0;
let readerCalls = 0;
const success = await submitMutationAndRefresh({
  state: initialState,
  writer: async () => { writerCalls += 1; },
  readers: [
    async () => {
      readerCalls += 1;
      return [
        initialState.lessons[0],
        { id: "actual-1", record_kind: "actual", planned_lesson_id: "planned-1", workplace_name: "诺应教育" },
      ];
    },
    async () => { readerCalls += 1; return []; },
    async () => { readerCalls += 1; return []; },
  ],
});
assert.equal(writerCalls, 1);
assert.equal(readerCalls, 3);
assert.deepEqual(success.expandedLessonWorkplaces, ["诺应教育"]);
assert.deepEqual(success.collapsedWageWorkplaces, ["致远教育", "新领域"]);
assert.ok(success.lessons.some((lesson) => lesson.id === "actual-1"), "new actual is visible in refreshed data");
assert.equal(success.url, initialState.url);
assert.equal(success.view, initialState.view);
assert.deepEqual(success.appliedFilters, initialState.appliedFilters);

writerCalls = 0;
readerCalls = 0;
const readerFailure = await submitMutationAndRefresh({
  state: initialState,
  writer: async () => { writerCalls += 1; },
  readers: [
    async () => { readerCalls += 1; throw new Error("reader failed"); },
    async () => { readerCalls += 1; return []; },
    async () => { readerCalls += 1; return []; },
  ],
});
assert.equal(writerCalls, 1);
assert.equal(readerCalls, 3);
assert.equal(readerFailure.message, refreshFailureMessage);
assert.deepEqual(readerFailure.expandedLessonWorkplaces, initialState.expandedLessonWorkplaces);
assert.deepEqual(readerFailure.collapsedWageWorkplaces, initialState.collapsedWageWorkplaces);
assert.deepEqual(readerFailure.lessons, initialState.lessons);

writerCalls = 0;
readerCalls = 0;
await assert.rejects(
  () => submitMutationAndRefresh({
    state: initialState,
    writer: async () => { writerCalls += 1; throw new Error("writer failed"); },
    readers: [async () => { readerCalls += 1; return []; }],
  }),
  /writer failed/,
);
assert.equal(writerCalls, 1);
assert.equal(readerCalls, 0);

const submitDialog = page.match(/async function submitDialog\(\) \{([\s\S]*?)\n\}/)?.[1] || "";
const deleteHandler = page.match(/async function handleLessonActionClick\(event\) \{([\s\S]*?)\n\}/)?.[1] || "";
const settlementHandler = page.match(/async function handleSettlementActionClick\(event\) \{([\s\S]*?)\n\}/)?.[1] || "";
const incomeHandler = page.match(/async function submitIncomeGenerationConfirmDialog\(\) \{([\s\S]*?)\n\}/)?.[1] || "";
for (const handler of [submitDialog, deleteHandler, settlementHandler, incomeHandler]) {
  assert.match(handler, /refreshPageDataAfterMutation\(\)/);
  assert.doesNotMatch(handler, /loadPageDataForQuery\(\)|\bloadPageData\(/);
}

assert.equal([...page.matchAll(/await refreshPageDataAfterMutation\(\)/g)].length, 4);
assert.equal([...page.matchAll(/\bloadPageData\(/g)].length, 3);
assert.match(page, new RegExp(refreshFailureMessage.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")));
assert.doesNotMatch(api, /collapsePolicy|expandedWorkplaces|collapsedWageWorkplaces/);
assert.doesNotMatch(page, /\.rpc\s*\(/);
assert.doesNotMatch(page, /\.from\s*\([^)]*\)\s*\.\s*(?:insert|update|delete|upsert)\s*\(/);

console.log("PTW_MUTATION_REFRESH_STATE_TEST_PASS");
