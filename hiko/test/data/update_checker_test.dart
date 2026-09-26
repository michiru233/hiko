import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/update_checker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('版本比较', () {
    test('parseVersion:容忍 v 前缀、+build 后缀与缺省段', () {
      expect(UpdateChecker.parseVersion('v1.30.0'), [1, 30, 0]);
      expect(UpdateChecker.parseVersion('1.30.0+33'), [1, 30, 0]);
      expect(UpdateChecker.parseVersion('1.30'), [1, 30, 0]);
      expect(UpdateChecker.parseVersion('垃圾'), [0, 0, 0]);
    });

    test('compareVersions:patch/minor/major 逐级比较', () {
      expect(UpdateChecker.compareVersions('1.29.0', 'v1.30.0'), -1);
      expect(UpdateChecker.compareVersions('1.30.0', '1.30.0'), 0);
      expect(UpdateChecker.compareVersions('2.0.0', '1.99.99'), 1);
      expect(UpdateChecker.compareVersions('1.30.1', '1.30.0'), 1);
    });

    test('isNewer:仅当 latest 严格大于 current', () {
      expect(UpdateChecker.isNewer('1.29.0', 'v1.30.0'), isTrue);
      expect(UpdateChecker.isNewer('1.30.0', 'v1.30.0'), isFalse);
      expect(UpdateChecker.isNewer('1.31.0', 'v1.30.0'), isFalse);
    });
  });

  group('release 解析与资产选择', () {
    final release = UpdateChecker.parseRelease({
      'tag_name': 'v1.30.0',
      'name': 'v1.30.0',
      'body': '更新说明',
      'assets': [
        {'name': 'app-release.apk', 'browser_download_url': 'u1', 'size': 100},
        {'name': 'hiko-v1.30.0-macos.zip', 'browser_download_url': 'u2', 'size': 200},
        {'name': 'notes.txt', 'browser_download_url': 'u3', 'size': 5},
      ],
    });

    test('parseRelease:tag/说明/资产齐全', () {
      expect(release.tagName, 'v1.30.0');
      expect(release.body, '更新说明');
      expect(release.assets.length, 3);
      expect(release.assets.first.url, 'u1');
    });

    test('pickAsset:android 选 .apk,macos 选 -macos.zip', () {
      expect(UpdateChecker.pickAsset(release, 'android')!.name, 'app-release.apk');
      expect(UpdateChecker.pickAsset(release, 'macos')!.name, 'hiko-v1.30.0-macos.zip');
    });

    test('pickAsset:无匹配返回 null(不误选 .txt/.zip 之外的资产)', () {
      final empty = GithubRelease(
          tagName: 'v1', name: 'n', body: '', assets: const []);
      expect(UpdateChecker.pickAsset(empty, 'android'), isNull);
      expect(UpdateChecker.pickAsset(empty, 'macos'), isNull);

      final apkOnly = const GithubAsset(name: 'bundle.aab', url: 'u', size: 1);
      expect(
        UpdateChecker.pickAsset(
          GithubRelease(tagName: 'v1', name: 'n', body: '', assets: [apkOnly]),
          'android',
        ),
        isNull,
      );
    });
  });

  group('fetchLatestRelease UTF-8 解码', () {
    test('含中文发布说明的响应体按 UTF-8 解码不乱码(完整请求路径)', () async {
      const body = 'v1.38.0 更新说明：修复检查更新中文乱码，中文版本介绍正常显示。';
      final jsonBytes = utf8.encode(jsonEncode({
        'tag_name': 'v1.38.0',
        'name': 'v1.38.0',
        'body': body,
        'assets': [
          {
            'name': 'hiko-v1.38.0-macos.zip',
            'browser_download_url': 'https://example.com/hiko-v1.38.0-macos.zip',
            'size': 123,
          },
        ],
      }));
      final client = MockClient(
        (request) async => http.Response.bytes(jsonBytes, 200),
      );

      final release = await UpdateChecker.fetchLatestRelease(client: client);

      expect(release.tagName, 'v1.38.0');
      expect(release.body, body);
      expect(release.assets.single.name, 'hiko-v1.38.0-macos.zip');
    });
  });

  // ------------------------------------------------------------ 1.98.0 网页端点兜底
  //
  // api.github.com 匿名限额每 IP 每小时 60 次，手机 CGNAT 出口经常被耗光 → 403
  // （安卓实机截图踩过）。兜底 = releases/latest 的 302 重定向。

  group('releaseFromRedirect / releaseFromTag（纯函数）', () {
    test('绝对与相对重定向地址都能解析出版本号', () {
      final abs = UpdateChecker.releaseFromRedirect(
        'https://github.com/michiru233/hiko/releases/tag/v1.97.2',
      );
      expect(abs!.tagName, 'v1.97.2');
      expect(abs.body, isEmpty, reason: '兜底路径拿不到发布说明，UI 会自动隐藏');

      final rel = UpdateChecker.releaseFromRedirect(
        '/michiru233/hiko/releases/tag/v1.98.0',
      );
      expect(rel!.tagName, 'v1.98.0');
    });

    test('不是发版 URL 时返回 null（不硬猜）', () {
      expect(UpdateChecker.releaseFromRedirect('/michiru233/hiko'), isNull);
      expect(
        UpdateChecker.releaseFromRedirect(
          'https://github.com/michiru233/hiko/releases',
        ),
        isNull,
      );
    });

    test('按发版命名约定合成资产链接，与 pickAsset 的约定一致', () {
      final android = UpdateChecker.releaseFromTag(
        'v1.98.0',
        platform: 'android',
      );
      expect(android.assets.single.name, 'hiko-v1.98.0-android.apk');
      expect(
        android.assets.single.url,
        'https://github.com/michiru233/hiko/releases/download/v1.98.0/hiko-v1.98.0-android.apk',
      );
      expect(UpdateChecker.pickAsset(android, 'android')!.name,
          'hiko-v1.98.0-android.apk');

      // Windows 与 macOS 共用 macos.zip（pickAsset 的既有约定）
      final macos = UpdateChecker.releaseFromTag(
        'v1.98.0',
        platform: 'macos',
      );
      expect(macos.assets.single.name, 'hiko-v1.98.0-macos.zip');
      expect(UpdateChecker.pickAsset(macos, 'windows')!.name,
          'hiko-v1.98.0-macos.zip');
    });
  });

  group('fetchLatestRelease 网页端点兜底（403 场景）', () {
    test('API 403 时自动改走 releases/latest 的 302 重定向', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          // 匿名限流的典型响应
          return http.Response('{"message": "API rate limit exceeded"}', 403);
        }
        if (request.url.path.endsWith('/releases/latest')) {
          return http.Response(
            '',
            302,
            headers: {
              'location': '/michiru233/hiko/releases/tag/v1.98.0',
            },
          );
        }
        return http.Response('not found', 404);
      });

      final release = await UpdateChecker.fetchLatestRelease(client: client);

      expect(release.tagName, 'v1.98.0');
      // 兜底合成按当前平台命名（fetchLatestReleaseViaWeb 不传 platform 时
      // 用 Platform.operatingSystem），测试在哪个宿主跑就断言哪个平台。
      final asset = UpdateChecker.pickAsset(release, Platform.operatingSystem);
      final expected =
          UpdateChecker.releaseFromTag('v1.98.0').assets.single.url;
      expect(
        asset!.url,
        expected,
        reason: '兜底合成的链接必须能直接进 downloadAsset',
      );
    });

    test('网页端点也没拿到重定向时抛出可读的异常（不再裸报 403）', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('', 403);
        }
        return http.Response('', 500);
      });

      await expectLater(
        UpdateChecker.fetchLatestRelease(client: client),
        throwsA(isA<HttpException>()),
      );
    });

    test('重定向地址不符合发版形态时抛异常（不硬猜）', () async {
      final client = MockClient((request) async {
        if (request.url.host == 'api.github.com') {
          return http.Response('', 403);
        }
        return http.Response(
          '',
          302,
          headers: {'location': '/michiru233/hiko'},
        );
      });

      await expectLater(
        UpdateChecker.fetchLatestRelease(client: client),
        throwsA(isA<HttpException>()),
      );
    });
  });
}
