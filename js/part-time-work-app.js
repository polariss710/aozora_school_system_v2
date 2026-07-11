import { APP_VERSION } from "./config.js";
import { initPartTimeWorkPage } from "./pages/part-time-work-page.js?v=v10.3.68-part-time-annual-summary";

document.addEventListener("DOMContentLoaded", async () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    await initPartTimeWorkPage();
  } catch (error) {
    const messageArea = document.querySelector("#partTimeWorkMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `私塾打工页面初始化失败：${error.message || error}`;
    }
  }
});
