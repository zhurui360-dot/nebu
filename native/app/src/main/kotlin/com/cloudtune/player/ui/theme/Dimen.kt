package com.cloudtune.player.ui.theme

import androidx.compose.ui.unit.dp

/**
 * 圆角阶梯。和 Flutter 版的 R 对齐，保证两版观感一致：
 * sm8 / md12 / lg20 / xl26 / xxl30 / card28 / dock24
 */
object R {
    val sm = 8.dp
    val md = 12.dp
    val lg = 20.dp
    val xl = 26.dp
    val xxl = 30.dp
    val card = 28.dp
    val dock = 24.dp

    /** 封面圆角 */
    val cover = 24.dp
    val coverSm = 14.dp

    /** 快捷方块 */
    val tile = 22.dp
}

/** 页面左右安全边距 */
object Pad {
    val page = 20.dp
    val pageWide = 24.dp
    val section = 26.dp
}

/** 底部预留：给导航胶囊留出空间 */
object Insets {
    val navBar = 96.dp
    val miniPlayer = 74.dp
}
