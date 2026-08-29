# PROGRESS（hiko 1.37.0：专辑艺术家排序改为专辑数多的排前面）

- 目标：filter.dart `artist_asc` 组间改为按全库专辑数降序（同数按名自然升序，空键最后，组内标题升序），菜单文案改「专辑艺术家（专辑多在前）」，不加分组标题。
- 顺序：0 基线核对（143 过/1 跳过/1 失败仅既有网络用例）→1 filter.dart 排序改造+categories_test 改写用例+反向验证红→绿 →2 菜单文案、bump 1.37.0+41、README/plans 同步、macOS release 构建与 gh release。
- 最大风险：改写旧用例时误动「回退/皆空排最后」两条既有用例语义（实际未动，全绿）。

## 任务状态
- [x] 任务 0：基线核对一致
- [x] 任务 1：排序实现 + 新用例（2 张排 1 张前）+ 反向验证（升序临时改动→红→还原→绿）
- [x] 任务 2：发版 1.37.0+41（git push `7088102..8a8269c`，Release https://github.com/michiru233/hiko/releases/tag/v1.37.0 ，资产 hiko-v1.37.0-macos.zip）
