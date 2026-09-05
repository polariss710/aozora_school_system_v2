// 公开仓库里不得存在个人数据表格文件。
//
// ---------------------------------------------------------------------------
// 为什么要这个检查
// ---------------------------------------------------------------------------
//
// 这个仓库是 PUBLIC 的。学生／老师名册被误提交进来，**已经发生过两次**：
//
//   2026-09-01  13 份材料（含一个学费候选 CSV，449 个 UUID）从公开历史清除。
//               那轮之后 .gitignore 加了 docs/*.csv、*.xls、*.xlsx。
//   2026-09-05  又发现 9 个 **.tsv**（约 641 行）**就在当前 HEAD 里**——
//               不是历史残留，是打开 GitHub 的 docs/ 直接就能看到。
//               含 student_name / student_id / teacher_name / teacher_id /
//               科目 / 上课日期时间 / 学费 / 汇率 / 账单与收入 ID 及状态。
//
// **第二次的直接原因是第一次的补救按扩展名做的。** 加了 csv/xls/xlsx，
// 换成 tsv 就穿过去了。而且其中一个文件在 sql/current/ 下，
// 只盯 docs/ 也会漏。
//
// 所以这个检查**不看扩展名、也不看目录**，只看内容特征：
//
//   首行像分隔符表头（≥3 个字段），且其中有姓名类列 → 判为个人数据表格
//
// 换成 .dat、.txt、.out 或者放到任何目录下，同样拦得住。
//
// ---------------------------------------------------------------------------
// 它拦不住什么（诚实记下，别高估）
// ---------------------------------------------------------------------------
//
//   - 姓名散落在散文里（比如分析文档正文提到某个学生）。业务负责人 2026-09-05
//     明确接受这类残留——70 个 .md 有此情况，全清等于删掉大半技术文档。
//   - 没有表头的裸数据行。
//   - 列名换成 name / 姓名 / 学生 之外的叫法。下面的关键词表尽量列全，
//     但它本质上仍是枚举，**新增导出格式时要回来看一眼**。
//
// 它能拦住的是那个真实发生过两次的形态：**带表头的表格导出**。

import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFileSync, statSync } from "node:fs";

let assertionCount = 0;
function check(condition, message) {
  assert.ok(condition, message);
  assertionCount += 1;
}

// 姓名类列。命中任意一个即视为含个人身份。
const NAME_COLUMNS = [
  "student_name",
  "teacher_name",
  "payee_name",
  "payee_name_snapshot",
  "student", // 有一个历史文件的列就叫 student
  "姓名",
  "学生",
  "老师",
  "教师",
];

// psql / 电子表格常见的分隔符。含 | 是因为 psql 默认输出就用它。
const DELIMITERS = ["\t", ",", ";", "|"];

function looksLikeMarkdownTable(lines) {
  // markdown 表格第二行是 |---|---| 这种分隔行。
  // 技术文档里正当地用表格列出字段名，不该被判成数据文件。
  const second = (lines[1] || "").trim();
  return /^\|?[\s:|-]+\|[\s:|-]*$/.test(second) && second.includes("-");
}

function detectHeader(text) {
  const lines = text.split("\n");
  const first = lines[0] || "";
  if (!first.trim()) return null;
  if (looksLikeMarkdownTable(lines)) return null;

  for (const delim of DELIMITERS) {
    const fields = first.split(delim).map((f) => f.trim().toLowerCase());
    if (fields.length < 3) continue;
    const hit = NAME_COLUMNS.find((col) => fields.includes(col.toLowerCase()));
    if (hit) return { delimiter: delim === "\t" ? "TAB" : delim, column: hit, fields: fields.length };
  }
  return null;
}

const tracked = execFileSync("git", ["ls-files", "-z"], { encoding: "utf8" })
  .split("\0")
  .filter(Boolean);

check(tracked.length > 0, "能列出已跟踪文件");

const offenders = [];
for (const path of tracked) {
  let stat;
  try {
    stat = statSync(path);
  } catch {
    continue; // 已删除但索引未更新之类
  }
  if (!stat.isFile() || stat.size === 0) continue;
  // 只读前 8KB —— 判据只用首行，没必要把大文件整个读进来
  let head;
  try {
    head = readFileSync(path, "utf8").slice(0, 8192);
  } catch {
    continue; // 二进制
  }
  const found = detectHeader(head);
  if (found) {
    offenders.push(`${path}  [分隔符 ${found.delimiter}，${found.fields} 列，命中 ${found.column}]`);
  }
}

check(
  offenders.length === 0,
  "已跟踪文件里存在个人数据表格（公开仓库禁止）：\n    "
    + offenders.join("\n    ")
    + "\n\n  处理方式见 ~/aozora-security-20260827/PROGRESS 的 09-05 一节："
    + "\n  从 HEAD 移除 → 重写历史 → 留本地备份分支（勿推） → 强推 → 另开 GitHub 工单。"
    + "\n  只加 .gitignore 是不够的——已跟踪文件不受它约束。",
);

console.log(`PII_DATA_FILE_LINT_PASS ${assertionCount}/${assertionCount}（扫描 ${tracked.length} 个已跟踪文件）`);
