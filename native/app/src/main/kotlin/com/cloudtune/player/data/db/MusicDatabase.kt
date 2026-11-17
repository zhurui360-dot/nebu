package com.cloudtune.player.data.db

import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import com.cloudtune.player.data.model.Track

/**
 * 曲库数据库。用原生 SQLiteOpenHelper，不引 Room/ksp：
 *  - 少一个注解处理器，构建更快更稳
 *  - 表结构就几张，手写 SQL 完全可控
 *
 * 字段对齐 Flutter 版 Track，方便以后从旧版导入数据。
 */
class MusicDatabase(context: Context) :
    SQLiteOpenHelper(context, DB_NAME, null, DB_VERSION) {

    override fun onCreate(db: SQLiteDatabase) {
        db.execSQL(
            """
            CREATE TABLE tracks (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                artist TEXT NOT NULL DEFAULT '',
                album_id TEXT NOT NULL DEFAULT '',
                album TEXT NOT NULL DEFAULT '',
                duration_ms INTEGER NOT NULL DEFAULT 0,
                path TEXT NOT NULL DEFAULT '',
                source TEXT NOT NULL DEFAULT 'local',
                cover_uri TEXT,
                track_no INTEGER NOT NULL DEFAULT 0,
                year INTEGER,
                date_added INTEGER NOT NULL DEFAULT 0,
                size_bytes INTEGER NOT NULL DEFAULT 0
            )
            """.trimIndent()
        )
        db.execSQL("CREATE INDEX idx_tracks_album ON tracks(album_id)")
        db.execSQL("CREATE INDEX idx_tracks_artist ON tracks(artist)")
        db.execSQL("CREATE INDEX idx_tracks_title ON tracks(title)")
    }

    override fun onUpgrade(db: SQLiteDatabase, old: Int, new: Int) {
        // 目前只有 v1；将来加列时在这里 ALTER，不清空用户数据
    }

    fun upsertAll(tracks: List<Track>) {
        writableDatabase.beginTransaction()
        try {
            val cv = ContentValues()
            for (t in tracks) {
                cv.clear()
                cv.put("id", t.id)
                cv.put("title", t.title)
                cv.put("artist", t.artist)
                cv.put("album_id", t.albumId)
                cv.put("album", t.albumName)
                cv.put("duration_ms", t.durationMs)
                cv.put("path", t.url)
                cv.put("source", t.source)
                cv.put("cover_uri", t.coverUri)
                cv.put("track_no", t.trackNo)
                cv.put("year", t.year)
                cv.put("date_added", t.addedAt)
                cv.put("size_bytes", t.sizeBytes)
                writableDatabase.insertWithOnConflict(
                    "tracks", null, cv, SQLiteDatabase.CONFLICT_REPLACE
                )
            }
            writableDatabase.setTransactionSuccessful()
        } finally {
            writableDatabase.endTransaction()
        }
    }

    /** 增量扫描：返回已存在的 (path -> size) 映射，没变的歌直接跳过 */
    fun existingPaths(): Map<String, Long> {
        val map = HashMap<String, Long>()
        readableDatabase.rawQuery("SELECT path, size_bytes FROM tracks", null).use { c ->
            while (c.moveToNext()) {
                map[c.getString(0)] = c.getLong(1)
            }
        }
        return map
    }

    fun deleteAll() = writableDatabase.delete("tracks", null, null)

    fun deleteBySource(source: String) =
        writableDatabase.delete("tracks", "source = ?", arrayOf(source))

    fun allTracks(): List<Track> {
        val list = ArrayList<Track>()
        readableDatabase.rawQuery(
            "SELECT id,title,artist,album_id,album,duration_ms,path,source,cover_uri,track_no,year,date_added,size_bytes " +
                "FROM tracks ORDER BY title COLLATE NOCASE",
            null,
        ).use { list.addAll(it.toTracks()) }
        return list
    }

    fun count(): Long =
        readableDatabase.rawQuery("SELECT COUNT(*) FROM tracks", null).use {
            if (it.moveToFirst()) it.getLong(0) else 0L
        }

    fun distinctAlbums(): List<AlbumRow> {
        val list = ArrayList<AlbumRow>()
        readableDatabase.rawQuery(
            """
            SELECT album_id, MAX(album) AS album, MAX(artist) AS artist,
                   COUNT(*) AS n, MAX(cover_uri) AS cover_uri
            FROM tracks
            WHERE album <> ''
            GROUP BY album_id
            ORDER BY album COLLATE NOCASE
            """.trimIndent(),
            null,
        ).use { c ->
            while (c.moveToNext()) {
                list.add(
                    AlbumRow(
                        id = c.getString(0),
                        name = c.getString(1),
                        artist = c.getString(2),
                        count = c.getInt(3),
                        coverUri = c.getString(4),
                    )
                )
            }
        }
        return list
    }

    fun distinctArtists(): List<ArtistRow> {
        val list = ArrayList<ArtistRow>()
        readableDatabase.rawQuery(
            """
            SELECT artist, COUNT(*) AS n FROM tracks
            WHERE artist <> '' GROUP BY artist ORDER BY artist COLLATE NOCASE
            """.trimIndent(),
            null,
        ).use { c ->
            while (c.moveToNext()) list.add(ArtistRow(c.getString(0), c.getInt(1)))
        }
        return list
    }

    fun search(query: String): List<Track> {
        if (query.isBlank()) return emptyList()
        val q = "%${query.trim()}%"
        val list = ArrayList<Track>()
        readableDatabase.rawQuery(
            "SELECT id,title,artist,album_id,album,duration_ms,path,source,cover_uri,track_no,year,date_added,size_bytes " +
                "FROM tracks WHERE title LIKE ? OR artist LIKE ? OR album LIKE ? " +
                "ORDER BY title COLLATE NOCASE LIMIT 200",
            arrayOf(q, q, q),
        ).use { list.addAll(it.toTracks()) }
        return list
    }

    private fun Cursor.toTracks(): List<Track> {
        val out = ArrayList<Track>()
        while (moveToNext()) {
            out.add(
                Track(
                    id = getString(0),
                    title = getString(1),
                    artist = getString(2),
                    albumId = getString(3),
                    albumName = getString(4),
                    durationMs = getLong(5),
                    url = getString(6),
                    source = getString(7),
                    coverUri = getString(8),
                    trackNo = getInt(9),
                    year = if (isNull(10)) null else getInt(10),
                    addedAt = getLong(11),
                    sizeBytes = getLong(12),
                )
            )
        }
        return out
    }

    data class AlbumRow(
        val id: String, val name: String, val artist: String,
        val count: Int, val coverUri: String?,
    )
    data class ArtistRow(val name: String, val count: Int)

    companion object {
        private const val DB_NAME = "nebu_music.db"
        private const val DB_VERSION = 1
    }
}
