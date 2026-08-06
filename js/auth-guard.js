import {
  failClosedSignOut,
  signOutLocal,
  subscribeToAuthChanges,
  verifyCurrentAuthContext,
} from "./api/auth-api.js?v=p0-g1-a-20260804-1";

let guardPromise = null;
let redirecting = false;

export function requireGlobalSession() {
  if (!guardPromise) {
    guardPromise = initializeGlobalSessionGuard();
  }
  return guardPromise;
}

async function initializeGlobalSessionGuard() {
  document.documentElement.classList.add("auth-pending");

  let context;
  try {
    context = await verifyCurrentAuthContext();
  } catch (error) {
    await failClosedSignOut();
    return redirectToLogin(error?.code || "session_invalid");
  }

  if (context.status !== "authorized") {
    return redirectToLogin("login_required");
  }

  clearLegacyBusinessEntityQueryParams();

  subscribeToAuthChanges((event) => {
    if (event === "SIGNED_OUT") {
      redirectToLogin("signed_out");
      return;
    }
    if (["TOKEN_REFRESHED", "USER_UPDATED"].includes(event)) {
      window.setTimeout(async () => {
        try {
          const refreshed = await verifyCurrentAuthContext();
          if (refreshed.status !== "authorized") {
            await failClosedSignOut();
            redirectToLogin("session_expired");
          }
        } catch (_error) {
          await failClosedSignOut();
          redirectToLogin("refresh_failed");
        }
      }, 0);
    }
  });

  installSessionBar(context);
  document.documentElement.classList.add("global-session-guard", "auth-authorized");
  document.documentElement.classList.remove("auth-pending");
  return context;
}

export function clearLegacyBusinessEntityQueryParams() {
  const url = new URL(window.location.href);
  let changed = false;
  for (const key of ["business_entity_id", "businessEntityId", "business_entity", "businessEntity"]) {
    if (url.searchParams.has(key)) {
      url.searchParams.delete(key);
      changed = true;
    }
  }
  if (changed) {
    window.history.replaceState(window.history.state, "", `${url.pathname}${url.search}${url.hash}`);
  }
}

function installSessionBar(context) {
  if (document.querySelector("#globalSessionBar")) return;

  const bar = document.createElement("div");
  bar.id = "globalSessionBar";
  bar.className = "global-session-bar";

  const identity = document.createElement("span");
  identity.className = "global-session-identity";
  identity.textContent = `${context.user.email || "已登录"} · ${roleLabel(context.membership.role)}`;

  const logoutButton = document.createElement("button");
  logoutButton.type = "button";
  logoutButton.className = "button global-session-logout";
  logoutButton.textContent = "退出";
  logoutButton.addEventListener("click", async () => {
    logoutButton.disabled = true;
    try {
      await signOutLocal();
    } finally {
      redirectToLogin("signed_out");
    }
  });

  bar.append(identity, logoutButton);
  document.body.append(bar);
}

function roleLabel(role) {
  return {
    admin: "管理员",
    operator: "操作员",
    read_only: "只读",
  }[role] || "未知角色";
}

function redirectToLogin(reason) {
  if (!redirecting) {
    redirecting = true;
    const loginUrl = new URL("./login.html", window.location.href);
    loginUrl.searchParams.set("return", currentInternalPath());
    loginUrl.searchParams.set("reason", safeReason(reason));
    window.location.replace(loginUrl.href);
  }
  return new Promise(() => {});
}

function currentInternalPath() {
  return `${window.location.pathname}${window.location.search}${window.location.hash}`;
}

function safeReason(reason) {
  const allowed = new Set([
    "login_required",
    "signed_out",
    "session_expired",
    "session_invalid",
    "refresh_failed",
    "membership_missing",
    "membership_inactive",
    "membership_unavailable",
    "role_invalid",
    "config_missing",
  ]);
  return allowed.has(reason) ? reason : "session_invalid";
}
