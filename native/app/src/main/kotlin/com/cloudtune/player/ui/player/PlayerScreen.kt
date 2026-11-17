package com.cloudtune.player.ui.player

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Close
import androidx.compose.material.icons.rounded.Loop
import androidx.compose.material.icons.rounded.Pause
import androidx.compose.material.icons.rounded.PlayArrow
import androidx.compose.material.icons.rounded.RepeatOne
import androidx.compose.material.icons.rounded.Shuffle
import androidx.compose.material.icons.rounded.SkipNext
import androidx.compose.material.icons.rounded.SkipPrevious
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.cloudtune.player.data.model.PlayMode
import com.cloudtune.player.data.model.Track
import com.cloudtune.player.playback.PlayerController
import com.cloudtune.player.ui.components.CoverArt
import com.cloudtune.player.ui.components.formatTime
import com.cloudtune.player.ui.theme.Brand
import com.cloudtune.player.ui.theme.Pad
import com.cloudtune.player.ui.theme.PlayBtnBg
import com.cloudtune.player.ui.theme.PlayBtnFg
import com.cloudtune.player.ui.theme.R
import com.cloudtune.player.ui.theme.T
import com.cloudtune.player.ui.theme.Text1
import com.cloudtune.player.ui.theme.Text2
import com.cloudtune.player.ui.theme.Text3

/** 全屏播放页：大封面 + 歌名歌手 + 进度 + 完整控制。接 PlayerController 实时状态。 */
@Composable
fun PlayerScreen(player: PlayerController, onClose: () -> Unit) {
    val track by player.currentTrack.collectAsState()
    val playing by player.playing.collectAsState()
    val position by player.position.collectAsState()
    val duration by player.duration.collectAsState()
    val mode by player.playMode.collectAsState()

    if (track == null) {
        // 没有正在播放的歌（空库），给个空态
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("还没有播放的歌曲", style = T.h2, color = Text2)
                Spacer(Modifier.height(16.dp))
                Text("去曲库添加音乐吧", style = T.sub, color = Text3)
                Spacer(Modifier.height(24.dp))
                Text("关闭", style = T.sub, color = Brand, modifier = Modifier.clickable(onClick = onClose))
            }
        }
        return
    }

    val t = track!!
    Column(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(horizontal = Pad.page),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // 顶栏
        Row(
            Modifier.fillMaxWidth().height(52.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Rounded.Close,
                contentDescription = "收起",
                tint = Text1,
                modifier = Modifier.size(26.dp).clickable(onClick = onClose),
            )
            Spacer(Modifier.weight(1f))
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("正在播放", style = T.caption, color = Text3)
                Text(t.albumName, style = T.time, color = Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.weight(1f))
            Spacer(Modifier.size(26.dp))
        }

        Spacer(Modifier.height(28.dp))

        // 大封面
        val coverSize = 300.dp
        if (t.coverUri != null) {
            AsyncImage(
                model = t.coverUri,
                contentDescription = t.albumName,
                modifier = Modifier
                    .size(coverSize)
                    .clip(androidx.compose.foundation.shape.RoundedCornerShape(R.xxl)),
            )
        } else {
            CoverArt(albumId = t.albumId, size = coverSize, radius = R.xxl)
        }

        Spacer(Modifier.height(36.dp))

        // 歌名 + 歌手
        Text(
            t.title,
            style = T.h1.copy(fontWeight = FontWeight.Bold),
            color = Text1,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(8.dp))
        Text(t.artist, style = T.sub, color = Text2, maxLines = 1, overflow = TextOverflow.Ellipsis)

        Spacer(Modifier.height(32.dp))

        // 进度条
        var dragging by remember { mutableStateOf(false) }
        var dragValue by remember { mutableStateOf(0f) }
        val shownValue = if (dragging) dragValue else (if (duration > 0) position.toFloat() / duration else 0f)
        Slider(
            value = shownValue.coerceIn(0f, 1f),
            onValueChange = { dragging = true; dragValue = it },
            onValueChangeFinished = {
                player.seekTo((dragValue * duration).toLong())
                dragging = false
            },
            modifier = Modifier.fillMaxWidth(),
            colors = SliderDefaults.colors(
                thumbColor = Brand,
                activeTrackColor = Brand,
                inactiveTrackColor = Text3.copy(alpha = 0.25f),
            ),
        )
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(formatTime(if (dragging) (dragValue * duration).toLong() else position), style = T.time, color = Text3)
            Text(formatTime(duration), style = T.time, color = Text3)
        }

        Spacer(Modifier.height(24.dp))

        // 播放控制
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceEvenly,
        ) {
            Icon(
                imageVector = when (mode) {
                    PlayMode.shuffle -> Icons.Rounded.Shuffle
                    PlayMode.one -> Icons.Rounded.RepeatOne
                    PlayMode.list -> Icons.Rounded.Loop
                },
                contentDescription = "播放模式",
                tint = if (mode != PlayMode.list) Brand else Text2,
                modifier = Modifier.size(24.dp).clickable(onClick = { player.cyclePlayMode() }),
            )
            Icon(
                Icons.Rounded.SkipPrevious,
                contentDescription = "上一曲",
                tint = Text1,
                modifier = Modifier.size(34.dp).clickable(onClick = { player.previous() }),
            )
            // 主播放键
            Box(
                Modifier
                    .size(72.dp)
                    .clip(CircleShape)
                    .background(PlayBtnBg)
                    .clickable(onClick = { player.toggle() }),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    imageVector = if (playing) Icons.Rounded.Pause else Icons.Rounded.PlayArrow,
                    contentDescription = if (playing) "暂停" else "播放",
                    tint = PlayBtnFg,
                    modifier = Modifier.size(36.dp),
                )
            }
            Icon(
                Icons.Rounded.SkipNext,
                contentDescription = "下一曲",
                tint = Text1,
                modifier = Modifier.size(34.dp).clickable(onClick = { player.next() }),
            )
            // 右侧占位对齐
            Box(Modifier.size(24.dp))
        }

        Spacer(Modifier.height(20.dp))
        Text(
            "队列 ${player.tracks.value.size} 首",
            style = T.caption,
            color = Text3,
        )
    }
}
