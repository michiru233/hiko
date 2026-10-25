# Hiko 详情页 M3E 重构 — 计划书

> 生成时间：2026-10-25（本机时间）
> 前置：M3E 主重构已收官（plan-hiko-m3e-redesign.md，1.99.26~33 全部发版）
> 本计划针对**专辑详情页**这一块独立面，沿用主计划的五条设计原则与全部组件资产。
> 实施记录按版本追加在本文 §10。

---

## 1. 任务目标与范围

把「专辑详情」从旧视觉全面迁到 M3E：桌面右侧详情面板（M3ESheet 壳已就位，**内容未动**）、
移动端全屏详情页（**完全未动**）、以及两处共用的 detail_kit 组件族。

| # | 决策 | 结论 |
|---|---|---|
| D0-1 | 改造深度 | 全量重设计，不做双皮肤/回滚开关（对齐主计划 D1） |
| D0-2 | 技术路线 | 自研 M3E 层组件拼装，零新依赖 |
| D0-3 | Hero 链 | 保留 1.99.29 已建的 `card-{id}` 链式形变，不再新增英雄时刻 |
| D0-4 | 动效 | 按 §7 规则：弹簧只跟离散交互，列表滚动路径零弹簧零滤镜 |

**不在范围内**：在线详情面板的结构性重做（其壳已 M3E、共享组件顺带受益，
单独版本再议，见 §6）。

---

## 2. 现状盘点

### 2.1 三个面

| 面 | 文件 | 现状 |
|---|---|---|
| 桌面右侧详情面板 | `detail_drawer.dart`（340 行） | 壳已换 `M3ESheet.side`（480dp 色调面），**内容仍是旧组件**：HikoEyebrowPill、旧 pill 按钮组、HikoInfoRow、HikoSegmentedTabs、HikoTrackRow |
| 移动端全屏详情页 | `album_detail_screen.dart`（514 行） | **完全未 M3E**：透明 AppBar + 全宽封面 → 自绘 meta 胶囊 → 分色胶囊 → 操作按钮 → 双 tab → 曲目/歌词；与桌面各有一套重复实现（`_buildMetaPill`/`_buildPersonPill`/`_buildTrackItem`） |
| 共享组件族 | `detail_kit.dart`（781 行，12 个组件） | 两端 + 在线多处消费；含功能性 InheritedWidget（`HikoDetailTextScale`/`HikoTagFontScope`，字号缩放设置依赖它们，**必须存活**） |

### 2.2 既有资产（直接可用）

`M3ESheet`（side/bottom）、`M3ECard`、`M3EButton`（4 变体 3 尺寸）、`M3EChip`、
`M3EList/ListItem`、`M3EPressable`、`M3EAppBar.small`、M3E 字阶/形状/海拔 token、
Hero 链（`card-{id}` / `drawer-{id}`）。

### 2.3 顽疾

1. **双实现漂移**：桌面/移动各一套 meta 胶囊与曲目行，改一处忘一处（1.94.0 就修过一次不同步）。
2. **胶囊过载**：一行里挤 4 种语义胶囊（分类/圈子/声优/DLsite 标签），无层级。
3. **信息行弱**：总时长/完成进度/标签/DLsite 行平铺无分组，扫读性差。

---

## 3. 详情页设计原则（继承主计划五原则 + 两条专属）

1. **层深用色阶**：页面 `surface`；信息组用 `surfaceContainerLow` 卡面（M3ECard）；
   当前曲目选中态 `secondaryContainer`。零描边、零模糊。
2. **字阶三档**：标题 `titleLarge` Emphasized；元数据 `labelMedium`；正文 `bodyMedium`。
   禁自造字号（现文件里 fontSize 9~22 共 14 档要收敛）。
3. **形状克制**：封面角 28（Hero 链终点）；卡面 16；胶囊 full；曲目行 12。
   嵌套内角 = 外角 − padding。
4. **一个主行动**：每屏只有一个 filled 主键「从头播放」；其余动作降级为
   outlined/图标钮——现在是 4 个等权重 pill，视觉上没有主次。
5. **弹簧不跟滚动**：仅曲目行按压、tab 切换、sheet 进出用弹簧。

---

## 4. 逐区方案

### 4.1 头部（封面 + 标题 + 元数据）

- 桌面（480 面板）：**封面 160dp 角 28 左浮 + 右侧标题列**两栏头部（§8.4 原案）——
  标题 `titleLarge` Emphasized（两行截断），下方 `labelMedium` 两行：声优 · RJ 码。
  Hero tag `drawer-{id}` 保持。
- 移动（视 D1 裁决）：全宽封面（角 0 贴边，或按 D1-B 改角 28 卡内嵌），
  标题 `headlineSmall` Emphasized。
- 眉题胶囊（`未分类 · ALBUM local-xxx ▾`）：改成 `M3EChip`（可点改分类，语义不变），
  ALBUM 内部 id 从展示层**移除**（对用户无意义的哈希串，截图可见 `local-a6c1d64d1c088c07`；
  RJ 码已在元数据行展示）。

### 4.2 分色胶囊（社团/声优）

保留分色（筛选语义强依赖紫/蓝），但基座换 `M3EPressable` + `M3EChip` 材质：
分色只留**左侧 4dp 色点 + 文字**（现状是整胶囊染色底，深色下刺眼）。
点选 = 筛选（既有行为），选中态 `secondaryContainer`。

### 4.3 操作区（主次分明）

- 主键：`M3EButton.filled`「从头播放」（40dp，弹簧按压）。
- 次键：收藏（❤ toggle，激活态 `errorContainer`）、评分（★ 未评分/已评分 N 星）、
  整理（↻）三个 `M3EButton.outlined`。
- 全部 40dp 同高一行，间距 8；桌面窄面板放不下时图标钮变体（40dp 圆 + tooltip）。

### 4.4 信息组（现 HikoInfoRow 平铺 → 分组卡面）

`M3ECard(surfaceContainerLow, 角 16)` 包裹三段信息，组内 56dp 行：

| 组 | 行 |
|---|---|
| 数据 | 总时长（N 首 · 时长）、完成进度（xxx%，附 4dp 细进度条）、评分（★×N / 未评分） |
| 标签 | DLsite 标签 `M3EChip` 流式（点选 = 回列表筛选，现行为） |
| 来源 | DLsite RJ · dlsiteTitle（有则显示） |

### 4.5 曲目列表 / 歌词（§8.4 已定规格的落地）

- 曲目行：`M3EList` 56dp 单行——序号 `labelMedium`、曲名 `bodyMedium`（超长展开保留）、
  时长右对齐 `labelMedium`；**当前曲目** `secondaryContainer` 角 16 + 播放态图标；
  按压弹簧 0.97。点行 = 播放该曲 + 跳播放页（现行为）。
- 双 tab：`M3EButtonGroup`（连通式分段，40dp）替换 HikoSegmentedTabs——
  「曲目列表 (N)」/「歌词字幕」；歌词 tab 保留 hasLyrics 徽标。
- 歌词视图：`DrawerLyricsView` 字阶换 `bodyMedium`、当前行 `bodyMedium Emphasized` +
  `primary` 色（现自造字号收敛进来）。

### 4.6 组件落点

| 旧 | 新 |
|---|---|
| hikoFilledPillStyle / hikoOutlinedPillStyle | `M3EButton`（pill 样式族删除） |
| HikoEyebrowPill | `M3EChip`（含分类切换交互） |
| HikoPersonPill | `M3EChip` + 色点变体（新 `M3EChip.dot` 或局部包装） |
| HikoInfoRow | 56dp M3EList 行（组卡内） |
| HikoSegmentedTabs + HikoTabButton | `M3EButtonGroup` |
| HikoTrackRow（桌面版） | `M3EList` 行 |
| HikoTagChip | `M3EChip`（blocked 态保留） |

`HikoDetailTextScale` / `HikoTagFontScope` / `HikoTagChip` 的在线消费者
（online_work_grid / album_card 等）**不动**：只删详情页私有用法，
组件本体保留到在线面重做时处理（§6）。

---

## 5. 移动端形态（D1 裁决点，见 §9）

- **D1-A（推荐）**：保留全屏详情页，M3E 化其内容（复用 §4 的同一套行组件）。
  全屏浏览曲目/歌词空间充裕，且 1.77 的胶囊筛选回传链路不动。
- **D1-B（原 §8.4 原案）**：改 `M3ESheet.bottom` 拖到全屏——交互更 M3E，
  但要重写手势 + 与「胶囊筛选回传」栈管理纠缠，回归面大。

无论 A/B，内容行组件**只有一套**（§4.6 的去重目标）。

---

## 6. 在线详情面板联动（不在本版，仅记录）

`online_detail_panel` 的壳已 M3E（1.99.30）；其内容是独立实现（OnlineDetailBody），
不消费 detail_kit 的详情行组件。若 §4 组件（分组卡/曲目行）成熟，
在线面板可作为下一个独立小版本复用——**本版不做**。

---

## 7. 版本切分

单版本 **1.99.34+147**（一个面、一套组件、无状态迁移，没必要拆两版）：

| 步骤 | 内容 |
|---|---|
| 1 | detail_kit 新增 M3E 行组件（分组卡/曲目行/tab 组/分色胶囊），旧组件保留供在线用 |
| 2 | 桌面 `detail_drawer` 内容全量换装 |
| 3 | 移动 `album_detail_screen` 换装（按 D1 裁决）+ 删私有重复实现 |
| 4 | 测试适配 + 新锁（见 §8）→ 双端构建 → 实跑截图 → Release |

---

## 8. 测试与验收

### 8.1 现有测试影响面

- 详情相关：locate_playing（Key 锁不随材质变）、overlay 测试（不涉详情）。
- `detail_kit` 组件若有直测先跑一遍确认红面。
- 移动端胶囊筛选回传链路（1.77/1.94.0）必须有测试锁住不被重写破坏。

### 8.2 新增回归锁

| 锁 | 断言 |
|---|---|
| 主行动唯一锁 | 详情头部区域 `M3EButton` filled 变体恰好 1 个（从头播放） |
| 曲目选中锁 | 当前播放曲目行挂 `secondaryContainer` 底 + 专用 Key |
| Hero 链锁 | 详情封面仍在 `card-{id}`（移动）/`drawer-{id}`（桌面）Hero 内 |
| 字号缩放锁 | `HikoDetailTextScale`/`HikoTagFontScope` 存活，textScale=1.3 时曲目行字号仍正确 |

### 8.3 每版固定动作

`flutter test` 记 passed/skipped；`flutter analyze` 0 新增 error；
双端构建；macOS 实跑截图核对；aapt2 版本核验；Release notes 只写用户视角。

---

## 9. 裁决记录

| # | 决策 | 结论 |
|---|---|---|
| D1 | 移动端形态 | **A：保留全屏页，M3E 化内容**（用户裁决 2026-10-25） |
| D2 | 操作区形态 | **主键 + 三次键**（从头播放 filled；收藏/评分/整理 outlined）（用户裁决） |
| D3 | 桌面头部两栏 | **两栏**：封面 160 角 28 + 右侧标题列（用户裁决） |
| D4 | ALBUM 内部 id 移除 | **从展示层移除**，数据层主键不变（用户裁决） |
| D5 | 在线面板范围 | 本版不做（已记录 §6） |

## 10. 实施记录

### 1.99.34（2026-10-25）

**落地**：detail_kit 追加 `HikoTrackRowM3E`（56dp/角 16/secondaryContainer 选中态，
旧 `HikoTrackRow` 保留供在线详情）与 `HikoDetailInfoRowM3E`（56dp + 4dp 进度条）；
`HikoEyebrowPill`（outlined chip，**内部 id 从展示层移除**，调用方只传分类名）与
`HikoPersonPill`（左侧 4dp 色点 + 文字、选中态 secondaryContainer）原位 M3E 化
（在线详情面板同步受益，结构不动）。
桌面 `detail_drawer`：两栏头部（封面 160 角 28 + 右侧 titleLargeEmphasized 标题列）、
操作区 M3EButton（1 filled + 3 outlined）、信息分组卡（总时长/完成进度/评分/DLsite）、
M3EButtonGroup 双 tab、`HikoTrackRowM3E` 曲目列表。
移动 `album_detail_screen`：同套组件换装（headlineSmallEmphasized 标题 + 元数据行
声优·RJ·时长 + 完成进度卡 + M3E 曲目行），**删除私有 `_buildMetaPill`/
`_buildPersonPill`/`_buildTab`/`_buildActionButtons` 重复实现**；胶囊筛选回传
（1.77 链路）与 Hero 链不变。`DrawerLyricsView` 内部字阶未动（其行高 metrics
是 LyricsAutoScroll 居中算法的承重件，改动风险大于收益——偏差记录）。

**验证**：`flutter test` **783 passed / 2 skipped**（新增 detail_m3e_test：主行动唯一锁、
D4 内部 id 不展示、480dp 无溢出、分组卡/分段锁）；analyze 45 条 0 error；
APK aapt2 147 / 1.99.34 三 ABI。
实跑备注：桌面抽屉目验因用户正在使用机器而中止（键盘自动化停用，Hiko 已静默退出），
以 480dp 组件测试 + Release 包交付，效果请以实机为准。

**交付**：版本 `1.99.34+147`；Release：`hiko-v1.99.34-macos.zip` + `hiko-v1.99.34-android.apk`。
