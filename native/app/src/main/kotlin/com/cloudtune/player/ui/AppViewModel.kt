package com.cloudtune.player.ui

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cloudtune.player.data.MusicRepository
import com.cloudtune.player.data.model.PlayMode
import com.cloudtune.player.data.model.Track
import com.cloudtune.player.playback.PlayerController
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * 全 App 共享的 ViewModel：把曲库仓库和播放器桥接起来。
 * 所有屏共用同一个实例（viewModel() 默认 activity scope），状态天然同步。
 */
class AppViewModel(app: Application) : AndroidViewModel(app) {
    val repo = MusicRepository.get(app)
    val player = PlayerController.get(app)

    val tracks = repo.tracks
    val albums = repo.albums
    val artists = repo.artists
    val scanning = repo.scanning
    val scanProgress = repo.scanProgress

    // 播放页是否展开
    private val _playerExpanded = MutableStateFlow(false)
    val playerExpanded: StateFlow<Boolean> = _playerExpanded.asStateFlow()

    // 当前专辑/歌手筛选（曲库下钻）
    private val _albumFilter = MutableStateFlow<String?>(null)
    val albumFilter: StateFlow<String?> = _albumFilter.asStateFlow()
    private val _artistFilter = MutableStateFlow<String?>(null)
    val artistFilter: StateFlow<String?> = _artistFilter.asStateFlow()

    fun expandPlayer() { _playerExpanded.value = true }
    fun collapsePlayer() { _playerExpanded.value = false }

    /** 播放指定歌曲：以当前曲库列表为队列 */
    fun playTrack(track: Track, queue: List<Track> = tracks.value) {
        val idx = queue.indexOfFirst { it.id == track.id }.let { if (it >= 0) it else 0 }
        player.playQueue(queue, idx)
        _playerExpanded.value = true
    }

    /** 播放整张专辑 */
    fun playAlbum(albumId: String) {
        val list = repo.albumTracks(albumId)
        if (list.isNotEmpty()) {
            player.playQueue(list, 0)
            _playerExpanded.value = true
        }
    }

    fun toggle() = player.toggle()
    fun next() = player.next()
    fun previous() = player.previous()
    fun seek(ms: Long) = player.seekTo(ms)
    fun cycleMode() = player.cyclePlayMode()

    fun scanLocal() {
        viewModelScope.launch { repo.scanLocal() }
    }

    fun scanWebDav(onDone: (String) -> Unit) {
        viewModelScope.launch {
            try {
                val r = repo.scanWebDav()
                val err = if (r.errors.isEmpty()) "" else "，${r.errors.size} 个目录读取失败"
                onDone("WebDAV 扫描完成，新增 ${r.added} 首$err")
            } catch (e: Exception) {
                onDone("WebDAV 扫描失败：${e.message ?: "未知错误"}")
            }
        }
    }

    fun openAlbum(id: String) { _albumFilter.value = id }
    fun closeAlbum() { _albumFilter.value = null }
    fun openArtist(name: String) { _artistFilter.value = name }
    fun closeArtist() { _artistFilter.value = null }

    fun search(q: String) = repo.search(q)

    fun clearLibrary() = repo.clearAll()
}
