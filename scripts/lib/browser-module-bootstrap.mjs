// 让 node 能加载 js/ 下的浏览器模块。仅有副作用，无导出。
//
// 两件事：
//   一、js/supabase-client.js 从 https://esm.sh 远程导入 createClient，node 默认
//      加载器不支持 https: 协议。模块解析钩子把它映射到本地捕获桩。
//   二、supabase-client.js 在模块顶层访问 window.localStorage，且以是否成功清理
//      legacy storage 作为 fail-closed 条件。给出最小可用实现。
//
// 2026-08-26 起，js/pages/settlement-online-state.js 也需要它：权威快照的登记
// 入口收进了 API 层，state 层因此间接依赖 supabase 客户端。原本零依赖的页面层
// 单元测试都要经过这里——这是那条来源约束的内在成本。
//
// 必须在 import 任何 js/ 模块之前求值。用静态 import 引入本模块、再用
// await import() 取被测模块，即可保证顺序。

import { register } from "node:module";

register("./remote-import-hooks.mjs", import.meta.url);

const memoryStorage = new Map();
globalThis.window = {
  localStorage: {
    getItem: (k) => (memoryStorage.has(k) ? memoryStorage.get(k) : null),
    setItem: (k, v) => memoryStorage.set(k, String(v)),
    removeItem: (k) => memoryStorage.delete(k),
    key: (i) => [...memoryStorage.keys()][i] ?? null,
    get length() { return memoryStorage.size; },
  },
};
globalThis.localStorage = globalThis.window.localStorage;
