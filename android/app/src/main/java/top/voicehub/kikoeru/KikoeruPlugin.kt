package top.voicehub.kikoeru

import android.content.Intent
import android.net.Uri
import androidx.activity.result.ActivityResult
import androidx.documentfile.provider.DocumentFile
import com.getcapacitor.JSObject
import com.getcapacitor.PermissionState
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.ActivityCallback
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import org.json.JSONArray
import org.json.JSONObject

/**
 * Kikoeru 原生插件：在 Android 上实现 window.kikoeru（与 desktop preload.js 同签名契约）。
 * 见 .zcode/plans/plan-kikoeru-android-capacitor.md §5。
 */
@CapacitorPlugin(
    name = "Kikoeru",
    permissions = [
        Permission(alias = "notifications", strings = [android.Manifest.permission.POST_NOTIFICATIONS])
    ]
)
class KikoeruPlugin : Plugin() {

    private var library: LibraryStore? = null

    override fun load() {
        super.load()
        library = LibraryStore(context)
        PlaybackController.notify = { name, data -> notifyListeners(name, data) }
        // 注意：不能在这里 startForegroundService —— MediaSessionService 空闲时不会立即
        // startForeground，会触发 ForegroundServiceDidNotStartInTimeException。
        // 播放服务改为首次播放动作时惰性启动（见 ensurePlaybackService）。
    }

    /** 首次播放动作时启动播放服务（只启动一次），随后的 load/play 直接操作已就绪的 player */
    private fun ensurePlaybackService() {
        if (PlaybackController.serviceStarted) return
        PlaybackController.serviceStarted = true
        try {
            context.startForegroundService(Intent(context, KikoeruPlaybackService::class.java))
        } catch (_: Exception) { }
    }

    // ---- M0：库持久化 / 版本 ----
    @PluginMethod
    fun loadLibrary(call: PluginCall) {
        try {
            val albums = library?.load() ?: JSONArray()
            call.resolve(JSObject().put("albums", albums))
        } catch (e: Exception) {
            call.reject("读取音声库失败: ${e.message}", e)
        }
    }

    @PluginMethod
    fun saveAlbums(call: PluginCall) {
        val albums = call.getArray("albums") ?: run {
            call.reject("缺少 albums 参数")
            return
        }
        try {
            library?.save(albums)
            call.resolve()
        } catch (e: Exception) {
            call.reject("保存音声库失败: ${e.message}", e)
        }
    }

    @PluginMethod
    fun getVersion(call: PluginCall) {
        val version = try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName
        } catch (e: Exception) {
            "0.0.0"
        }
        call.resolve(JSObject().put("version", version))
    }

    // ---- M1：导入 ----
    @PluginMethod
    fun importAudioFolder(call: PluginCall) {
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
        startActivityForResult(call, intent, "importTreeResult")
    }

    @ActivityCallback
    private fun importTreeResult(call: PluginCall, result: ActivityResult) {
        if (result.resultCode == android.app.Activity.RESULT_CANCELED || result.data?.data == null) {
            call.resolve(JSObject().put("canceled", true))
            return
        }
        val treeUri = result.data!!.data!!
        try {
            context.contentResolver.takePersistableUriPermission(
                treeUri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            // 已授权或 ROM 差异时可能抛异常，忽略；读取不受影响
        }
        Thread {
            try {
                val albums = scanTree(treeUri)
                // 回调切主线程投递，避免从后台线程直接操作 WebView 通道
                execute { call.resolve(JSObject().put("canceled", false).put("albums", albums).put("scannedPath", treeUri.toString())) }
            } catch (e: Exception) {
                execute { call.reject("导入失败: ${e.message}", e) }
            }
        }.start()
    }

    /**
     * 扫描整棵 SAF 树：分组 → 逐张专辑解析 → 进度事件 → 合并入库（每 5 张增量保存，崩溃不丢全部）。
     * 对应桌面 importAudioFolder 的 scanFolder + saveLibrary 合并逻辑。
     */
    private fun scanTree(treeUri: Uri): JSONArray {
        val appContext = context
        val root = DocumentFile.fromTreeUri(appContext, treeUri)
            ?: throw IllegalStateException("无法访问所选文件夹")
        val groups = ImportScanner.groupByFolder(root)

        val albums = JSONArray()
        val existing = library?.load() ?: JSONArray()
        val merged = LinkedHashMap<String, JSONObject>()
        for (i in 0 until existing.length()) {
            existing.optJSONObject(i)?.let { merged[it.optString("id")] = it }
        }

        var processed = 0
        val total = groups.size
        for ((dir, files) in groups) {
            try {
                val album = ImportScanner.scanAlbum(appContext, dir, files)
                if (album != null) {
                    merged[album.optString("id")] = album
                    albums.put(album)
                }
            } catch (e: Exception) {
                // 单张专辑扫描失败不应中断整个导入（对应桌面注释）
            }
            processed += 1
            val progress = JSObject()
                .put("folderIndex", 1)
                .put("folderTotal", 1)
                .put("processed", processed)
                .put("total", total)
            // 进度事件切主线程投递（notifyListeners 经 WebView 消息通道）
            execute { notifyListeners("import:progress", progress) }
            if (processed % 5 == 0) {
                library?.save(JSONArray(merged.values.toList()))
            }
        }
        library?.save(JSONArray(merged.values.toList()))
        return albums
    }

    // ---- M2：播放（native-audio.js shim 调用）----
    @PluginMethod
    fun playbackLoad(call: PluginCall) {
        val uri = call.getString("uri") ?: run {
            call.reject("缺少 uri")
            return
        }
        ensurePlaybackService()
        PlaybackController.load(uri, call.getDouble("positionMs")?.toLong())
        call.resolve()
    }

    @PluginMethod
    fun playbackPlay(call: PluginCall) {
        ensurePlaybackService()
        PlaybackController.play()
        call.resolve()
    }

    @PluginMethod
    fun playbackPause(call: PluginCall) {
        ensurePlaybackService()
        PlaybackController.pause()
        call.resolve()
    }

    @PluginMethod
    fun playbackSeek(call: PluginCall) {
        PlaybackController.seekTo(call.getDouble("position") ?: 0.0)
        call.resolve()
    }

    @PluginMethod
    fun playbackVolume(call: PluginCall) {
        PlaybackController.setVolume(call.getDouble("volume") ?: 1.0)
        call.resolve()
    }

    @PluginMethod
    fun playbackMetadata(call: PluginCall) {
        PlaybackController.setMetadata(
            call.getString("title"),
            call.getString("artist"),
            call.getString("cover")
        )
        call.resolve()
    }

    @PluginMethod
    fun requestNotificationPermission(call: PluginCall) {
        requestPermissionForAlias("notifications", call, "permissionCallback")
    }

    @PermissionCallback
    private fun permissionCallback(call: PluginCall) {
        call.resolve(
            JSObject().put("granted", getPermissionState("notifications") == PermissionState.GRANTED)
        )
    }

    // ---- M3：DLsite 标签刮削 ----
    @PluginMethod
    fun scrapeDlsite(call: PluginCall) {
        val ids = call.getArray("ids") ?: run {
            call.reject("缺少 ids")
            return
        }
        val force = call.getBoolean("force") ?: false
        val idSet = (0 until ids.length()).map { ids.optString(it) }.toSet()
        Thread {
            try {
                val albums = library?.load() ?: JSONArray()
                val mutable = (0 until albums.length()).map { albums.getJSONObject(it) }.toMutableList()
                val targets = mutable.filter { idSet.contains(it.optString("id")) }

                var noRj = 0
                val withRj = mutableListOf<Pair<JSONObject, String>>()
                for (album in targets) {
                    val rj = albumRjCode(album)
                    if (rj != null) {
                        album.put("rjCode", rj)
                        withRj.add(album to rj)
                    } else {
                        noRj += 1
                    }
                }

                val config = loadScrapeConfig()
                val total = withRj.size
                var processed = 0
                var scraped = 0
                var failed = 0
                var skipped = 0
                val details = JSONArray()
                for ((album, rj) in withRj) {
                    processed += 1
                    if (!force && (album.optJSONArray("tags")?.length() ?: 0) > 0) {
                        skipped += 1
                        notifyListeners("dlsite:progress", JSObject().put("processed", processed).put("total", total))
                        continue
                    }
                    try {
                        val html = DlsiteScraper.fetchWorkPage(rj, config.optString("proxy"))
                        val tags = DlsiteScraper.parseTags(html)
                        val title = DlsiteScraper.parseTitle(html)
                        album.put("tags", JSONArray(tags))
                        album.put("dlsiteTitle", title ?: JSONObject.NULL)
                        details.put(
                            JSObject()
                                .put("id", album.optString("id"))
                                .put("rj", rj)
                                .put("tags", JSONArray(tags))
                                .put("title", title)
                        )
                        if (tags.isNotEmpty()) scraped += 1 else failed += 1
                    } catch (e: Exception) {
                        failed += 1
                        details.put(JSObject().put("id", album.optString("id")).put("rj", rj).put("error", e.message))
                    }
                    Thread.sleep(400) // 礼貌限速
                    notifyListeners("dlsite:progress", JSObject().put("processed", processed).put("total", total))
                }
                library?.save(JSONArray(mutable))
                call.resolve(
                    JSObject()
                        .put("scraped", scraped)
                        .put("failed", failed)
                        .put("skipped", skipped)
                        .put("noRj", noRj)
                        .put("details", details)
                )
            } catch (e: Exception) {
                call.reject("刮削失败: ${e.message}", e)
            }
        }.start()
    }

    /** 与桌面 albumRjCode 一致：优先存值，其次从路径/标题/曲目名提取 */
    private fun albumRjCode(album: JSONObject): String? {
        album.optString("rjCode").takeIf { it.isNotBlank() }?.let { return it }
        val tracks = album.optJSONArray("tracks")
        val trackNames = if (tracks != null) {
            (0 until tracks.length()).mapNotNull { tracks.optJSONObject(it)?.optString("name") }.joinToString(" ")
        } else ""
        return ImportScanner.extractRjCode(album.optString("sourcePath"), album.optString("title"), trackNames)
    }

    @PluginMethod
    fun getScrapeConfig(call: PluginCall) {
        call.resolve(loadScrapeConfig())
    }

    @PluginMethod
    fun setScrapeConfig(call: PluginCall) {
        saveScrapeConfig(JSObject().put("proxy", call.getString("proxy") ?: ""))
        call.resolve(loadScrapeConfig())
    }

    private fun loadScrapeConfig(): JSObject {
        val sp = context.getSharedPreferences("kikoeru_scrape", android.content.Context.MODE_PRIVATE)
        return JSObject().put("proxy", sp.getString("proxy", "") ?: "")
    }

    private fun saveScrapeConfig(config: JSObject) {
        val sp = context.getSharedPreferences("kikoeru_scrape", android.content.Context.MODE_PRIVATE)
        sp.edit().putString("proxy", config.optString("proxy")).apply()
    }

    // ---- M4：数据操作 ----
    @PluginMethod
    fun removeAlbum(call: PluginCall) {
        val id = call.getString("id")
        val deleteFiles = call.getBoolean("deleteFiles") ?: false
        try {
            val albums = library?.load() ?: JSONArray()
            val album = (0 until albums.length()).map { albums.getJSONObject(it) }
                .find { it.optString("id") == id }
            if (album == null) {
                call.resolve(JSObject().put("ok", false).put("reason", "not-found"))
                return
            }
            var deletedFiles = 0
            if (deleteFiles) deletedFiles = deleteAlbumFiles(album)
            val kept = JSONArray()
            for (i in 0 until albums.length()) {
                if (albums.optJSONObject(i).optString("id") != id) kept.put(albums.getJSONObject(i))
            }
            library?.save(kept)
            call.resolve(JSObject().put("ok", true).put("deletedFiles", deletedFiles))
        } catch (e: Exception) {
            call.reject("删除失败: ${e.message}", e)
        }
    }

    @PluginMethod
    fun removeAlbums(call: PluginCall) {
        val ids = call.getArray("ids") ?: run {
            call.reject("缺少 ids")
            return
        }
        val deleteFiles = call.getBoolean("deleteFiles") ?: false
        val idSet = (0 until ids.length()).map { ids.optString(it) }.toSet()
        try {
            val albums = library?.load() ?: JSONArray()
            var deletedFiles = 0
            val kept = JSONArray()
            for (i in 0 until albums.length()) {
                val album = albums.getJSONObject(i)
                if (idSet.contains(album.optString("id"))) {
                    if (deleteFiles) deletedFiles += deleteAlbumFiles(album)
                } else {
                    kept.put(album)
                }
            }
            library?.save(kept)
            call.resolve(JSObject().put("ok", true).put("deletedFiles", deletedFiles))
        } catch (e: Exception) {
            call.reject("删除失败: ${e.message}", e)
        }
    }

    /** 删除专辑源文件（曲目 + 封面 + 空目录），对应桌面 fs.rm + fs.rmdir 语义 */
    private fun deleteAlbumFiles(album: JSONObject): Int {
        var deleted = 0
        val resolver = context.contentResolver
        val targets = mutableListOf<Uri>()
        val tracks = album.optJSONArray("tracks")
        if (tracks != null) {
            for (i in 0 until tracks.length()) {
                tracks.optJSONObject(i)?.optString("url")?.takeIf { it.isNotBlank() }
                    ?.let { targets.add(Uri.parse(it)) }
            }
        }
        album.optString("localCover").takeIf { it.startsWith("content:") }
            ?.let { targets.add(Uri.parse(it)) }

        for (uri in targets) {
            try {
                if (DocumentFile.fromSingleUri(context, uri)?.delete() == true) deleted += 1
            } catch (_: Exception) { }
        }
        // 源目录删除（对应桌面 rmdir：清空文件后目录可删）
        album.optString("sourcePath").takeIf { it.startsWith("content:") }?.let {
            try {
                if (DocumentFile.fromSingleUri(context, Uri.parse(it))?.delete() == true) deleted += 1
            } catch (_: Exception) { }
        }
        return deleted
    }

    @PluginMethod
    fun cleanMissing(call: PluginCall) {
        try {
            val albums = library?.load() ?: JSONArray()
            var removedAlbums = 0
            var removedTracks = 0
            val kept = JSONArray()
            val resolver = context.contentResolver
            for (i in 0 until albums.length()) {
                val album = albums.getJSONObject(i)
                val tracks = album.optJSONArray("tracks")
                if (tracks == null || tracks.length() == 0) {
                    kept.put(album)
                    continue
                }
                val alive = JSONArray()
                for (j in 0 until tracks.length()) {
                    val track = tracks.getJSONObject(j)
                    val url = track.optString("url")
                    val exists = try {
                        resolver.openFileDescriptor(Uri.parse(url), "r")?.let { it.close(); true } ?: false
                    } catch (_: Exception) { false }
                    if (exists || !url.startsWith("content:")) alive.put(track)
                    else removedTracks += 1
                }
                if (alive.length() == 0) {
                    removedAlbums += 1
                    continue
                }
                if (alive.length() == tracks.length()) {
                    kept.put(album)
                } else {
                    album.put("tracks", alive)
                    album.put("duration", alive.length())
                    kept.put(album)
                }
            }
            library?.save(kept)
            call.resolve(JSObject().put("removedAlbums", removedAlbums).put("removedTracks", removedTracks))
        } catch (e: Exception) {
            call.reject("清理失败: ${e.message}", e)
        }
    }

    /** 尽力而为：用 DocumentsUI 打开专辑所在文件夹 */
    @PluginMethod
    fun revealInFolder(call: PluginCall) {
        val id = call.getString("id")
        val albums = library?.load() ?: JSONArray()
        val album = (0 until albums.length()).map { albums.getJSONObject(it) }
            .find { it.optString("id") == id }
        val dirUri = album?.optString("sourcePath")?.takeIf { it.startsWith("content:") }
        if (dirUri == null) {
            call.resolve(JSObject().put("ok", false).put("error", "无本地文件夹"))
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(dirUri), "vnd.android.document/directory")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            getActivity()?.startActivity(intent)
            call.resolve(JSObject().put("ok", true))
        } catch (e: Exception) {
            call.resolve(JSObject().put("ok", false).put("error", e.message))
        }
    }

    /** 桌面是打开数据目录；Android 上改为导出 library.json（分享） */
    @PluginMethod
    fun openDataDir(call: PluginCall) {
        try {
            val src = java.io.File(context.filesDir, "library.json")
            val out = java.io.File(context.cacheDir, "kikoeru-library.json")
            out.writeText(src.readText())
            val uri = androidx.core.content.FileProvider.getUriForFile(
                context, "${context.packageName}.fileprovider", out
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            getActivity()?.startActivity(Intent.createChooser(intent, "导出音声库"))
            call.resolve()
        } catch (e: Exception) {
            call.reject("导出失败: ${e.message}", e)
        }
    }
}
