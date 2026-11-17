package com.cloudtune.player.data.scanner

import android.content.Context
import android.provider.MediaStore
import com.cloudtune.player.data.db.MusicDatabase
import com.cloudtune.player.data.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * 本地音乐扫描：查系统 MediaStore，不自己解析标签。
 *
 * 这是原生相对 Flutter 的最大优势——Android 系统已经把所有音频的
 * 标题/歌手/专辑/时长/封面索引好了。Flutter 版要自己解析 FLAC/MP3 标签
 * （services/tags + cover_codec，几千行），这里一次 ContentResolver 查询就够。
 *
 * 增量扫描：库里记了 path->size，没变的直接跳过；系统里已删除的清掉。
 */
class LocalScanner(private val context: Context, private val db: MusicDatabase) {

    data class ScanResult(
        val added: Int,
        val updated: Int,
        val removed: Int,
        val total: Int,
    )

    suspend fun scan(onProgress: (current: Int, total: Int) -> Unit = { _, _ -> }): ScanResult =
        withContext(Dispatchers.IO) {
            val existing = db.existingPaths()

            val projection = arrayOf(
                MediaStore.Audio.Media._ID,
                MediaStore.Audio.Media.TITLE,
                MediaStore.Audio.Media.ARTIST,
                MediaStore.Audio.Media.ALBUM,
                MediaStore.Audio.Media.ALBUM_ID,
                MediaStore.Audio.Media.DURATION,
                MediaStore.Audio.Media.DATA,
                MediaStore.Audio.Media.SIZE,
                MediaStore.Audio.Media.DATE_ADDED,
                MediaStore.Audio.Media.TRACK,
                MediaStore.Audio.Media.YEAR,
                MediaStore.Audio.Media.IS_MUSIC,
            )

            val selection = "${MediaStore.Audio.Media.IS_MUSIC} != 0 AND ${MediaStore.Audio.Media.DURATION} >= ?"
            val found = ArrayList<Track>()
            val seenPaths = HashSet<String>()

            val cursor = context.contentResolver.query(
                MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                projection,
                selection,
                arrayOf("10000"), // 过滤掉 <10 秒的提示音/音效
                "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )

            cursor?.use { c ->
                val iId = c.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val iTitle = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TITLE)
                val iArtist = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ARTIST)
                val iAlbum = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
                val iAlbumId = c.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM_ID)
                val iDuration = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val iData = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
                val iSize = c.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val iAdded = c.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val iTrack = c.getColumnIndexOrThrow(MediaStore.Audio.Media.TRACK)
                val iYear = c.getColumnIndexOrThrow(MediaStore.Audio.Media.YEAR)

                val total = c.count
                var n = 0
                while (c.moveToNext()) {
                    n++
                    if (n % 50 == 0) onProgress(n, total)

                    val path = c.getString(iData) ?: continue
                    seenPaths.add(path)
                    val size = if (c.isNull(iSize)) 0L else c.getLong(iSize)
                    if (existing[path] == size) continue // 没变，跳过

                    val id = c.getLong(iId)
                    val title = c.getString(iTitle)?.takeIf { it.isNotBlank() }
                        ?: path.substringAfterLast('/').substringBeforeLast('.')
                    val artist = c.getString(iArtist)?.takeIf { it.isNotBlank() && it != "<unknown>" }
                        ?: "未知歌手"
                    val album = c.getString(iAlbum)?.takeIf { it.isNotBlank() && it != "<unknown>" }
                        ?: "未知专辑"
                    val albumId = c.getLong(iAlbumId).toString()
                    val contentUri = "content://media/external/audio/media/$id"
                    // 专辑封面走 MediaStore 的 album art content uri
                    val coverUri = "content://media/external/audio/albumart/$albumId"

                    found.add(
                        Track(
                            id = "local_$id",
                            title = title,
                            artist = artist,
                            albumId = "local_album_$albumId",
                            albumName = album,
                            durationMs = if (c.isNull(iDuration)) 0L else c.getLong(iDuration),
                            url = contentUri,
                            source = "local",
                            coverUri = coverUri,
                            format = path.substringAfterLast('.', "mp3").lowercase(),
                            addedAt = if (c.isNull(iAdded)) 0L else c.getLong(iAdded) * 1000,
                            trackNo = if (c.isNull(iTrack)) 0 else c.getInt(iTrack),
                            year = if (c.isNull(iYear)) null else c.getInt(iYear),
                            sizeBytes = size,
                        )
                    )
                }
                onProgress(total, total)
            }

            // 清掉系统里已不存在的本地歌
            val stale = existing.keys.filterNot { seenPaths.contains(it) }
            if (stale.isNotEmpty()) {
                val delDb = db.writableDatabase
                delDb.beginTransaction()
                try {
                    for (p in stale) {
                        delDb.delete("tracks", "path = ? AND source = 'local'", arrayOf(p))
                    }
                    delDb.setTransactionSuccessful()
                } finally {
                    delDb.endTransaction()
                }
            }

            if (found.isNotEmpty()) db.upsertAll(found)

            ScanResult(
                added = found.size,
                updated = found.size, // 简化：found 里既有新增也有内容变化的
                removed = stale.size,
                total = seenPaths.size,
            )
        }
}
