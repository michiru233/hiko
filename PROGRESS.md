# PROGRESS（hiko 1.35.0：主界面排序新增按专辑艺术家）

## 开工回执（任务 0，2026-08-26）
- 目标：主界面排序菜单新增「专辑艺术家 A → Z」，选中后按 albumArtist（为空回退 artist，皆空排最后）naturalCompare 升序排列，同艺术家内按标题升序。
- 顺序：0 基线核对→1 filter.dart 增加 artist_asc→2 categories_test.dart 单测及红绿验证→3 home_screen.dart UI 菜单项与 label→4 发版 1.35.0+39（构建、Release、文档更新）。
- 最大风险：空艺术家字段排序边界情况处理与同艺术家内标题二级排序未对齐。
- 基线核对：`flutter test` 结果为 +137 ~1 -1（唯一失败为 update_checker_network_test 真实 GitHub 网络测试，符合预期基线）。
- 代码落点：`_sortOptions` 位于 `lib/ui/screens/home_screen.dart:1220`，`albumArtist` 位于 `lib/models/album.dart:10`。

## 任务状态
- [x] 任务 0：基线核对与落点确认（+137 ~1 -1 基线确认）
- [x] 任务 1：filter.dart 增加 artist_asc 排序逻辑（键取 albumArtist 优先回退 artist，皆空置底，二级按标题升序）
- [x] 任务 2：categories_test.dart 新增单测并反向验证（红→绿：临时 break 时 3 个新用例均报错，恢复后 14/14 全绿）
- [x] 任务 3：home_screen.dart 增加 UI 选项及 label（analyze 0 error，全量测试 +140 ~1 -1）
- [x] 任务 4：发版 1.35.0+39（构建 macOS release、打包 zip、git push、gh release、追加 plan 文档）
