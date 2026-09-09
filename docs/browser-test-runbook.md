# 浏览器测试怎么跑

`scripts/*browser-test*.mjs` 需要 Playwright 与一个本地静态服务器，两者都不在仓库里，
所以它们**默认跑不起来**，只会抛 `*_NODE_MODULES_REQUIRED`。仓库此前没有记录运行方式，
这份文档补上。

## 1. 装 Playwright（不下载它自带的浏览器）

```bash
mkdir -p /tmp/pw && cd /tmp/pw
echo '{"name":"pw-harness","private":true}' > package.json
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm i playwright --no-audit --no-fund
```

`PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1` 省掉一百多 MB 的浏览器下载，改用机器上已有的 Chrome。

## 2. 起静态服务器

各测试的默认端口不同，看各自的 `*_BASE_URL` 默认值（d1 用 8018，d2a/a3 用 8019）。

```bash
cd ~/Documents/aozora_school_system_v2
python3 -m http.server 8018 --bind 127.0.0.1 &
python3 -m http.server 8019 --bind 127.0.0.1 &
```

服务仓库根目录即可。测试自己会把 `js/lesson-app.js` 路由成空模块，
所以不会触发真实鉴权跳转。

## 3. 跑

```bash
export PHASE2C_D1_NODE_MODULES=/tmp/pw/node_modules
export PHASE2C_D2A_NODE_MODULES=/tmp/pw/node_modules
export PHASE2C_D1_BROWSER_EXECUTABLE="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
export PHASE2C_D2A_BROWSER_EXECUTABLE="$PHASE2C_D1_BROWSER_EXECUTABLE"

for t in scripts/*clearance*browser-test*.mjs; do node "$t"; done
```

## 4. 当前状态（2026-09-10 首次在本机运行）

| 测试 | 结果 |
|---|---|
| `school-phase2c-d2-a3-clearance-completion-browser-test-20260818.mjs` | ✅ PASS |
| `school-phase2c-d2-a2-clearance-business-ui-browser-test-20260818.mjs` | ✅ PASS |
| `school-phase2c-d1-clearance-workspace-browser-test-20260818.mjs` | ❌ 超时于 `.lesson-clearance-preview-card` |
| `school-phase2c-d2a-clearance-submit-browser-test-20260818.mjs` | ❌ 超时于最终确认框关闭 |

⚠️ 后两项的失败**早于 2026-09-09 的清偿工作区改动**——
把组件退回 `fefe415^` 后它们同样失败，根因尚未诊断。
