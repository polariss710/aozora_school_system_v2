import { APP_VERSION } from "./config.js";
import { initWageRulePage } from "./pages/wage-rule-page.js?v=v10.3.73-single-business-entity";

document.addEventListener("DOMContentLoaded", () => {
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
