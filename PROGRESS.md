# PROGRESS（hiko 1.39.0：重发缺失 Mpv.framework 的 macOS 包，修复启动黑屏）

- 目标：v1.38.0 包因构建期 mpv 依赖缓存损坏且下载失败被静默吞掉而缺 Mpv.framework，用户启动即黑屏；以 1.39.0+43 重发含 Mpv.framework 的包，并在 v1.38.0 Release 说明加黑屏警告。零代码改动（仅版本号与文档）。
- 顺序：0 基线核对（HEAD 0b34766 / pubspec 1.38.0+42 / pub 缓存 Mpv.xcframework 在位）→1 bump 版本+记录 →2 构建+Mpv.framework 反向验证+zip →3 启动自测 →4 push+Release+v1.38.0 警告。
- 最大风险：构建环境再次静默缺库（以「find 计数为 0 禁止发布」反向验证堵住）。

## 任务状态
- [x] 任务 0：基线核对一致
- [x] 任务 1：pubspec 1.39.0+43，hiko/PROGRESS.md 与根 PROGRESS.md 记录
- [ ] 任务 2/3：构建、打包、启动自测
- [ ] 任务 4：git push + gh release v1.39.0 + v1.38.0 黑屏警告
