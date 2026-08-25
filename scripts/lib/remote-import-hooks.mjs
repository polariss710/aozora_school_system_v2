// node 模块解析钩子：把生产代码里的远程 ESM 导入映射到本地桩。
//
// js/supabase-client.js 从 https://esm.sh/@supabase/supabase-js@2 导入
// createClient，node 默认加载器不支持 https: 协议，因此任何 import 了
// api 层的测试都会在加载阶段失败。有了这个钩子，测试就能驱动真实的
// api 模块——包括 buildLockPayload 的 camelCase → snake_case 转换与最终
// 提交给 Edge 的 body——而不是只测页面层的中间结构。
export async function resolve(specifier, context, next) {
  if (specifier.startsWith("https://esm.sh/@supabase/supabase-js")) {
    return {
      url: new URL("./supabase-capture-stub.mjs", import.meta.url).href,
      shortCircuit: true,
    };
  }
  return next(specifier, context);
}
