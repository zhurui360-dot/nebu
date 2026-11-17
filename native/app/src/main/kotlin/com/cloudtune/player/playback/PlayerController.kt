package com.cloudtune.player.playback

import android.content.Context
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.ListenableFuture
import com.cloudtune.player.data.model.PlayMode
import com.cloudtune.player.data.model.Track
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * UI 与播放服务之间的桥梁：连接 MediaController，把播放器状态转成 StateFlow。
 *
 * UI 只 watch 这里的 state，所有播放操作走 methods —— 不直接碰 ExoPlayer。
 * 进度用 250ms 轮询（不是每帧），避免重组风暴。
 */
class PlayerController private constructor(context: Context) {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var controllerFuture: ListenableFuture<MediaController>? = null
    private var controller: MediaController? = null

    /** controller 连上前的待播请求：首次打开立刻点歌不会丢 */
    private var pending: Pair<List<Track>, Int>? = null

    private val _tracks = MutableStateFlow<List<Track>>(emptyList())
    val tracks: StateFlow<List<Track>> = _tracks.asStateFlow()

    private val _currentIndex = MutableStateFlow(-1)
    val currentIndex: StateFlow<Int> = _currentIndex.asStateFlow()

    private val _playing = MutableStateFlow(false)
    val playing: StateFlow<Boolean> = _playing.asStateFlow()

    private val _position = MutableStateFlow(0L)
    val position: StateFlow<Long> = _position.asStateFlow()

    private val _duration = MutableStateFlow(0L)
    val duration: StateFlow<Long> = _duration.asStateFlow()

    private val _playMode = MutableStateFlow(PlayMode.list)
    val playMode: StateFlow<PlayMode> = _playMode.asStateFlow()

    private val _currentTrack = MutableStateFlow<Track?>(null)
    val currentTrack: StateFlow<Track?> = _currentTrack.asStateFlow()

    /** 最近一次播放错误（UI 弹 Toast 后调 clearError() 消费掉） */
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun clearError() { _error.value = null }

    private val listener = object : Player.Listener {
        override fun onPlaybackStateChanged(state: Int) {
            _playing.value = controller?.isPlaying == true
            if (state == Player.STATE_READY) {
                _duration.value = controller?.duration?.takeIf { it > 0 } ?: 0L
                syncCurrentFromTag()
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            _playing.value = isPlaying
        }

        override fun onMediaItemTransition(item: MediaItem?, reason: Int) {
            syncCurrentFromTag()
            _position.value = 0L
        }

        override fun onPlayerError(error: PlaybackException) {
            // 之前"点歌没反应"连个提示都没有；至少把原因带出来
            _error.value = when (error.errorCode) {
                PlaybackException.ERROR_CODE_IO_FILE_NOT_FOUND,
                PlaybackException.ERROR_CODE_IO_NO_PERMISSION -> "找不到音频文件，试试重新扫描曲库"
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_FAILED,
                PlaybackException.ERROR_CODE_IO_NETWORK_CONNECTION_TIMEOUT -> "网络连不上，检查网络或 WebDAV 配置"
                PlaybackException.ERROR_CODE_PARSING_CONTAINER_UNSUPPORTED -> "音频格式不支持播放"
                else -> "播放失败（${error.errorCodeName}）"
            }
        }
    }

    init {
        val token = PlaybackService.sessionToken(context)
        controllerFuture = MediaController.Builder(context, token).buildAsync()
        controllerFuture?.addListener({
            controller = controllerFuture?.get()
            controller?.addListener(listener)
            // 连上后先兑现待播请求，否则同步状态
            pending?.let { (list, idx) ->
                pending = null
                doPlayQueue(list, idx)
            } ?: controller?.let { syncCurrentFromTag() }
        }, { it.run() }) // 主线程 executor
        startTicker()
    }

    private fun startTicker() {
        scope.launch {
            while (isActive) {
                controller?.let { c ->
                    if (c.isPlaying) _position.value = c.currentPosition
                    val d = c.duration
                    if (d > 0) _duration.value = d
                }
                delay(250L)
            }
        }
    }

    private fun syncCurrentFromTag() {
        val c = controller ?: return
        val idx = c.currentMediaItemIndex
        if (idx in _tracks.value.indices) {
            _currentIndex.value = idx
            _currentTrack.value = _tracks.value[idx]
        } else {
            // controller 里的队列还没设（首次启动）：从 tag 取
            val tag = c.currentMediaItem?.localConfiguration?.tag as? Track
            if (tag != null) _currentTrack.value = tag
        }
    }

    /** 设置播放队列并从指定位置开始播。tracks 变了会整队替换。 */
    fun playQueue(tracks: List<Track>, startIndex: Int) {
        if (tracks.isEmpty()) return
        _tracks.value = tracks
        _currentIndex.value = startIndex
        _currentTrack.value = tracks.getOrNull(startIndex)
        val c = controller
        if (c == null) {
            // 首次打开时 controller 还在异步连接，先记下来，连上后自动播
            pending = tracks to startIndex
            return
        }
        doPlayQueue(tracks, startIndex)
    }

    private fun doPlayQueue(tracks: List<Track>, startIndex: Int) {
        val c = controller ?: return
        val items = tracks.map { it.toMediaItem() }
        c.setMediaItems(items, startIndex.coerceIn(0, tracks.lastIndex), 0L)
        applyModeToPlayer()
        c.prepare()
        c.play()
    }

    fun toggle() {
        val c = controller ?: return
        if (c.isPlaying) c.pause() else c.play()
    }

    fun next() {
        controller?.seekToNextMediaItem()
    }

    fun previous() {
        val c = controller ?: return
        // 播放超过 3 秒时，上一曲先回到开头（和主流播放器一致）
        if (c.currentPosition > 3000) c.seekTo(0) else c.seekToPreviousMediaItem()
    }

    fun seekTo(ms: Long) {
        controller?.seekTo(ms)
        _position.value = ms
    }

    fun setPlayMode(mode: PlayMode) {
        _playMode.value = mode
        applyModeToPlayer()
    }

    private fun applyModeToPlayer() {
        val c = controller ?: return
        c.repeatMode = when (_playMode.value) {
            PlayMode.one -> Player.REPEAT_MODE_ONE
            else -> Player.REPEAT_MODE_OFF
        }
        c.shuffleModeEnabled = _playMode.value == PlayMode.shuffle
    }

    fun cyclePlayMode() {
        val next = when (_playMode.value) {
            PlayMode.list -> PlayMode.shuffle
            PlayMode.shuffle -> PlayMode.one
            PlayMode.one -> PlayMode.list
        }
        setPlayMode(next)
    }

    fun release() {
        controller?.removeListener(listener)
        controllerFuture?.let { MediaController.releaseFuture(it) }
        controller = null
    }

    companion object {
        @Volatile
        private var INSTANCE: PlayerController? = null
        fun get(context: Context): PlayerController =
            INSTANCE ?: synchronized(this) {
                INSTANCE ?: PlayerController(context.applicationContext).also { INSTANCE = it }
            }
    }
}
