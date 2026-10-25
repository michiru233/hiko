package top.voicehub.hiko

import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private lateinit var plugin: HikoPlugin

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // 左边缘系统手势排除（1.54）：应用内"左缘右滑呼出抽屉"优先于系统返回手势。
            // 系统限制每边最多排除 200dp——全高声明会被裁掉，只保留最后 200dp；
            // 下半屏滑动可靠呼出抽屉，上半屏由系统返回手势接管（汉堡按钮兜底）。
            val density = resources.displayMetrics.density
            window.decorView.post {
                val h = window.decorView.height
                val w = (24 * density).toInt()
                val maxExclude = (200 * density).toInt()
                window.decorView.systemGestureExclusionRects = listOf(
                    Rect(0, h - maxExclude, w, h),
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        plugin = HikoPlugin()
        plugin.register(this, flutterEngine)
        registerSystemChannel(flutterEngine)
    }

    /// 系统信息通道（1.99.31 配色种子「跟随系统」的 Android 实现）：
    /// 读 Material You 的 system_accent1 调色板当种子色。
    /// 不用 dynamic_color 包（依赖 material_ui，plan §9 禁引入）；
    /// system_accent1_* 是 Android 12+ 的框架隐藏资源，getIdentifier 拿不到
    /// 就返回 null（Dart 侧回退预设强调色）。
    private fun registerSystemChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "hiko/system"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "accentColor" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    // 明暗各取一档：种子进 HCT 重生成整套色板，取中间调
                    // （600/300）比 100/900 稳（部分厂商 ROM 会覆盖极端档）。
                    val lightId = resources.getIdentifier(
                        "system_accent1_600", "color", "android"
                    )
                    val darkId = resources.getIdentifier(
                        "system_accent1_300", "color", "android"
                    )
                    val night = (resources.configuration.uiMode and
                        Configuration.UI_MODE_NIGHT_MASK) ==
                        Configuration.UI_MODE_NIGHT_YES
                    val id = if (night) darkId else lightId
                    if (id == 0) {
                        result.success(null)
                    } else {
                        result.success(getColor(id))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        plugin.onImportTreeResult(requestCode, resultCode, data)
        plugin.onBackupResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        plugin.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }
}
