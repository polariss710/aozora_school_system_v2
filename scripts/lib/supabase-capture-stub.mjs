// Supabase 客户端桩：记录 functions.invoke 与 rpc 的实际入参，供测试检查。
// 不发起任何网络请求。

export const invocations = [];
export const rpcCalls = [];

const rpcResponses = new Map();

// 预置某个 RPC 的返回值。值可以是数据本身，也可以是 (args) => data。
// 未预置的 RPC 返回 null——与真实环境「查无此行」同形，不会让测试误以为成功。
export function setRpcResponse(functionName, data) {
  rpcResponses.set(functionName, data);
}

export function resetCapture() {
  invocations.length = 0;
  rpcCalls.length = 0;
  rpcResponses.clear();
}

// 取某个 RPC 最近一次调用的入参。用于断言参数来源——例如证明锁定预览的
// p_explicit_user_amount_cny 取自 status 草稿而非调用方传入。
export function lastRpcArgs(functionName) {
  for (let i = rpcCalls.length - 1; i >= 0; i -= 1) {
    if (rpcCalls[i].functionName === functionName) return rpcCalls[i].args;
  }
  return null;
}

export function createClient() {
  return {
    auth: {
      getSession: async () => ({ data: { session: null }, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
    },
    functions: {
      invoke: async (functionName, options) => {
        invocations.push({ functionName, body: options?.body });
        // 返回契约要求的成功形态：api 层校验 data.ok === true 且 data.result 存在
        // （js/api/student-settlement-online-api.js:63）。形态不对会被判成
        // SETTLEMENT_EDGE_RESPONSE_INVALID，测试就走不到成功路径。
        return {
          data: {
            ok: true,
            operation: "lock",
            request_id: "capture-stub",
            result: { effective_status: "ordinary_locked" },
          },
          error: null,
        };
      },
    },
    rpc: async (functionName, args) => {
      rpcCalls.push({ functionName, args });
      if (!rpcResponses.has(functionName)) return { data: null, error: null };
      const configured = rpcResponses.get(functionName);
      const data = typeof configured === "function" ? configured(args) : configured;
      return { data, error: null };
    },
    from: () => ({ select: () => ({ data: null, error: null }) }),
  };
}
