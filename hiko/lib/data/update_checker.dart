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

  /// 网页端点（不走 API 限流）。`releases/latest` 会 302 到 `/releases/tag/<tag>`。
  static const repoWebBase = 'https://github.com/michiru233/hiko';

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
  ///
  /// 1.98.0 起带**网页端点兜底**：`api.github.com` 匿名限额是**每 IP 每小时 60 次**，
  /// 手机蜂窝网络的出口 IP（CGNAT）是共享的，经常被整站用户耗光 → 403（安卓实机
  /// 截图踩过）。非 200 时改走 `github.com/.../releases/latest` 的 302 重定向
  /// （网站端点无此限额），从重定向地址解析版本号、按发版命名约定合成下载链接。
  /// 代价是兜底路径拿不到发布说明正文（body 为空，UI 自动隐藏），可接受。
  static Future<GithubRelease> fetchLatestRelease({
    http.Client? client,
    Map<String, String>? headers,
  }) async {
    final c = client ?? http.Client();
    try {
      final resp = await c
          .get(
            Uri.parse('$repoApiBase/releases/latest'),
            headers: {
              // GitHub API 的硬性要求：带 UA 的请求才受理
              'User-Agent': 'hiko-update-check',
              'Accept': 'application/vnd.github+json',
              ...?headers,
            },
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        return parseRelease(
          await compute(_decodeJson, resp.bodyBytes),
        );
      }
      return await fetchLatestReleaseViaWeb(client: c, headers: headers);
    } finally {
      if (client == null) c.close();
    }
  }

  /// 网页端点兜底：`github.com/<repo>/releases/latest` 302 → `.../releases/tag/<tag>`。
  /// 刻意 `followRedirects = false`：package:http 的 Response 不带最终 URL，
  /// 只有 Location 头能可靠给出目标版本。
  static Future<GithubRelease> fetchLatestReleaseViaWeb({
    http.Client? client,
    Map<String, String>? headers,
  }) async {
    final c = client ?? http.Client();
    try {
      final request = http.Request(
        'GET',
        Uri.parse('$repoWebBase/releases/latest'),
      )
        ..followRedirects = false
        ..headers['User-Agent'] = 'hiko-update-check';
      if (headers != null) request.headers.addAll(headers);
      final resp = await c.send(request).timeout(const Duration(seconds: 10));
      if (resp.statusCode < 300 || resp.statusCode >= 400) {
        throw HttpException(
          'GitHub 网页端点 ${resp.statusCode}（API 403 通常是无鉴权限流：'
          '每 IP 每小时 60 次，稍后再试）',
        );
      }
      final location = resp.headers['location'];
      final release = location == null ? null : releaseFromRedirect(location);
      if (release == null) {
        throw HttpException('无法从 GitHub 重定向解析版本：$location');
      }
      return release;
    } finally {
      if (client == null) c.close();
    }
  }

  /// 从重定向地址解析版本并合成 Release（纯函数）。
  ///
  /// 吃绝对地址（`https://github.com/.../releases/tag/v1.97.2`）与相对路径
  /// （`/michiru233/hiko/releases/tag/v1.97.2`）两种形态。不是发版 URL 时返回
  /// null —— 解析失败别硬猜，让上层报错。
  static GithubRelease? releaseFromRedirect(String location) {
    final path = Uri.tryParse(location)?.path ?? location;
    final match =
        RegExp(r'/releases/tag/(v?\d+\.\d+\.\d+.*)$').firstMatch(path);
    if (match == null) return null;
    return releaseFromTag(match.group(1)!);
  }

  /// 按本仓库的**发版命名约定**从 tag 合成 Release：
  /// 资产恒为 `hiko-<tag>-android.apk` / `hiko-<tag>-macos.zip`
  /// （Windows 与 macOS 共用 macos.zip，与 [pickAsset] 的约定一致），
  /// 直链 `github.com/.../releases/download/<tag>/<name>` 不依赖 API。
  ///
  /// [platform] 默认当前平台；size 置 0 —— 下载进度以响应的
  /// `contentLength` 为准（见 [downloadAsset]）。
  static GithubRelease releaseFromTag(
    String tag, {
    String? platform,
  }) {
    final norm = (platform ?? Platform.operatingSystem).toLowerCase();
    final assetName = norm == 'android'
        ? 'hiko-$tag-android.apk'
        : 'hiko-$tag-macos.zip';
    return GithubRelease(
      tagName: tag,
      name: '',
      body: '',
      assets: [
        GithubAsset(
          name: assetName,
          url: '$repoWebBase/releases/download/$tag/$assetName',
          size: 0,
        ),
      ],
    );
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
