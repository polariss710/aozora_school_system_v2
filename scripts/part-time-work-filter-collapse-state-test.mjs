import assert from "node:assert/strict";
import fs from "node:fs";
import { partTimeWorkCollapseStateFromFilters } from "../js/utils/part-time-work-filter-state.js";

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
const loadHandler = page.match(/async function loadPageData\(options = \{\}\) \{([\s\S]*?)\n\}/)?.[1] || "";
const collapseHandler = page.match(/function applyAppliedFilterCollapseState\([\s\S]*?\n\}/)?.[0] || "";

assert.match(loadHandler, /applyAppliedFilterCollapseState\(filters\)/);
assert.match(collapseHandler, /expandedWorkplaces\.clear\(\)/);
assert.match(collapseHandler, /collapsedWageWorkplaces\.clear\(\)/);
assert.match(collapseHandler, /expandedLessonWorkplaces/);
assert.match(collapseHandler, /collapsedWageWorkplaces/);
assert.doesNotMatch(page, /expandSelectedWorkplace/);
assert.doesNotMatch(resetHandler, /applyAppliedFilterCollapseState|expandedWorkplaces|collapsedWageWorkplaces|loadPageData|renderVisibleLessons|renderWageCalculation/);
assert.match(resetHandler, /showMessage\("success", "已重置筛选条件"\)/);

// Manual expansion is intentionally transient: the next applied-filter load rebuilds both regions.
let lessonExpanded = new Set(["致远教育"]);
let wageCollapsed = new Set(["诺应教育", "新领域"]);
const nextState = partTimeWorkCollapseStateFromFilters({ workplaceName: "" }, workplaces);
lessonExpanded = new Set(nextState.expandedLessonWorkplaces);
wageCollapsed = new Set(nextState.collapsedWageWorkplaces);
assert.deepEqual([...lessonExpanded], []);
assert.deepEqual([...wageCollapsed], workplaces);

console.log("PTW_P1_B1_FILTER_COLLAPSE_STATE_TEST_PASS");
