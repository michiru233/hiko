# Hiko M3E 收口计划（2026-10-31）

> 读者：接手 Hiko 的 agent + 用户审阅。
> 起点：`main` = `43d54b3`（v1.99.59），基线 `947 passed / 2 skipped`、`analyze 42 issues / 0 error`。
> 目标：把设计系统里**最后的组件缺位**补齐，每补一块发一版，互不阻塞。

## 0. 顺序与结论

| 版本 | 内容 | 为什么排这个位置 |
|---|---|---|
| **1.99.60** | `M3ETextField` 收口（11 处）+ 小件（加载环 2、分割线 2） | 输入框是**唯一完全没有 M3E 覆盖的控件族**；补完之后「新页面不用再手写 Material 控件」这句话才成立 |
| ~~1.99.61~~ | ~~菜单收口~~ → **已于 1.99.40 完成**，作废 | 核实发现 `PopupMenuButton(` / `showMenu(` 全仓为 0，12 处 `M3EMenu` |
| **1.99.61**（改） | 底部弹层材质统一（「更多」面板 → `M3ESheet(bottom)`）+ 统计页自适应 | 「更多」面板手写了一份与 `M3ESheet` 重复的材质；统计页 48dp 横向 padding 在 360dp 上挤三张卡 |
| **1.99.62**（改） | 库备份轮转（`library.json` 滚动快照 + 恢复入口） | 唯一一个**功能**项，不是样式项；`library.json` 现在只有原子写、没有历史快照，误删不可回滚 |

每版独立 bump patch（`1.99.60+173` 起，build 位独立递增）、独立 `gh release`、独立 plan 章节与提交。

## 1. 现状实测（HEAD `43d54b3`）

| 控件族 | M3E 覆盖 | 剩余缺口 |
|---|---|---|
| 按钮 / 图标按钮 / FAB / 按钮组 | ✅ | — |
| 开关 / 复选 / 滑杆 / 下拉 / 搜索栏 / Chip | ✅ | — |
| **输入框** | ❌ | `TextField(` **11 处**，三种写法各写一遍 |
| 菜单 | ✅（1.99.40） | `PopupMenuButton` **0**、`showMenu` **0**、12 处 `M3EMenu`；仅 `context_menu.dart` 是自绘实现但规格已一致 |
| 加载 | 组件有，未全量采用 | `CircularProgressIndicator` **2** |
| 分割线 | ❌ | 裸 `Divider` **2**（其中一处还在用旧的 `theme.dividerColor`） |
| 底部弹层 | 组件有，未全量采用 | `showModalBottomSheet` **2**，其中「更多」面板手写了一份与 `M3ESheet` 重复的材质 |

## 2. 1.99.60：`M3ETextField` + 小件

### 2.1 11 处 `TextField(` 的三种写法

**A. 行内无标签框**（设置行 trailing、翻页跳转）

| 位置 | 现状 |
|---|---|
| `hiko/lib/ui/widgets/settings_dialog.dart:1032` 在线服务器 | 220dp 宽、`OutlineInputBorder` + `M3EShape.sm`、`isDense`、`contentPadding 10/8`、`labelSmall` |
| `hiko/lib/ui/widgets/settings_dialog.dart:1313` 刮削代理 | 同上（复制粘贴的第二份） |
| `hiko/lib/ui/widgets/online_work_grid.dart:491` 跳页 | 54×28、居中、`digitsOnly`、`contentPadding 4`、`hintText '跳页'` |

**B. 对话框浮动标签框**

| 位置 | 现状 |
|---|---|
| `hiko/lib/ui/widgets/category_dialog.dart:89` 分类名称 | `labelText` + `hintText` + **`errorText`（自定义校验态）** |
| `hiko/lib/ui/widgets/online_account_dialogs.dart:91` 用户名 | `labelText` + `isDense` + `bodySmall` |
| `hiko/lib/ui/widgets/online_account_dialogs.dart:104` 密码 | 同上 + `obscureText` + `onSubmitted` |
| `hiko/lib/ui/widgets/online_account_dialogs.dart:505` 歌单名 | 同上 + `maxLength: 40` |
| `hiko/lib/ui/screens/home_screen.dart:2183/2188/2192` 标题/声优/社团 | 只剩 `labelText`，连边框样式都没写（吃全局 `InputDecorationTheme`） |

**C. 对话框内搜索**（`hiko/lib/ui/screens/home_screen.dart:2101` 搜索标签）：`prefixIcon` + 无边框 + `isDense`。

### 2.2 API

```dart
class M3ETextField extends StatelessWidget {
  const M3ETextField({
    super.key,
    required this.controller,
    this.label,        // 框上方 labelSmall（不进框浮动）
    this.hintText,
    this.helperText,
    this.errorText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.enabled = true,
    this.autofocus = false,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.inputFormatters,
    this.textAlign = TextAlign.start,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.size = M3ETextFieldSize.compact,
    this.width,        // 行内场景（220 / 54）
  });
}

enum M3ETextFieldSize { compact, regular }
```

**壳的规格**

- 底：`surfaceContainerHigh` 填充、无描边（Material 的 outline 框在深色主题里发灰，是现在「三种规格」观感的来源）
- 圆角：`compact` 用 `M3EShape.sm`(8)、`regular` 用 `M3EShape.md`(12)
- focus：1.5dp `primary` 描边（`AnimatedContainer`，时长走具名常量，样式账本锁放行「具名声明」）
- 错误：`error` 描边 + 下方 `bodySmall` `errorText`（`category_dialog` 现在就靠这个，不能丢）
- 文字：`compact` → `labelSmall`（高 32）、`regular` → `bodySmall`（高 40）；光标 `primary`
- 标签**框上方**而不是框内浮动：行高固定，`_SettingRow` 的 72dp 双行不会被浮动标签挤跳
- 内部仍是 `TextField`：IME / 选区 / 快捷键 / 无障碍都交框架，只统一壳与排版——与 `M3ESearchBar` 同一策略（见该文件头注释）
- `M3ESearchBar` **不动**：56 全圆 + 前置搜索图标是搜索栏语义，不是表单输入框

### 2.3 迁移映射

| 行内 / 表单 | 换成 |
|---|---|
| A 三处 | `M3ETextField(controller: …, hintText: …, size: compact, width: 220 / 54)` |
| B 八处 | `M3ETextField(controller: …, label: '…', size: regular)`（密码加 `obscureText`，歌单名加 `maxLength`） |
| C 一处 | `M3ETextField(hintText: '搜索标签', prefixIcon: Icon(Icons.search_rounded), size: regular)` |

注意：`settings_dialog` 那两处现在是**每次 build 都 new 一个 `TextEditingController`**（`TextEditingController(text: settings.onlineServer)`）。顺手改成 `late final` 并只在外部值变化时同步，避免打字时光标被重置——这是真实缺陷，不是风格问题。

### 2.4 小件

- `CircularProgressIndicator(strokeWidth: 2)` **2 处** → `M3ELoadingIndicator(size: 16 / 22)`（`online_screen:932` 搜索建议、`online_detail_panel:208` 详情加载）
- 新增 `M3EDivider`（`height: 1`、`outlineVariant`、可选 `indent` / `endIndent`）→ 换 `online_screen:457`（顺带把旧的 `theme.dividerColor@0.4` 埋掉）与 `offline_download_dialog:179`

### 2.5 验收

- `grep -rn 'TextField(' hiko/lib --include=*.dart | grep -v 'lib/ui/m3e/'` == **0**
- `flutter analyze` 保持 42 条 / 0 error（不多一条）；`flutter test` ≥ 947 passed / 2 skipped
- 新增 `hiko/test/ui/m3e/m3e_text_field_test.dart`：高度（compact 32 / regular 40）、标签在框上方、focus 描边出现、错误态文案、`obscureText` 生效、`onSubmitted` 触发
- 样式账本锁（`test/ui/style_ledger_lock_test.dart`）**不改**就能过：新组件在 `lib/ui/m3e/` 内，调用点不引入字面圆角/字号/时长

## 3. 1.99.61：底部弹层材质统一 + 统计页自适应

> **原计划「菜单收口」作废**（2026-10-31 实地核实）：`grep -rn "PopupMenuButton(" hiko/lib` = **0**、
> `showMenu(` = **0**、`MenuAnchor(` 只剩 `m3e_menu.dart:66`（M3EMenu 自己的引擎），
> `PopupMenuItem` 只出现在注释里。仓库已有 **12 处 `M3EMenu(` 调用点**，且
> `plan-hiko-flutter-rewrite.md:4138` 记着「1.99.40：M3EMenu 落地 + 六处菜单统一」——
> 这一版在 1.99.40 就做完了，§0 表里的「`PopupMenuButton` 6 + `MenuAnchor` 1」是把注释算进去的旧计数。
> 唯一剩下的自绘菜单 `lib/ui/widgets/context_menu.dart`（`showHikoContextMenu`，2 个调用点）
> 行规格 48dp / `M3EShape.xs` / `labelLarge` 已与 `M3EMenu` 一致，去重属纯重构（界面零变化、
> 要自己补 `FocusTraversal`），**不作**，留作将来的 `chore:`。

本版实际内容：

- **「更多」面板**（`hiko/lib/ui/screens/home_screen.dart:928` `_openMoreSheet`）：
  现在手写 `backgroundColor: surfaceContainerLow` + `RoundedRectangleBorder(Radius.circular(M3EShape.xl))`，
  与 `M3ESheet(variant: bottom)` 的材质定义重复（改一处会漏另一处）→ 改成
  `backgroundColor: Colors.transparent` + `M3ESheet(variant: M3ESheetVariant.bottom)` 包内容。
- **曲目列表 sheet**（`fullscreen_player_screen:1236`）：已经是 `transparent` + `M3ESheet(bottom)`，
  只核对不改（这个就是「正确写法」的样板）。
- **统计页**（`hiko/lib/ui/widgets/stats_view.dart`，179 行）：
  - 横向 padding 硬编码 `48` —— 360dp 手机上三张卡只剩 264dp 宽，`累计收听` 的长文本（如「12小时34分钟」）
    在 `titleMedium` 下溢出。改成 `LayoutBuilder`：`maxWidth >= 720` 用 48 / 否则 16。
  - 三张卡固定 `Row` + `Expanded` → 宽屏三列、窄屏竖排（`Column`），卡片本身抽出不带 `Expanded` 的 widget。
  - 三颗状态 chip 固定 `Row`（`听完 N` / `听过 N` / `未听 N`）→ `Wrap(spacing: 8, runSpacing: 8)`。
- 验收：`test/ui/business_surface_style_lock_test.dart` 的三条统计断言继续成立（语义色、无自持色值、
  `radius: M3EShape.lg`）；新增统计页在 360dp / 720dp 两档的溢出自查。

## 4. 1.99.62：库备份轮转

- `library_store.save()` 写完 `library.json` 后，把上一份内容写进 `backups/library-YYYYMMDD-HHmmss.json`（滚动保留最近 5 份、总量上限 50 MB）
- 危险操作前额外留一份：`clearAll()`、备份导入（`restoreToPrefs`）、全量扫描
- 恢复入口：设置 → 数据与维护 → 「历史快照」（列时间 + 张数 + 大小，点一行二次确认后恢复）
- 测试：临时目录 + FakeAsync 下不能用真实 I/O（`testWidgets` 里会挂死），因此**逻辑走纯函数 + `Directory` 注入**，widget 测试只测列表渲染

## 6. 风险与已知偏离

- 1.99.60 会动 11 个调用点，其中 `home_screen` 的编辑作品对话框没有专属测试——靠「TextField 归零」+ 手动构造的两条对话框测试兜底
- `settings_dialog` 的 controller 生命周期修复属于顺手修的真实缺陷，写进提交正文
- 若某处 `TextField` 需要 `InputDecoration` 的独特能力（如 `maxLength` 计数器、`prefixIcon` 动画），先在 `M3ETextField` 加参数，**不在调用点开旁路**

## 7. 待裁决（不阻塞 1.99.60）

- Q5 歌词字阶（行高 `45 × lyricsFontScale` 是承重值）
- Q6 Windows 实机验收（需要 Win 机器）
- APK「没有签名文件」报障（需要机型 / Android 版本 / 安装方式 / 报错原文）
- `.memsearch/` 是否入 `.gitignore`；旧 Electron+Capacitor 原型（86 文件）是否单开 `chore:` 版清掉

## 8. 实施记录

### 1.99.60（2026-10-31，已发布 `v1.99.60`）

- ✅ `M3ETextField` + `M3ETextFieldSize`（`lib/ui/m3e/components/inputs/m3e_text_field.dart`），
  `M3EDivider`（`lib/ui/m3e/components/surfaces/m3e_divider.dart`），两者已加进 `m3e.dart` barrel。
- ✅ 11 处 `TextField(` 全部迁移，`grep -rn 'TextField(' hiko/lib | grep -v lib/ui/m3e/` → 0。
- ✅ 设置页两个行内输入框改 `late final` 控制器 + `FocusNode` + `_syncController`，
  修掉「打字时光标跳回开头」。**这一条计划书 §2.3 里只写成「顺手」，实测是真 bug：**
  原实现每帧 `TextEditingController(text: …)`，重建即重置选区。
- ✅ 加载环 2 处 → `M3ELoadingIndicator`；裸 `Divider` 2 处 → `M3EDivider`。
- ✅ 新增 `test/ui/m3e/m3e_text_field_test.dart` 6 条；全量 **953 passed / 2 skipped**；analyze 42/0。
- 偏离：`context_menu.dart:183` 那条 0.6dp 分隔线**没换**——它在自绘右键菜单里，属于菜单
  语义（与 `M3EMenuDivider` 的 8/6 padding 不同），归到 1.99.61 菜单收口一起处理。
- 计划书 §2.5 的验收「`grep TextField(` == 0」达成；「analyze 不多一条」达成（中途多出的
  一条 `unnecessary_cast` 出在测试里，已消）。

### 1.99.61（2026-10-31，已发布 `v1.99.61`）

- ✅ 计划书 §3 的「菜单收口」**作废**：`grep -rn "PopupMenuButton(" hiko/lib` = 0、`showMenu(` = 0、
  `MenuAnchor(` 只剩 `m3e_menu.dart:66`、`PopupMenuItem` 只在注释里、12 处 `M3EMenu(` 调用点，
  `plan-hiko-flutter-rewrite.md` §1.99.40 已记「M3EMenu 落地 + 六处菜单统一」→ 这一项 1.99.40 就做完了。
  `context_menu.dart` 去重属纯重构（界面零变化），不做，记为将来的 `chore:`。
- ✅ 「更多」面板改走 `M3ESheet(bottom)`（`home_screen._openMoreSheet`），删掉手写材质。
- ✅ 统计页自适应：`LayoutBuilder` 断点 720，边距 48 / 16，三卡 `Row` / `Column`，
  值单行省略，三颗 chip 改 `Wrap`。
- ✅ 新增 `test/ui/stats_view_test.dart` 4 条；全量 **957 passed / 2 skipped**；analyze 42/0。
- ✅ `1.99.61+174` 双端构建 + APK 后签（v1/v2/v3 全 true）+ `gh release create v1.99.61`。
- 顺序调整：后续版本顺延 —— 1.99.62 = 库备份轮转（原 §5 内容）。
