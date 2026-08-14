package top.voicehub.hiko

import android.app.Activity
import android.content.Intent
import android.net.Uri
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

/**
 * Hiko 原生插件（MethodChannel）：SAF 导入 / 删除源文件 / 失效探测 / 打开文件夹 / 导出库。
 * 对应旧版 KikoeruPlugin.kt 移植；播放由 audio_service 接管，不再需要 Media3 前台服务。
 *
 * 导入采用**事件流式回传**（onAlbum/onProgress），避免旧版整份 JSON 一次过桥导致 OOM。
 */
class HikoPlugin : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "top.voicehub.hiko/plugin"
        private const val REQ_IMPORT_TREE = 1001
    }

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var pendingImport: MethodChannel.Result? = null

    fun register(activity: Activity, engine: FlutterEngine) {
        this.activity = activity
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "importAudioFolder" -> startImport(result)
            // 常驻音乐目录扫描：按已授权 tree URI 直接扫描（不弹选择器），事件流与导入一致
            "scanFolder" -> scanFolder(call, result)
            "deleteFiles" -> deleteFiles(call, result)
            "probeUris" -> probeUris(call, result)
            "revealInFolder" -> revealInFolder(call, result)
            "shareLibrary" -> shareLibrary(result)
            else -> result.notImplemented()
        }
    }

    /** 扫描已授权的音乐目录（常驻目录自动扫描用） */
    private fun scanFolder(call: MethodCall, result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        val uri = call.argument<String>("uri")?.let(Uri::parse)
        if (uri == null) {
            result.error("bad-uri", "目录 URI 无效", null)
            return
        }
        Thread {
            try {
                val scanError = scanTree(activity, uri)
                mainHandler.post {
                    if (scanError == null) {
                        result.success(mapOf("ok" to true))
                    } else {
                        result.error("scan-failed", scanError, null)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("scan-failed", e.message, null) }
            }
        }.start()
    }

    // ---- 导入（SAF）----
    private fun startImport(result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        pendingImport = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
            .putExtra(Intent.EXTRA_TITLE, "选择音声文件夹")
        activity.startActivityForResult(intent, REQ_IMPORT_TREE)
    }

    /** MainActivity.onActivityResult 转发 */
    fun onImportTreeResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode != REQ_IMPORT_TREE) return
        val result = pendingImport ?: return
        pendingImport = null
        val uri = data?.data
        val activity = activity ?: return result.error("no-activity", "Activity 未就绪", null)
        if (uri == null || resultCode != Activity.RESULT_OK) {
            result.success(mapOf("canceled" to true, "total" to 0))
            return
        }
        try {
            activity.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        } catch (e: Exception) {
            // 部分目录不允许持久授权，继续（只读也可导入）
        }
        Thread {
            try {
                val scanError = scanTree(activity, uri)
                // MethodChannel 的 Result 必须在主线程回调
                mainHandler.post {
                    if (scanError == null) {
                        result.success(mapOf("canceled" to false, "scannedPath" to uri.toString()))
                    } else {
                        result.error("scan-failed", scanError, null)
                    }
                }
            } catch (e: Exception) {
                mainHandler.post { result.error("scan-failed", e.message, null) }
            }
        }.start()
    }

    /** 主线程 Handler：MethodChannel 的 invokeMethod/Result 均要求主线程 */
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    /** 后台扫描：事件经主线程回传；返回 null 成功 / 错误消息 */
    private fun scanTree(activity: Activity, rootUri: Uri): String? {
        val context = activity.applicationContext
        val root = DocumentFile.fromTreeUri(context, rootUri)
        if (root == null) return "无法打开所选文件夹"
        val groups = ImportScanner.groupByFolder(root)
        var processed = 0
        for ((dir, files) in groups) {
            val album = ImportScanner.scanAlbum(context, dir, files)
            if (album != null) {
                // JSONObject 不能直接过 MethodChannel（引擎只支持 Map/List/String/num/bool），
                // 递归转成 Map 后再传，否则抛 "Unsupported value" 导致整次导入失败
                val bridge = album.toBridge()
                val now = ++processed
                val total = groups.size
                mainHandler.post {
                    try {
                        channel?.invokeMethod("onAlbum", bridge)
                        channel?.invokeMethod(
                            "onProgress",
                            mapOf("processed" to now, "total" to total)
                        )
                    } catch (e: Exception) {
                        // 单张专辑事件发送失败不中断扫描；Dart 侧以已收到的专辑为准
                    }
                }
            }
        }
        return null
    }

    /** org.json 对象 → MethodChannel 可编码的 Map/List（递归） */
    private fun Any.toBridge(): Any? = when (this) {
        is JSONObject -> {
            val map = LinkedHashMap<String, Any?>()
            keys().forEach { key -> map[key] = get(key).toBridge() }
            map
        }
        is JSONArray -> (0 until length()).map { get(it).toBridge() }
        JSONObject.NULL -> null
        else -> this
    }

    // ---- 删除源文件（SAF）----
    private fun deleteFiles(call: MethodCall, result: MethodChannel.Result) {
        val context = activity?.applicationContext
        if (context == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        val uris = (call.argument<List<String>>("files") ?: emptyList()).map(Uri::parse)
        val dirUri = call.argument<String>("dirUri")?.let(Uri::parse)
        var deleted = 0
        for (uri in uris) {
            try {
                val doc = DocumentFile.fromSingleUri(context, uri)
                if (doc != null && doc.delete()) deleted++
            } catch (_: Exception) {
                // 文件可能已不存在（对应旧版 force 删除）
            }
        }
        if (dirUri != null) {
            try {
                val dir = DocumentFile.fromTreeUri(context, dirUri)
                if (dir != null && dir.listFiles().isEmpty() && dir.delete()) {
                    // 空目录已删
                }
            } catch (_: Exception) {
            }
        }
        result.success(mapOf("deleted" to deleted))
    }

    // ---- 失效探测（批量）----
    private fun probeUris(call: MethodCall, result: MethodChannel.Result) {
        val context = activity?.applicationContext
        if (context == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        val uris = (call.argument<List<String>>("uris") ?: emptyList()).map(Uri::parse)
        val alive = uris.map { uri ->
            try {
                val fd = context.contentResolver.openFileDescriptor(uri, "r")
                fd?.use { true } ?: false
            } catch (_: Exception) {
                false
            }
        }
        result.success(mapOf("alive" to alive))
    }

    // ---- 打开所在文件夹（DocumentsUI，尽力而为）----
    private fun revealInFolder(call: MethodCall, result: MethodChannel.Result) {
        val activity = activity ?: return result.error("no-activity", "Activity 未就绪", null)
        val uri = call.argument<String>("uri")?.let(Uri::parse)
        if (uri == null) {
            result.success(mapOf("ok" to false))
            return
        }
        try {
            val intent = Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, "vnd.android.document/directory")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            activity.startActivity(intent)
            result.success(mapOf("ok" to true))
        } catch (e: Exception) {
            result.success(mapOf("ok" to false, "error" to e.message))
        }
    }

    // ---- 导出分享 library.json（对应旧版 openDataDir 的 Android 语义）----
    private fun shareLibrary(result: MethodChannel.Result) {
        val context = activity?.applicationContext
        if (context == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        try {
            val lib = File(context.filesDir, "library.json")
            if (!lib.exists()) {
                result.error("not-found", "库文件不存在", null)
                return
            }
            val cacheFile = File(context.cacheDir, "library.json")
            lib.copyTo(cacheFile, overwrite = true)
            val uri = FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                cacheFile
            )
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity?.startActivity(Intent.createChooser(intent, "导出 library.json"))
            result.success(mapOf("ok" to true))
        } catch (e: Exception) {
            result.error("share-failed", e.message, null)
        }
    }
}
