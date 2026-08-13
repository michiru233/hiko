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
