package com.cloudtune.player

import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import com.cloudtune.player.ui.RootShell
import com.cloudtune.player.ui.theme.NebuTheme
import com.cloudtune.player.ui.theme.ThemeStore

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 外观设置：深色 / 浅色 / 跟随系统。状态栏样式跟随主题，
        // 深色底上系统栏图标必须是亮的，浅色底上必须是暗的，否则会消失。
        ThemeStore.init(this)

        applyHighestRefreshRate()

        setContent {
            val dark by ThemeStore.isDark.collectAsState()
            LaunchedEffect(dark) {
                val bar = if (dark) {
                    SystemBarStyle.dark(Color.TRANSPARENT)
                } else {
                    SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT)
                }
                enableEdgeToEdge(
                    statusBarStyle = bar,
                    navigationBarStyle = bar,
                )
            }
            NebuTheme {
                RootShell()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // 从后台回来时系统可能已经把刷新率降回 60，再要一次
        applyHighestRefreshRate()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // 跟随系统模式下，系统切深浅色要即时响应
        ThemeStore.onSystemThemeChanged(this)
    }

    /**
     * 把刷新率拉到设备支持的最高值（120/144Hz 机型直接吃满）。
     *
     * 只设 `preferredRefreshRate`，**不锁** `preferredDisplayModeId`——
     * 锁 mode 有几率被切到低分辨率档，画质反而下降。
     */
    private fun applyHighestRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return

        // 注意：Activity.getDisplay() 是 API 30 才有的，低版本直接调会 NoSuchMethodError
        val d = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        } ?: return

        val modes = d.supportedModes
        if (modes.isEmpty()) return
        val best = modes.maxByOrNull { it.refreshRate } ?: return
        val attrs = window.attributes
        if (attrs.preferredRefreshRate != best.refreshRate) {
            attrs.preferredRefreshRate = best.refreshRate
            window.attributes = attrs
        }
    }
}
