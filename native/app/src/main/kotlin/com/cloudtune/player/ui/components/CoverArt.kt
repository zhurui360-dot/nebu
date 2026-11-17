package com.cloudtune.player.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.cloudtune.player.ui.theme.R
import kotlin.math.absoluteValue

/**
 * 7 套封面渐变，和 Flutter 版完全一致（配色表照搬，保证两版观感统一）。
 * 0 号是《学不会》山景的位置，这里先统一走渐变，后续接真封面。
 */
private val CoverGradients: List<List<Color>> = listOf(
    listOf(Color(0xFF2B1B4D), Color(0xFF7C5CFF), Color(0xFF33D6FF)),
    listOf(Color(0xFF101830), Color(0xFF3C5BD8), Color(0xFF9BB8FF)),
    listOf(Color(0xFF141C2E), Color(0xFF4A5B8C), Color(0xFFB9C6E8)),
    listOf(Color(0xFF2A1024), Color(0xFFC2418A), Color(0xFFFFB84D)),
    listOf(Color(0xFF0F2A2B), Color(0xFF1F9E8A), Color(0xFF8CE0C0)),
    listOf(Color(0xFF2B1A12), Color(0xFFB65C2E), Color(0xFFF3C07B)),
    listOf(Color(0xFF1F2A44), Color(0xFF5A6FA8), Color(0xFFC7D3EE)),
)

/** albumId → 渐变序号。用稳定 hash，保证同一张专辑每次结果一致。 */
fun coverStyleOf(albumId: String): Int =
    albumId.hashCode().absoluteValue % CoverGradients.size

/**
 * 专辑封面。
 *
 * 渐变斜向铺 + 一层左上白色高光，让纯色渐变看起来像"有印刷质感的实体封面"，
 * 而不是一块扁平色块。
 */
@Composable
fun CoverArt(
    albumId: String,
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    radius: Dp = R.coverSm,
) {
    val colors = CoverGradients[coverStyleOf(albumId)]
    val shape = RoundedCornerShape(radius)

    Box(
        modifier = modifier
            .size(size)
            .clip(shape)
            .background(
                Brush.linearGradient(
                    colors = colors,
                    start = Offset.Zero,
                    end = Offset.Infinite,
                ),
            )
            .background(
                // 左上受光：实体封面的印刷高光
                Brush.linearGradient(
                    colors = listOf(Color.White.copy(alpha = 0.16f), Color.Transparent),
                    start = Offset.Zero,
                    end = Offset(300f, 300f),
                ),
            ),
    )
}
