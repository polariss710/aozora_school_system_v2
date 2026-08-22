import assert from "node:assert/strict";
import fs from "node:fs";
import {
  PART_TIME_WORK_COLLAPSE_POLICIES,
  assertPartTimeWorkCollapsePolicy,
  partTimeWorkCollapseStateFromFilters,
  preservePartTimeWorkCollapseState,
} from "../js/utils/part-time-work-filter-state.js";

const page = fs.readFileSync("js/pages/part-time-work-page.js", "utf8");
const workplaces = ["诺应教育", "致远教育", "新领域"];

const allCollapsed = {
  expandedLessonWorkplaces: [],
  collapsedWageWorkplaces: workplaces,
};
assert.deepEqual(partTimeWorkCollapseStateFromFilters({ workplaceName: "" }, workplaces), allCollapsed);
assert.deepEqual(partTimeWorkCollapseStateFromFilters({ workplaceName: "未知私塾" }, workplaces), allCollapsed);

for (const workplaceName of workplaces) {
  assert.deepEqual(
    partTimeWorkCollapseStateFromFilters({ workplaceName }, workplaces),
    {
      expandedLessonWorkplaces: [workplaceName],
      collapsedWageWorkplaces: workplaces.filter((option) => option !== workplaceName),
    },
  );
}

assert.deepEqual(
  partTimeWorkCollapseStateFromFilters({
    workplaceName: "诺应教育",
    classDescription: "骆德锋理数一对一",
  }, workplaces),
  {
    expandedLessonWorkplaces: ["诺应教育"],
    collapsedWageWorkplaces: ["致远教育", "新领域"],
  },
);

const resetHandler = page.match(/dom\.resetButton\.addEventListener\("click", \(\) => \{([\s\S]*?)\n  \}\);/)?.[1] || "";
const loadHandler = page.match(/async function loadPageData\(options\) \{([\s\S]*?)\n\}/)?.[1] || "";
const queryLoadHandler = page.match(/function loadPageDataForQuery\([^)]*\) \{([\s\S]*?)\n\}/)?.[1] || "";
const mutationRefreshHandler = page.match(/function refreshPageDataAfterMutation\(\) \{([\s\S]*?)\n\}/)?.[1] || "";
const collapseHandler = page.match(/function applyAppliedFilterCollapseState\([\s\S]*?\n\}/)?.[0] || "";
const clearHandler = page.match(/function clearQueryResults\(\) \{([\s\S]*?)\n\}/)?.[1] || "";
const submitHandler = page.match(/dom\.filterForm\.addEventListener\("submit", \(event\) => \{([\s\S]*?)\n  \}\);/)?.[1] || "";

assert.match(queryLoadHandler, /CANONICAL_FROM_FILTERS/);
assert.match(queryLoadHandler, /PRESERVE_CURRENT/);
assert.match(queryLoadHandler, /preserveCollapseState/);
assert.match(submitHandler, /loadPageDataForQuery\(\{ preserveCollapseState: true \}\)/);
assert.match(mutationRefreshHandler, /PRESERVE_CURRENT/);
assert.match(loadHandler, /assertPartTimeWorkCollapsePolicy\(collapsePolicy\)/);
assert.match(loadHandler, /collapsePolicy === PART_TIME_WORK_COLLAPSE_POLICIES\.CANONICAL_FROM_FILTERS/);
assert.match(loadHandler, /collapsePolicy === PART_TIME_WORK_COLLAPSE_POLICIES\.PRESERVE_CURRENT/);
assert.match(collapseHandler, /replaceSetContents\(expandedWorkplaces/);
assert.match(collapseHandler, /replaceSetContents\(collapsedWageWorkplaces/);
assert.doesNotMatch(page, /expandSelectedWorkplace/);
assert.match(resetHandler, /clearQueryResults\(\)/);
assert.doesNotMatch(resetHandler, /applyAppliedFilterCollapseState|expandedWorkplaces|collapsedWageWorkplaces|loadPageData|loadPageDataForQuery|refreshPageDataAfterMutation|renderVisibleLessons|renderWageCalculation/);
assert.doesNotMatch(clearHandler, /expandedWorkplaces|collapsedWageWorkplaces|renderedLessonWorkplaceKeys|renderedWageWorkplaceKeys/);
assert.match(resetHandler, /showMessage\("success", "已重置筛选条件；点击“查询”后刷新结果。"\)/);
assert.equal([...page.matchAll(/\bloadPageData\(/g)].length, 3, "raw loadPageData is limited to its definition and two semantic wrappers");

assert.equal(
  assertPartTimeWorkCollapsePolicy(PART_TIME_WORK_COLLAPSE_POLICIES.CANONICAL_FROM_FILTERS),
  "canonical_from_filters",
);
assert.equal(
  assertPartTimeWorkCollapsePolicy(PART_TIME_WORK_COLLAPSE_POLICIES.PRESERVE_CURRENT),
  "preserve_current",
);
assert.throws(() => assertPartTimeWorkCollapsePolicy(), /PTW_COLLAPSE_POLICY_INVALID:missing/);
assert.throws(() => assertPartTimeWorkCollapsePolicy("unknown"), /PTW_COLLAPSE_POLICY_INVALID:unknown/);

const preserved = preservePartTimeWorkCollapseState({
  previousLessonWorkplaceKeys: ["诺应教育", "致远教育"],
  previousWageWorkplaceKeys: ["诺应教育", "致远教育"],
  expandedLessonWorkplaces: ["诺应教育"],
  collapsedWageWorkplaces: ["致远教育"],
  nextLessonWorkplaceKeys: ["诺应教育", "新领域"],
  nextWageWorkplaceKeys: ["诺应教育", "新领域"],
});
assert.deepEqual(preserved, {
  expandedLessonWorkplaces: ["诺应教育"],
  collapsedWageWorkplaces: ["新领域"],
});

const independentlyPreserved = preservePartTimeWorkCollapseState({
  previousLessonWorkplaceKeys: workplaces,
  previousWageWorkplaceKeys: workplaces,
  expandedLessonWorkplaces: ["诺应教育"],
  collapsedWageWorkplaces: ["诺应教育", "新领域"],
  nextLessonWorkplaceKeys: workplaces,
  nextWageWorkplaceKeys: workplaces,
});
assert.deepEqual(independentlyPreserved.expandedLessonWorkplaces, ["诺应教育"]);
assert.deepEqual(independentlyPreserved.collapsedWageWorkplaces, ["诺应教育", "新领域"]);

console.log("PTW_P1_B1_FILTER_COLLAPSE_STATE_TEST_PASS");
