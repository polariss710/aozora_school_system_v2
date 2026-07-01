import { APP_VERSION } from "./config.js";
import { initWageDetailPage } from "./pages/wage-detail-page.js?v=v10.3.50-batch-duty-report-zip";

document.addEventListener("DOMContentLoaded", async () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initWageDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#wageDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资结算详情页面初始化失败：${error.message || error}`;
    }
  }
});
