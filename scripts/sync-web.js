// 生成 Capacitor webDir（web/）：把根目录共享 UI 文件拷贝进来，
// 并注入 Android 专属脚本（kikoeru-bridge.js 等）。
// 用法：node scripts/sync-web.js
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const webDir = path.join(root, 'web');
const bridgeDir = path.join(root, 'bridge');

const SHARED = ['index.html', 'app.js', 'styles.css'];
const BRIDGE_FILES = ['kikoeru-bridge.js', 'native-audio.js']; // 存在的才会被拷贝/注入

fs.mkdirSync(webDir, { recursive: true });

// 1. 拷贝共享 UI（真源在仓库根目录，保持单份维护）
for (const name of SHARED) {
  const src = path.join(root, name);
  if (!fs.existsSync(src)) throw new Error(`缺少共享文件: ${name}`);
  fs.copyFileSync(src, path.join(webDir, name));
}

// 1.5 Android 构建：移除 <audio> 元素（播放由 native-audio.js shim 接管）
const htmlCopy = path.join(webDir, 'index.html');
let htmlText = fs.readFileSync(htmlCopy, 'utf8');
htmlText = htmlText.replace(/<audio[^>]*><\/audio>/, '');
fs.writeFileSync(htmlCopy, htmlText);

// 2. 拷贝 Android 专属脚本
const injected = [];
for (const name of BRIDGE_FILES) {
  const src = path.join(bridgeDir, name);
  if (fs.existsSync(src)) {
    fs.copyFileSync(src, path.join(webDir, name));
    injected.push(name);
  }
}

// 3. 在 web/index.html 的 <script src="app.js"> 之前注入专属脚本
const htmlPath = path.join(webDir, 'index.html');
let html = fs.readFileSync(htmlPath, 'utf8');
const extra = injected
  .map(name => `  <script src="${name}"></script>`)
  .join('\n');
if (!html.includes(extra)) {
  const marker = '<script src="app.js"></script>';
  if (!html.includes(marker)) throw new Error('web/index.html 中未找到 app.js script 标签');
  html = html.replace(marker, `${extra}\n  ${marker}`);
  fs.writeFileSync(htmlPath, html);
}

console.log(`[sync-web] web/ 已生成：${SHARED.join(', ')}${injected.length ? ` + ${injected.join(', ')}` : ''}`);
