import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_blacklist.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';

/// 在线浏览控制器的**来源 → 端点**映射单测（不联网）。
///
/// 这组用例存在的理由只有一个：1.94.0 的裁决 Q2=甲 决定了标签筛选走
/// **结构化端点** `/api/tags/{id}/works`，而不是「拿标签名当关键词去打
/// `/api/search/{kw}`」。两者在界面上看不出区别（都能筛出作品），
/// 所以**没有断言就会在未来被悄悄改回去** —— 而改回去会丢掉
/// 「tagname 是全站模糊匹配、而非这个标签本身」这一层语义差异。
///
/// 手法照抄 `online_playlist_test.dart`：用 `HttpOverrides` 记录真实发出的
/// URI，然后抛 `SocketException` 让请求必失败。这样既能断言「发了什么」，
/// 又完全不联网 —— 也就不能 mock client，因为要观测的正是 client 内部
/// 根据来源选出的那个路径。
void main() {
  /// 建一个只 override 客户端的容器。
  ///
  /// 刻意不 override `settingsProvider`：`onlineClientProvider` 是唯一被
  /// `OnlineBrowseNotifier` 读取的依赖，直接把它换掉就不会有人去碰
  /// SharedPreferences（异步落盘在测试环境会挂起）。
  ({ProviderContainer container, List<Uri> requested}) harness() {
    final requested = <Uri>[];
    HttpOverrides.global = _UrlRecorder(requested);
    addTearDown(() => HttpOverrides.global = null);

    final container = ProviderContainer(
      overrides: [
        onlineClientProvider.overrideWith(
          (ref) => KikoeruClient(baseUrl: 'https://api.example.invalid'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container: container, requested: requested);
  }

  /// 请求路径（**已解码**）。
  ///
  /// `Uri.path` 会保留百分号编码（`/api/search/%E5%82%AC%E7%9C%A0`），
  /// 断言里写人类可读的 `/api/search/催眠` 就必须自己解一次。
  String pathOf(Uri u) => Uri.decodeComponent(u.path);

  /// 当前请求的路径集合（去重，便于「不该出现某个路径」的断言）
  Set<String> pathsOf(List<Uri> uris) => uris.map(pathOf).toSet();

  group('来源 → 端点（1.94.0 裁决 Q2=甲）', () {
    test('全站浏览走 /api/works', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.refresh();

      expect(h.requested, isNotEmpty);
      expect(pathsOf(h.requested), {'/api/works'});
    });

    test('关键词搜索走 /api/search/{kw}', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.search('催眠');

      expect(h.requested, isNotEmpty);
      expect(pathOf(h.requested.first), '/api/search/催眠');
      // 搜索是模糊匹配，与标签端点毫无关系
      expect(pathOf(h.requested.first), isNot(startsWith('/api/tags/')));
    });

    test('标签筛选走 /api/tags/{id}/works —— 不是 /api/search', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      expect(h.requested, isNotEmpty);
      expect(pathOf(h.requested.first), '/api/tags/222/works');
      // 回归锁：只要有人把标签筛选改回「用名字去搜索」，这条立刻红
      expect(
        h.requested.any((u) => pathOf(u).startsWith('/api/search')),
        isFalse,
        reason: '标签筛选必须走结构化端点，不能退化成关键词搜索',
      );
    });

    test('标签筛选按 id 而非名字：同名标签只会打各自的 id', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      // 实测存在「同名不同 id」的标签，所以端点必须由 id 决定
      await notifier.selectTag(const OnlineTag(id: 4, name: '亲热/甜蜜'));
      expect(pathOf(h.requested.last), '/api/tags/4/works');
    });

    test('三个来源都带上当前排序键（来源与排序正交）', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(const OnlineTag(id: 496, name: 'バイノーラル'));
      final tagUri = h.requested.last;
      expect(tagUri.queryParameters['order'], notifier.state.sort.key);
      expect(tagUri.queryParameters['sort'], OnlineSort.sortParam);
      expect(tagUri.queryParameters['page'], '1');
    });
  });

  group('标签筛选的状态清理', () {
    test('selectTag 清掉关键词与「只看带字幕」', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.search('催眠');
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));

      expect(notifier.state.source, OnlineSource.tag);
      expect(notifier.state.tag?.id, 222);
      // 这两个筛选项在标签来源下是隐藏的，留着就会变成「看不见的筛选」
      expect(notifier.state.keyword, isEmpty);
      expect(notifier.state.subtitleOnly, isFalse);
    });

    test('标签来源下「只看带字幕」不可用', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      expect(notifier.state.canFilterSubtitle, isFalse);

      // 即便被调用也不该发起新请求（避免发出服务端不认的 subtitle 参数）
      final before = h.requested.length;
      await notifier.toggleSubtitleOnly();
      expect(h.requested.length, before);
      expect(notifier.state.subtitleOnly, isFalse);
    });

    test('搜索会清掉标签（两个来源互斥，不同时生效）', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      await notifier.search('催眠');

      expect(notifier.state.source, OnlineSource.search);
      expect(notifier.state.tag, isNull);
      expect(pathOf(h.requested.last), '/api/search/催眠');
    });
  });

  group('退出标签筛选回榜单（用户裁决：一律回最新榜）', () {
    test('applyPreset(latestPreset) 清掉标签并回到 /api/works', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      expect(notifier.state.source, OnlineSource.tag);

      await notifier.applyPreset(OnlineSort.latestPreset);

      expect(notifier.state.source, OnlineSource.browse);
      expect(notifier.state.tag, isNull);
      expect(notifier.state.sort, OnlineSort.latestPreset);
      expect(pathOf(h.requested.last), '/api/works');
      expect(
        h.requested.last.queryParameters['order'],
        OnlineSort.latestPreset.key,
        reason: '取消标签筛选一律回最新榜，不是冷启动的热门榜',
      );
      // 双重锁定：这条「一律回最新榜」是用户**推翻**了推荐答案（我曾推荐回热门榜）
      // 之后定的。断言写成「不是热门」比只断言「是最新」更能挡住后人顺手改回去。
      expect(
        h.requested.last.queryParameters['order'],
        isNot(OnlineSort.popularPreset.key),
      );
    });

    test('最新榜预设与冷启动默认榜不是同一个（否则「回最新榜」是空操作）', () async {
      // 冷启动落在热门榜（dl_count 倒序），所以从热门点「最新」会真的换榜。
      // 如果哪天有人把两者改成同一个值，这条会红 —— 那时「退出筛选回最新榜」
      // 就变成了「回热门榜」，与用户裁决相悖。
      expect(OnlineSort.latestPreset, isNot(OnlineSort.popularPreset));
      final container = harness().container;
      expect(
        container.read(onlineBrowseProvider).sort,
        OnlineSort.popularPreset,
        reason: '冷启动基线：热门榜',
      );
    });
  });

  group('声优 / 社团筛选 → 端点（1.97.0）', () {
    const vaFilter = OnlineCreatorFilter(
      kind: OnlineCreatorKind.va,
      name: '涼花みなせ',
    );
    const circleFilter = OnlineCreatorFilter(
      kind: OnlineCreatorKind.circle,
      name: 'Whisper Secret',
    );

    test('全站浏览 + 声优筛选改走 /api/search/{\$va:名\$}', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectCreator(vaFilter);

      expect(pathOf(h.requested.last), '/api/search/\$va:涼花みなせ\$',
          reason: '/api/works 会静默丢弃关键词，必须换搜索接口');
      expect(notifier.state.creator, vaFilter);
      expect(notifier.state.canFilterSubtitle, isFalse,
          reason: '搜索端点没有字幕参数，chip 必须藏起来');
    });

    test('搜索来源 + 声优筛选 = \$va: 与关键词拼接', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.search('催眠');
      await notifier.selectCreator(vaFilter);

      expect(pathOf(h.requested.last), '/api/search/\$va:涼花みなせ\$ 催眠');
      expect(notifier.state.keyword, '催眠', reason: '状态里保留原关键词，拼接发生在请求层');
    });

    test('标签来源 + 社团筛选 = \$tag: 与 \$circle: 拼接，不走结构化端点', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      // 注意顺序：selectTag 会清掉 creator（对齐「搜索清标签」的互斥语义），
      // 所以叠加必须是「先选标签、再点声优/社团」—— 这正是详情页胶囊的实际路径
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      await notifier.selectCreator(circleFilter);

      final last = pathOf(h.requested.last);
      expect(last, startsWith('/api/search/'),
          reason: '结构化端点吃不下 \$circle:，换实测等价的 \$tag: 关键词');
      expect(last, contains('\$tag:青梅竹马\$'));
      expect(last, contains('\$circle:Whisper Secret\$'));
    });

    test('selectCreator 保留搜索词，但清掉「只看带字幕」', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.search('催眠');
      await notifier.selectCreator(vaFilter);

      expect(notifier.state.source, OnlineSource.search,
          reason: '保留来源：搜索结果里点声优 = 关键词 ∩ 声优，不是扔回全站');
      expect(notifier.state.subtitleOnly, isFalse);
    });

    test('再选同一个 creator 不重复请求（幂等）', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectCreator(vaFilter);
      final count = h.requested.length;
      await notifier.selectCreator(vaFilter);
      expect(h.requested.length, count);
    });

    test('applyPreset / 新搜索 / 新标签都会清掉 creator', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      await notifier.selectCreator(vaFilter);
      await notifier.applyPreset(OnlineSort.latestPreset);
      expect(notifier.state.creator, isNull, reason: '取消筛选回最新榜');
      expect(pathOf(h.requested.last), '/api/works');

      await notifier.selectCreator(vaFilter);
      await notifier.search('催眠');
      expect(notifier.state.creator, isNull, reason: '新一轮搜索不该叠着看不见的筛选');

      await notifier.selectCreator(vaFilter);
      await notifier.selectTag(const OnlineTag(id: 222, name: '青梅竹马'));
      expect(notifier.state.creator, isNull, reason: '标签与 creator 同族互斥进入');
    });

    test('预设 chip 高亮在 creator 激活时熄灭', () async {
      final h = harness();
      final notifier = h.container.read(onlineBrowseProvider.notifier);

      expect(notifier.state.isPresetActive(OnlineSort.popularPreset), isTrue);
      await notifier.selectCreator(vaFilter);
      expect(notifier.state.isPresetActive(OnlineSort.popularPreset), isFalse,
          reason: '那已经是「筛选下的排序」，不是榜单本身');
    });

    test('term 语法逐字节钉死（拼错静默不筛，必须防回归）', () {
      expect(vaFilter.term, '\$va:涼花みなせ\$');
      expect(circleFilter.term, '\$circle:Whisper Secret\$');
      expect(vaIncludeTerm('あ'), '\$va:あ\$');
      expect(circleIncludeTerm('あ'), '\$circle:あ\$');
    });
  });
}

/// 记录请求 URL 但不联网的 HttpClient（照抄 online_playlist_test 的做法）
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
