package com.cloudtune.player.ui.theme

import android.content.Context
import android.content.res.Configuration
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 外观模式：深色 / 浅色 / 跟随系统 */
enum class AppearanceMode { DARK, LIGHT, SYSTEM }

fun AppearanceMode.label(): String = when (this) {
    AppearanceMode.DARK -> "深色玻璃"
    AppearanceMode.LIGHT -> "浅色玻璃"
    AppearanceMode.SYSTEM -> "跟随系统"
}

/**
 * 主题状态的唯一入口。
 *
 * 持久化到 SharedPreferences；`isDark` 是 Compose 可观察的 StateFlow——
 * MainActivity 用来切系统栏样式，NebuTheme 用来选 Material 配色，
 * 具体的色彩 token 由 [applyNebuTokens] 整批赋值。
 */
object ThemeStore {

    private const val PREFS = "nebu_prefs"
    private const val KEY = "appearance_mode"

    private val _mode = MutableStateFlow(AppearanceMode.DARK)
    val mode: StateFlow<AppearanceMode> = _mode.asStateFlow()

    private val _isDark = MutableStateFlow(true)
    val isDark: StateFlow<Boolean> = _isDark.asStateFlow()

    /** App 启动时调一次：读回持久化的选择 */
    fun init(context: Context) {
        val saved = prefs(context).getString(KEY, null)
        val m = saved?.let { runCatching { AppearanceMode.valueOf(it) }.getOrNull() }
            ?: AppearanceMode.DARK
        _mode.value = m
        resolveAndApply(m, context)
    }

    /** 用户改外观设置 */
    fun set(context: Context, m: AppearanceMode) {
        prefs(context).edit().putString(KEY, m.name).apply()
        _mode.value = m
        resolveAndApply(m, context)
    }

    /** 系统深浅色变化时（仅 SYSTEM 模式生效）重新解析 */
    fun onSystemThemeChanged(context: Context) {
        if (_mode.value == AppearanceMode.SYSTEM) resolveAndApply(AppearanceMode.SYSTEM, context)
    }

    private fun resolveAndApply(m: AppearanceMode, context: Context) {
        val dark = when (m) {
            AppearanceMode.DARK -> true
            AppearanceMode.LIGHT -> false
            AppearanceMode.SYSTEM -> {
                val mask = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
                mask == Configuration.UI_MODE_NIGHT_YES || mask == Configuration.UI_MODE_NIGHT_UNDEFINED
            }
        }
        _isDark.value = dark
        applyNebuTokens(dark)
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
