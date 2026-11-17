package com.cloudtune.player.ui.theme

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color

/*
 * 语义色 token 体系。
 *
 * 关键设计：所有 token 都是顶层 `var … by mutableStateOf`——
 * 全 App 的屏幕直接写 `Text1`、`BgBottom`（读法与旧版完全一致），
 * 但它们背后是 Compose 快照状态。切换主题时 ThemeStore 重新赋值，
 * 所有读到它们的组合自动重组，一行屏幕代码都不用改。
 *
 * 两套调色：
 *  · 深色：深靛夜空 + 白色玻璃（设计稿原味）
 *  · 浅色：iOS 浅色玻璃——雾紫灰底 + 白玻璃 + 深墨文字，播放键反转为深底白字
 */

// ---------- 背景：纵向渐变 ----------
var BgTop by mutableStateOf(Color(0xFF0E0B24)); private set
var BgMid by mutableStateOf(Color(0xFF0A1327)); private set
var BgBottom by mutableStateOf(Color(0xFF061720)); private set

// ---------- 文字 ----------
var Text1 by mutableStateOf(Color(0xFFF8F9FD)); private set
var Text2 by mutableStateOf(Color(0xB8FFFFFF)); private set
var Text3 by mutableStateOf(Color(0xFFA7AEC0)); private set

// ---------- 玻璃：受光面 / 背光面 / 边缘 ----------
var GlassFillTop by mutableStateOf(Color(0x1AFFFFFF)); private set
var GlassFillBottom by mutableStateOf(Color(0x05FFFFFF)); private set
var GlassBorderTop by mutableStateOf(Color(0x38FFFFFF)); private set
var GlassBorderBottom by mutableStateOf(Color(0x0DFFFFFF)); private set

// ---------- 磨砂浮层（导航/迷你播放条）：底色 + 边缘 ----------
var FrostedBase by mutableStateOf(Color(0xD11A1F33)); private set
var FrostedBorderTop by mutableStateOf(Color(0x42FFFFFF)); private set
var FrostedBorderBottom by mutableStateOf(Color(0x12FFFFFF)); private set

// ---------- 分隔线 ----------
var Line1 by mutableStateOf(Color(0x14FFFFFF)); private set
var Line2 by mutableStateOf(Color(0x24FFFFFF)); private set

// ---------- 播放键（深色主题白底深字 / 浅色主题反转为深底白字） ----------
var PlayBtnBg by mutableStateOf(Color(0xFFFFFFFF)); private set
var PlayBtnFg by mutableStateOf(Color(0xFF16121F)); private set

// ---------- 光斑强度（浅色底上要减淡，不然会发脏） ----------
var GlowStrength by mutableStateOf(1f); private set

// ---------- 品牌（两套主题共用） ----------
val Brand = Color(0xFF8B5CFF)
val BrandDeep = Color(0xFF6A45E8)
val BrandCyan = Color(0xFF33D6FF)

// ---------- 光斑（三个，紫主 / 青对位 / 品红补暖） ----------
val GlowPurple = Color(0xFF7C5CFF)
val GlowCyan = Color(0xFF33D6FF)
val GlowPink = Color(0xFFFF5FA2)

/** 按 dark 开关整批切换 token。只由 ThemeStore 调用。 */
internal fun applyNebuTokens(dark: Boolean) {
    if (dark) {
        BgTop = Color(0xFF0E0B24); BgMid = Color(0xFF0A1327); BgBottom = Color(0xFF061720)
        Text1 = Color(0xFFF8F9FD); Text2 = Color(0xB8FFFFFF); Text3 = Color(0xFFA7AEC0)
        GlassFillTop = Color(0x1AFFFFFF); GlassFillBottom = Color(0x05FFFFFF)
        GlassBorderTop = Color(0x38FFFFFF); GlassBorderBottom = Color(0x0DFFFFFF)
        FrostedBase = Color(0xD11A1F33)
        FrostedBorderTop = Color(0x42FFFFFF); FrostedBorderBottom = Color(0x12FFFFFF)
        Line1 = Color(0x14FFFFFF); Line2 = Color(0x24FFFFFF)
        PlayBtnBg = Color(0xFFFFFFFF); PlayBtnFg = Color(0xFF16121F)
        GlowStrength = 1f
    } else {
        BgTop = Color(0xFFECE9F8); BgMid = Color(0xFFF0F1F8); BgBottom = Color(0xFFE9EEF4)
        Text1 = Color(0xFF16192B); Text2 = Color(0x9916192B); Text3 = Color(0xFF8A90A3)
        GlassFillTop = Color(0x99FFFFFF); GlassFillBottom = Color(0x40FFFFFF)
        GlassBorderTop = Color(0x99FFFFFF); GlassBorderBottom = Color(0x2EFFFFFF)
        FrostedBase = Color(0xE6FFFFFF)
        FrostedBorderTop = Color(0x66FFFFFF); FrostedBorderBottom = Color(0x1FFFFFFF)
        Line1 = Color(0x0F000000); Line2 = Color(0x1F000000)
        PlayBtnBg = Color(0xFF16192B); PlayBtnFg = Color(0xFFFFFFFF)
        GlowStrength = 0.45f
    }
}
