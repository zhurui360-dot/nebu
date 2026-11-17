package com.cloudtune.player.data.webdav

import com.cloudtune.player.data.db.MusicDatabase
import com.cloudtune.player.data.model.Track
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** 递归扫描 WebDAV 目录，把音频文件写进曲库。 */
class WebDavScanner(private val db: MusicDatabase) {

    companion object {
        private val AUDIO_EXT = setOf(
            "mp3", "flac", "m4a", "aac", "ogg", "opus", "wav", "wma", "ape", "mp4", "aiff",
        )
    }

    data class Result(val added: Int, val errors: List<String>)

    suspend fun scan(
        account: WebDavAccountStore.Account,
        onProgress: (String) -> Unit = {},
    ): Result = withContext(Dispatchers.IO) {
        val client = WebDavClient(account.baseUrl, account.username, account.password)
        val found = ArrayList<Track>()
        val errors = ArrayList<String>()
        val visited = HashSet<String>()

        suspend fun walk(path: String, depth: Int) {
            if (depth > 12 || path in visited) return
            visited.add(path)
            onProgress(path)
            val entries = try {
                client.list(path)
            } catch (e: Exception) {
                errors.add("$path: ${e.message ?: "读取失败"}")
                return
            }
            for (e in entries) {
                if (e.isDir) {
                    walk(e.path, depth + 1)
                } else if (e.name.substringAfterLast('.').lowercase() in AUDIO_EXT) {
                    val name = e.name.substringBeforeLast('.')
                    val parts = name.split(" - ", limit = 2)
                    val artist = if (parts.size == 2) parts[0].trim() else "未知歌手"
                    val title = if (parts.size == 2) parts[1].trim() else name.trim()
                    found.add(
                        Track(
                            id = "webdav_${e.path.hashCode()}",
                            title = title.ifBlank { e.name },
                            artist = artist,
                            albumId = "webdav_album",
                            albumName = "WebDAV 音乐",
                            durationMs = 0L, // 元数据要下载文件头才能拿到，MVP 先留 0
                            url = client.directUrl(e.path),
                            source = "webdav",
                            format = e.name.substringAfterLast('.').lowercase(),
                            sizeBytes = e.size,
                        )
                    )
                }
            }
        }

        try {
            walk(account.folder, 0)
        } catch (e: Exception) {
            errors.add(e.message ?: "扫描失败")
        }

        // 先清掉旧 WebDAV 数据再整批写入
        db.deleteBySource("webdav")
        if (found.isNotEmpty()) db.upsertAll(found)
        Result(found.size, errors)
    }
}
