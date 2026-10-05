import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';
import 'package:hiko/data/online/online_provider.dart';

/// 「取消声优 / 社团筛选」（标记上的 ✕）的回归锁（1.99.19）。
///
/// 实机反馈：「只有社团筛选的时候，✕ 点不了」。根因不在标记的热区，
/// 而在 `applyPreset` 的「已停在这个榜上就不白刷」早退：`selectCreator`
/// 刻意不改 source / sort，于是「最新榜 + 社团筛选」正好满足早退的那些条件，
/// 取消动作（旧实现走 `applyPreset(latestPreset)`）被静默吞掉 —— 观感就是
/// 点不动。1.99.19 裁决：✕ 只摘掉这一维、回到筛之前的上下文（Q4=A），
/// 早退判断补上 tag / creator / keyword（Q5=A）。
///
/// ## 为什么既有测试没抓到这颗雷
/// 既有 harness 让所有 HTTP 必失败（`SocketException`），`state.works` 恒为空，
/// 而旧早退多看了一条 `works.isNotEmpty` —— 于是它永远不会触发。
/// 本文件用**假客户端**返回真数据，先让页面上有内容，再走取消路径。
class _FakeClient extends KikoeruClient {
  _FakeClient() : super(baseUrl: 'https://api.example.invalid');

  int fetches = 0;

  OnlineWorkPage _page() => OnlineWorkPage(
        works: List.generate(
          3,
          (i) => OnlineWork(
            id: 100 + i,
            title: '作品$i',
            circleName: 'すたじおむび',
          ),
        ),
        currentPage: 1,
        pageSize: KikoeruClient.defaultPageSize,
        totalCount: 3,
      );

  @override
  Future<OnlineWorkPage> fetchWorks({
    int page = 1,
    int pageSize = KikoeruClient.defaultPageSize,
    OnlineSort sort = OnlineSort.createDate,
    bool subtitleOnly = false,
    String excludeKeyword = '',
  }) async {
    fetches++;
    return _page();
  }

  @override
  Future<OnlineWorkPage> searchWorks(
    String keyword, {
    int page = 1,
    int pageSize = KikoeruClient.defaultPageSize,
    OnlineSort sort = OnlineSort.createDate,
    bool subtitleOnly = false,
    String excludeKeyword = '',
  }) async {
    fetches++;
    return _page();
  }

  @override
  Future<OnlineWorkPage> fetchWorksByTag(
    OnlineTag tag, {
    int page = 1,
    int pageSize = KikoeruClient.defaultPageSize,
    OnlineSort sort = OnlineSort.dlCountDesc,
    bool subtitleOnly = false,
    String excludeKeyword = '',
  }) async {
    fetches++;
    return _page();
  }
}

const _circle = OnlineCreatorFilter(
  kind: OnlineCreatorKind.circle,
  name: 'すたじおむび',
);
const _va = OnlineCreatorFilter(
  kind: OnlineCreatorKind.va,
  name: '柚木つばめ',
);

void main() {
  ({ProviderContainer container, _FakeClient client, OnlineBrowseNotifier notifier})
      harness() {
    final client = _FakeClient();
    final container = ProviderContainer(
      overrides: [onlineClientProvider.overrideWith((ref) => client)],
    );
    addTearDown(container.dispose);
    return (
      container: container,
      client: client,
      notifier: container.read(onlineBrowseProvider.notifier),
    );
  }

  test('最新榜 + 社团筛选：✕（clearCreator）必须真的清掉筛选并重发请求', () async {
    final h = harness();
    await h.notifier.applyPreset(OnlineSort.latestPreset);
    expect(h.notifier.state.works, isNotEmpty,
        reason: '前提：页面上有数据（旧 harness 缺的正是这一条）');

    await h.notifier.selectCreator(_circle);
    expect(h.notifier.state.creator, _circle);
    expect(h.notifier.state.source, OnlineSource.browse,
        reason: '前提：selectCreator 刻意不改来源');
    expect(h.notifier.state.sort, OnlineSort.latestPreset,
        reason: '前提：排序也不变 —— 旧早退的三条这就算齐了');

    final before = h.client.fetches;
    await h.notifier.clearCreator();

    expect(h.notifier.state.creator, isNull, reason: '✕ 必须真的清掉社团筛选');
    expect(h.client.fetches, greaterThan(before), reason: '取消是一次真请求');
    expect(h.notifier.state.source, OnlineSource.browse, reason: '来源保留（Q4=A）');
    expect(h.notifier.state.sort, OnlineSort.latestPreset, reason: '排序保留（Q4=A）');
    expect(h.notifier.state.works, isNotEmpty, reason: '取消后重新拉回列表');
  });

  test('搜索词 + 声优筛选：✕ 只摘声优，搜索词与来源保留（Q4=A）', () async {
    final h = harness();
    await h.notifier.search('催眠');
    await h.notifier.selectCreator(_va);
    expect(h.notifier.state.source, OnlineSource.search,
        reason: '前提：筛声优保留搜索来源');

    await h.notifier.clearCreator();

    expect(h.notifier.state.creator, isNull);
    expect(h.notifier.state.source, OnlineSource.search,
        reason: '取消声优筛选不该把用户扔回全站（旧实现走 applyPreset 会）');
    expect(h.notifier.state.keyword, '催眠', reason: '搜索词必须留着');
  });

  test('幂等：本来就没有 creator 时取消不白刷一次', () async {
    final h = harness();
    await h.notifier.applyPreset(OnlineSort.latestPreset);
    final before = h.client.fetches;

    await h.notifier.clearCreator();

    expect(h.client.fetches, before);
  });

  test('社团筛选激活时点「最新」chip 不再被早退吞掉（Q5=A）', () async {
    final h = harness();
    await h.notifier.applyPreset(OnlineSort.latestPreset);
    await h.notifier.selectCreator(_circle);
    final before = h.client.fetches;

    await h.notifier.applyPreset(OnlineSort.latestPreset);

    expect(h.notifier.state.creator, isNull, reason: '榜单语义：点榜单 = 回榜单（清筛选）');
    expect(h.client.fetches, greaterThan(before), reason: '必须真的重刷');
  });

  test('字幕 / 分级标记的取消同样不受早退影响（正交筛选）', () async {
    final h = harness();
    await h.notifier.applyPreset(OnlineSort.latestPreset);
    final before = h.client.fetches;

    await h.notifier.clearSubtitleOnly();
    await h.notifier.clearAgeFilter();

    expect(h.client.fetches, before, reason: '本来就没开，不该白刷');
  });
}
