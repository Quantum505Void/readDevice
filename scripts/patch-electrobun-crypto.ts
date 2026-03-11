/**
 * patch-electrobun-crypto.ts  
 * postinstall: 把 AES-GCM polyfill 注入 Electrobun dynamicPreload
 * 解决 WebKit2GTK views:// 非安全来源导致 crypto.subtle 不可用问题
 */
import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { build } from "bun";

const root = new URL("..", import.meta.url).pathname;
const nativePath = join(root, "node_modules/electrobun/dist/api/bun/proc/native.ts");
const polyfillSrc = join(root, "scripts/crypto-polyfill-src.ts");
const MARKER = "// [electrobun-crypto-polyfill]";
const SEARCH = "dynamicPreload = `\nwindow.__electrobunWebviewId = ${id};";

if (!existsSync(nativePath)) { console.log("electrobun not found, skip"); process.exit(0); }
const content = readFileSync(nativePath, "utf8");
if (content.includes(MARKER)) { console.log("already patched"); process.exit(0); }
if (!content.includes(SEARCH)) { console.error("pattern not found"); process.exit(1); }

const result = await build({ entrypoints: [polyfillSrc], target: "browser", minify: true });
const poly = await result.outputs[0].text();
const escaped = poly.replace(/\\/g, "\\\\").replace(/`/g, "\\`").replace(/\$\{/g, "\\${");
writeFileSync(nativePath, content.replace(SEARCH,
  `dynamicPreload = \`${MARKER}\n${escaped}\nwindow.__electrobunWebviewId = \${id};`), "utf8");
console.log("✓ Patched crypto.subtle polyfill into electrobun");
