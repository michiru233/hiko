import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/update_checker.dart';

/// 实网验证:GitHub Releases API 解析(仓库 michiru233/hiko 公开,无需鉴权)
void main() {
  test('真实 GitHub API:拉最新 Release,tag 可解析且带双平台资产', () async {
    final release = await UpdateChecker.fetchLatestRelease();

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
