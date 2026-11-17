package com.cloudtune.player.data

import android.content.Context
import com.cloudtune.player.data.db.MusicDatabase
import com.cloudtune.player.data.model.Album
import com.cloudtune.player.data.model.Track
import com.cloudtune.player.data.scanner.LocalScanner
import com.cloudtune.player.data.webdav.WebDavAccountStore
import com.cloudtune.player.data.webdav.WebDavScanner
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * 曲库仓库：应用级单例，统一对外暴露曲库数据。
 *
 * UI 只 watch 这里的 StateFlow，不再各自读数据库——切歌、扫描完、加来源后
 * 一次 refresh() 全屏同步，避免 Flutter 版那种派生数据缓存失效的坑。
 */
class MusicRepository private constructor(private val context: Context) {

    private val db = MusicDatabase(context)
    private val localScanner = LocalScanner(context, db)
    private val webDavScanner = WebDavScanner(db)
    val webDavAccounts = WebDavAccountStore(context)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    private val _tracks = MutableStateFlow<List<Track>>(emptyList())
    val tracks: StateFlow<List<Track>> = _tracks.asStateFlow()

    private val _albums = MutableStateFlow<List<MusicDatabase.AlbumRow>>(emptyList())
    val albums: StateFlow<List<MusicDatabase.AlbumRow>> = _albums.asStateFlow()

    private val _artists = MutableStateFlow<List<MusicDatabase.ArtistRow>>(emptyList())
    val artists: StateFlow<List<MusicDatabase.ArtistRow>> = _artists.asStateFlow()

    private val _scanning = MutableStateFlow(false)
    val scanning: StateFlow<Boolean> = _scanning.asStateFlow()

    private val _scanProgress = MutableStateFlow(0f) // 0..1
    val scanProgress: StateFlow<Float> = _scanProgress.asStateFlow()

    private val _count = MutableStateFlow(0L)
    val count: StateFlow<Long> = _count.asStateFlow()

    init {
        refresh()
    }

    fun refresh() {
        scope.launch {
            val all = withContext(Dispatchers.IO) { db.allTracks() }
            _tracks.value = all
            _albums.value = withContext(Dispatchers.IO) { db.distinctAlbums() }
            _artists.value = withContext(Dispatchers.IO) { db.distinctArtists() }
            _count.value = all.size.toLong()
        }
    }

    /** 扫描本地音乐（增量）。返回扫描结果供 UI 提示。 */
    suspend fun scanLocal(): LocalScanner.ScanResult = withContext(Dispatchers.Main) {
        _scanning.value = true
        _scanProgress.value = 0f
        try {
            val r = localScanner.scan { cur, total ->
                _scanProgress.value = if (total > 0) cur.toFloat() / total else 0f
            }
            refresh()
            r
        } finally {
            _scanning.value = false
            _scanProgress.value = 1f
        }
    }

    /** 扫描 WebDAV（增量由 WebDavScanner 内部整批替换） */
    suspend fun scanWebDav(): WebDavScanner.Result = withContext(Dispatchers.Main) {
        val account = webDavAccounts.load()
            ?: throw IllegalStateException("还没有配置 WebDAV 账号")
        _scanning.value = true
        try {
            val r = webDavScanner.scan(account) { _scanProgress.value = 0.5f }
            refresh()
            r
        } finally {
            _scanning.value = false
            _scanProgress.value = 1f
        }
    }

    fun search(query: String): List<Track> = db.search(query)

    fun albumTracks(albumId: String): List<Track> =
        _tracks.value.filter { it.albumId == albumId }

    fun artistTracks(artist: String): List<Track> =
        _tracks.value.filter { it.artist == artist }

    fun clearAll() {
        scope.launch {
            withContext(Dispatchers.IO) { db.deleteAll() }
            refresh()
        }
    }

    companion object {
        @Volatile
        private var INSTANCE: MusicRepository? = null
        fun get(context: Context): MusicRepository =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: MusicRepository(context.applicationContext).also { INSTANCE = it }
            }
    }
}
