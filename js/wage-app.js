import { APP_VERSION } from "./config.js";
import { initWagePage } from "./pages/wage-page.js?v=v10.3.49-batch-duty-report-export";

document.addEventListener("DOMContentLoaded", async () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initWagePage();
  } catch (error) {
    const messageArea = document.querySelector("#wageMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资结算页面初始化失败：${error.message || error}`;
    }
  }
});
