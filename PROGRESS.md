# PROGRESS（hiko 1.36.0：默认按专辑艺术家排序并记住选择）

- 目标：AppSettings 增加 albumSort（默认 artist_asc，非法回退 artist_asc），home_screen 冷启动与切换绑定 settingsProvider.albumSort 记住排序，不加分组标题。
- 顺序：0 基线核对→1 settings_store 增加 albumSort 与测试（含红绿反向验证）→2 home_screen 接入 settingsProvider 并移除本地 recent 默认→3 bump 1.36.0+40、文档更新、全量测试、macOS release 构建与 gh release。
- 最大风险：非法或旧键兼容回退不全；home_screen 仍残留本地 'recent' 导致初次渲染闪烁或覆盖设置。

## 任务状态
- [x] 任务 0：基线核对（version 1.35.0+39, analyze 32 issues, 17 tests passed）
- [x] 任务 1：settings_store.dart 增加 albumSort 持久化及单测（6 passed，反向验证红→绿已通过）
- [x] 任务 2：home_screen.dart 接上 settingsProvider.albumSort 并移除本地 'recent'
- [x] 任务 3：文档与发版 1.36.0+40（README, plan, macOS release 构建, git push, gh release）
