import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_blacklist.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';
import 'package:hiko/data/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 在线标签黑名单（1.95.0）的单测。
///
/// 这组用例护的是三件**界面上看不出来**的事：
/// 1. **排除项的确切拼法**（`$-tag:名$`）。服务端对未知命名空间不报错，
///    只是不筛 —— 拼错一个字符的结果不是「报错」而是「静默失效」，
///    所以必须逐字节钉死。
/// 2. **黑名单为空时请求与 1.95.0 之前完全一致**（浏览仍走 `/api/works`）。
///    否则「没用过黑名单的用户」也会被动换端点。
/// 3. **黑名单非空时的端点映射**：`/api/works` 会静默忽略一切排除参数
///    （实测 `excludeTags` / `keyword` 全被吃掉），唯一的路径是改走搜索接口。
///    这一条与 `online_browse_source_test.dart` 的「来源 → 端点」是同一类回归锁。
///
/// 手法沿用 `online_browse_source_test.dart`：`HttpOverrides` 记录真实发出的 URI
/// （不能 mock client，因为要观测的正是 client 内部选出的那条路径）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------------------ 纯函数

  group('排除项构造（服务端语法，实测）', () {
    test(r'排除前缀写在 $ 之后：$-tag:名$ 而不是 -$tag:名$', () {
      expect(tagExclusionTerm('青梅竹马'), r'$-tag:青梅竹马$');
      expect(tagIncludeTerm('青梅竹马'), r'$tag:青梅竹马$');
    });

    test('黑名单为空 → 空串（不是空串的话请求就换了端点）', () {
      expect(exclusionKeyword(const []), '');
    });

    test('多个排除项空格连接', () {
      final keyword = exclusionKeyword(const [
        OnlineTag(id: 222, name: '青梅竹马'),
        OnlineTag(id: 496, name: 'バイノーラル'),
      ]);
      expect(keyword, r'$-tag:青梅竹马$ $-tag:バイノーラル$');
    });

    test('按 id 去重（同一份名单里不该出现两条同名排除项）', () {
      final keyword = exclusionKeyword(const [
        OnlineTag(id: 222, name: '青梅竹马'),
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      expect(keyword, r'$-tag:青梅竹马$');
    });

    test('名字为空或全空白的条目被跳过', () {
      final keyword = exclusionKeyword(const [
        OnlineTag(id: 1, name: ''),
        OnlineTag(id: 2, name: '   '),
        OnlineTag(id: 3, name: '幼なじみ'),
      ]);
      expect(keyword, r'$-tag:幼なじみ$');
    });
  });

  group('isTagBlocked / blockedIdSet', () {
    test('id <= 0 的标签永远不算被屏蔽（没有 id 就无法持久化判定）', () {
      final ids = blockedIdSet(const [OnlineTag(id: 0, name: '无 id 的标签')]);
      expect(ids, isEmpty);
      expect(
        isTagBlocked(const OnlineTag(id: 0, name: '无 id 的标签'), ids),
        isFalse,
      );
    });

    test('按 id 判定，同名不同 id 互不影响', () {
      final ids = blockedIdSet(const [OnlineTag(id: 222, name: '青梅竹马')]);
      expect(isTagBlocked(const OnlineTag(id: 222, name: '改名了'), ids), isTrue);
      expect(isTagBlocked(const OnlineTag(id: 223, name: '青梅竹马'), ids),
          isFalse);
    });
  });

  // ------------------------------------------------------------ 存取

  group('黑名单的存取', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('持久化往返：只写 id + name（不写 count）', () async {
      final notifier = SettingsNotifier();
      await notifier.load();

      await notifier.setBlockedTags(const [
        OnlineTag(id: 222, name: '青梅竹马', count: 1322),
      ]);
      expect(notifier.state.blockedTags.single.name, '青梅竹马');

      // count 是服务端的聚合值、会变；写进去就会让「同一份名单序列化出
      // 不同字符串」，所以持久化形态里必须没有它
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('hiko-online-blocked-tags');
      expect(raw, isNotNull);
      expect(raw, isNot(contains('count')));
      expect(raw, contains('"id":222'));

      // 重启后仍在
      final reloaded = SettingsNotifier();
      await reloaded.load();
      expect(reloaded.state.blockedTags.single.id, 222);
      expect(reloaded.state.blockedTags.single.name, '青梅竹马');
    });

    test('addBlockedTag 按 id 去重', () async {
      final notifier = SettingsNotifier();
      await notifier.load();

      await notifier.addBlockedTag(const OnlineTag(id: 222, name: '青梅竹马'));
      await notifier.addBlockedTag(const OnlineTag(id: 222, name: '青梅竹马'));
      await notifier.addBlockedTag(const OnlineTag(id: 496, name: 'バイノーラル'));

      expect(notifier.state.blockedTags.map((t) => t.id), [222, 496]);
    });

    test('removeBlockedTag 只删指定 id；未知 id 是空操作', () async {
      final notifier = SettingsNotifier();
      await notifier.load();
      await notifier.setBlockedTags(const [
        OnlineTag(id: 222, name: '青梅竹马'),
        OnlineTag(id: 496, name: 'バイノーラル'),
      ]);

      await notifier.removeBlockedTag(222);
      expect(notifier.state.blockedTags.map((t) => t.id), [496]);

      await notifier.removeBlockedTag(9999);
      expect(notifier.state.blockedTags.map((t) => t.id), [496]);
    });

    test('clearBlockedTags 清空', () async {
      final notifier = SettingsNotifier();
      await notifier.load();
      await notifier.setBlockedTags(const [OnlineTag(id: 222, name: 'x')]);
      await notifier.clearBlockedTags();
      expect(notifier.state.blockedTags, isEmpty);
    });

    test('坏数据只丢坏的那几条，不整份清空', () async {
      // 混合：合法项、非 map 项、名字为空的项、重复 id
      SharedPreferences.setMockInitialValues({
        'hiko-online-blocked-tags':
            '[{"id":222,"name":"青梅竹马"}, 42, {"id":1,"name":""},'
                '{"id":222,"name":"重复"}]',
      });
      final notifier = SettingsNotifier();
      await notifier.load();

      expect(notifier.state.blockedTags.length, 1);
      expect(notifier.state.blockedTags.single.name, '青梅竹马');
    });

    test('整份不是 JSON 数组时退化成空名单，不抛异常', () async {
      SharedPreferences.setMockInitialValues({
        'hiko-online-blocked-tags': 'not json at all',
      });
      final notifier = SettingsNotifier();
      await notifier.load();
      expect(notifier.state.blockedTags, isEmpty);
    });
  });

  // ------------------------------------------------------------ 端点映射

  group('端点映射（黑名单非空时必须绕开 /api/works）', () {
    test('全站浏览：黑名单非空 → 改走 /api/search/{排除项}', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      await h.container.read(onlineBrowseProvider.notifier).refresh();

      expect(pathOf(h.requested.last), r'/api/search/$-tag:青梅竹马$');
      // 回归锁：/api/works 会静默忽略一切排除参数，退回它黑名单就失效了
      expect(pathsOf(h.requested), isNot(contains('/api/works')));
    });

    test('黑名单为空时浏览仍走 /api/works（没用过黑名单的用户不受影响）', () async {
      final h = harness();
      await h.container.read(onlineBrowseProvider.notifier).refresh();

      expect(pathsOf(h.requested), {'/api/works'});
    });

    test('搜索：排除项拼在关键词前面（与 asmr.one 的 globalFilter 同序）', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      await h.container.read(onlineBrowseProvider.notifier).search('催眠');

      expect(pathOf(h.requested.last), r'/api/search/$-tag:青梅竹马$ 催眠');
    });

    test(r'标签筛选：改走 $tag:名$ + 排除项（结构化端点会忽略排除参数）', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 496, name: 'バイノーラル'),
      ]);
      await h.container.read(onlineBrowseProvider.notifier)
          .selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      expect(
        pathOf(h.requested.last),
        r'/api/search/$tag:青梅竹马$ $-tag:バイノーラル$',
      );
      expect(
        h.requested.any((u) => pathOf(u).startsWith('/api/tags/')),
        isFalse,
        reason: '有排除项时不能走结构化标签端点：它会忽略排除参数',
      );
    });

    test('标签筛选：黑名单里没有别的标签时保持结构化端点', () async {
      // 屏蔽的正是要筛的那个标签 → 它自己不算排除项，于是排除项为空
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      await h.container.read(onlineBrowseProvider.notifier).selectTag(
            const OnlineTag(id: 222, name: '青梅竹马'),
            bypassBlocklist: true,
          );

      expect(pathOf(h.requested.last), '/api/tags/222/works');
    });

    test('「仍要查看」只放行那一个标签，别的屏蔽项照旧生效', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
        OnlineTag(id: 496, name: 'バイノーラル'),
      ]);
      await h.container.read(onlineBrowseProvider.notifier).selectTag(
            const OnlineTag(id: 222, name: '青梅竹马'),
            bypassBlocklist: true,
          );

      // 222 被放行、496 仍在排除项里 —— 用户说的是「我就要看这一个」，
      // 把别的屏蔽项一起放出来是替他做了另一个决定
      expect(
        pathOf(h.requested.last),
        r'/api/search/$tag:青梅竹马$ $-tag:バイノーラル$',
      );
    });

    test('三种来源都继续带排序与分页参数', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.refresh();

      final uri = h.requested.last;
      expect(uri.queryParameters['order'], notifier.state.sort.key);
      expect(uri.queryParameters['sort'], OnlineSort.sortParam);
      expect(uri.queryParameters['page'], '1');
    });

    test('「只看带字幕」在有排除项时依然带 subtitle=1', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.toggleSubtitleOnly();

      expect(h.requested.last.queryParameters['subtitle'], '1');
    });
  });

  // ------------------------------------------------------------ 屏蔽后的收尾

  group('屏蔽 / 移出之后的收尾（裁决 Q1=甲 + 「自筛自屏」= 甲）', () {
    test('屏蔽的不是当前筛选标签 → 留在原来源、回第 1 页重拉', () async {
      // 现实场景：正在按 222 筛选，在结果页里右键把另一个标签 496 加了黑名单
      final h = harness(blocked: const [
        OnlineTag(id: 496, name: 'バイノーラル'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      await notifier.reloadAfterBlock(tagId: 496);

      expect(notifier.state.source, OnlineSource.tag);
      expect(notifier.state.tag?.id, 222);
      expect(notifier.state.page, 1);
      expect(
        pathOf(h.requested.last),
        r'/api/search/$tag:青梅竹马$ $-tag:バイノーラル$',
      );
    });

    test('屏蔽的正是当前筛选标签 → 退出筛选、回最新榜', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      await notifier.reloadAfterBlock(tagId: 222);

      // 不退出的话请求会变成 `$tag:X$ $-tag:X$`，实测必然是 0 条 ——
      // 留下筛选标记而结果空白是自相矛盾的状态
      expect(notifier.state.source, OnlineSource.browse);
      expect(notifier.state.tag, isNull);
      expect(pathOf(h.requested.last), '/api/works');
      expect(
        h.requested.last.queryParameters['order'],
        OnlineSort.latestPreset.key,
        reason: '沿用 1.94.0 已定的「退出标签筛选一律回最新榜」',
      );
    });

    test('移出黑名单不会退出标签筛选（结果只会变多）', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      await notifier.reloadAfterUnblock(tagId: 222);

      expect(notifier.state.source, OnlineSource.tag);
      expect(notifier.state.tag?.id, 222);
    });

    test('「仍要查看」之后把该标签移出黑名单 → 绕过标记被清掉', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.selectTag(
        const OnlineTag(id: 222, name: '青梅竹马'),
        bypassBlocklist: true,
      );
      expect(notifier.state.bypassBlocklist, isTrue);

      // 真实调用顺序：调用方先把标签移出名单，再让浏览控制器收尾
      h.settings.setBlocked(const []);
      await notifier.reloadAfterUnblock(tagId: 222);

      // 标签不再被屏蔽了，留着「绕过」这个标记会让下一次屏蔽在这个筛选里失效
      expect(notifier.state.bypassBlocklist, isFalse);
      expect(notifier.state.tag?.id, 222);
      // 名单空了 → 排除项为空 → 回到结构化标签端点
      expect(pathOf(h.requested.last), '/api/tags/222/works');
    });

    test('清空全部黑名单 → 重拉，并且请求回到 /api/works', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.refresh();
      expect(pathOf(h.requested.last), startsWith('/api/search'));

      // 调用方（管理对话框）先把名单清空，再让浏览控制器重拉
      h.settings.setBlocked(const []);
      await notifier.reloadAfterUnblock();

      expect(notifier.state.page, 1);
      expect(pathOf(h.requested.last), '/api/works');
    });
  });

  group('bypassBlocklist 的存活范围', () {
    test('翻页与改排序都不清它（否则前后页不是同一份筛选）', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);
      await notifier.selectTag(
        const OnlineTag(id: 222, name: '青梅竹马'),
        bypassBlocklist: true,
      );

      await notifier.setSort(OnlineSort.rateDesc);
      expect(notifier.state.bypassBlocklist, isTrue);

      await notifier.setPageSize(60);
      expect(notifier.state.bypassBlocklist, isTrue);
    });

    test('换来源（预设 / 搜索 / 新标签）会清它', () async {
      final h = harness(blocked: const [
        OnlineTag(id: 222, name: '青梅竹马'),
      ]);
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(
        const OnlineTag(id: 222, name: '青梅竹马'),
        bypassBlocklist: true,
      );
      await notifier.applyPreset(OnlineSort.popularPreset);
      expect(notifier.state.bypassBlocklist, isFalse);

      await notifier.selectTag(
        const OnlineTag(id: 222, name: '青梅竹马'),
        bypassBlocklist: true,
      );
      await notifier.search('催眠');
      expect(notifier.state.bypassBlocklist, isFalse);

      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      expect(notifier.state.bypassBlocklist, isFalse);
    });
  });
}

// ---------------------------------------------------------------- 测试脚手架

/// 建一个同时 override 客户端与设置（黑名单）的容器。
///
/// 必须连 `settingsProvider` 一起换掉：黑名单是从设置里读的，而真 notifier 的
/// 任何 setter 都会走 SharedPreferences 异步落盘（测试环境会挂起）。
/// 这里直接置 `state`，一个字节都不落盘。
({ProviderContainer container, List<Uri> requested, _BlocklistSettings settings})
    harness({List<OnlineTag> blocked = const []}) {
  final requested = <Uri>[];
  HttpOverrides.global = _UrlRecorder(requested);
  addTearDown(() => HttpOverrides.global = null);

  final settings = _BlocklistSettings(blocked);
  final container = ProviderContainer(
    overrides: [
      onlineClientProvider.overrideWith(
        (ref) => KikoeruClient(baseUrl: 'https://api.example.invalid'),
      ),
      settingsProvider.overrideWith((ref) => settings),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, requested: requested, settings: settings);
}

/// 只把黑名单放进 state 的 SettingsNotifier，纯粹为了喂给 `_fetch` 读。
class _BlocklistSettings extends SettingsNotifier {
  _BlocklistSettings(List<OnlineTag> blocked) {
    setBlocked(blocked);
  }

  /// 模拟「管理对话框改了名单」而不碰 SharedPreferences
  void setBlocked(List<OnlineTag> blocked) {
    state = state.copyWith(blockedTags: blocked);
  }
}

/// 请求路径（**已解码**）。`Uri.path` 会保留百分号编码。
String pathOf(Uri u) => Uri.decodeComponent(u.path);

Set<String> pathsOf(List<Uri> uris) => uris.map(pathOf).toSet();

/// 记录请求 URL 但不联网的 HttpClient（照抄 online_browse_source_test 的做法）
class _UrlRecorder extends HttpOverrides {
  _UrlRecorder(this.requested);

  final List<Uri> requested;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _UrlRecorderClient(requested);
}

class _UrlRecorderClient implements HttpClient {
  _UrlRecorderClient(this.requested);

  final List<Uri> requested;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requested.add(url);
    throw const SocketException('单测环境不联网');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
