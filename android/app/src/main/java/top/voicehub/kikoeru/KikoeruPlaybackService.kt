package top.voicehub.kikoeru

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.BitmapFactory
import android.os.IBinder
import android.view.KeyEvent
import androidx.core.app.NotificationCompat
import androidx.media.app.NotificationCompat.MediaStyle
import android.support.v4.media.session.MediaSessionCompat
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import com.getcapacitor.JSObject

/**
 * 前台播放服务：ExoPlayer + MediaSession，自己管理 startForeground 与媒体通知。
 *
 * 不用 MediaSessionService：它的前台化依赖内部"用户参与"判定，在短视频等快速播放结束
 * 场景下不会及时 startForeground，触发 ForegroundServiceDidNotStartInTimeException。
 * 这里 onStartCommand 立即 startForeground，播放状态变化时刷新通知，完全可控。
 */
class KikoeruPlaybackService : Service() {

    private var player: ExoPlayer? = null
    private var mediaSession: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        val exo = ExoPlayer.Builder(this).build()
        player = exo
        PlaybackController.player = exo

        exo.addListener(object : Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                PlaybackController.emit("audio:state", JSObject().put("playing", isPlaying))
                refreshNotification()
            }

            override fun onPlaybackStateChanged(playbackState: Int) {
                // 注意：不在这里 stopSelf —— 本应用 ended 后渲染层会立即接下一曲
                //（列表循环/单曲循环），stopSelf 会与服务重启标志竞态导致停摆。
                // 服务生命周期由 onTaskRemoved（无播放时）管理。
                if (playbackState == Player.STATE_ENDED) {
                    PlaybackController.emit("audio:ended", JSObject())
                    refreshNotification()
                }
            }
        })

        mediaSession = MediaSession.Builder(this, exo)
            .setCallback(object : MediaSession.Callback {
                override fun onMediaButtonEvent(
                    session: MediaSession,
                    controllerInfo: MediaSession.ControllerInfo,
                    mediaButtonIntent: Intent
                ): Boolean {
                    val keyCode = mediaButtonIntent
                        .getParcelableExtra(Intent.EXTRA_KEY_EVENT, KeyEvent::class.java)
                        ?.keyCode
                    val command = when (keyCode) {
                        KeyEvent.KEYCODE_MEDIA_NEXT -> "next"
                        KeyEvent.KEYCODE_MEDIA_PREVIOUS -> "prev"
                        else -> null
                    }
                    if (command != null) {
                        // 队列逻辑在渲染层：转发给 WebView 触发 #nextBtn/#prevBtn
                        PlaybackController.emit("audio:command", JSObject().put("command", command))
                        return true
                    }
                    return super.onMediaButtonEvent(session, controllerInfo, mediaButtonIntent)
                }
            })
            .build()
        PlaybackController.session = mediaSession

        PlaybackController.onPlayerReady()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_PLAY -> PlaybackController.play()
            ACTION_PAUSE -> PlaybackController.pause()
            ACTION_NEXT -> PlaybackController.emit("audio:command", JSObject().put("command", "next"))
            ACTION_PREV -> PlaybackController.emit("audio:command", JSObject().put("command", "prev"))
        }
        // 立即前台化：满足 startForegroundService 的 5 秒约束
        startForeground(
            NOTIFICATION_ID,
            buildNotification(),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onTaskRemoved(rootIntent: Intent?) {
        val p = player
        if (p == null || !p.playWhenReady || p.mediaItemCount == 0) {
            stopSelf()
        }
    }

    override fun onDestroy() {
        mediaSession?.run {
            player.release()
            release()
        }
        mediaSession = null
        player = null
        PlaybackController.player = null
        PlaybackController.session = null
        PlaybackController.serviceStarted = false
        PlaybackController.stopTicker()
        super.onDestroy()
    }

    // ---- 媒体通知 ----
    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "播放控制",
            NotificationManager.IMPORTANCE_LOW
        ).apply { description = "音声播放与锁屏控制" }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun refreshNotification() {
        try {
            getSystemService(NotificationManager::class.java)
                .notify(NOTIFICATION_ID, buildNotification())
        } catch (_: Exception) { }
    }

    private fun buildNotification(): Notification {
        val exo = player
        val meta: MediaMetadata = exo?.mediaMetadata ?: MediaMetadata.EMPTY
        val title = meta.title?.toString()?.ifBlank { null } ?: "Kikoeru"
        val artist = meta.artist?.toString()?.ifBlank { null } ?: "音声收藏室"
        val artwork = meta.artworkData?.let { bytes ->
            try { BitmapFactory.decodeByteArray(bytes, 0, bytes.size) } catch (_: Exception) { null }
        }
        val playing = exo?.playWhenReady == true
        val playPauseAction = if (playing) ACTION_PAUSE else ACTION_PLAY
        val playPauseIcon = if (playing) android.R.drawable.ic_media_pause else android.R.drawable.ic_media_play

        val openApp = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentTitle(title)
            .setContentText(artist)
            .setLargeIcon(artwork)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOnlyAlertOnce(true)
            .setOngoing(playing)
            .setContentIntent(openApp)
            .setStyle(
                MediaStyle()
                    .setMediaSession(MediaSessionCompat.Token.fromToken(mediaSession!!.platformToken))
                    .setShowActionsInCompactView(0, 1, 2)
            )
            .addAction(android.R.drawable.ic_media_previous, "上一首", serviceIntent(ACTION_PREV, 1))
            .addAction(playPauseIcon, if (playing) "暂停" else "播放", serviceIntent(playPauseAction, 2))
            .addAction(android.R.drawable.ic_media_next, "下一首", serviceIntent(ACTION_NEXT, 3))
            .build()
    }

    private fun serviceIntent(action: String, requestCode: Int): PendingIntent {
        val intent = Intent(this, KikoeruPlaybackService::class.java).setAction(action)
        return PendingIntent.getService(
            this, requestCode, intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    companion object {
        const val ACTION_PLAY = "top.voicehub.kikoeru.action.PLAY"
        const val ACTION_PAUSE = "top.voicehub.kikoeru.action.PAUSE"
        const val ACTION_NEXT = "top.voicehub.kikoeru.action.NEXT"
        const val ACTION_PREV = "top.voicehub.kikoeru.action.PREV"
        private const val NOTIFICATION_ID = 1001
        private const val CHANNEL_ID = "kikoeru_playback"
    }
}
