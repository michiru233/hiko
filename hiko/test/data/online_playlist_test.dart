import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:hiko/data/online/kikoeru_client.dart';
import 'package:hiko/data/online/online_models.dart';

/// 1.93.0 在线收藏（asmr.one 歌单体系）的模型与纯函数。
///
/// 这里钉的全是**实测得来的服务端契约**（2026-09-26 对真实账号跑过）：
/// id 是 UUID 字符串、系统歌单返回原始 key、privacy 三档、create 与 add/remove
/// 的参数形态不一致。契约一变这里先红，比线上才发现好。
void main() {
  group('OnlinePlaylist 解析', () {
    test('完整字段：id 是 UUID 字符串，但 latestWorkID 是数字', () {
      final playlist = OnlinePlaylist.fromJson({
        'id': '338ab0b8-7c0e-43b9-b3f6-19c314d252bf',
        'user_name': '1828612500',
        'privacy': 0,
        'locale': '',
        'playback_count': 0,
        'name': '__SYS_PLAYLIST_LIKED',
        'description': '',
        'created_at': '2023-07-03 09:53:02',
        'updated_at': '2026-09-26 05:19:58',
        'works_count': 92,
        'latestWorkID': 1626202,
        'mainCoverUrl': 'https://api.asmr.one/api/cover/1626202.jpg?type=main',
      });
      expect(playlist.id, '338ab0b8-7c0e-43b9-b3f6-19c314d252bf');
      expect(playlist.worksCount, 92);
      expect(playlist.latestWorkId, 1626202);
      expect(playlist.userName, '1828612500');
      expect(playlist.hasCover, isTrue);
    });

    test('缺字段不炸：works_count / latestWorkID / mainCoverUrl 都可省略', () {
      final playlist = OnlinePlaylist.fromJson({'id': 'x', 'name': '听完'});
      expect(playlist.worksCount, 0);
      expect(playlist.latestWorkId, isNull);
      expect(playlist.hasCover, isFalse);
      expect(playlist.privacy, OnlinePlaylist.defaultPrivacy);
    });

    test('空歌单的 mainCoverUrl 是服务端占位图，不算有封面', () {
      final playlist = OnlinePlaylist.fromJson({
        'id': 'x',
        'name': '空',
        'mainCoverUrl': '/statics/no-image.jpg',
      });
      expect(playlist.hasCover, isFalse);
    });
  });

  group('系统保留歌单', () {
    OnlinePlaylist of(String name) =>
        OnlinePlaylist(id: 'id-$name', name: name, worksCount: 3);

    test('名字是原始 key，展示名归一到中文', () {
      expect(of(OnlinePlaylist.sysLiked).displayName, '我喜欢的');
      expect(of(OnlinePlaylist.sysMarked).displayName, '我标记的');
      expect(of('听完').displayName, '听完');
    });

    test('系统歌单不可改名 / 不可删除，普通歌单可以', () {
      expect(of(OnlinePlaylist.sysLiked).editable, isFalse);
      expect(of(OnlinePlaylist.sysLiked).isSystem, isTrue);
      expect(of(OnlinePlaylist.sysLiked).isLiked, isTrue);
      expect(of(OnlinePlaylist.sysMarked).editable, isFalse);
      expect(of('听完').editable, isTrue);
      expect(of('听完').isSystem, isFalse);
    });

    test('空名字回退「未命名歌单」，不留空白按钮', () {
      expect(of('  ').displayName, '未命名歌单');
    });

    test('privacy 三档的中文名', () {
      expect(
        const OnlinePlaylist(id: 'x', name: 'n', privacy: 0).privacyLabel,
        '私享',
      );
      expect(
        const OnlinePlaylist(id: 'x', name: 'n', privacy: 1).privacyLabel,
        '不公开',
      );
      expect(
        const OnlinePlaylist(id: 'x', name: 'n', privacy: 2).privacyLabel,
        '公开',
      );
      // 越界值不崩，退回最严格的私享
      expect(
        const OnlinePlaylist(id: 'x', name: 'n', privacy: 9).privacyLabel,
        '私享',
      );
    });
  });

  group('分页包装', () {
    test('OnlinePlaylistPage 读 pagination', () {
      final page = OnlinePlaylistPage.fromJson({
        'playlists': [
          {'id': 'a', 'name': 'p1'},
          {'id': 'b', 'name': 'p2'},
        ],
        'pagination': {'page': 2, 'pageSize': 50, 'totalCount': 3},
      });
      expect(page.playlists.map((p) => p.id), ['a', 'b']);
      expect(page.page, 2);
      expect(page.totalCount, 3);
    });

    test('PlaylistWorkPage 复用 OnlineWork 结构', () {
      final page = PlaylistWorkPage.fromJson({
        'works': [
          {'id': 1657200, 'title': 'x', 'source_id': 'RJ01657200'},
        ],
        'pagination': {'page': 1, 'pageSize': 500, 'totalCount': 1},
      });
      expect(page.works.single.id, 1657200);
      expect(page.works.single.rjCode, 'RJ01657200');
      expect(page.totalCount, 1);
    });

    test('字段缺失时返回空列表而不是抛异常', () {
      expect(OnlinePlaylistPage.fromJson({}).playlists, isEmpty);
      expect(PlaylistWorkPage.fromJson({}).works, isEmpty);
    });

    test('带 exist 的条目解析出三态：true / false / null', () {
      final page = OnlinePlaylistPage.fromJson({
        'playlists': [
          {'id': 'a', 'name': 'p', 'exist': true},
          {'id': 'b', 'name': 'q', 'exist': false},
          {'id': 'c', 'name': 'r'},
        ],
      });
      expect(page.playlists[0].exist, isTrue);
      expect(page.playlists[1].exist, isFalse);
      expect(page.playlists[2].exist, isNull,
          reason: '没查过 ≠ 明确不在，否则预勾选会先抹掉再跳回来');
    });
  });

  group('OnlineUser', () {
    test('未登录：loggedIn=false，name 为空', () {
      final user = OnlineUser.fromJson({
        'user': {'loggedIn': false},
        'auth': true,
        'reg': true,
      });
      expect(user.loggedIn, isFalse);
      expect(user.name, '');
    });

    test('已登录：取 name / group / email', () {
      final user = OnlineUser.fromJson({
        'user': {
          'loggedIn': true,
          'name': '1828612500',
          'group': 'user',
          'email': null,
          'recommenderUuid': '1a44cc09-7192-48d1-81f8-726c808847f3',
        },
        'auth': true,
        'reg': true,
      });
      expect(user.loggedIn, isTrue);
      expect(user.name, '1828612500');
      expect(user.group, 'user');
      expect(user.email, isNull);
    });

    test('user 段缺失按未登录处理', () {
      expect(OnlineUser.fromJson({}).loggedIn, isFalse);
      expect(OnlineUser.fromJson({'user': 'oops'}).loggedIn, isFalse);
    });
  });

  group('planPlaylistDiff（多选菜单的差分，裁决 Q8=B）', () {
    test('只加不减：全部落在 addTo', () {
      final diff = planPlaylistDiff(
        current: {'a'},
        desired: {'a', 'b', 'c'},
      );
      expect(diff.addTo, ['b', 'c']);
      expect(diff.removeFrom, isEmpty);
      expect(diff.isNotEmpty, isTrue);
      expect(diff.requestCount, 2);
    });

    test('只减不加：全部落在 removeFrom', () {
      final diff = planPlaylistDiff(
        current: {'a', 'b'},
        desired: {'a'},
      );
      expect(diff.addTo, isEmpty);
      expect(diff.removeFrom, ['b']);
      expect(diff.requestCount, 1);
    });

    test('既有加也有减：两边都给，且互不重叠', () {
      final diff = planPlaylistDiff(
        current: {'a', 'b'},
        desired: {'b', 'c'},
      );
      expect(diff.addTo, ['c']);
      expect(diff.removeFrom, ['a']);
      expect(diff.addTo.toSet().intersection(diff.removeFrom.toSet()), isEmpty);
    });

    test('没动就一条请求都不发', () {
      final diff = planPlaylistDiff(current: {'a'}, desired: {'a'});
      expect(diff.isEmpty, isTrue);
      expect(diff.requestCount, 0);
    });

    test('从零勾到全选 / 从全选清空', () {
      final add = planPlaylistDiff(current: {}, desired: {'a', 'b'});
      expect(add.addTo, ['a', 'b']);
      final remove = planPlaylistDiff(current: {'a', 'b'}, desired: {});
      expect(remove.removeFrom, ['a', 'b']);
    });
  });

  group('令牌归一（sanitizeToken）', () {
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig';

    test('原样保留合法 JWT', () {
      expect(KikoeruClient.sanitizeToken(jwt), jwt);
    });

    test('剥掉复制时带上的噪声前缀 —— 实测带前缀会被服务端判 invalid token', () {
      expect(KikoeruClient.sanitizeToken('__q_strn|$jwt'), jwt);
    });

    test('剥掉 Bearer 前缀与多余空白 / 换行', () {
      expect(KikoeruClient.sanitizeToken('Bearer $jwt'), jwt);
      expect(KikoeruClient.sanitizeToken('  bearer $jwt\n'), jwt);
      expect(KikoeruClient.sanitizeToken(' $jwt '), jwt);
    });

    test('空串与纯空白得到空串（视为未登录）', () {
      expect(KikoeruClient.sanitizeToken(''), '');
      expect(KikoeruClient.sanitizeToken('   '), '');
    });

    test('客户端构造时就归一，authenticated 跟着它走', () {
      final client = KikoeruClient(baseUrl: 'https://api.asmr.one', token: 'x|$jwt');
      expect(client.token, jwt);
      expect(client.authenticated, isTrue);
      expect(
        KikoeruClient(baseUrl: 'https://api.asmr.one').authenticated,
        isFalse,
      );
      // 匿名副本不带令牌（登录端点用）
      expect(client.anonymous().authenticated, isFalse);
    });
  });

  group('服务端错误文案（parseServerError）', () {
    test('{"error":"…"} —— 登录失败就是这种，中文原文直接可用', () {
      expect(
        KikoeruClient.parseServerError('{"error":"用户名或密码错误."}'),
        '用户名或密码错误.',
      );
      expect(
        KikoeruClient.parseServerError('{"error":"invalid token"}'),
        'invalid token',
      );
    });

    test('{"errors":[{"msg","param"}]} —— express-validator 形态', () {
      expect(
        KikoeruClient.parseServerError(
          '{"errors":[{"value":"RJ01626202","msg":"Invalid value",'
          '"param":"works[0]","location":"body"}]}',
        ),
        'Invalid value（works[0]）',
      );
      expect(
        KikoeruClient.parseServerError(
          '{"errors":[{"msg":"boom"}]}',
        ),
        'boom',
      );
    });

    test('{"message":"…"} 兜底', () {
      expect(
        KikoeruClient.parseServerError('{"message":"nope"}'),
        'nope',
      );
    });

    test('非 JSON（网关 HTML 错误页）返回 null，交给状态码兜底', () {
      expect(KikoeruClient.parseServerError(''), isNull);
      expect(KikoeruClient.parseServerError('<html>502</html>'), isNull);
      expect(KikoeruClient.parseServerError('[1,2,3]'), isNull);
      expect(KikoeruClient.parseServerError('{}'), isNull);
    });
  });

  group('KikoeruException', () {
    test('401 才算令牌失效；网络层失败（无状态码）不算', () {
      expect(
        KikoeruException('登录已过期，请重新登录', null, 401).isUnauthorized,
        isTrue,
      );
      expect(
        KikoeruException('服务器返回 500', null, 500).isUnauthorized,
        isFalse,
      );
      expect(KikoeruException('连不上').isUnauthorized, isFalse);
    });
  });

  // 1.93.0 发布后用户实测「刷新在线收藏」报 `pageSize: Invalid value`：
  // playlist 系端点（get-playlists / get-playlist-works /
  // get-work-exist-status-in-my-playlists）**共用同一个校验器，上限 100**，
  // 传 200/500 是**整个请求被 400 拒掉**。而 `/api/works` 那一系能吃 500，
  // 是另一套校验 —— 当时把两边的上限混用了。
  group('playlist 系端点 pageSize 上限（1.93.1 回归锁）', () {
    test('上限是 100，夹取函数把越界值就地纠正', () {
      expect(KikoeruClient.playlistMaxPageSize, 100);
      expect(KikoeruClient.clampPlaylistPageSize(0), 1);
      expect(KikoeruClient.clampPlaylistPageSize(-5), 1);
      expect(KikoeruClient.clampPlaylistPageSize(1), 1);
      expect(KikoeruClient.clampPlaylistPageSize(100), 100);
      expect(KikoeruClient.clampPlaylistPageSize(101), 100);
      expect(KikoeruClient.clampPlaylistPageSize(200), 100);
      expect(KikoeruClient.clampPlaylistPageSize(500), 100);
    });

    test('/api/works 那一系的上限不同，别互相套用', () {
      // 这个断言的意义在于钉住「两套校验」这个事实：
      // 如果哪天有人把 defaultPageSize 当成 playlist 的上限，这条会红。
      expect(KikoeruClient.defaultPageSize, lessThanOrEqualTo(100));
      expect(KikoeruClient.playlistMaxPageSize, greaterThanOrEqualTo(20));
    });

    test('三个端点发出的 pageSize 一律被夹到 100（即使调用方传越界值）', () async {
      final requested = <Uri>[];
      HttpOverrides.global = _UrlRecorder(requested);
      addTearDown(() => HttpOverrides.global = null);

      final client = KikoeruClient(
        baseUrl: 'https://api.example.invalid',
        token: 'jwt',
      );
      // 每次都传越界值；GET 会逐个镜像重试，所以只断言「发出去的 URI 全部合规」
      await _swallow(() => client.fetchPlaylists(pageSize: 500));
      await _swallow(() => client.fetchPlaylistWorks('pid', pageSize: 999));
      await _swallow(() => client.fetchWorkPlaylistStatus(1, pageSize: 200));

      expect(requested, isNotEmpty, reason: '应当至少发出一次请求');
      for (final uri in requested) {
        expect(uri.queryParameters['pageSize'], '100', reason: '$uri');
      }
    });

    test('不传 pageSize 时默认值同样在 100 以内', () async {
      final requested = <Uri>[];
      HttpOverrides.global = _UrlRecorder(requested);
      addTearDown(() => HttpOverrides.global = null);

      final client = KikoeruClient(
        baseUrl: 'https://api.example.invalid',
        token: 'jwt',
      );
      await _swallow(client.fetchPlaylists);
      await _swallow(() => client.fetchPlaylistWorks('pid'));
      await _swallow(() => client.fetchWorkPlaylistStatus(1));

      expect(requested, isNotEmpty);
      for (final uri in requested) {
        expect(uri.queryParameters['pageSize'], '100', reason: '$uri');
      }
    });
  });
}

/// 吞掉异常只为了拿到「请求发出时用的 URL」——单测不联网，请求必失败
Future<void> _swallow(Future<Object?> Function() call) async {
  try {
    await call();
  } catch (_) {
    // 期望之内：连不上
  }
}

/// 记录请求 URL 但不联网的 HttpClient（照抄 online_work_card_test 的做法）
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
