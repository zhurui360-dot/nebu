package com.cloudtune.player.data.model

/**
 * 一首歌。字段对齐 Flutter 版 Track。
 *
 * url 的语义：
 *  - source = "local"：本地文件的 content:// Uri 或绝对路径，ExoPlayer 直接播
 *  - source = "webdav"：WebDAV 直链（带认证头交给播放器）
 */
data class Track(
    val id: String,
    val title: String,
    val albumId: String = "",
    val albumName: String = "",
    val artist: String = "",
    val durationMs: Long = 0L,
    val url: String = "",
    val source: String = "local",
    /** 封面 Uri（MediaStore 缩略图 / 内嵌封面落盘），null 走渐变兜底 */
    val coverUri: String? = null,
    val format: String = "mp3",
    val addedAt: Long = 0L,
    val trackNo: Int = 0,
    val year: Int? = null,
    val sizeBytes: Long = 0L,
) {
    fun playbackUrl(): String = url
}

data class Album(
    val id: String,
    val name: String,
    val artist: String = "未知歌手",
    val year: Int = 0,
    val coverStyle: Int = 1,
    val coverUri: String? = null,
)

enum class PlayMode { list, one, shuffle }
