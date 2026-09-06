package top.voicehub.hiko

import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

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
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        plugin.onImportTreeResult(requestCode, resultCode, data)
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
