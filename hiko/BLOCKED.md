# BLOCKED — 1.33.0 通知层级与扫描进度修复

- 任务 0 基线与文档一致：`flutter analyze` 32 条既有 warning/info；`flutter test` 129 passed、1 skipped、1 failed，唯一失败为 `test/data/update_checker_network_test.dart` 无法取得 GitHub latest 的 `.apk` 资产。该失败保留，不修改业务或测试掩盖。
- macOS release 基线构建成功；现有 `scripts/build-macos-dmg.sh` 可用，待最终版本构建后执行。
- 最终回归保留唯一既有网络阻塞：`test/data/update_checker_network_test.dart` 返回 `HttpException: GitHub API 403`；本期未修改网络业务或测试掩盖。
- 其余：无。

# BLOCKED — 待裁决清单

本期(1.29.0)无阻塞项。顺手发现、未动手的清理项:

1. `hiko/android/app/src/main/kotlin/top/voicehub/hiko/ImportScanner.kt` 的 `scanAlbum(context, albumDir, files)`(约 L290)为旧目录式扫描函数,当前无任何调用者(主路径为 `scanAlbums` 文件级扫描),属可清理死代码;因不在本期任务范围,未动。
2. `test/widget_test.dart:35` 的 `found` 局部变量未使用(存量 analyzer warning,非本期引入),未动。
