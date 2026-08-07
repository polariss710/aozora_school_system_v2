import { APP_VERSION } from "./config.js?v=phase-b4-remaining-20260807-1";
import { requireGlobalSession } from "./auth-guard.js?v=phase-b4-remaining-20260807-1";
import { initWageRuleDetailPage } from "./pages/wage-rule-detail-page.js?v=phase-b4-remaining-20260807-1";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initWageRuleDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#wageRuleDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资规则详情页面初始化失败：${error.message || error}`;
    }
  }
});
