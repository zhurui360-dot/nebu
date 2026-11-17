package com.cloudtune.player.ui.theme

import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp

/**
 * 字号阶梯。比 Material3 默认更紧凑、字距更负——玻璃质感需要"文字贴在玻璃上"，
 * 字距一松就散了。中文用系统字重，英文数字走默认。
 */
object T {
    /** 首页问候 */
    val greeting = TextStyle(fontSize = 24.sp, lineHeight = 30.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.5).sp)

    /** 页面主标题 */
    val h1 = TextStyle(fontSize = 28.sp, lineHeight = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.8).sp)

    /** 分区标题 */
    val h2 = TextStyle(fontSize = 16.sp, lineHeight = 22.sp, fontWeight = FontWeight.Bold)

    /** 卡片主标题 */
    val title = TextStyle(fontSize = 17.sp, lineHeight = 23.sp, fontWeight = FontWeight.SemiBold)

    /** 列表行标题 */
    val rowTitle = TextStyle(fontSize = 15.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium)

    /** 正文 */
    val body = TextStyle(fontSize = 13.5.sp, lineHeight = 20.sp)

    /** 副标题 / 说明 */
    val sub = TextStyle(fontSize = 13.sp, lineHeight = 18.sp)

    /** 小字 */
    val caption = TextStyle(fontSize = 12.sp, lineHeight = 16.sp)

    /** 标签（快方块下方） */
    val label = TextStyle(fontSize = 11.sp, lineHeight = 14.sp, fontWeight = FontWeight.Medium)

    /** 时间码 */
    val time = TextStyle(
        fontSize = 10.sp,
        lineHeight = 13.sp,
        fontWeight = FontWeight.Medium,
        fontFamily = FontFamily.Monospace,
    )
}
