import 'dart:io';

import 'package:kikoeru/data/library_store.dart';
import 'package:kikoeru/data/scanner.dart';
import 'package:kikoeru/models/album.dart';

/// 开发用种子脚本：扫描测试目录并写入指定位置的 library.json。
/// 用法：dart run bin/seed.dart <扫描根目录> [输出目录]
Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args[0] : '/tmp/kikoeru-import-test';
  final files = await collectFiles(root);
  final groups = groupFilesByFolder(files);
  final albums = <Album>[];
  for (final entry in groups.entries) {
    final album = await scanAlbum(entry.key, entry.value);
    if (album != null) albums.add(album);
  }
  if (args.length > 1) {
    await LibraryStore(overrideDir: Directory(args[1])).save(albums);
  } else {
    stdout.writeln('seeded ${albums.length} albums（未指定输出目录，仅预览）');
  }
  for (final a in albums) {
    stdout.writeln('  ${a.title} | ${a.rjCode ?? '无 RJ'} | ${a.tracks.length} 首 | ${a.localCover?.substring(0, 30) ?? '无封面'}');
  }
}
