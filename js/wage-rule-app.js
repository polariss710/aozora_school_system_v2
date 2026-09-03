import { APP_VERSION } from "./config.js?v=phase-d-lock-authoritative-source-20260826-1";
import { requireGlobalSession } from "./auth-guard.js?v=operator-role-access-20260903-1";
import { initWageRulePage } from "./pages/wage-rule-page.js?v=phase-d-lock-authoritative-source-20260826-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initWageRulePage();
  } catch (error) {
    const messageArea = document.querySelector("#wageRuleMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资规则页面初始化失败：${error.message || error}`;
    }
  }
});
