package com.cloudtune.player.ui.update

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.cloudtune.player.BuildConfig
import com.cloudtune.player.data.update.UpdateInfo
import com.cloudtune.player.data.update.UpdateService
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.io.File

enum class UpdatePhase {
    /** 静默检查中，不打扰用户 */
    Idle,
    Checking,
    /** 有新版，等用户决定 */
    Found,
    Downloading,
    /** 下载完，等系统安装界面 */
    Ready,
    /** 已是最新（手动检查时才提示） */
    Latest,
    Error,
}

data class UpdateUiState(
    val phase: UpdatePhase = UpdatePhase.Idle,
    val info: UpdateInfo? = null,
    val progress: Float = 0f,
    val error: String? = null,
    val apkFile: File? = null,
) {
    val busy: Boolean get() = phase == UpdatePhase.Checking || phase == UpdatePhase.Downloading
    val visible: Boolean
        get() = phase != UpdatePhase.Idle
}

class UpdateViewModel(app: Application) : AndroidViewModel(app) {

    private val _state = MutableStateFlow(UpdateUiState())
    val state: StateFlow<UpdateUiState> = _state.asStateFlow()

    /**
     * 启动时静默检查一次。
     *
     * 静默 = 没有更新、网络不通都**不弹任何东西**。启动就报"检查失败"是最招人烦的做法，
     * 用户根本没主动要求检查。
     */
    fun checkSilently() {
        viewModelScope.launch {
            try {
                val info = UpdateService.check(
                    currentVersionCode = BuildConfig.VERSION_CODE,
                    currentVersion = BuildConfig.VERSION_NAME,
                )
                if (info != null) {
                    _state.value = UpdateUiState(phase = UpdatePhase.Found, info = info)
                }
            } catch (_: Exception) {
                // 静默失败：什么都不做
            }
        }
    }

    /** 手动检查：结果一定要给用户一个明确回应 */
    fun checkManually() {
        if (_state.value.busy) return
        viewModelScope.launch {
            _state.value = _state.value.copy(phase = UpdatePhase.Checking, error = null)
            try {
                val info = UpdateService.check(
                    currentVersionCode = BuildConfig.VERSION_CODE,
                    currentVersion = BuildConfig.VERSION_NAME,
                )
                _state.value = if (info == null) {
                    UpdateUiState(phase = UpdatePhase.Latest)
                } else {
                    UpdateUiState(phase = UpdatePhase.Found, info = info)
                }
            } catch (e: Exception) {
                _state.value = UpdateUiState(
                    phase = UpdatePhase.Error,
                    error = e.message ?: "检查更新失败",
                )
            }
        }
    }

    fun download() {
        val info = _state.value.info ?: return
        if (_state.value.phase == UpdatePhase.Downloading) return

        viewModelScope.launch {
            _state.value = _state.value.copy(phase = UpdatePhase.Downloading, progress = 0f)
            try {
                val file = UpdateService.download(getApplication(), info) { p ->
                    _state.value = _state.value.copy(progress = p)
                }
                _state.value = _state.value.copy(phase = UpdatePhase.Ready, apkFile = file)
            } catch (e: Exception) {
                _state.value = _state.value.copy(
                    phase = UpdatePhase.Error,
                    error = e.message ?: "下载失败",
                )
            }
        }
    }

    /** 拉起安装器；没权限就先送去设置页 */
    fun install(onNeedPermission: () -> Unit) {
        val ctx = getApplication<Application>()
        val apk = _state.value.apkFile ?: return
        if (!UpdateService.canInstall(ctx)) {
            onNeedPermission()
            return
        }
        UpdateService.install(ctx, apk)
    }

    fun dismiss() {
        // 下载中不允许关掉，否则用户不知道后台在干什么
        if (_state.value.phase == UpdatePhase.Downloading) return
        _state.value = UpdateUiState()
    }
}
