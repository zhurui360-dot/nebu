package com.cloudtune.player.ui.home

import com.cloudtune.player.data.model.Album
import com.cloudtune.player.data.model.Track

/**
 * 临时示例库：让 UI 先跑起来、验收玻璃观感用。
 * 接 Room + WebDAV 扫描后整个对象删掉，改成 ViewModel 输出的 UiState。
 */
object DemoLibrary {

    val tracks: List<Track> = listOf(
        Track(
            id = "tr-1", title = "听见光的样子", albumId = "al-1", albumName = "夜航",
            artist = "林屿", durationMs = 228_000, addedAt = 1_700_001_000,
        ),
        Track(
            id = "tr-2", title = "夏末的信", albumId = "al-2", albumName = "光的样子",
            artist = "陈一禾", durationMs = 252_000, addedAt = 1_700_002_000,
        ),
        Track(
            id = "tr-3", title = "Winter Tale", albumId = "al-3", albumName = "冬",
            artist = "林屿", durationMs = 176_000, addedAt = 1_700_003_000,
        ),
        Track(
            id = "tr-4", title = "星河漫步", albumId = "al-1", albumName = "夜航",
            artist = "林屿", durationMs = 200_000, addedAt = 1_700_004_000,
        ),
        Track(
            id = "tr-5", title = "潮汐", albumId = "al-4", albumName = "海边的房间",
            artist = "苏晚", durationMs = 241_000, addedAt = 1_700_005_000,
        ),
    )

    val albums: List<Album> = listOf(
        Album(id = "al-1", name = "夜航", artist = "林屿", year = 2024),
        Album(id = "al-2", name = "光的样子", artist = "陈一禾", year = 2023),
        Album(id = "al-3", name = "冬", artist = "林屿", year = 2022),
        Album(id = "al-4", name = "海边的房间", artist = "苏晚", year = 2024),
    )

    val recent: List<Track> = tracks.take(4)

    val current: Track = tracks.first()

    fun albumOf(track: Track): Album =
        albums.firstOrNull { it.id == track.albumId }
            ?: Album(id = track.albumId, name = track.albumName, artist = track.artist)
}

/** 毫秒 → m:ss */
fun formatTime(ms: Long): String {
    val total = ms / 1000
    return "%d:%02d".format(total / 60, total % 60)
}

/** 按时段给问候语 */
fun greetingForHour(hour: Int): String = when {
    hour < 11 -> "早上好"
    hour < 18 -> "下午好"
    else -> "晚上好"
}
