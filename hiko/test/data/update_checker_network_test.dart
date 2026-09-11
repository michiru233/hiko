import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/update_checker.dart';

/// 实网验证:GitHub Releases API 解析(仓库 michiru233/hiko 公开,无需鉴权)
///
/// 默认跳过。匿名额度是「60 次/小时/出口 IP」，而且这个额度挂在**出口 IP** 上、
/// 与本机代理节点上的其他使用者共享（本机实测出口为境外机房 IP，`--noproxy` 也
/// 绕不开，代理在网卡层接管流量）——让它默认参与 `flutter test`，测试结果就会随
/// 别人的 API 用量随机变红。这个波动从 1.49.0 起反复出现在发版记录里。
///
/// 要跑实网时显式启用，并带上 token 走 5000 次/小时的鉴权额度：
///   HIKO_NETWORK_TESTS=1 flutter test \
///     --dart-define=GITHUB_TOKEN="$(gh auth token)" \
///     test/data/update_checker_network_test.dart
void main() {
  test('真实 GitHub API:拉最新 Release,tag 可解析且带双平台资产', () async {
    if (Platform.environment['HIKO_NETWORK_TESTS'] != '1') {
      markTestSkipped('实网测试默认跳过：HIKO_NETWORK_TESTS=1 启用');
      return;
    }

    // 有 GITHUB_TOKEN 时带 Authorization 头绕开匿名限流，否则走匿名请求。
    // 必须写成 const：String.fromEnvironment 只在 const 上下文里才读得到
    // --dart-define；写成 final 会静默取到默认空串，这条分支就永远是死的。
    const token = String.fromEnvironment('GITHUB_TOKEN');
    final headers = token.isEmpty
        ? null
        : {'Authorization': 'Bearer $token'};
    final release = await UpdateChecker.fetchLatestRelease(headers: headers);

    expect(release.tagName, isNotEmpty);
    expect(release.tagName, startsWith('v'));
    // 版本号可被比较逻辑解析
    expect(UpdateChecker.parseVersion(release.tagName), isNot([0, 0, 0]));

    // 资产选择:发版惯例带 macOS zip(Android 暂停后不再发 .apk)
    final macZip = UpdateChecker.pickAsset(release, 'macos');
    expect(macZip, isNotNull, reason: 'latest release 应含 -macos.zip 资产');
    expect(macZip!.size, greaterThan(0));

    // 旧版本号一定落后于最新 release(历史版本判定)
    expect(UpdateChecker.isNewer('1.0.0', release.tagName), isTrue);
    // 最新版本自身不算「有更新」
    final bare = release.tagName.replaceFirst('v', '');
    expect(UpdateChecker.isNewer(bare, release.tagName), isFalse);
  });
}
