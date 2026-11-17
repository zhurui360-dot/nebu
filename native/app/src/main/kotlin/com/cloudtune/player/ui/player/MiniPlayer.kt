package com.cloudtune.player.ui.player

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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.cloudtune.player.playback.PlayerController
import com.cloudtune.player.ui.components.SongCover
import com.cloudtune.player.ui.glass.FrostedGlass
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2

/** 迷你播放条：悬浮在底部导航上方，有歌在播时显示。点任意处展开播放页。 */
@Composable
fun MiniPlayer(
    player: PlayerController,
    onExpand: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val track by player.currentTrack.collectAsState()
    val playing by player.playing.collectAsState()
    val position by player.position.collectAsState()
    val duration by player.duration.collectAsState()
    val t = track ?: return

    FrostedGlass(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = Pad.page)
            .height(60.dp)
            .clickable(onClick = onExpand),
        radius = 18.dp,
        elevation = 12.dp,
    ) {
        Box {
            Row(
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 10.dp, vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                SongCover(t, 42.dp, 10.dp)
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        t.title,
                        style = T.rowTitle,
                        color = Text1,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        t.artist,
                        style = T.caption,
                        color = Text2,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                Icon(
                    imageVector = if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = if (playing) "暂停" else "播放",
                    tint = Text1,
                    modifier = Modifier
                        .size(30.dp)
                        .clip(CircleShape)
                        .clickable { player.toggle() },
                )
                Spacer(Modifier.width(6.dp))
                Icon(
                    Icons.Rounded.SkipNext,
                    contentDescription = "下一曲",
                    tint = Text1,
                    modifier = Modifier
                        .size(28.dp)
                        .clickable { player.next() },
                )
            }
            // 底部播放进度线
            if (duration > 0) {
                LinearProgressIndicator(
                    progress = { (position.toFloat() / duration).coerceIn(0f, 1f) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(2.dp)
                        .align(Alignment.BottomCenter),
                    color = Brand,
                    trackColor = androidx.compose.ui.graphics.Color.Transparent,
                )
            }
        }
    }
}
