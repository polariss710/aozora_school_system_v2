import { APP_VERSION } from "./config.js";
import { initContractGeneratorPage } from "./pages/contract-generator-page.js?v=v10.3.31-contract-generator-beta";

document.addEventListener("DOMContentLoaded", () => {
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initContractGeneratorPage();
  } catch (error) {
    const messageArea = document.querySelector("#contractGeneratorMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `合同生成页面初始化失败：${error.message || error}`;
    }
  }
});
