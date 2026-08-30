import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// GitHub Release 资产
class GithubAsset {
  final String name; // 如 app-release.apk / hiko-v1.30.0-macos.zip
  final String url; // browser_download_url
  final int size; // 字节

  const GithubAsset({required this.name, required this.url, required this.size});
}

/// GitHub Release(仅取更新功能所需字段)
class GithubRelease {
  final String tagName; // 如 v1.30.0
  final String name; // 标题
  final String body; // 发布说明
  final List<GithubAsset> assets;

  const GithubRelease({
    required this.tagName,
    required this.name,
    required this.body,
    required this.assets,
  });
}

/// GitHub 更新检查(纯逻辑可单测,IO 仅 fetchLatestRelease / downloadAsset)
class UpdateChecker {
  static const repoApiBase = 'https://api.github.com/repos/michiru233/hiko';

  /// 解析 releases/latest 的 JSON(纯函数)
  static GithubRelease parseRelease(Map<String, dynamic> json) => GithubRelease(
        tagName: json['tag_name'] as String? ?? '',
        name: json['name'] as String? ?? '',
        body: json['body'] as String? ?? '',
        assets: [
          for (final a in (json['assets'] as List? ?? <dynamic>[]))
            GithubAsset(
              name: (a as Map)['name'] as String? ?? '',
              url: a['browser_download_url'] as String? ?? '',
              size: (a['size'] as num?)?.toInt() ?? 0,
            ),
        ],
      );

  /// 版本字符串 → [major, minor, patch];容忍 v 前缀与 +build 后缀;非法段按 0
  static List<int> parseVersion(String version) {
    final core = version.trim().replaceFirst(RegExp('^v'), '').split('+').first;
    final parts = core.split('.');
    return [
      for (var i = 0; i < 3; i++) int.tryParse(i < parts.length ? parts[i] : '0') ?? 0,
    ];
  }

  /// 比较版本:a<b 返回 -1,相等 0,a>b 返回 1
  static int compareVersions(String a, String b) {
    final va = parseVersion(a);
    final vb = parseVersion(b);
    for (var i = 0; i < 3; i++) {
      if (va[i] != vb[i]) return va[i].compareTo(vb[i]);
    }
    return 0;
  }

  /// latest 是否比 current 新(容忍 v 前缀)
  static bool isNewer(String current, String latest) =>
      compareVersions(current, latest) < 0;

  /// 按平台选下载资产:
  /// - macos:发版惯例 `*-macos.zip`;
  /// - android:`.apk` 结尾(排除 .aab);
  /// 无匹配返回 null。
  static GithubAsset? pickAsset(GithubRelease release, String platform) {
    final norm = platform.toLowerCase();
    if (norm == 'macos' || norm == 'windows') {
      return release.assets
          .where((a) => a.name.toLowerCase().endsWith('-macos.zip'))
          .firstOrNull;
    }
    if (norm == 'android') {
      return release.assets
          .where((a) => a.name.toLowerCase().endsWith('.apk'))
          .firstOrNull;
    }
    return null;
  }

  /// 拉取最新 Release(10 秒超时;失败抛异常由调用方提示)。
  /// [headers] 供测试注入 token 以绕开匿名限流；置 null 走匿名请求（与旧行为一致）。
  static Future<GithubRelease> fetchLatestRelease({
    http.Client? client,
    Map<String, String>? headers,
  }) async {
    final c = client ?? http.Client();
    try {
      final resp = await c
          .get(Uri.parse('$repoApiBase/releases/latest'), headers: headers)
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        throw HttpException('GitHub API ${resp.statusCode}');
      }
      return parseRelease(
        await compute(_decodeJson, resp.bodyBytes),
      );
    } finally {
      if (client == null) c.close();
    }
  }

  static Map<String, dynamic> _decodeJson(List<int> body) =>
      (const JsonDecoder().convert(utf8.decode(body)) as Map<String, dynamic>);

  /// 流式下载资产到 destPath,回调 (已收字节, 总字节)
  static Future<void> downloadAsset(
    GithubAsset asset,
    String destPath, {
    void Function(int received, int total)? onProgress,
    http.Client? client,
  }) async {
    final c = client ?? http.Client();
    try {
      final request = http.Request('GET', Uri.parse(asset.url));
      final resp = await c.send(request).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw HttpException('下载 ${resp.statusCode}');
      final total = resp.contentLength ?? asset.size;
      final sink = File(destPath).openWrite();
      var received = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received, total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      if (client == null) c.close();
    }
  }

  /// 更新包下载落点:
  /// - Android:应用 cache 目录(getTemporaryDirectory = getCacheDir,
  ///   处于 FileProvider cache-path 覆盖范围,可直接调起安装器;code_cache 不行);
  /// - 桌面:~/Downloads(macOS 解压拖入 /Applications 由用户完成)。
  static Future<String> suggestDestPath(GithubAsset asset) async {
    if (Platform.isAndroid) {
      final dir = await getTemporaryDirectory();
      return p.join(dir.path, 'hiko_update_${asset.name}');
    }
    final home = Platform.environment['HOME'] ?? Directory.systemTemp.path;
    final downloads = Directory(p.join(home, 'Downloads'));
    if (!await downloads.exists()) await downloads.create(recursive: true);
    return p.join(downloads.path, asset.name);
  }
}
