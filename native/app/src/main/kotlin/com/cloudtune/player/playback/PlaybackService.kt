package com.cloudtune.player.playback

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.Player
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionToken
import com.cloudtune.player.MainActivity

/**
 * 后台播放服务。ExoPlayer + MediaSession：
 *  - 前台服务保活，退到后台/锁屏继续放
 *  - 系统通知栏 + 锁屏由 Media3 的 DefaultMediaNotificationProvider 自动生成
 *  - UI 通过 MediaController 连接，不直接持有 ExoPlayer（避免生命周期泄漏）
 */
class PlaybackService : MediaSessionService() {

    private var player: ExoPlayer? = null
    private var session: MediaSession? = null

    override fun onCreate() {
        super.onCreate()
        player = buildPlayer()
        val sessionIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        session = MediaSession.Builder(this, player!!)
            .setSessionActivity(sessionIntent)
            .build()
    }

    private fun buildPlayer(): ExoPlayer = ExoPlayer.Builder(this)
        .setMediaSourceFactory(
            // 关键：必须包一层 DefaultDataSource。
            // AuthDataSourceFactory 只造 DefaultHttpDataSource（给 WebDAV 加认证头），
            // 直接交给播放器的话 content:// 本地文件根本打不开——"点了歌没声音"的根因。
            // DefaultDataSource 会按 scheme 分发：content://→ContentDataSource，
            // file://→FileDataSource，http(s)→转给带认证的工厂。
            androidx.media3.exoplayer.source.DefaultMediaSourceFactory(
                DefaultDataSource.Factory(this, AuthDataSourceFactory(this))
            )
        )
        .setAudioAttributes(
            AudioAttributes.Builder()
                .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                .setUsage(C.USAGE_MEDIA)
                .build(),
            /* handleAudioFocus = */ true, // 来电话自动暂停
        )
        .setHandleAudioBecomingNoisy(true) // 拔耳机暂停
        .build()

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = session

    override fun onDestroy() {
        session?.release()
        player?.release()
        session = null
        player = null
        super.onDestroy()
    }

    companion object {
        fun sessionToken(context: android.content.Context) =
            SessionToken(context, android.content.ComponentName(context, PlaybackService::class.java))
    }
}

/** 把我们的 Track 转成 Media3 MediaItem（带元信息，通知栏能显示歌名歌手） */
fun Track.toMediaItem(): MediaItem = MediaItem.Builder()
    .setMediaId(id)
    .setUri(if (url.startsWith("/")) Uri.fromFile(java.io.File(url)) else Uri.parse(url))
    .setMediaMetadata(
        MediaMetadata.Builder()
            .setTitle(title)
            .setArtist(artist)
            .setAlbumTitle(albumName)
            .setArtworkUri(coverUri?.let { Uri.parse(it) })
            .build()
    )
    .setTag(this)
    .build()

// import 别名：避免 Track 与 media3 的同名冲突
private typealias Track = com.cloudtune.player.data.model.Track
