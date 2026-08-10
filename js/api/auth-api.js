import { hasSupabaseConfig, supabase } from "../supabase-client.js?v=p1-b2b-auth-storage-20260810-1";

const VALID_ROLES = new Set(["admin", "operator", "read_only"]);
let currentAuthContext = null;

export class AuthAccessError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "AuthAccessError";
    this.code = code;
  }
}

export function getCurrentAuthContext() {
  return currentAuthContext;
}

export function getCurrentSession() {
  return currentAuthContext?.session || null;
}

export async function verifyCurrentAuthContext() {
  if (!hasSupabaseConfig()) {
    throw new AuthAccessError("config_missing", "登录服务尚未配置。");
  }

  const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
  if (sessionError) {
    throw new AuthAccessError("session_error", "无法恢复登录状态，请重新登录。");
  }

  const session = sessionData?.session || null;
  if (!session) {
    currentAuthContext = null;
    return { status: "anonymous", session: null, user: null, membership: null };
  }

  const { data: userData, error: userError } = await supabase.auth.getUser();
  if (userError || !userData?.user) {
    currentAuthContext = null;
    throw new AuthAccessError("session_invalid", "登录状态已失效，请重新登录。");
  }

  const { data: membershipData, error: membershipError } = await supabase.rpc(
    "school_get_current_app_membership"
  );
  if (membershipError) {
    currentAuthContext = null;
    throw new AuthAccessError("membership_unavailable", "无法确认当前权限，请重新登录。");
  }

  const membership = Array.isArray(membershipData)
    ? membershipData[0] || null
    : membershipData || null;
  const user = userData.user;

  if (!membership || membership.user_id !== user.id) {
    currentAuthContext = null;
    throw new AuthAccessError("membership_missing", "当前账号没有系统访问权限。");
  }
  if (membership.is_active !== true) {
    currentAuthContext = null;
    throw new AuthAccessError("membership_inactive", "当前账号权限已停用。");
  }
  if (!VALID_ROLES.has(membership.role)) {
    currentAuthContext = null;
    throw new AuthAccessError("role_invalid", "当前账号角色无效。");
  }

  currentAuthContext = { session, user, membership };
  return { status: "authorized", ...currentAuthContext };
}

export async function signInAndVerify(email, password) {
  const normalizedEmail = String(email || "").trim();
  if (!normalizedEmail || !password) {
    throw new AuthAccessError("credentials_required", "请输入邮箱和密码。");
  }

  const { error } = await supabase.auth.signInWithPassword({
    email: normalizedEmail,
    password: String(password),
  });
  if (error) {
    throw new AuthAccessError("credentials_invalid", "邮箱或密码错误。");
  }

  try {
    const context = await verifyCurrentAuthContext();
    if (context.status !== "authorized") {
      throw new AuthAccessError("session_invalid", "登录状态无效，请重试。");
    }
    return context;
  } catch (error) {
    await signOutLocal();
    throw error;
  }
}

export async function signOutLocal() {
  currentAuthContext = null;
  const { error } = await supabase.auth.signOut({ scope: "local" });
  if (error) {
    throw new AuthAccessError("logout_failed", "退出失败，请刷新后重试。");
  }
}

export async function failClosedSignOut() {
  currentAuthContext = null;
  try {
    await supabase.auth.signOut({ scope: "local" });
  } catch (_error) {
    // Navigation remains fail-closed even when local token cleanup fails.
  }
}

export function subscribeToAuthChanges(callback) {
  const { data } = supabase.auth.onAuthStateChange((event, session) => {
    callback(event, session || null);
  });
  return () => data?.subscription?.unsubscribe();
}
