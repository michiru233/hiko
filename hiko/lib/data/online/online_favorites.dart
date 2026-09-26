import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'kikoeru_client.dart';
import 'online_account.dart';
import 'online_models.dart';
import 'online_provider.dart';

/// 「我的歌单」作品的本地索引（1.93.0）。
///
/// 为什么要有它：这一版要在三个地方用同一份事实 ——
/// ① 列表卡片的收藏角标；② 「在线收藏」页的作品网格；③ 多选歌单菜单的预勾选。
/// 三处分别去问服务端会得到三份可能不一致的数据，所以统一在这里拉一次。
///
/// 服务端侧**确实**有更细的接口（`get-work-exist-status-in-my-playlists` 按作品查、
/// `/api/works` 带 `withPlaylistStatus` 按页查），但前者一作品一请求、后者只覆盖
/// `/api/works` 一条链路（搜索与标签端点不接受 POST），都拼不出一个统一视图。
/// 所以按裁决 Q10=B 的精神：数据仍以服务端为准，只是本地缓存一份。
@immutable
class OnlineFavorites {
  OnlineFavorites({
    this.playlists = const [],
    this.worksById = const {},
    this.truncated = false,
  }) : _playlistIdsByWork = _indexByWork(worksById);

  static final empty = OnlineFavorites();

  /// 我的歌单，顺序沿用服务端（「我喜欢的」排最前）
  final List<OnlinePlaylist> playlists;

  /// 歌单 id → 该歌单内的作品（服务端顺序：最近加入的在前）
  final Map<String, List<OnlineWork>> worksById;

  /// 某个歌单的作品多到触及安全上限被截断。UI 据此提示「列表可能不全」
  final bool truncated;

  /// 作品 id → 它所属的歌单 id 集合
  final Map<int, Set<String>> _playlistIdsByWork;

  static Map<int, Set<String>> _indexByWork(Map<String, List<OnlineWork>> byId) {
    final out = <int, Set<String>>{};
    for (final entry in byId.entries) {
      for (final work in entry.value) {
        (out[work.id] ??= <String>{}).add(entry.key);
      }
    }
    return out;
  }

  /// 被任意歌单收录过的作品 id（角标与计数都读它）
  Set<int> get allWorkIds => _playlistIdsByWork.keys.toSet();

  /// 作品所在的歌单 id 集合；不在任何歌单里返回空集
  Set<String> playlistsOf(int workId) =>
      _playlistIdsByWork[workId] ?? const <String>{};

  bool contains(int workId) => _playlistIdsByWork.containsKey(workId);

  /// 某个歌单的作品；[playlistId] 为 null = 全部歌单的并集（按歌单顺序拼接、按作品去重）
  List<OnlineWork> worksOf(String? playlistId) {
    if (playlistId != null) return worksById[playlistId] ?? const [];
    final seen = <int>{};
    final out = <OnlineWork>[];
    for (final playlist in playlists) {
      for (final work in worksById[playlist.id] ?? const <OnlineWork>[]) {
        if (seen.add(work.id)) out.add(work);
      }
    }
    return out;
  }

  /// 「全部」或某个歌单的作品数
  int countOf(String? playlistId) => playlistId == null
      ? allWorkIds.length
      : (worksById[playlistId]?.length ?? 0);

  /// 把 [work] 在若干歌单里的存在状态就地改掉，不重新拉整张表。
  ///
  /// 给多选菜单确认后的**即时反馈**用：等一次网络往返再刷新的话，
  /// 按钮会在点下之后保持原样几百毫秒，看着像没生效。
  OnlineFavorites appliedLocally({
    required OnlineWork work,
    required PlaylistDiff diff,
  }) {
    if (diff.isEmpty) return this;
    final next = <String, List<OnlineWork>>{};
    for (final entry in worksById.entries) {
      next[entry.key] = _applyTo(entry.value, work, diff: diff, playlistId: entry.key);
    }
    return OnlineFavorites(
      playlists: playlists,
      worksById: next,
      truncated: truncated,
    );
  }

  static List<OnlineWork> _applyTo(
    List<OnlineWork> list,
    OnlineWork work, {
    required PlaylistDiff diff,
    required String playlistId,
  }) {
    if (diff.removeFrom.contains(playlistId)) {
      return list.where((w) => w.id != work.id).toList();
    }
    if (diff.addTo.contains(playlistId) && !list.any((w) => w.id == work.id)) {
      // 服务端按「最近加入」倒序，新加的就排最前
      return [work, ...list];
    }
    return list;
  }
}

@immutable
class OnlineFavoritesState {
  const OnlineFavoritesState({
    required this.index,
    this.loading = false,
    this.error,
  });

  final OnlineFavorites index;
  final bool loading;
  final String? error;

  /// 至少拉成功过一次（哪怕结果是 0 个歌单）
  bool get loaded => !loading && error == null;

  OnlineFavoritesState copyWith({
    OnlineFavorites? index,
    bool? loading,
    String? error,
    bool clearError = false,
  }) =>
      OnlineFavoritesState(
        index: index ?? this.index,
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 歌单作品索引的加载与增量维护。
///
/// 生命周期跟着登录态走：登出即清空，登录（或冷启动恢复出登录态）即拉一次。
class OnlineFavoritesNotifier extends StateNotifier<OnlineFavoritesState> {
  OnlineFavoritesNotifier(this._ref)
      : super(OnlineFavoritesState(index: OnlineFavorites.empty)) {
    // 登录态一变就重建索引：登出清空，登录重拉。
    // 只在 next=true 时动手 —— 「false → false」这种因为恢复流程而产生的
    // 重复通知不该白清一次（虽然结果一样，但会多推一帧）。
    _ref.listen<bool>(onlineLoggedInProvider, (previous, next) {
      if (next) {
        unawaited(refresh());
      } else if (previous == true) {
        state = OnlineFavoritesState(index: OnlineFavorites.empty);
      }
    });
    // 首次装载延到微任务：provider 初始化期间改自己的 state 是被禁止的
    scheduleMicrotask(() {
      if (mounted && _ref.read(onlineLoggedInProvider)) {
        unawaited(refresh());
      }
    });
  }

  final Ref _ref;

  /// 歌单列表每页条数（= 服务端上限；正常用户一页拉完）
  static const _playlistPageSize = KikoeruClient.playlistMaxPageSize;

  /// 歌单列表最多翻几页。纯粹防死循环，正常永远用不到
  static const _maxPlaylistPages = 10;

  /// 单个歌单的作品最多翻几页。
  ///
  /// 一页 [_workPageSize] 条 × 50 页 = 5000 首；超过就截断并在 UI 上说明 ——
  /// 无上限地翻页会把一个坏掉的 `pagination` 变成无限请求循环。
  /// （1.93.0 写的是 500 条/页 × 20 页，但服务端上限其实是 100，见 [_workPageSize]。）
  static const _maxWorkPages = 50;

  /// 单个歌单的作品每页条数 = playlist 系端点的服务端上限（100）。
  ///
  /// 注意别跟 `/api/works` 的 500 混用：1.93.0 这里写死 500，服务端直接 400
  /// `pageSize: Invalid value`，整个「刷新在线收藏」都失败了。
  static const _workPageSize = KikoeruClient.playlistMaxPageSize;

  /// 同时在飞的歌单请求数。歌单之间没有依赖，但没有节制地并发对公共实例不礼貌
  static const _playlistConcurrency = 4;

  /// 拉取（或重拉）全部歌单及其作品。
  ///
  /// [showLoading] 为 false 时保留旧数据静默刷新 —— 收藏操作的收尾用这个，
  /// 免得网格在用户眼皮底下闪一下白。
  Future<void> refresh({bool showLoading = true}) async {
    if (!mounted) return;
    if (!_ref.read(onlineLoggedInProvider)) {
      state = OnlineFavoritesState(index: OnlineFavorites.empty);
      return;
    }
    if (showLoading) state = state.copyWith(loading: true, clearError: true);
    final client = _ref.read(onlineClientProvider);
    try {
      final playlists = await _fetchPlaylists(client);
      final worksById = <String, List<OnlineWork>>{};
      var truncated = false;

      for (var start = 0; start < playlists.length; start += _playlistConcurrency) {
        final end = math.min(start + _playlistConcurrency, playlists.length);
        final slice = playlists.sublist(start, end);
        final results = await Future.wait(
          slice.map((p) => _fetchAllWorks(client, p.id)),
        );
        for (var i = 0; i < slice.length; i++) {
          worksById[slice[i].id] = results[i].works;
          if (results[i].truncated) truncated = true;
        }
      }

      if (!mounted) return;
      state = OnlineFavoritesState(
        index: OnlineFavorites(
          playlists: playlists,
          worksById: worksById,
          truncated: truncated,
        ),
      );
    } on KikoeruException catch (e) {
      if (!mounted) return;
      if (e.isUnauthorized) {
        // 令牌过期：清令牌 + 提示重登（裁决 Q7=A，不静默重试）
        await _ref.read(onlineAccountProvider.notifier).handleUnauthorized();
      }
      if (!mounted) return;
      state = state.copyWith(loading: false, error: e.message);
    } catch (e) {
      if (!mounted) return;
      state = state.copyWith(loading: false, error: '歌单加载失败：$e');
    }
  }

  /// 收藏变更后的局部更新：先把结构改掉让 UI 立刻正确，再**后台**拉一次真值。
  ///
  /// 后台那次是为了修正 `works_count`、排序，以及别的客户端（网页版）期间的改动。
  /// 失败也不回滚 —— 本地这份至少不比点之前更错。
  void applyLocal({required OnlineWork work, required PlaylistDiff diff}) {
    if (diff.isEmpty) return;
    state = state.copyWith(
      index: state.index.appliedLocally(work: work, diff: diff),
      clearError: true,
    );
    unawaited(refresh(showLoading: false));
  }

  /// 新建歌单成功后把新歌单并入索引（此时它还没有作品）
  void addPlaylist(OnlinePlaylist playlist) {
    if (state.index.playlists.any((p) => p.id == playlist.id)) {
      unawaited(refresh(showLoading: false));
      return;
    }
    final worksById = {...state.index.worksById, playlist.id: const <OnlineWork>[]};
    state = state.copyWith(
      index: OnlineFavorites(
        playlists: [...state.index.playlists, playlist],
        worksById: worksById,
        truncated: state.index.truncated,
      ),
      clearError: true,
    );
    unawaited(refresh(showLoading: false));
  }

  /// 改名成功后就地更新名字，再后台校准
  void renamePlaylist(String playlistId, String name) {
    state = state.copyWith(
      index: OnlineFavorites(
        playlists: [
          for (final p in state.index.playlists)
            p.id == playlistId ? p.copyWith(name: name) : p,
        ],
        worksById: state.index.worksById,
        truncated: state.index.truncated,
      ),
      clearError: true,
    );
    unawaited(refresh(showLoading: false));
  }

  /// 删除成功后就地把歌单摘掉，再后台校准
  void removePlaylist(String playlistId) {
    state = state.copyWith(
      index: OnlineFavorites(
        playlists: state.index.playlists.where((p) => p.id != playlistId).toList(),
        worksById: {
          for (final entry in state.index.worksById.entries)
            if (entry.key != playlistId) entry.key: entry.value,
        },
        truncated: state.index.truncated,
      ),
      clearError: true,
    );
    unawaited(refresh(showLoading: false));
  }

  Future<List<OnlinePlaylist>> _fetchPlaylists(KikoeruClient client) async {
    final out = <OnlinePlaylist>[];
    for (var page = 1; page <= _maxPlaylistPages; page++) {
      final result =
          await client.fetchPlaylists(page: page, pageSize: _playlistPageSize);
      out.addAll(result.playlists);
      if (result.playlists.isEmpty || out.length >= result.totalCount) break;
    }
    return out;
  }

  Future<({List<OnlineWork> works, bool truncated})> _fetchAllWorks(
    KikoeruClient client,
    String playlistId,
  ) async {
    final works = <OnlineWork>[];
    for (var page = 1; page <= _maxWorkPages; page++) {
      final result = await client.fetchPlaylistWorks(
        playlistId,
        page: page,
        pageSize: _workPageSize,
      );
      works.addAll(result.works);
      if (result.works.isEmpty || works.length >= result.totalCount) {
        return (works: works, truncated: false);
      }
    }
    return (works: works, truncated: true);
  }
}

final onlineFavoritesProvider =
    StateNotifierProvider<OnlineFavoritesNotifier, OnlineFavoritesState>(
  (ref) => OnlineFavoritesNotifier(ref),
);
