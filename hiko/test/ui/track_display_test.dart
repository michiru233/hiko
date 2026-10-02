import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/ui/widgets/detail_kit.dart';

/// hikoTrackDisplayName（1.99.12）：剥掉与序号列重复的 TrackNN_ 类前缀。
void main() {
  test('Track 前缀（下划线分隔）被剥掉', () {
    expect(
      hikoTrackDisplayName('Track01_邊舌吻邊用粗大腿撸雞'),
      '邊舌吻邊用粗大腿撸雞',
    );
  });

  test('小写 track + 连字符/空格/点分隔同样识别', () {
    expect(hikoTrackDisplayName('track2-在對小寶寶說話'), '在對小寶寶說話');
    expect(hikoTrackDisplayName('Track 03.用金色比基尼'), '用金色比基尼');
    expect(hikoTrackDisplayName('track04 誘惑'), '誘惑');
  });

  test('无前缀曲名原样保留', () {
    expect(hikoTrackDisplayName('雨夜耳语'), '雨夜耳语');
    expect(hikoTrackDisplayName('01_/manual 的名字'), '01_/manual 的名字');
  });

  test('剥完为空则保留原名（名字就叫 Track01）', () {
    expect(hikoTrackDisplayName('Track01'), 'Track01');
    expect(hikoTrackDisplayName('track_01'), 'track_01'); // 无数字不成前缀
  });

  test('Track 后非数字不是前缀', () {
    expect(hikoTrackDisplayName('TrackBook_不是前缀'), 'TrackBook_不是前缀');
    expect(hikoTrackDisplayName('Track01xxx_紧贴数字'), 'Track01xxx_紧贴数字');
  });

  test('只剥第一个前缀，正文里的 track 不受影响', () {
    expect(
      hikoTrackDisplayName('Track01_讲述 track  history'),
      '讲述 track  history',
    );
  });
}
