/// 在线标签**黑名单**的纯逻辑（1.95.0 裁决 Q1=甲、Q2=甲、Q3=A）。
///
/// ## 为什么是「编进搜索关键字」而不是客户端过滤
///
/// asmr.one 的黑名单（它的设置里叫「全局筛选」，注释写着「筛选/屏蔽关键词，
/// 语法与搜索关键字相同」）做法是：把排除项拼到 `keyword` 前面，并且**只要它非空
/// 就不走 `/api/works` 列表接口，改走搜索接口**。这样过滤发生在**服务端**，
/// `totalCount` 与分页天然正确。
///
/// 客户端过滤做不到这一点：一页 20 条里滤掉 5 条，页面就只剩 15 条、
/// 总数还对不上，而且「被滤掉的条数」随页面波动 —— 观感像是列表坏了。
///
/// ## 语法（从 asmr.one 前端 bundle 的 `SearchKeywordService` 挖出，并逐条实测）
///
/// `$命名空间:值$`，排除前缀是 `-`（写在 `$` 之后：`$-tag:值$`）。
///
/// 2026-09-26 实测结论（都是打真实接口比对的，不是推断）：
///
/// - **只能按名字匹配，不能按 id**：`$tag:222$` → 0 条；`$tag:幼なじみ$` → 1322 条。
///   所以黑名单**必须存名字**，`OnlineTag.id` 只用于去重与展示。
/// - **名字里的空格与 `/` 都安全**：`$tag:Teens love$` ≡ 结构化端点（60 条）；
///   `$tag:内射/中出$` ≡ 结构化端点（21565 条）。全站 422 个标签里带空格的只有 1 个。
/// - **改名向后兼容**：`cosplay/角色扮演`（旧名）、`Cosplay`（新名）、`コスプレ`（日文名）
///   给出同一个 449 —— 服务端认识 `i18n.history` 里的历史名。这条很重要：
///   它意味着「存名字」不会因为服务端改标签名而静默失效。
/// - **语言无关**：`$tag:幼なじみ$` ≡ `$tag:青梅竹马$`。
/// - **`$tag:<名>$` 与结构化端点 `/api/tags/{id}/works` 完全等价**（totalCount 与
///   逐位顺序都相同，三个标签逐一验过）—— 所以黑名单激活时把标签筛选也切到
///   `$tag:` 这条路径，结果集不会有任何变化。
/// - **纯排除可用**：没有任何正向词时 `$-tag:ASMR$` 单独返回 44155 条（全站 62453），
///   所以「浏览 + 黑名单」也能整条走搜索接口。
/// - **排除只是过滤、不改排序键**，但排序键相等的**并列项 tie-break 会变**
///   （实测抓到一例：`release` 同为 2026-06-27 的两件顺序对调）。这是必须接受的行为。
/// - 60 个排除项 → 编码后 URL 2552 字节，服务端正常返回。**不需要条数上限**。
library;

import 'online_models.dart';

/// 按标签**排除**的搜索项。`name` 里的特殊字符无需转义（见文件头实测）。
String tagExclusionTerm(String name) => '\$-tag:$name\$';

/// 按标签**正向筛选**的搜索项。
///
/// 与结构化端点等价（实测），黑名单激活时用它把标签筛选并到同一次搜索里 ——
/// 搜索接口不支持「结构化标签 + 关键词」的组合，只能这样叠。
String tagIncludeTerm(String name) => '\$tag:$name\$';

/// 把黑名单编成一段排除关键字。
///
/// 返回**空串**表示「没有排除项」，这是本版最重要的一条约定：
/// **黑名单为空时，请求必须与 1.95.0 之前逐字节一致**（端点、参数都不变），
/// 调用方据此决定走原端点还是走搜索接口。
String exclusionKeyword(Iterable<OnlineTag> blocked) {
  final terms = <String>[];
  final seenIds = <int>{};
  final seenNames = <String>{};
  for (final tag in blocked) {
    final name = tag.name.trim();
    if (name.isEmpty) continue;
    // 与 `parseOnlineTags` 同一套去重口径：有 id 按 id，没 id 只能按名字。
    // 重复项会让关键字变长、还会让同一标签被排除两次（服务端无害但没必要）。
    final duplicate =
        tag.id > 0 ? !seenIds.add(tag.id) : !seenNames.add(name);
    if (duplicate) continue;
    seenNames.add(name);
    terms.add(tagExclusionTerm(name));
  }
  return terms.join(' ');
}

/// 已屏蔽标签的 id 集合，供卡片 / 详情页 O(1) 判断要不要弱化显示（裁决 Q4=乙）。
///
/// 只收 `id > 0` 的条目：`id <= 0` 的黑名单项是坏数据（老版本手工写入等），
/// 它没法可靠地认出卡片上的标签，硬认会误伤。
Set<int> blockedIdSet(Iterable<OnlineTag> blocked) => {
      for (final tag in blocked)
        if (tag.id > 0) tag.id,
    };

/// 该标签是否已被屏蔽。[blockedIds] 来自 [blockedIds] 生成的集合。
bool isTagBlocked(OnlineTag tag, Set<int> blockedIds) =>
    tag.id > 0 && blockedIds.contains(tag.id);
