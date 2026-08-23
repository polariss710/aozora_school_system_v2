import assert from "node:assert/strict";
import { assertAppVersionAtLeast } from "./static-test-helpers.mjs";
import crypto from "node:crypto";
import fs from "node:fs";

const html = fs.readFileSync("lesson.html", "utf8");
const app = fs.readFileSync("js/lesson-app.js", "utf8");
const config = fs.readFileSync("js/config.js", "utf8");
const lessonApi = fs.readFileSync("js/api/lesson-api.js", "utf8");
const clearanceApi = fs.readFileSync("js/api/lesson-clearance-api.js", "utf8");
const sha256 = (value) => crypto.createHash("sha256").update(value).digest("hex");

const makeupCopy = "仅在老师实际完成补课后登记。系统将生成补课实际课时，并按实际授课月份计算老师工资；如需使用已有超额课时抵扣待补余额，请使用“课时余额与清偿”。";
const clearanceCopy = "用于使用已登记的超额课时抵扣待补余额，不会生成新的实际课时，也不会新增老师工资；如老师实际又完成了一次补课，请使用“登记待补课完成”。";

assert.equal((html.match(new RegExp(makeupCopy, "g")) || []).length, 1);
assert.equal((html.match(new RegExp(clearanceCopy, "g")) || []).length, 1);
assert.match(html, /补课不新增学生学费；请在补课实际发生月份登记，来源课程可以选择以前月份。/);
assert.match(html, /清偿对象始终由业务人员人工选择；系统仅提供“较早产生的余额优先”建议，请在最终提交前核对。/);
assert.doesNotMatch(html, /请在补课实际发生月份登记；来源课程可以选择以前月份。补课不新增学生学费。/);
assert.doesNotMatch(html, /查看待补对象、可用超额、套餐余额及清偿历史。系统仅提供“较早产生的余额优先”建议/);

const makeupHeader = html.match(/<div class="section-heading">\s*<h2 id="createCrossMonthMakeupActualTitle">[\s\S]*?<\/div>/)?.[0] || "";
const clearanceHeader = html.match(/<header class="lesson-clearance-dialog-header">[\s\S]*?<button class="button" id="lessonClearanceWorkspaceCloseButton"/)?.[0] || "";
assert.match(makeupHeader, new RegExp(makeupCopy));
assert.match(clearanceHeader, new RegExp(clearanceCopy));
assert.doesNotMatch(clearanceHeader, /UUID|manifest|request identity|request_identity/i);
assert.match(html, /id="createCrossMonthMakeupActualSubmitButton"[^>]*>登记待补课完成</);
assert.match(html, /id="lessonClearanceConfirmButton"/);

assert.match(html, /lesson-app\.js\?v=makeup-source-origin-v2-20260820-1/);
assert.match(app, /config\.js\?v=makeup-source-origin-v2-20260820-1/);
assertAppVersionAtLeast(config, "v10.5.55");
assert.equal(sha256(lessonApi), "cf0ea1a26f5ddfa80eb3e522c6a2f3a847ab34981563129b7152bcaf2d0276c7");
assert.equal(sha256(clearanceApi), "259b79fe2273d6fed19707542af806d65380a7b81ea9a92fe2af81741b73a149");

console.log("LESSON_MAKEUP_CLEARANCE_COPY_STATIC_TEST_PASS");
