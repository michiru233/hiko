import 'package:flutter_test/flutter_test.dart';
import 'package:hiko/lyrics/lyrics_resolver.dart';
import 'package:hiko/models/track.dart';

void main() {
  test('lyricsText 字段优先:content:// 音轨直接解析嵌入文本,不碰磁盘', () async {
    final track = Track(
      index: 0,
      name: '01',
      // Android SAF 音轨 URL 无法映射本地路径,过去 resolve 必返回 null
      url: 'content://com.android.externalstorage.documents/tree/xxx/document/01.mp3',
      lyricsText: '[00:01.00]ささやき\n[00:03.50]おやすみ\n',
    );
    final lyrics = await LyricsResolver.resolve(track);
    expect(lyrics, isNotNull);
    expect(lyrics!.lines, isNotEmpty);
    // LRC 时间戳被解析为对应行
    final first = lyrics.lines.first;
    expect(first.text, 'ささやき');
  });

  test('lyricsText 为 VTT/SRT 形态(含 --> )时走 VttParser', () async {
    final track = Track(
      index: 0,
      name: '02',
      url: 'content://xxx/02.wav',
      lyricsText: 'WEBVTT\n\n00:00:01.000 --> 00:00:03.000\nこんにちは\n',
    );
    final lyrics = await LyricsResolver.resolve(track);
    expect(lyrics, isNotNull);
    expect(lyrics!.lines.first.text, 'こんにちは');
  });

  test('旧 JSON 兼容:无 lyricsText 字段解析为 null,含字段可往返', () {
    // 旧库(1.28 及以前)的 track JSON 没有 lyricsText 键
    final legacy = Track.fromJson({
      'index': 0,
      'name': '01',
      'url': 'file:///tmp/01.mp3',
      'duration': 123.5,
      'cover': null,
    });
    expect(legacy.lyricsText, isNull);
    expect(legacy.toJson().containsKey('lyricsText'), isFalse);

    // 新库带字段:往返保留
    final fresh = Track.fromJson({
      'index': 1,
      'name': '02',
      'url': 'content://xxx/02.mp3',
      'duration': 10,
      'lyricsText': '[00:01.00]テスト',
    });
    expect(fresh.lyricsText, '[00:01.00]テスト');
    final roundTrip = Track.fromJson(fresh.toJson());
    expect(roundTrip.lyricsText, '[00:01.00]テスト');
  });
}
