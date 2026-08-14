import 'dart:io';

import 'package:hiko/data/library_store.dart';
import 'package:hiko/data/scanner.dart' as scanner;
import 'package:hiko/models/album.dart';

/// 开发用种子脚本：扫描测试目录并写入指定位置的 library.json。
/// 用法：dart run bin/seed.dart <扫描根目录> [输出目录]
Future<void> main(List<String> args) async {
  final root = args.isNotEmpty ? args[0] : '/tmp/hiko-import-test';
  final albums = await scanner.scanPath(root);
  if (args.length > 1) {
    await LibraryStore(overrideDir: Directory(args[1])).save(albums);
  } else {
    stdout.writeln('seeded ${albums.length} albums（未指定输出目录，仅预览）');
  }
  for (final a in albums) {
    stdout.writeln('  ${a.title} | ${a.rjCode ?? '无 RJ'} | ${a.tracks.length} 首 | ${a.localCover?.substring(0, 30) ?? '无封面'}');
  }
}
