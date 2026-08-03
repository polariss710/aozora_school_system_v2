import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initBusinessEntityPage } from "./pages/business-entity-page.js?v=v10.1.9-business-owner-ui-polish";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
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
