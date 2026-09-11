// ⚠️ 版本钉死。原来是浮动的 @2：
//   · 线上 v5 包构建于 2026-08-25，里面是【那天】解析到的版本；
//   · 只要重新部署，supabase-js 就必然跳到重新解析时的版本 —— 钉不钉都会跳。
//   钉死的作用是让这次跳变成一次【明确记录的决定】，并让回退可复现：
//   拿同一份源码重新部署，得到的是同一个依赖版本。
//   2.112.4 = Codex 2026-09-11 取证时 @2 的解析结果。
// ⚠️ 另外 6 个 Edge 仍是浮动的 @2，本批不动它们。
import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.112.4";

import {
  SettlementOnlinePublicError,
  type JsonRecord,
  type SettlementOnlineAuthContext,
  type SettlementOnlineDependencies,
} from "./student-settlement-online-contract.ts";

type RpcArgumentsBuilder<TInput> = (
  actorUserId: string,
  input: TInput,
) => JsonRecord;

type PrivateAuthContext = {
  userClient: SupabaseClient;
};

// 准入描述符：由各入口固定注入，决定用哪个库内守卫、失败时报哪个码。
// ⚠️ guardRpc 必须是 authenticated 可执行的守卫（用户 JWT 调用），
//    库内那两个 assert 是 owner-only，不能从这里调。
export type SettlementOnlineAuthorization = {
  guardRpc: string;
  errorCode: string;
  message: string;
};

export function createSettlementOnlineDependencies<TInput>(
  rpcName: string,
  buildArguments: RpcArgumentsBuilder<TInput>,
  authorization: SettlementOnlineAuthorization,
): SettlementOnlineDependencies<TInput> {
  return {
    createRequestId: () => crypto.randomUUID(),
    nowMs: () => performance.now(),

    async authenticateUser(authorization: string): Promise<SettlementOnlineAuthContext> {
      const schoolUrl = requiredEnv("SCHOOL_SUPABASE_URL");
      const anonKey = requiredEnv("SUPABASE_ANON_KEY");
      const token = authorization.replace(/^Bearer\s+/i, "");
      const userClient = createClient(schoolUrl, anonKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
          detectSessionInUrl: false,
        },
        global: {
          headers: {
            Authorization: authorization,
          },
        },
      });
      const { data, error } = await userClient.auth.getUser(token);
      if (error || !data.user?.id) {
        throw new SettlementOnlinePublicError(
          "SETTLEMENT_EDGE_AUTH_INVALID",
          "登录状态无效或已过期，请重新登录。",
          401,
          "reauthenticate",
        );
      }
      return {
        userId: data.user.id,
        privateContext: { userClient } satisfies PrivateAuthContext,
      };
    },

    async authorize(context: SettlementOnlineAuthContext): Promise<void> {
      const privateContext = context.privateContext as PrivateAuthContext;
      const { data, error } = await privateContext.userClient.rpc(
        authorization.guardRpc,
      );
      // 守卫返回调用者自己的 uuid；必须与已认证用户一致，否则不算通过。
      if (error || String(data || "").toLowerCase() !== context.userId.toLowerCase()) {
        throw new SettlementOnlinePublicError(
          authorization.errorCode,
          authorization.message,
          403,
        );
      }
    },

    async invokeOnlineRpc(actorUserId: string, input: TInput): Promise<unknown> {
      // The service-role secret is deliberately resolved only after user JWT and
      // active-admin checks have completed in the shared request handler.
      const schoolUrl = requiredEnv("SCHOOL_SUPABASE_URL");
      const serviceRoleKey = requiredEnv("SCHOOL_SERVICE_ROLE_KEY");
      const serviceClient = createClient(schoolUrl, serviceRoleKey, {
        auth: {
          autoRefreshToken: false,
          persistSession: false,
          detectSessionInUrl: false,
        },
      });
      const { data, error } = await serviceClient.rpc(
        rpcName,
        buildArguments(actorUserId, input),
      );
      if (error) throw error;
      return data;
    },

    log(event: JsonRecord): void {
      console.info(JSON.stringify(event));
    },
  };
}

function requiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error("SETTLEMENT_EDGE_CONFIGURATION_INVALID");
  return value;
}
