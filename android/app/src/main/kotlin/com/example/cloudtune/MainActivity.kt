package com.example.cloudtune

import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

/// 必须继承 AudioServiceActivity：
/// audio_service 的媒体会话要挂在这上面，通知栏/锁屏/系统媒体卡才能接管。
class MainActivity : AudioServiceActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyHighestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        // 不少机型切后台再回来会把申请过的刷新率重置回 60Hz，回前台再要一次
        applyHighestRefreshRate()
    }

    /**
     * 不写死任何帧率：直接读这块屏自己支持的刷新率，取最高档交给窗口。
     *
     * 系统对「没有主动声明」的应用普遍默认 60Hz——手机开了高刷，App 里也还是 60 帧。
     * 这里只是「不设上限」：60Hz 机型拿到 60，90Hz 拿 90，120Hz 拿 120，144Hz 拿 144，
     * 由设备自己的面板决定，代码里没有任何硬编码的帧率数字。
     *
     * 只设 preferredRefreshRate（刷新率偏好），不锁 preferredDisplayModeId——
     * 锁 mode 会把分辨率一起钉死，部分机型上会导致画面变糊。
     */
    @Suppress("DEPRECATION")
    private fun applyHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val disp = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                display
            } else {
                windowManager.defaultDisplay
            } ?: return

            val best = disp.supportedModes.maxByOrNull { it.refreshRate } ?: return
            if (best.refreshRate <= 0f) return

            val lp = window.attributes
            lp.preferredRefreshRate = best.refreshRate
            window.attributes = lp
        } catch (_: Throwable) {
            // 个别 ROM 不允许改窗口刷新率，忽略即可，退回系统默认
        }
    }
}
