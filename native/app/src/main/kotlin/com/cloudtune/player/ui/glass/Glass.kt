package com.cloudtune.player.ui.glass

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.theme.GlassBorderTop
import com.cloudtune.player.ui.theme.GlassFillBottom
import com.cloudtune.player.ui.theme.GlassFillTop
import com.cloudtune.player.ui.theme.R

/**
 * iOS 26/27 风格的玻璃材质（三层：折射 / 受光 / 边缘）。
 *
 * ── 为什么不做 backdrop blur ────────────────────────────────
 * Flutter 版的每张玻璃卡都是 `BackdropFilter`（模糊背后），首页同屏 7 层，
 * 每层还叠一个饱和度色彩矩阵——滚动时每帧重算 7 次高斯模糊，这是掉帧真凶。
 *
 * 这一版的分工：
 *  · 页面内的玻璃卡：背后只有平滑渐变+光斑，模糊它在视觉上没有任何信息量，
 *    所以直接不做模糊，靠「上亮下暗的半透明填充 + 顶部受光 + 边缘高光」立构成玻璃。
 *    代价从「一次离屏模糊」降到「两次渐变绘制」，等于免费。
 *  · 浮在滚动内容上的（导航胶囊 / 迷你播放条 / 弹出层）：必须真模糊，
 *    走 [FrostedGlass] 那条路径，全 App 只有 3 处。
 */
@Composable
fun Glass(
    modifier: Modifier = Modifier,
    radius: Dp = R.card,
    /** 品牌染色：叠在玻璃底之上，用于强调卡（如「继续播放」） */
    tint: Color? = null,
    /** 顶部受光：小控件打开更立体，大卡片关掉避免压住首行文字 */
    topLight: Boolean = true,
    /** 是否带外投影。贴合页面的板块关掉能省一次合成 */
    elevated: Boolean = true,
    elevation: Dp = 12.dp,
    borderColor: Color = GlassBorderTop,
    content: @Composable BoxScope.() -> Unit,
) {
    val shape = RoundedCornerShape(radius)

    var m = modifier
    if (elevated) {
        m = m.shadow(
            elevation = elevation,
            shape = shape,
            ambientColor = Color.Black.copy(alpha = 0.30f),
            spotColor = Color.Black.copy(alpha = 0.40f),
        )
    }

    m = m
        .clip(shape)
        // 折射层：左上受光面 → 右下背光面
        .background(
            Brush.verticalGradient(listOf(GlassFillTop, GlassFillBottom)),
            shape,
        )

    if (tint != null) {
        m = m.background(tint, shape)
    }

    // 边缘：一圈渐变描边，左上亮、右下几乎消失
    m = m.border(
        width = 1.dp,
        brush = Brush.linearGradient(
            listOf(borderColor, borderColor.copy(alpha = 0.06f)),
        ),
        shape = shape,
    )

    Box(m) {
        if (topLight) {
            Box(
                Modifier
                    .align(Alignment.TopCenter)
                    .fillMaxWidth()
                    .height(46.dp)
                    .background(
                        Brush.verticalGradient(
                            listOf(Color.White.copy(alpha = 0.15f), Color.Transparent),
                        ),
                    ),
            )
        }
        content()
    }
}

/**
 * 可点击的玻璃卡：按下轻微内缩，松开弹回。
 * 用 spring 而不是固定 duration —— iOS 的手感来自"过冲回弹"，线性动画会发死。
 */
@Composable
fun GlassCard(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    radius: Dp = R.card,
    tint: Color? = null,
    topLight: Boolean = true,
    elevated: Boolean = true,
    elevation: Dp = 12.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.975f else 1f,
        animationSpec = spring(dampingRatio = 0.55f, stiffness = 900f),
        label = "glass-press",
    )

    Glass(
        modifier = modifier
            .scale(scale)
            .clickable(
                interactionSource = interaction,
                indication = null,
                onClick = onClick,
            ),
        radius = radius,
        tint = tint,
        topLight = topLight,
        elevated = elevated,
        elevation = elevation,
        content = content,
    )
}
