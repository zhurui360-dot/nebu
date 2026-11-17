package com.cloudtune.player.ui.glass

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.theme.FrostedBase
import com.cloudtune.player.ui.theme.FrostedBorderBottom
import com.cloudtune.player.ui.theme.FrostedBorderTop
import com.cloudtune.player.ui.theme.R

/**
 * 浮层磨砂玻璃：导航胶囊、迷你播放条、弹出面板。
 *
 * 这些组件浮在「会滚动的列表」上方，背后内容必须被糊住，不能像页面内卡片那样只靠半透明。
 * Compose 没有 BackdropFilter 等价物（`Modifier.blur()` 模糊的是自己不是背后），
 * 所以这里用「高不透明度暗色底 + 顶部强受光 + 亮边」来造磨砂感——
 * 也就是 iOS 7–15 那套毛玻璃的老办法，在没有真模糊的前提下观感最接近。
 *
 * 全 App 只有 3 处用它，后续如果要真模糊（Haze / RenderEffect）也只改这一个组件。
 */
@Composable
fun FrostedGlass(
    modifier: Modifier = Modifier,
    radius: Dp = R.dock,
    elevation: Dp = 20.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)

    Box(
        modifier = modifier
            .shadow(
                elevation = elevation,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.45f),
                spotColor = Color.Black.copy(alpha = 0.55f),
            )
            .clip(shape)
            // 磨砂底压住背后内容（深色=暗靛 0.82 / 浅色=近白 0.90，token 随主题切换）
            .background(FrostedBase, shape)
            .background(
                Brush.verticalGradient(
                    listOf(Color.White.copy(alpha = 0.10f), Color.White.copy(alpha = 0.02f)),
                ),
                shape,
            )
            .border(
                width = 1.dp,
                brush = Brush.linearGradient(
                    listOf(FrostedBorderTop, FrostedBorderBottom),
                ),
                shape,
            ),
    ) {
        // 顶部受光带：玻璃厚度感的来源
        Box(
            Modifier
                .align(Alignment.TopCenter)
                .fillMaxWidth()
                .height(24.dp)
                .background(
                    Brush.verticalGradient(
                        listOf(Color.White.copy(alpha = 0.10f), Color.Transparent),
                    ),
                ),
        )
        content()
    }
}
