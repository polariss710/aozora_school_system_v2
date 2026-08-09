import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

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

export function createSettlementOnlineDependencies<TInput>(
  rpcName: string,
  buildArguments: RpcArgumentsBuilder<TInput>,
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

    async requireActiveAdmin(context: SettlementOnlineAuthContext): Promise<void> {
      const privateContext = context.privateContext as PrivateAuthContext;
      const { data, error } = await privateContext.userClient.rpc(
        "school_require_current_app_admin",
      );
      if (error || String(data || "").toLowerCase() !== context.userId.toLowerCase()) {
        throw new SettlementOnlinePublicError(
          "SETTLEMENT_ADMIN_REQUIRED",
          "当前账号没有执行该操作的管理员权限。",
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
