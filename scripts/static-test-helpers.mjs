// 静态测试共用断言。
//
// 背景：多个阶段性静态测试把全局 APP_VERSION 钉死成该阶段当时的具体版本，
// 例如 assert.match(config, /APP_VERSION = "v10\.5\.55"/)。但 APP_VERSION 是
// 全站共享、每批改动都会前向升级的，因此这类断言在下一次升版时必然失效，
// 与被测行为是否回归无关。截至 2026-08-23 已有 7 个测试因此长期为红。
//
// 直接改成 /v10\.5\.\d+/ 会丢掉原意（「该阶段确实升过版」）。这里改用单调断言：
// 版本必须不低于该阶段引入时的基线。原意保留，且不会因将来升版而再次失效。

const VERSION_RE = /APP_VERSION\s*=\s*"v(\d+)\.(\d+)\.(\d+)"/;

function parse(text, label) {
  const match = VERSION_RE.exec(text);
  if (!match) {
    throw new Error(`${label}: 未找到形如 APP_VERSION = "vX.Y.Z" 的声明`);
  }
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

function compare(a, b) {
  for (let i = 0; i < 3; i += 1) {
    if (a[i] !== b[i]) return a[i] < b[i] ? -1 : 1;
  }
  return 0;
}

/**
 * 断言 js/config.js 的 APP_VERSION 不低于给定基线。
 *
 * @param {string} config    js/config.js 的文本内容
 * @param {string} baseline  形如 "v10.5.55" 的基线版本，通常是该测试所属阶段
 *                           引入时的生产版本
 */
export function assertAppVersionAtLeast(config, baseline) {
  const parsedBaseline = parse(`APP_VERSION = "${baseline}"`, "baseline");
  const actual = parse(config, "js/config.js");
  if (compare(actual, parsedBaseline) < 0) {
    throw new Error(
      `APP_VERSION 回退：期望不低于 ${baseline}，实际 v${actual.join(".")}`
    );
  }
}
