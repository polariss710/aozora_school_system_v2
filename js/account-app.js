import { APP_VERSION } from "./config.js";
import { initAccountPage } from "./pages/account-page.js?v=v2.109.0-account-app-type-isolation-20260613";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initAccountPage();
  } catch (error) {
    const messageArea = document.querySelector("#accountMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `账户管理页面初始化失败：${error.message || error}`;
    }
  }
});
