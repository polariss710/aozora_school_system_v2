import {
  failClosedSignOut,
  signOutLocal,
  subscribeToAuthChanges,
  verifyCurrentAuthContext,
} from "./api/auth-api.js?v=p1-b2b-auth-storage-20260810-1";

let guardPromise = null;
let redirecting = false;

// 非管理员角色的页面白名单。
//
// admin 不在表内，表示不受限制。未列出的页面对该角色一律拒绝——fail-closed，
// 新增页面默认只有管理员可进，需要开放时显式加进来。
//
// ---------------------------------------------------------------------------
// 这是分阶段开放的第一版
// ---------------------------------------------------------------------------
//
// 用户 2026-09-03 确认的最终定位：教务老师应能处理**收入与支出以外的所有事务**，
// 包括教师工资结算。因此下列页面属于「以后要开、这一版先不开」：
//
//   settlement.html / settlement-detail.html    月度结算
//   wage.html / wage-detail.html                工资结算
//   wage-rule.html / wage-rule-detail.html      工资规则
//
// 开放它们时只需加进这个集合，不需要动别的地方。
//
// ---------------------------------------------------------------------------
// 外部授课是永久排除，不是「以后再开」
// ---------------------------------------------------------------------------
//
//   part-time-work.html / part-time-work-annual.html
//
// 那是塾长个人在外部私塾打工的收入记录，不属于本塾业务，只服务于他本人。
// **不要因为「除收入支出外都开放」这条规则而把它加进来。**
//
// ---------------------------------------------------------------------------
// 关于金额
// ---------------------------------------------------------------------------
//
// 课时管理能看到课时费、报价单要填单价，两者都在白名单内——这是用户明确认可的：
// 教务老师最终要负责生成每月预定课时并填写单价。学生管理与老师管理页面本身
// 不显示金额。
//
// 需要挡住的是收入、支出、报销、利润这类账目页面，不是「所有出现数字的页面」。
const ROLE_PAGE_ALLOWLIST = {
  operator: new Set([
    "student.html",
    "lesson.html",
    "lesson-detail.html",
    "teacher.html",
    "quote-plan.html",
    "contract-generator.html",
    "weekly-lesson-dashboard.html",
    "weekly-schedule-image.html",
    "classroom-schedule.html",
  ]),
};

// read_only 尚未单独设计，暂与 operator 共用同一份白名单。写入能力由数据库层
// 的 assert 函数区分，不依赖这里。
ROLE_PAGE_ALLOWLIST.read_only = ROLE_PAGE_ALLOWLIST.operator;

// 被拒绝时的落点。选学生管理是因为它是教务工作的入口页，且在白名单内。
const ROLE_FALLBACK_PAGE = "student.html";

function currentPageFileName() {
  const last = window.location.pathname.split("/").pop();
  return last || "index.html";
}

function isPageAllowedForRole(role, pageFileName) {
  const allowlist = ROLE_PAGE_ALLOWLIST[role];
  if (!allowlist) {
    // admin，或将来新增的未配置角色。未配置角色走 fail-closed 更安全，但那会
    // 让 admin 也被挡住，因此这里只对已知受限角色生效；未知角色由更上游的
    // role_invalid 校验拦截。
    return role === "admin";
  }
  return allowlist.has(pageFileName);
}

// 按角色移除导航中不可访问的链接，并清掉因此变空的分组。
//
// 侧边栏在每个页面的 HTML 里各自硬编码，因此这里用运行时移除而不是改 30 份
// HTML。注意这只是遮挡——数据库层的读权限并未按角色收紧，懂技术的人仍可直接
// 查询。用户已知悉并接受：使用场景是自己太太做教务，目的是防误操作而非防攻击。
function applyNavRoleVisibility(role) {
  if (!ROLE_PAGE_ALLOWLIST[role]) return;

  for (const link of document.querySelectorAll(".sidebar-nav a[href]")) {
    const href = link.getAttribute("href") || "";
    if (!href.startsWith("./") && !href.endsWith(".html")) continue;
    const page = href.replace(/^\.\//, "").split(/[?#]/)[0];
    if (!isPageAllowedForRole(role, page)) {
      link.remove();
    }
  }

  for (const group of document.querySelectorAll(".sidebar-nav .page-nav-group")) {
    if (!group.querySelector("a[href]")) {
      group.remove();
    }
  }
}

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

  // 页面级角色准入。放在会话校验之后、渲染之前：此时身份已确认，而页面内容尚未
  // 加载，被拒绝的角色不会短暂看到不该看的界面。
  const role = context.membership?.role;
  if (!isPageAllowedForRole(role, currentPageFileName())) {
    redirectToAllowedPage();
    return context;
  }

  applyNavRoleVisibility(role);
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

// 权限不足时跳到白名单内的落点页，而不是跳登录页。
//
// 跳登录会让人以为会话失效、反复重登仍进不去；跳一个能用的页面则直接传达了
// 「这个账号看不到这里」。复用 redirecting 标志，避免与登录跳转互相打断。
function redirectToAllowedPage() {
  if (redirecting) return;
  redirecting = true;
  const target = new URL(`./${ROLE_FALLBACK_PAGE}`, window.location.href);
  target.searchParams.set("denied", currentPageFileName());
  window.location.replace(target.href);
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
