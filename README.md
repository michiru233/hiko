# Kikoeru macOS 音声管理器

本地优先的音声库界面原型，参考 neokikoeru 的“本地库 + 专辑元数据 + 播放队列”思路，当前版本无需安装依赖即可运行。

## 启动

```bash
npm run dev
```

打开 `http://localhost:4173`。macOS 用户也可以双击 `run.command`，它会启动本地服务并打开浏览器。

## macOS 桌面版

安装 Node.js 依赖后运行：

```bash
npm install
npm run desktop
```

构建 `.dmg` / `.zip`：

```bash
npm run dist
```

每次执行 `npm run dist` 会自动递增次版本号，例如 `0.1.0 → 0.2.0 → 0.3.0`，并同步更新 `package-lock.json`。日常运行 `npm run desktop` 不会修改版本号。

## 已实现

- macOS 风格窗口、侧栏分类和本地存储占用提示
- 专辑封面网格展示（离线 SVG 封面，不依赖外部图片）
- 搜索标题、社团、声优；按最近添加、标题、时长排序
- 未听完 / 已收藏筛选，收藏状态可直接切换
- 专辑详情侧栏、曲目列表、播放状态和底部播放条
- `⌘ K` 快速聚焦搜索
- 选择本地文件夹，按文件夹聚合导入音频；自动识别 `cover`、`front`、`封面` 等图片
- 真实音频播放、播放/暂停、上一首/下一首、循环、进度拖动

## Android 版（Capacitor 混合架构）

同一份 UI（`index.html` + `app.js` + `styles.css`）跑在 Android WebView 中，原生层（Kotlin 插件）实现与桌面 `window.kikoeru` 同签名的接口，三端功能对齐、代码共享。最低 Android 15（API 35）。

### 前置

```bash
npm install
# 需要 JDK 17+ 与 Android SDK（cmdline-tools, platform-tools, platforms;android-36, build-tools）
# SDK 路径写入 android/local.properties：sdk.dir=/path/to/sdk
```

### 构建 / 运行

```bash
npm run android:build   # 同步 web 资源 + cap sync + 构建 debug APK
npm run android:run     # 同步并安装到已连接设备/模拟器
```

`npm run android:build` 的输出在 `android/app/build/outputs/apk/debug/app-debug.apk`。发布用 `./gradlew assembleRelease`（需配置签名）。

### Android 原生能力（Kotlin 插件，见 `android/app/src/main/java/top/voicehub/kikoeru/`）

- **导入**：SAF `ACTION_OPEN_DOCUMENT_TREE` 选目录（持久化授权），递归扫描 + `MediaMetadataRetriever` 元数据解析 + 封面缩放，深层目录 RJ 号提取
- **播放**：Media3 ExoPlayer + 前台服务 + 媒体通知/锁屏控制；`bridge/native-audio.js` 把 `<audio>` 调用桥接到原生引擎（app.js 零改动）
- **刮削**：DLsite 标签刮削（原生请求无 CORS、代理可配、进度事件），解析逻辑与桌面同一套正则
- **数据操作**：删除专辑（含源文件）、清理失效记录、打开所在文件夹、导出音声库

### 架构说明

```
web/（构建产物，cap sync 到 Android）  ← scripts/sync-web.js 从根目录拷贝共享 UI + Android 专属脚本
bridge/kikoeru-bridge.js    window.kikoeru = Capacitor 插件封装（接口契约同 preload.js）
bridge/native-audio.js      <audio> DOM shim → 原生 Media3 引擎
```

版本号：`npm run bump-version` 会同步 package.json 与 `android/app/build.gradle` 的 versionCode/versionName。

