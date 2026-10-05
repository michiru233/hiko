# Hiko 模块契约与踩坑明细

> 2026-10-05 从 `MEMORY.md` 拆出（原文件超注入上限被截断）。
> 规则/发版流程见 `hiko-rules.md`；**本文只记「实测过的契约」与「已经踩过的坑」**。

## 在线模块（asmr.one / Kikoeru）契约（实测别猜）
- 排序白名单：create_date/release/dl_count/price/rate_average_2dp/review_count/id/rating，白名单外 400；order=id≈RJ 号。
- 列表项自带 tags `{id,name(zh-cn),i18n}` 与 vas `{id,name}`；**vas 的 id 当前被丢弃（List<String>），
  circle 是 circleId+circleName**。
- 标签筛选走 `/api/tags/{id}/works`（不换搜索端点，测试钉死）；取消回最新榜。
- **服务端无排除参数，黑名单/排除只能编进关键词**：`$-tag:名$`、`$tag:名$`、`$circle:名$`、`$va:名$` 等，
  拼错静默不筛。黑名单空时逐字节回退原请求。端点映射：浏览→/api/works、搜索→/api/search/{kw}、
  标签→/api/tags/{id}/works；有排除时全部改走 search。
- **pageSize 两套校验**：/api/works 系可到 500；playlist 三端点共用校验上限 100（`clampPlaylistPageSize`）。
- 封面唯一出口 `coverMainUrl(workId)`：type 白名单 240x240/main/sam，main=560×420。
- api.asmr.one/works/{id}=404，网页在 www.asmr.one。
- 黑名单：存 `AppSettings.blockedTags`（单键 JSON，按 id 判定）；长按菜单在标签胶囊上；屏蔽后立即重拉+回第 1 页
  （`reloadAfterBlock`）；自筛自屏要退出筛选。可点胶囊 hover 用 `HikoPillInteraction`（InkWell 墨迹被不透明底盖住）。
- TextPainter 预量必须传 `MediaQuery.textScalerOf(context)`。
- **胶囊标记布局不变量（1.97.1/1.97.2/1.99.5）**：筛选标记（标签/creator/黑名单/字幕/分级，
  `online_filter_marker.dart`）内部「文字 + ✕」的 Row，**文字必须 Flexible**（外层被 flex 挤压时非 flex 文字
  会让 ✕ 溢出屏幕）；**外层使用处也必须再包 Flexible**（1.97.1 重构丢过一次）。
  **✕ 热区 `_MarkerCloseButton.hitSize = 36`**（1.99.5 裁决 Q1=A）：旧热区仅 19×19，指尖偏 14px 就落空；
  承载热区的盒子必须同步变高（hit test 不命中父级尺寸之外），所以标记 Container 上下内边距为 0、
  左右统一 `left:4/right:0`。**移动端激活的筛选标记独占一行**（第二行下方），1.99.5 起由 `Row` 改 **`Wrap`**，
  maxTextWidth 由屏宽推导 `(屏宽−140).clamp(96,320)`；桌面保持内联。回归锁 `test/ui/online_filter_marker_test.dart`。
- 账号：JWT 存 `hiko-online-token`，不进 AppSettings；令牌失效仍 200 只看字段；写操作先本地后校准；
  收藏差分 `planPlaylistDiff`；自测只在临时歌单。
- 在线外观：常量单一来源 `settings_store` 范围常量（tagFontSize 8–18 默认 11 全局、card/detail 倍率 0.75–1.60、
  trackTitleFontSize 10–20 默认 12 绝对值不乘详情倍率）+ 列数 0/3–8 档位；设置页「在线外观」与在线页 Aa chip
  两入口共用 `OnlineFontSliderRow`（带重置）；**白名单归一化已改 clamp**。卡面高度预算 =
  `onlineCardTextBlockHeight`/`onlineCardTagRowHeight` 纯函数，行高写死 1.3/1.2。详情面板 `HikoDetailTextScale`
  （专辑标题 22、副标题 12）；曲目标题走独立旋钮（`HikoTrackRow.titleFontSize` 可空，本地传 null 保持 12×scale）。
  每页条数落盘 `hiko-online-page-size`（20/60/100），移动端分页条隐藏该 chip、页码半径 ±1。
- **声优/社团筛选（1.97.0；取消语义 1.99.19 改）**：`OnlineCreatorFilter{va|circle,name}`，机制 =
  `$va:名$`/`$circle:名$` 关键词（`online_blacklist.dart` 的 `vaIncludeTerm`/`circleIncludeTerm`）；
  入口 = 详情页胶囊菜单（浏览页+收藏页）；**`selectCreator` 刻意保留来源与搜索词**（= 这批关键词 ∩ 这位），
  creator 正交保留于翻页/排序/刷新，`applyPreset`/`search`/`selectTag` 清除。
  **取消走 `clearCreator()`**（2026-10-05 裁决 Q4=A）：只摘掉这一维、来源/搜索词/排序/标签原样保留；
  不再走 `applyPreset(latestPreset)`（那会把来源与搜索词一起吃掉）。
- **⚠️ `applyPreset` 的早退必须算上「它会清掉的东西」（1.99.19）**：`selectCreator` 不改 source/sort，
  于是「最新榜 + 社团筛选」正好命中 `source==browse && sort==preset && works.isNotEmpty` 三条 ——
  旧判断会把「取消筛选」与「点预设 chip」静默吞掉（实机症状：✕ 点不了）。
  回归锁 `test/data/online_creator_cancel_test.dart`（**必须让 works 非空**：旧 harness 里 HTTP 必失败、
  works 恒空，这颗雷一直没被测到）。
- **字幕筛选（1.99.5 裁决 Q3=B）**：`subtitle=1` 是**查询参数**，实测在 `/api/works`、`/api/tags/{id}/works`、
  `/api/search/{kw}` 三处都生效。任何来源都可用且**正交保留**，必须有可关闭标记兜底（不许看不见的筛选）。
- **分级筛选（1.99.5 裁决 Q4=B）**：`OnlineAgeCategory{adult'R18', r15'R15', general'全年龄'}`，
  `age_category_string` 取值完备。UI = 三个复选框放进排序下拉（`online_sort_menu.dart`）；
  勾 1 个 → `$age:key$`，勾 2 个 → **`$-age:未勾的那个$`**，全勾/全不勾 = 不筛。
  **⚠️ `$age:A$ $age:B$` 之间是 AND 不是 OR**。「显示两个」只能用排除式。
  词形 `ageIncludeTerm`/`ageExclusionTerm`。分级词与 creator 词合流成 `filterTerms`，任一非空即全部改走 search 端点。
- **⚠️ 排序下拉不要用 `PopupMenuItem(enabled: false)` 来「留住菜单」**：M3 下会把 DefaultTextStyle 换成
  onSurface@38% 灰 + `Semantics(enabled: false)`。正确做法见 `_AgeFilterItem`：继承 `PopupMenuItemState`
  只覆写 `handleTap`（不 `Navigator.pop`）；复选框用 `IgnorePointer` 包住当纯指示器，整行由父类 InkWell 接住。
  菜单绝对上限 400。**`PopupMenuItem.child` 是必填**；`createState` 的返回类型是
  `PopupMenuItemState<T, PopupMenuItem<T>>`。
- **在线返回键（1.99.5 裁决 Q2=B）**：`home_screen.dart` 的 `_handleOnlineBack({allowExit})` ——
  安卓返回键 true / 桌面 Esc `isMobile`。`在线` 视图只清筛选回最新榜（干净态且 allowExit 才 `SystemNavigator.pop`），
  `在线收藏` 退回 `在线`，其它视图返回 false 交回旧兜底。判定用 `hasActiveFilter` / `isAtOnlineHome`。
- **「Aa」三合一菜单（1.99.20 裁决 Q1=B/Q2=A/Q3=A/Q4=A/Q5=A）**：
  - **移动端在线视图（`在线` / `在线收藏`）顶栏整行收起**：`home_screen.dart` 的 `_buildTopbar` 开头
    `if (isMobile && _isOnlineView) return const SizedBox.shrink();` —— 那一排在移动端只有 4 个图标按钮
    （定位当前播放 / 切换主题 / 隐私模糊 / 随机播放），其中**「定位当前播放」与「随机播放」都只作用于本地库**
    （随机播放 = 盲选一张本地专辑），在线页毫无意义却各占一格。桌面端宽度富裕，顶栏原样保留。
  - `OnlineAaMenu`（`online_appearance.dart`）三项 = **在线外观**（落回原 `showOnlineAppearanceDialog`）+
    分隔线 + **防社死** + **外观切换**。两端统一 `PopupMenu` 下拉；标签仍写「Aa」（不换图标）。
    两个开关是**开关式**：`_AaMenuToggleItem` 覆写 `handleTap` **不 `Navigator.pop`**、条目右侧显示当前状态
    （已开启/已关闭、深色/浅色），能连着把两个都调完（同 `online_sort_menu.dart` 的 `_AgeFilterItem` 手法）。
  - **⚠️ 「在线收藏」页原先没有任何外观入口，`Aa` 只长在 `OnlineScreen` 里** —— 顶栏一收，
    手机上**防社死在该页就彻底够不着**（它只有顶栏按钮这一个入口：⌘⇧H 手机按不出来、设置页里也没有）；
    所以 1.99.20 顺带在 `OnlineFavoritesScreen._buildHeader` 的状态行右侧补了一个 `OnlineAaMenu`。
    **未登录且非离线分区时收藏页只有登录引导、不走 `_buildHeader`**，也就没有 Aa（那一屏没有封面墙，防社死无对象）；
    测试要造「已登录」假账号才会渲染出头部（见 `test/ui/online_aa_menu_test.dart` 的 `_LoggedInAccount`）。
  - **⚠️ 防社死的开关逻辑只有一份实现**：`online_appearance.dart` 的 `togglePrivacyBlur(WidgetRef)`，
    顶栏按钮 / ⌘⇧H / Aa 菜单三处共用。**副作用「开启时隐藏桌面歌词」不能漏** —— 漏了就等于把防社死
    开了个口子（浮动歌词裸奔曲名/台词）。
- **播放页「跳详情」的落栈（1.99.19 裁决 Q2=A）**：移动端跳过去的那一次必须要求「列表以上不留历史」——
  `detail_jump_requests.dart` 的 `pushDetailAboveList(nav, route)`（= `pushAndRemoveUntil(r.isFirst)`），
  否则详情页叠详情页、一次返回退不到列表。**播放页仍由 `_openAlbumDetail` 自己 pop**（先 pop 再发请求）：
  它的退场动画照常播（`pushAndRemoveUntil` 会跳过正在 popping 的条目），桌面路径零改动。
  列表点卡片、详情页之间跳语言版本（1.99.2 要「返回回原作品」）都保持普通压栈。

## 在线卡片与网格（1.99.21：胶囊化 + 瀑布流）
- **卡片结构**（`online_screen.dart` 的 `OnlineWorkCard`）：封面 `AspectRatio(1)`（`Expanded` 已删）→
  标题 13/w700（`kOnlineCardTitleFontSize`，与本地卡面同款）→ 四组 `Wrap`：
  ① 艺术家（`work.vas` **逐个一枚**）② 社团（`circleName`）③ 作品号 + 时长 + 下载量 ④ 标签（全部）。
  取不到的元数据**整枚不出现**，不留占位。（在线数据结构里没有 genre，所以没有「分类」胶囊。）
- **六类胶囊配色**（`online_card_kit.dart` 的 `onlinePillColors(kind, isDark:, scheme:)`）：
  艺术家蓝 / 社团琥珀金 / 作品号 `scheme.primary` 实底反白加粗 / 时长中性灰 / 下载量玫红 / 标签青
  （`HikoTagChip`）。语法统一「浅底 + 同色相深字」，暗色主题降 alpha 不换色相。
  抽成**公开纯函数**是为了让「颜色必须互相区分」可测（见 `test/ui/online_work_card_test.dart`）。
- **时长统一 `formatDuration`**（`2小时25分钟`），**不用** `OnlineWork.durationLabel`（`2:25:00` 钟表写法）。
- **标签全部展示、自然换行**：`+N` 截断、`_CardTagRow`、`_chipWidth`（TextPainter 量宽）已整体删除。
- **⚠️ 高度预算函数已不存在**：`onlineCardTextBlockHeight` / `onlineCardTagRowHeight` 随 `SliverGrid`
  一起删了。它们存在的唯一理由是「网格 `mainAxisExtent` 整屏统一」，而「标签只能单行 + `+N`」
  又是高度固定逼出来的 —— 瀑布流一上，这两套复杂度是同源消失。改卡片内部间距不要再回头找它们。
- **两种网格都在 `online_work_grid.dart`**：box 形态 `MasonryGridView.count`、sliver 形态
  `SliverMasonryGrid.count`，共用顶层 `_buildWorkCard`。列数仍走 `_resolveColumns`
  （自动档 = 桌面「至少 200px 一张」、移动端 2 列；900 宽 = 3 列）——
  **别换成 `WithMaxCrossAxisExtent`**：它按 `ceil` 算，900 宽会变 4 列，自动档观感当场变。
- **卡片自己读 `onlineCardTextScale`**（`ref.watch(settingsProvider.select(...))`），网格不再传参 ——
  网格算卡高这件事已经不存在，留着「读出来传进去」只是多一处能忘传的接口。

## 导航栏可见配置（1.99.4 / 1.99.6）
- 一级导航（桌面侧栏 + 安卓底栏）**两端共用一份** `AppSettings.navViews`（有序可见列表，单键 JSON `hiko-nav-views`）。
  列表内 = 显示且按此排序，不在列表 = 隐藏。
- 全集 `AppSettings.navViewsAll`（**7 项**）= 本地音声 / 最近添加 / 最近播放 / 收藏夹 / 在线 / 在线收藏 / 统计；
  `navViewHome = '本地音声'` 为根视图**永久显示**。空/坏数据回退全集（老用户无此键 = 全显示）。
  **`'正在播放'` 已于 1.99.6 移出白名单**（改由安卓底栏固定格承载），存量配置里带着它会被白名单过滤**静默丢弃 = 自动迁移**。
- 移动端底栏**不用 `BottomNavigationBar`**（>5 项必挤压溢出），是 `lib/ui/widgets/mobile_bottom_nav.dart` 的公开
  `MobileBottomNav`：`(项数+2)×76 ≤ 可用宽度` 则均分，否则整行横向滚动；**末尾固定两格「正在播放」「设置」**，
  不占 navViews 表、用户关不掉。**label 直接用视图名**（'本地音声' / '在线' …），不是短名。
- 当前视图被隐藏 → build 开头立即回退 `navViews.first`（只对 7 个内置视图名生效）。
- 设置页「导航栏」二级页：`ReorderableListView` + **`onReorderItem`**（v3.41 起 `onReorder` 已废弃，用旧的会新增 lint）
  + 开关 + 下方「已隐藏」区恢复。
- **「全部音声」已改名「本地音声」**：它是视图 key 与显示文案同一字符串，改名必须 lib/test/README 一起替换。

## 安卓播放栏手势与底栏固定格（1.99.6）
- **从左往右划掉播放栏 = 收起 + 暂停**（只做移动端）。`player_bar.dart` 的 `onDismiss` 为 null 时**不套** `Dismissible`
  （桌面路径逐字节不变）；套上时 `direction: startToEnd` + `dismissThresholds: {startToEnd: 0.35}` +
  **`resizeDuration: null`**（源码 `_startResizeAnimation` 只在 `== null` 时立即回调 `onDismissed`；走 zero 仍要开控制器，
  且 build 会进 `_resizeAnimation != null` 分支断言「dismissed but still in the tree」）。
- **栏内三个 Slider（进度/增益/倍速）天然排除**：手势竞技场最内层优先，滑杆赢；**不要**设 `eagerGestureRecognizer`。
  已用测试钉死（同时断言 `seekCalls > 0`，否则用例是空过的）。
- **还原判据 = 任何一次「暂停 → 播放」跳变**（点歌/播放键/系统媒体键/通知栏/耳机线控）。实现是
  `ref.listen<bool>(playbackProvider.select((s) => s.playing), (prev, next) ...)` —— **必须用 listen 的 prev/next**，
  `ref.watch` 只给当前值。进全屏播放页本身**不**还原。
- `playerBarVisible = !isMobile || (album != null && !_playerBarDismissed)` 是**唯一判据**：播放栏的 `if` 与
  详情抽屉底部留白（`118 : 60`）都必须用它（否则划掉后抽屉下留 58px 空洞）。
- **`_isInPlayerBar(globalPos)` 必须显式让位**：包裹整页的 1.54 左边缘呼出抽屉 `Listener` 是播放栏的**祖先**，
  raw pointer 不进手势竞技场、**永远**会送到它那儿。用 `GlobalKey` + `renderBox.localToGlobal(Offset.zero) & size` 判矩形。
- 底栏固定格「正在播放」→ 全屏播放页；`playerEnabled = album != null` 控制置灰，**禁用格照旧占位**（不跳位）。
- **`HomeScreen(debugMobileLayout)`**：`@visibleForTesting` 可选参数，唯一用途是在 macOS 宿主上打开移动布局。
  **生产代码永不传它**；配它做整页移动测试时画布要给到 900 宽（宿主是 macOS，播放栏会多一个桌面歌词按钮，真机宽度会溢出）。

## 测试坑（踩过的）
- 同一 testWidgets 两次 pumpWidget 换 overrides 第二次不生效；ticker 首帧 elapsed=0，ensureVisible 后 pump 两次。
- **widget 测试里凡是会写到设置的交互必须 `SharedPreferences.setMockInitialValues({})`**，
  否则 `getInstance()` 永不返回、测试**挂死**（不是失败）。
- 设置对话框新增分类会改变既有分类可见性 → 按文案点设置项的测试要 `ensureVisible` 后再 tap。
- **测弹出菜单要调 `tester.view.physicalSize`**：默认 600px 高 → 菜单 `maxHeight=45%×600=270`，
  折线以下的条目 `tap()` 会**落在 ModalBarrier 上把菜单关掉**，报错却像「找不到控件」。
- **`tap(find.byType(Checkbox))` 被 `IgnorePointer` 包着时必报 hit-test warning**，加 `warnIfMissed: false`。
- **`pumpAndSettle` 撞上无限动画会超时**（全屏播放页播放中的唱片、在线详情页拉不到数据时的加载圈）。
  点过它之后只能用有界 pump（3×300ms / 8×120ms）；`playing: false` 时唱片不转，可放心 settle。
- **假控制器子类化 `PlaybackController` 只能写 `_Fake(super._ref)`**（基类构造参数名私有）；
  `container.read(playbackProvider.notifier)` 的静态类型是基类，要 `as _Fake`。
- **`tester.pageBack()` 依赖 tooltip 'Back'**：AppBar 的前导若不是标准 `BackButton` 就找不到；
  模拟系统返回用 `await tester.binding.handlePopRoute()`（贴近安卓返回键/边缘手势）。
- **被不透明路由完全覆盖的页面不在 finder 里**（`find.byType` 默认 `skipOffstage: true`）——
  判「栈里还有没有某页」要在 pop 之后断言。
- 在线详情页的测试：`onlineDetailProvider(workId).overrideWith(...)` 挡掉网络
  （flutter_test 里所有 HTTP 都 400，未捕获的 `KikoeruException` 会让用例失败）。
- **回归锁必须摘掉修复验证会红**（改动落栈/筛选这类语义时逐条验一遍）。

## 玻璃材质门面（1.99.22 接入：liquid_glass_widgets；1.99.23 修移动端卡顿）

- 依赖 `liquid_glass_widgets: ^1.9.0`：零三方运行时依赖，自带 5 个 `.frag`，**无需任何
  Xcode / Gradle / CocoaPods 改动**，会自动打进双端产物到
  `flutter_assets/packages/liquid_glass_widgets/shaders/`（已核验 macOS 与 APK 均在）。
- **业务代码只 import `lib/ui/widgets/hiko_glass.dart`**，不要直接依赖库 API（该库 1.0.0→1.9.0
  发了 21 版，breaking change 集中在早期；门面就是为了把升级/换库收敛在一个文件）。
- **两档契约**（`HikoGlassTier`，由公开纯函数 `hikoGlassQuality` / `hikoGlassUseOwnLayer` /
  **`hikoGlassBlur`** 决定）：

  | | `surface` | `tile` |
  |---|---|---|
  | 质量 | `premium` | `standard` |
  | 图层 | `useOwnLayer: true` | `false` |
  | **`blur`** | **20** | **0** |
  | 用在哪 | 静止浮层 / 栏 | 滚动长列表 |

- 浮层**必须** `useOwnLayer: true`：premium 档若既不自建图层、又无 `LiquidGlassLayer` 祖先，
  调试构建会命中 `LiquidGlassBlendGroup` 的断言。项目**不需要** `LiquidGlassWidgets.wrap()`
  （源码注释明写 optional，只在用 `theme:` / `adaptiveQuality:` 时才需要），也不需要改 app root；
  `initialize()` 只是预热 shader。
- tile **必须** `useOwnLayer: false` **且 `blur = 0`**：逐卡自建图层吃显存；
  **而 `blur > 0` 才是真正的性能杀手** —— `LightweightLiquidGlass.paint()` 在
  `blurSigma > 0` 时无条件 `pushLayer(BackdropFilterLayer)`（sigma 高斯 + 饱和矩阵），
  且 `alwaysNeedsCompositing` 随之变 true，**每个实例**都是一次逐帧实时背景模糊 + 独立合成层。
  置 0 走 `_paintGlassContent` 直画分支：不建层、不模糊，但程序化边缘光 / Fresnel / 立体斜面全保留。
- ⚠️ **`backgroundKey` ≠ 性能开关（1.99.22 我记错了，是当天卡顿的成因）**：它只管「采样 ticker」，
  用于把**静止**背景采样一次复用；不传只是不启动该 ticker，**不等于不捕获背景**。真正的开关是 `blur`。
  修法：tile 档沿用 surface 档的 `blur = 20` = 每张卡一次 sigma20 实时模糊，必须按档位取值
  （门面里是 `blur ?? hikoGlassBlur(tier)`，显式传 `blur:` 仍可覆盖，给静态胶囊微调用）。
- `animationDuration` 对 tint / 描边色 / 描边宽 / **阴影列表**做隐式补间
  （`_ShadowListTween` + `BoxShadow.lerpList`，后者已处理项数不一致）。专辑卡与在线卡都靠它保住
  300ms 选中过渡——**门面是无状态的，忘传就静默退化成瞬变**。
- `solid: true` = 实心圆角矩形、不跑着色器，给「常态玻璃 / 激活实心主色」的双态控件
  （首页标签 chip、多选按钮）。激活态本该实心，做成玻璃反而透背景、削弱选中力度。
- **在 `flutter_test` 里玻璃会自动降级成普通子树**（非 Impeller 时 `LiquidGlassBlendGroup` 直接透传，
  `GlassContainer` 走 `LightweightLiquidGlass`），所以玻璃放进被测试覆盖的播放栏/底栏**不会打穿基线**
  ——已用临时探针实测（三条全过、`takeException()` 全 null）后才敢替换。
  反过来说：**两档搞混、补间失效、blur 漏喂默认值，在测试里渲染结果完全一样、看不出来**，
  只能靠 `test/ui/hiko_glass_test.dart` 的纯函数 / 参数锁（1.99.23 补了 blur 那三条，
  其中两条直接断言渲染出来的 `LiquidGlassSettings.blur`）。
- 全项目真 `BackdropFilter` 玻璃只有 5 处：播放栏、移动端底栏、右键菜单、在线详情关闭钮、
  详情抽屉关闭钮。**1.99.23 起滚动列表里的玻璃卡有两处：本地专辑卡 + 在线卡**（之前在线卡是
  纯透明 `Container`，只有选中态一条描边，摆在专辑卡旁边明显是两种材质，用户实机指出）；
  首页那几处 `*GlassCard` token 是筛选组 / 标签 chip / 多选 / 排序的**静态工具栏胶囊**，不是列表卡。
- `GlassAdaptiveScope` 把 **Windows / Linux / Web 静态封顶在 `standard` 档**，只有
  Metal(macOS/iOS) 与 Vulkan(Android) 走满血多 pass 管线 → 三端观感不均，Windows 会明显弱一档。
- 旧的 `lib/ui/widgets/glass_container.dart` 已删（换完后 lib+test 零引用）。
  `HikoColors.*Glass*` 那 10 个 token 保留，仍是门面的取色来源。
- 迁移旧锁的坑：`test/ui/locate_playing_test.dart` 的 `glowCard` 原靠
  `w is AnimatedContainer && w.decoration.border != null` 定位，描边搬到门面后静默失效但**不会报错**
  （谓词只是不再匹配 → 断言 `findsOneWidget` 才失败）。已改为
  `w is HikoGlass && w.borderWidth == 1.5 && boxShadow 含 spreadRadius == 2`（双因子，比原来更严）。

## 遗留待裁决（摘要）
1.42 tag 颜色对比度；1.53 Android 整理入口语义/TALB 分组；1.54 右滑手势排除区/原位替换不重扫；
1.87 U+30FB 拆名误伤（已接受）；1.91–1.99 多项 Android 未实机验证（曲目行点击行为、hover 缺失、
分页条/菜单/对话框窄屏、滑杆手感、creator 菜单触屏、分页条精简后观感、8 列观感、
**1.99.5 的 36px 热区手感 / 分级复选框点选 / 移动端 4 标记 Wrap 排布**、**1.99.19 的跳详情落栈实机验证**、
**1.99.20 的移动端顶栏收起后观感 / Aa 菜单触屏手感 / 收藏页 Aa 位置**、
**1.99.21 的胶囊配色实机观感 / 瀑布流长列表滚动性能 / 窄屏四组胶囊换行密度**）；
**1.99.22 的 5 处浮层/栏玻璃观感 / 静态小胶囊（标签、多选、排序）上满血档是否发糊或拥挤 /
专辑卡在长网格滚动时的帧率（本版唯一有性能风险处）**）；
1.96 卡面单行标题封面偏高是否统一（未裁决）。1.95 明确不做：黑名单总开关/手动输入/按社团声优屏蔽。
（`hiko/hiko-v1.100.0-*` 遗留副本已不存在；2026-10-05 复查 `hiko/` 已无本地封包副本，1.99.17–1.99.19 均已核对远端资产后清理。）
