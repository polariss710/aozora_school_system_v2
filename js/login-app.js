import { APP_VERSION } from "./config.js?v=be-ui-20260806-1";
import {
  failClosedSignOut,
  signInAndVerify,
  verifyCurrentAuthContext,
} from "./api/auth-api.js?v=p0-g1-a-20260804-1";

const form = document.querySelector("#loginForm");
const emailInput = document.querySelector("#loginEmail");
const passwordInput = document.querySelector("#loginPassword");
const submitButton = document.querySelector("#loginSubmit");
const messageArea = document.querySelector("#loginMessage");
const version = document.querySelector("#loginVersion");

if (version) version.textContent = APP_VERSION;
renderReasonMessage();

form?.addEventListener("submit", async (event) => {
  event.preventDefault();
  setBusy(true);
  showMessage("正在验证登录和系统权限…", "info");
  try {
    await signInAndVerify(emailInput?.value, passwordInput?.value || "");
    window.location.replace(safeReturnTarget());
  } catch (error) {
    showMessage(error?.message || "登录失败，请重试。", "error");
  } finally {
    if (passwordInput) passwordInput.value = "";
    setBusy(false);
  }
});

void redirectAuthorizedSession();

async function redirectAuthorizedSession() {
  try {
    const context = await verifyCurrentAuthContext();
    if (context.status === "authorized") {
      window.location.replace(safeReturnTarget());
    }
  } catch (error) {
    await failClosedSignOut();
    showMessage(error?.message || "请重新登录。", "error");
  }
}

function safeReturnTarget() {
  const fallback = new URL("./index.html", window.location.href);
  const raw = new URLSearchParams(window.location.search).get("return");
  if (!raw || raw.startsWith("//")) return fallback.href;

  try {
    const candidate = new URL(raw, window.location.origin);
    const loginUrl = new URL("./login.html", window.location.href);
    const basePath = loginUrl.pathname.slice(0, loginUrl.pathname.lastIndexOf("/") + 1);
    if (candidate.origin !== window.location.origin) return fallback.href;
    if (!candidate.pathname.startsWith(basePath)) return fallback.href;
    if (candidate.pathname === loginUrl.pathname) return fallback.href;
    return `${candidate.pathname}${candidate.search}${candidate.hash}`;
  } catch (_error) {
    return fallback.href;
  }
}

function renderReasonMessage() {
  const reason = new URLSearchParams(window.location.search).get("reason");
  const messages = {
    signed_out: "已安全退出。",
    session_expired: "登录已过期，请重新登录。",
    session_invalid: "登录状态无效，请重新登录。",
    refresh_failed: "登录刷新失败，请重新登录。",
    membership_missing: "当前账号没有系统访问权限。",
    membership_inactive: "当前账号权限已停用。",
    membership_unavailable: "暂时无法确认系统权限，请重新登录。",
    role_invalid: "当前账号角色无效。",
    config_missing: "登录服务尚未配置。",
  };
  if (messages[reason]) showMessage(messages[reason], reason === "signed_out" ? "success" : "error");
}

function setBusy(busy) {
  if (emailInput) emailInput.disabled = busy;
  if (passwordInput) passwordInput.disabled = busy;
  if (submitButton) submitButton.disabled = busy;
}

function showMessage(text, type) {
  if (!messageArea) return;
  messageArea.textContent = text || "";
  messageArea.className = text ? `login-message login-message-${type}` : "login-message";
}
