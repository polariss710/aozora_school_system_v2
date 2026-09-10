import {
  getCurrentAuthContext,
  getCurrentSession as getVerifiedSession,
  signInAndVerify,
  signOutLocal,
} from "./api/auth-api.js?v=p1-b2b-auth-storage-20260810-1";

const authDom = {};
let isInitialized = false;

export function getCurrentSession() {
  return getVerifiedSession();
}

export function isLoggedIn() {
  return Boolean(getVerifiedSession()?.user && getCurrentAuthContext()?.membership?.is_active);
}

export function isActiveAdmin() {
  const context = getCurrentAuthContext();
  return Boolean(
    getVerifiedSession()?.user &&
    context?.membership?.is_active === true &&
    context.membership.role === "admin"
  );
}

// 教务老师（operator）2026-09-11 起兼任财务，账内凭证类操作对她开放。
//
// ⚠️ 这两个函数【只决定界面上给不给入口】，不是权限。真正的准入在数据库的
//    school_require_current_app_operator()；绕过界面直接调 RPC 一样会被拒。
//
// ⚠️ 不要拿它去替换 Cash 相关的 isActiveAdmin。按业务分工，
//    「她做财务（在账内产生凭证），他做出纳（资金实际进出）」，
//    Cash 提交属于出纳，仍然只给管理员。
export function isActiveAdminOrOperator() {
  const context = getCurrentAuthContext();
  return Boolean(
    getVerifiedSession()?.user &&
    context?.membership?.is_active === true &&
    ["admin", "operator"].includes(context.membership.role)
  );
}

export function requireActiveAdminOrOperator(showMessage, action) {
  if (isActiveAdminOrOperator()) return true;

  if (typeof showMessage === "function") {
    showMessage("error", `仅已启用的管理员或教务账号可以${action}。`);
  }
  return false;
}

export function requireActiveAdminForCashConfirmation(showMessage) {
  if (isActiveAdmin()) return true;

  if (typeof showMessage === "function") {
    showMessage("error", "仅已启用的管理员账号可以提交 Cash 确认请求。");
  }
  return false;
}

export function requireLoginForCashConfirmation(showMessage) {
  if (isLoggedIn()) return true;

  if (typeof showMessage === "function") {
    showMessage("error", "当前登录状态或系统权限无效，请重新登录。");
  }
  return false;
}

export async function initSchoolAuth() {
  cacheAuthDom();
  if (!authDom.panel || isInitialized) return;

  isInitialized = true;
  bindAuthEvents();
  renderAuthState();
}

function cacheAuthDom() {
  authDom.panel = document.querySelector("#schoolAuthPanel");
  authDom.form = document.querySelector("#schoolAuthForm");
  authDom.emailInput = document.querySelector("#schoolAuthEmailInput");
  authDom.passwordInput = document.querySelector("#schoolAuthPasswordInput");
  authDom.loginButton = document.querySelector("#schoolAuthLoginButton");
  authDom.logoutButton = document.querySelector("#schoolAuthLogoutButton");
  authDom.statusText = document.querySelector("#schoolAuthStatusText");
  authDom.userPanel = document.querySelector("#schoolAuthUserPanel");
  authDom.message = document.querySelector("#schoolAuthMessage");
}

function bindAuthEvents() {
  authDom.form?.addEventListener("submit", handleAuthLogin);
  authDom.logoutButton?.addEventListener("click", handleAuthLogout);
}

async function handleAuthLogin(event) {
  event.preventDefault();
  const email = authDom.emailInput?.value || "";
  const password = authDom.passwordInput?.value || "";

  setAuthFormDisabled(true);
  renderAuthMessage("正在验证登录和系统权限…", "info");
  try {
    await signInAndVerify(email, password);
    renderAuthMessage("登录成功。", "success");
    renderAuthState();
  } catch (error) {
    renderAuthMessage(error?.message || "登录失败，请重试。", "error");
  } finally {
    if (authDom.passwordInput) authDom.passwordInput.value = "";
    setAuthFormDisabled(false);
  }
}

async function handleAuthLogout() {
  setAuthFormDisabled(true);
  renderAuthMessage("正在退出…", "info");
  try {
    await signOutLocal();
    window.location.replace(new URL("./login.html?reason=signed_out", window.location.href).href);
  } catch (error) {
    renderAuthMessage(error?.message || "退出失败，请重试。", "error");
    setAuthFormDisabled(false);
  }
}

function renderAuthState() {
  const context = getCurrentAuthContext();
  const userEmail = context?.user?.email || "";
  const role = context?.membership?.role || "";

  authDom.form?.classList.toggle("is-hidden", Boolean(userEmail));
  authDom.userPanel?.classList.toggle("is-hidden", !userEmail);
  if (authDom.statusText) {
    authDom.statusText.textContent = userEmail ? `已登录：${userEmail}（${role}）` : "未登录";
  }
}

function renderAuthMessage(text, type) {
  if (!authDom.message) return;
  authDom.message.textContent = text || "";
  authDom.message.className = text ? `auth-message auth-message-${type}` : "auth-message";
}

function setAuthFormDisabled(isDisabled) {
  if (authDom.emailInput) authDom.emailInput.disabled = isDisabled;
  if (authDom.passwordInput) authDom.passwordInput.disabled = isDisabled;
  if (authDom.loginButton) authDom.loginButton.disabled = isDisabled;
  if (authDom.logoutButton) authDom.logoutButton.disabled = isDisabled;
}
