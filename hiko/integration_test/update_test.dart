import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:hiko/data/update_checker.dart';
import 'package:hiko/main.dart' as app;
import 'package:hiko/platform/platform_service.dart';

/// 应用内更新全链端到端(模拟器):
/// 启动 → 拉 GitHub 最新 Release → 以旧版本号判定「有更新」→
/// 流式下载 APK 到 cache → 原生 installApk 调起系统安装器。
/// 运行:flutter test integration_test/update_test.dart -d emulator-5554
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('检查更新 → 下载 APK → 调起系统安装器', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    // 1. 拉最新 Release(真实 GitHub API)
    final release = await UpdateChecker.fetchLatestRelease();
    expect(release.tagName, startsWith('v'));

    // 2. 旧版本号必须判定为「有更新」(设置页比较逻辑同一纯函数)
    expect(UpdateChecker.isNewer('1.0.0', release.tagName), isTrue);

    // 3. Android 资产存在且流式下载成功(cache 目录)
    final asset = UpdateChecker.pickAsset(release, 'android');
    expect(asset, isNotNull, reason: 'latest release 应含 .apk');
    final dest = await UpdateChecker.suggestDestPath(asset!);
    var progressSeen = false;
    await UpdateChecker.downloadAsset(asset, dest, onProgress: (received, total) {
      if (received > 0 && total > 0) progressSeen = true;
    });
    expect(progressSeen, isTrue, reason: '下载进度回调应触发');
    final file = File(dest);
    expect(await file.exists(), isTrue);
    expect(await file.length(), asset.size,
        reason: '下载字节数应与 GitHub 资产 size 一致');

    // 4. 原生 installApk:FileProvider + ACTION_VIEW 调起安装器(返回 ok 即成功调起)
    final container =
        ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    await container.read(platformServiceProvider).openDownloadedUpdate(dest);

    // 清理:删除已验证的下载文件(安装器已通过 uri 授权读取)
    await file.delete();
  });
}
