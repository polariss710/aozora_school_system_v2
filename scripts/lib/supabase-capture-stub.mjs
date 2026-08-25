// Supabase 客户端桩：记录所有 functions.invoke 调用，供测试检查真实提交体。
// 不发起任何网络请求。

export const invocations = [];

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
    rpc: async () => ({ data: null, error: null }),
    from: () => ({ select: () => ({ data: null, error: null }) }),
  };
}
