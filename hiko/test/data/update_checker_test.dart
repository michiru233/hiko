import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/data/update_checker.dart';

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
}
