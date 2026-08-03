import { APP_VERSION } from "./config.js";
import { requireGlobalSession } from "./auth-guard.js?v=p0-g1-a-20260804-1";
import { initPaymentDetailPage } from "./pages/payment-detail-page.js?v=v2.112.0-cash-retry-attempts-20260614";

const globalSessionPromise = requireGlobalSession();

document.addEventListener("DOMContentLoaded", async () => {
  await globalSessionPromise;
  const versionEl = document.querySelector("#appVersion");
  if (versionEl) {
    versionEl.textContent = APP_VERSION;
  }

  console.info("[aozora-school-v2]", APP_VERSION);

  try {
    initPaymentDetailPage();
  } catch (error) {
    const messageArea = document.querySelector("#paymentDetailMessageArea");
    if (messageArea) {
      messageArea.className = "message message-error";
      messageArea.textContent = `老师工资支付详情页面初始化失败：${error.message || error}`;
    }
  }
});
