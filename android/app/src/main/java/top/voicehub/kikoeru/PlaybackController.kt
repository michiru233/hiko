package top.voicehub.kikoeru

import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import com.getcapacitor.JSObject
import java.util.Base64

/**
 * 播放控制器：插件 ↔ Media3（ExoPlayer + MediaSession）之间的单例桥。
 *
 * 注意：Capacitor 插件方法经 @JavascriptInterface 跑在后台线程，而 ExoPlayer 必须在
 * 主线程访问，因此所有 player 操作一律 post 到主线程 Handler 执行。
 * 事件经 notify 回调 → 插件 notifyListeners → WebView 的 native-audio.js shim。
 */
object PlaybackController {

    var player: ExoPlayer? = null
    var session: MediaSession? = null
    var notify: ((String, JSObject) -> Unit)? = null

    /** 播放服务是否已启动（服务停止后复位，保证下次播放能重新拉起） */
    var serviceStarted = false

    private val mainHandler = Handler(Looper.getMainLooper())

    // 就绪前缓存的操作（仅主线程访问）
    private var pendingUri: String? = null
    private var pendingSeekMs: Long? = null
    private var pendingAction: String? = null // play / pause
    private var lastMetaKey: String? = null

    fun emit(name: String, data: JSObject = JSObject()) {
        notify?.invoke(name, data)
    }

    private val ticker = object : Runnable {
        override fun run() {
            val p = player ?: return
            val durationMs = if (p.duration > 0) p.duration else 0L
            emit(
                "audio:timeupdate",
                JSObject()
                    .put("currentTime", p.currentPosition / 1000.0)
                    .put("duration", durationMs / 1000.0)
            )
            mainHandler.postDelayed(this, 250)
        }
    }

    /** service onCreate 创建好 player/session 后调用（主线程），补放缓存操作 */
    fun onPlayerReady() {
        pendingUri?.let {
            load(it, pendingSeekMs)
            pendingUri = null
            pendingSeekMs = null
        }
        when (pendingAction) {
            "play" -> play()
            "pause" -> pause()
        }
        pendingAction = null
        mainHandler.removeCallbacks(ticker)
        mainHandler.post(ticker)
    }

    fun load(uri: String, positionMs: Long? = null) {
        mainHandler.post { doLoad(uri, positionMs) }
    }

    private fun doLoad(uri: String, positionMs: Long?) {
        val p = player
        if (p == null) {
            pendingUri = uri
            pendingSeekMs = positionMs
            return
        }
        lastMetaKey = null
        val mediaItem = MediaItem.Builder().setUri(Uri.parse(uri)).build()
        p.setMediaItem(mediaItem)
        p.prepare()
        p.pause()
        if (positionMs != null && positionMs > 0) p.seekTo(positionMs)
        emit("audio:loadedmetadata", JSObject().put("duration", 0))
    }

    fun play() {
        mainHandler.post {
            val p = player
            if (p == null) {
                pendingAction = "play"
                return@post
            }
            p.play()
        }
    }

    fun pause() {
        mainHandler.post {
            val p = player
            if (p == null) {
                pendingAction = "pause"
                return@post
            }
            p.pause()
        }
    }

    fun seekTo(seconds: Double) {
        mainHandler.post {
            val p = player ?: return@post
            if (!p.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)) return@post
            p.seekTo((seconds * 1000).toLong())
        }
    }

    fun setVolume(volume: Double) {
        mainHandler.post { player?.volume = volume.toFloat() }
    }

    /** 通知/锁屏元数据（观察播放条推送，media3 1.11 元数据挂在 MediaItem 上，需重建当前项） */
    fun setMetadata(title: String?, artist: String?, cover: String?) {
        mainHandler.post { doSetMetadata(title, artist, cover) }
    }

    private fun doSetMetadata(title: String?, artist: String?, cover: String?) {
        val p = player ?: return
        val current = p.currentMediaItem ?: return
        val uri = current.localConfiguration?.uri?.toString() ?: return
        val key = "$uri|${title ?: ""}|${artist ?: ""}"
        if (key == lastMetaKey) return
        lastMetaKey = key

        val builder = MediaMetadata.Builder()
        if (!title.isNullOrBlank()) builder.setTitle(title)
        if (!artist.isNullOrBlank()) builder.setArtist(artist)
        cover?.let { dataUrl ->
            if (dataUrl.startsWith("data:image")) {
                val comma = dataUrl.indexOf(',')
                if (comma > 0) {
                    try {
                        val mime = dataUrl.substring(5, comma).substringBefore(';')
                        val bytes = Base64.getDecoder().decode(dataUrl.substring(comma + 1))
                        builder.setArtworkData(bytes, MediaMetadata.PICTURE_TYPE_FRONT_COVER)
                    } catch (_: Exception) { }
                }
            }
        }
        val item = MediaItem.Builder()
            .setUri(uri)
            .setMediaMetadata(builder.build())
            .build()
        p.replaceMediaItem(p.currentMediaItemIndex, item)
    }

    fun stopTicker() {
        mainHandler.removeCallbacks(ticker)
    }
}
