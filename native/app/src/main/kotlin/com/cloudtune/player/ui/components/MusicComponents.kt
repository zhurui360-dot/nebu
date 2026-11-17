package com.cloudtune.player.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.MoreVert
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.cloudtune.player.data.model.Track
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/** 歌曲行：封面 + 标题 + 歌手·专辑 + 时长 + 更多。接真实 Track，点按播放。 */
@Composable
fun SongRow(
    track: Track,
    playing: Boolean,
    onClick: () -> Unit,
    onMore: (() -> Unit)? = null,
    modifier: Modifier = Modifier,
) {
    Row(
        modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = Pad.page, vertical = 7.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SongCover(track, 48.dp)
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(
                track.title,
                style = T.rowTitle.copy(fontWeight = if (playing) FontWeight.Bold else FontWeight.Normal),
                color = if (playing) Brand else Text1,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(2.dp))
            Text(
                "${track.artist} · ${track.albumName}",
                style = T.caption,
                color = Text2,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(Modifier.width(8.dp))
        Text(formatTime(track.durationMs), style = T.time, color = Text3)
        if (onMore != null) {
            Spacer(Modifier.width(6.dp))
            Icon(
                Icons.Rounded.MoreVert,
                contentDescription = "更多",
                tint = Text3,
                modifier = Modifier
                    .size(22.dp)
                    .clickable(onClick = onMore),
            )
        }
    }
}

/** 统一封面：有真实 Uri 用 AsyncImage，否则按 albumId 渐变兜底 */
@Composable
fun SongCover(track: Track, size: androidx.compose.ui.unit.Dp, radius: androidx.compose.ui.unit.Dp = 12.dp) {
    if (track.coverUri != null) {
        AsyncImage(
            model = track.coverUri,
            contentDescription = track.albumName,
            modifier = Modifier
                .size(size)
                .clip(androidx.compose.foundation.shape.RoundedCornerShape(radius)),
        )
    } else {
        CoverArt(
            albumId = track.albumId,
            size = size,
            radius = radius,
        )
    }
}

/** 播放中的均衡器动画（三个小竖条）——纯装饰，用固定高度避免持续重绘 */
@Composable
fun PlayingBars(color: androidx.compose.ui.graphics.Color = Brand) {
    Row(
        verticalAlignment = Alignment.Bottom,
        modifier = Modifier.height(14.dp),
    ) {
        repeat(3) { i ->
            Box(
                Modifier
                    .width(2.dp)
                    .height((6 + i * 3).dp)
                    .clip(CircleShape)
                    .background(color)
            )
            if (i < 2) Spacer(Modifier.width(2.dp))
        }
    }
}

fun formatTime(ms: Long): String {
    if (ms <= 0) return "0:00"
    val total = ms / 1000
    val m = total / 60
    val s = total % 60
    return "$m:${s.toString().padStart(2, '0')}"
}
