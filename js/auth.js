import { hasSupabaseConfig, supabase } from "./supabase-client.js?v=v2.111.0-supabase-auth-client-init-20260614";

const authDom = {};
let currentSession = null;
let isInitialized = false;

export function getCurrentSession() {
  return currentSession;
}

export function isLoggedIn() {
  return Boolean(currentSession?.user);
}

export function requireLoginForCashConfirmation(showMessage) {
  if (isLoggedIn()) {
    return true;
  }

  if (typeof showMessage === "function") {
    showMessage("error", "请先登录后再提交到 Cash 确认。");
  }

  return false;
}

export async function initSchoolAuth() {
  cacheAuthDom();

  if (!authDom.panel || isInitialized) {
    return;
  }

  isInitialized = true;
  bindAuthEvents();

  if (!hasSupabaseConfig()) {
    renderAuthMessage("Supabase 未配置，登录不可用。", "error");
    setAuthFormDisabled(true);
    renderAuthState();
    return;
  }

  const { data, error } = await supabase.auth.getSession();
  if (error) {
    renderAuthMessage(`读取登录状态失败：${error.message || error}`, "error");
  }

  currentSession = data?.session || null;
  renderAuthState();

  supabase.auth.onAuthStateChange((_event, session) => {
    currentSession = session || null;
    renderAuthState();
  });
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

  const email = authDom.emailInput?.value.trim();
  const password = authDom.passwordInput?.value || "";

  if (!email || !password) {
    renderAuthMessage("请输入 email 和 password。", "error");
    return;
  }

  setAuthFormDisabled(true);
  renderAuthMessage("正在登录...", "info");

  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) {
      throw error;
    }

    currentSession = data?.session || null;
    renderAuthMessage("登录成功。", "success");
    renderAuthState();
  } catch (error) {
    renderAuthMessage(`登录失败：${error.message || error}`, "error");
  } finally {
    if (authDom.passwordInput) {
      authDom.passwordInput.value = "";
    }
    setAuthFormDisabled(false);
  }
}

async function handleAuthLogout() {
  setAuthFormDisabled(true);
  renderAuthMessage("正在登出...", "info");

  try {
    const { error } = await supabase.auth.signOut();
    if (error) {
      throw error;
    }

    currentSession = null;
    renderAuthMessage("已登出。", "success");
    renderAuthState();
  } catch (error) {
    renderAuthMessage(`登出失败：${error.message || error}`, "error");
  } finally {
    setAuthFormDisabled(false);
  }
}

function renderAuthState() {
  const userEmail = currentSession?.user?.email || "";

  authDom.form?.classList.toggle("is-hidden", Boolean(userEmail));
  authDom.userPanel?.classList.toggle("is-hidden", !userEmail);

  if (authDom.statusText) {
    authDom.statusText.textContent = userEmail ? `已登录：${userEmail}` : "未登录";
  }
}

function renderAuthMessage(text, type) {
  if (!authDom.message) {
    return;
  }

  authDom.message.textContent = text || "";
  authDom.message.className = text ? `auth-message auth-message-${type}` : "auth-message";
}

function setAuthFormDisabled(isDisabled) {
  if (authDom.emailInput) {
    authDom.emailInput.disabled = isDisabled;
  }
  if (authDom.passwordInput) {
    authDom.passwordInput.disabled = isDisabled;
  }
  if (authDom.loginButton) {
    authDom.loginButton.disabled = isDisabled;
  }
  if (authDom.logoutButton) {
    authDom.logoutButton.disabled = isDisabled;
  }
}
