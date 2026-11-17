package com.cloudtune.player.ui.theme

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope

private val NebuDarkScheme = darkColorScheme(
    primary = Brand,
    onPrimary = Color.White,
    background = Color(0xFF061720),
    onBackground = Color(0xFFF8F9FD),
    surface = Color(0xFF0A1327),
    onSurface = Color(0xFFF8F9FD),
    surfaceVariant = Color(0xFF1B2030),
    onSurfaceVariant = Color(0xFFA7AEC0),
    outline = Color(0x24FFFFFF),
)

private val NebuLightScheme = lightColorScheme(
    primary = Brand,
    onPrimary = Color.White,
    background = Color(0xFFE9EEF4),
    onBackground = Color(0xFF16192B),
    surface = Color(0xFFF6F7FB),
    onSurface = Color(0xFF16192B),
    surfaceVariant = Color(0xFFE4E7F0),
    onSurfaceVariant = Color(0xFF8A90A3),
    outline = Color(0x1F000000),
)

@Composable
fun NebuTheme(content: @Composable () -> Unit) {
    val dark by ThemeStore.isDark.collectAsState()
    MaterialTheme(
        colorScheme = if (dark) NebuDarkScheme else NebuLightScheme,
        typography = MaterialTheme.typography,
        content = content,
    )
}

/**
 * 全局背景：纵向渐变 + 三个光斑。
 *
 * 关键性能决策：光斑用「径向渐变衰减到透明」画，**不用 blur**。
 * Flutter 版是 `LAYER_BLUR(radius:120)` 的实心圆 —— 每个光斑都要走一次离屏模糊；
 * 这里同样柔和的观感，代价是一次 radialGradient 绘制（几乎免费）。
 */
@Composable
fun NebuBackground(modifier: Modifier = Modifier) {
    val strength = GlowStrength
    Box(modifier.fillMaxSize().background(BgBottom)) {
        Canvas(Modifier.fillMaxSize()) {
            val w = size.width
            val h = size.height

            // 底色
            drawRect(
                Brush.verticalGradient(
                    0f to BgTop,
                    0.45f to BgMid,
                    1f to BgBottom,
                )
            )

            // 光斑 · 紫（左上，主光）
            glow(
                center = Offset(w * 0.12f, -h * 0.04f),
                radius = w * 1.0f,
                color = GlowPurple,
                alpha = 0.46f * strength,
            )
            // 光斑 · 青（右侧偏下，对位补光）
            glow(
                center = Offset(w * 1.05f, h * 0.60f),
                radius = w * 0.92f,
                color = GlowCyan,
                alpha = 0.30f * strength,
            )
            // 光斑 · 品红（左下，补暖）
            glow(
                center = Offset(-w * 0.08f, h * 0.94f),
                radius = w * 0.82f,
                color = GlowPink,
                alpha = 0.18f * strength,
            )
        }
    }
}

private fun DrawScope.glow(
    center: Offset,
    radius: Float,
    color: Color,
    alpha: Float,
) {
    drawCircle(
        brush = Brush.radialGradient(
            0f to color.copy(alpha = alpha),
            0.45f to color.copy(alpha = alpha * 0.55f),
            0.75f to color.copy(alpha = alpha * 0.18f),
            1f to Color.Transparent,
            center = center,
            radius = radius,
        ),
        radius = radius,
        center = center,
    )
}
