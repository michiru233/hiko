# BLOCKED — 待裁决清单

本期(1.29.0)无阻塞项。顺手发现、未动手的清理项:

1. `hiko/android/app/src/main/kotlin/top/voicehub/hiko/ImportScanner.kt` 的 `scanAlbum(context, albumDir, files)`(约 L290)为旧目录式扫描函数,当前无任何调用者(主路径为 `scanAlbums` 文件级扫描),属可清理死代码;因不在本期任务范围,未动。
2. `test/widget_test.dart:35` 的 `found` 局部变量未使用(存量 analyzer warning,非本期引入),未动。
