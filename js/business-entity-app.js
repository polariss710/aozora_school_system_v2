import { APP_VERSION } from "./config.js";
import { initBusinessEntityPage } from "./pages/business-entity-page.js?v=v2.102.0-business-entity-dialog-field-scope-20260612";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initBusinessEntityPage();
  } catch (error) {
    const messageArea = document.querySelector("#businessEntityMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `业务归属页面初始化失败：${error.message || error}`;
    }
  }
});
