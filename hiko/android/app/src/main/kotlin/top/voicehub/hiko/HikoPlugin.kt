package top.voicehub.hiko

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
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
        private const val REQ_POST_NOTIFICATIONS = 1002
    }

    private var channel: MethodChannel? = null
    private var activity: Activity? = null
    private var pendingImport: MethodChannel.Result? = null
    private var pendingPermission: MethodChannel.Result? = null

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
            "requestNotificationPermission" -> requestNotificationPermission(result)
            else -> result.notImplemented()
        }
    }

    // ---- 通知权限（Android 13+ 运行时申请,移植旧版 KikoeruPlugin 行为）----

    /** 申请 POST_NOTIFICATIONS:已授予/低版本直接回 true,否则弹系统对话框 */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        val activity = activity
        if (activity == null) {
            result.error("no-activity", "Activity 未就绪", null)
            return
        }
        if (Build.VERSION.SDK_INT < 33) {
            result.success(mapOf("granted" to true, "skipped" to true))
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            activity, Manifest.permission.POST_NOTIFICATIONS
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(mapOf("granted" to true))
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQ_POST_NOTIFICATIONS,
        )
    }

    /** MainActivity.onRequestPermissionsResult 转发 */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (requestCode != REQ_POST_NOTIFICATIONS) return
        val result = pendingPermission ?: return
        pendingPermission = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        result.success(mapOf("granted" to granted))
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
        val albums = try {
            // 文件级并行扫描 + 混合分组；进度在扫描阶段实时回传，专辑阶段由回调发送。
            ImportScanner.scanAlbums(context, root) { processed, total, phase, album ->
                mainHandler.post {
                    try {
                        album?.let { channel?.invokeMethod("onAlbum", it.toBridge()) }
                        channel?.invokeMethod(
                            "onProgress",
                            mapOf(
                                "processed" to processed,
                                "total" to total,
                                "phase" to phase,
                                "unit" to if (phase == "albums") "albums" else "files",
                            )
                        )
                    } catch (_: Exception) { }
                }
            }
        } catch (e: SecurityException) {
            // 授权已失效（App 重装/系统清理后常驻目录 URI 失效）
            return "目录访问权限已失效，请重新导入该目录"
        } catch (e: Exception) {
            return "扫描失败：${e.message}"
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
